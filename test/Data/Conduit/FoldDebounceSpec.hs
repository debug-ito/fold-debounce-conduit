module Data.Conduit.FoldDebounceSpec (main, spec) where

import Test.Hspec

import Data.Monoid (Monoid)
import Control.Concurrent (threadDelay)
import Control.Monad (forM_)
import System.Timeout (timeout)
import qualified Data.Conduit.FoldDebounce as F
import Data.Conduit (Source, ConduitM, ($$), yield, addCleanup)
import Control.Monad.IO.Class (liftIO)
import qualified Data.Conduit.List as CL
import Control.Concurrent.STM (atomically, TVar, newTVarIO, writeTVar, readTVar)
import Control.Monad.Trans.Resource (ResourceT, runResourceT)

main :: IO ()
main = hspec spec

delayedSource :: [(Int, a)] -> Source (ResourceT IO) a
delayedSource [] = return ()
delayedSource ((delay, item):rest) = do
  liftIO $ threadDelay delay
  yield item
  delayedSource rest

periodicSource :: Int -> [a] -> Source (ResourceT IO) a
periodicSource interval items = delayedSource $ zip (repeat interval) items

terminationDetector :: IO (TVar Bool, (ConduitM i o (ResourceT IO) r -> ConduitM i o (ResourceT IO) r))
terminationDetector = do
  terminated <- newTVarIO False
  return (terminated,
          addCleanup (\completed -> if not completed then liftIO $ atomically $ writeTVar terminated True else return () ) )

debSum :: Int -> Source (ResourceT IO) Int -> Source (ResourceT IO) Int
debSum delay = F.debounce F.Args { F.init = 0, F.fold = (+), F.cb = undefined } F.def { F.delay = delay }

debMonoid :: Monoid i => Int -> Source (ResourceT IO) i -> Source (ResourceT IO) i
debMonoid delay = F.debounce F.forMonoid F.def { F.delay = delay }

spec :: Spec
spec = do
  describe "debounce" $ do
    it "should fold inputs" $ do
      ret <- runResourceT $ debSum 500000 (periodicSource 10000 [1..10]) $$ CL.consume
      ret `shouldBe` [sum [1..10]]
    it "should debounce source" $ do
      let s = delayedSource [(1000, "a"), (1000, "b"), (200000, "c"), (1000, "d"), (1000, "e"), (200000, "f")]
      ret <- runResourceT $ debMonoid 100000 s $$ CL.consume
      ret `shouldBe` ["ab", "cde", "f"]
    it "should terminate debounced Source immediately if the original Source terminates immediately" $ do
      ret <- timeout 50000000 $ runResourceT $ debMonoid 60000000 (CL.sourceList ["A", "B", "C", "D", "E"]) $$ CL.consume
      ret `shouldBe` Just ["ABCDE"]
    it "should terminate the Sink for the original Source if the Sink for the debounced Source terminates" $ do
      (terminated, detector) <- terminationDetector
      let orig_source = detector $ periodicSource 10000 (repeat "a")
      ret <- runResourceT $ debMonoid 50000 orig_source $$ CL.take 4
      length ret `shouldBe` 4
      forM_ ret (`shouldContain` "aaa")
      threadDelay 20000
      atomically (readTVar terminated) `shouldReturn` True
    it "should terminate the debounced Source gracefully if the original Source throws exception" $ do
      let s = (periodicSource 1000 ["a", "b"]) >> error "Exception in origSource" >> (periodicSource 1000 ["c", "d"])
      ret <- runResourceT $ debMonoid 100000 s $$ CL.consume
      ret `shouldBe` ["ab"]
    it "should terminated the original Source gracefully if the Sink for debounced Source throws exception" $ do
      (terminated, detector) <- terminationDetector
      let orig_source = detector $ periodicSource 10000 (repeat "a")
          ret_sink = do
            taken <- CL.take 4
            _ <- error "Exception in retSink"
            return taken
      runResourceT (debMonoid 50000 orig_source $$ ret_sink) `shouldThrow` errorCall "Exception in retSink"
      threadDelay 20000
      atomically (readTVar terminated) `shouldReturn` True
