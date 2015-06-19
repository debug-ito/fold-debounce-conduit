module Data.Conduit.FoldDebounceSpec (main, spec) where

import Test.Hspec

import Data.Monoid (Monoid)
import Control.Concurrent (threadDelay)
import qualified Data.Conduit.FoldDebounce as F
import Data.Conduit (Source, ($$), yield)
import Control.Monad.IO.Class (liftIO)
import qualified Data.Conduit.List as CL

main :: IO ()
main = hspec spec

delayedSource :: [(Int, a)] -> Source IO a
delayedSource [] = return ()
delayedSource ((delay, item):rest) = do
  liftIO $ threadDelay delay
  yield item
  delayedSource rest

periodicSource :: Int -> [a] -> Source IO a
periodicSource interval items = delayedSource $ zip (repeat interval) items

debSum :: Int -> Source IO Int -> Source IO Int
debSum delay = F.debounce F.Args { F.init = 0, F.fold = (+), F.cb = undefined } F.def { F.delay = delay }

debMonoid :: Monoid i => Int -> Source IO i -> Source IO i
debMonoid delay = F.debounce F.forMonoid F.def { F.delay = delay }

spec :: Spec
spec = do
  describe "debounce" $ do
    it "should fold inputs" $ do
      ret <- debSum 500000 (periodicSource 10000 [1..10]) $$ CL.consume
      ret `shouldBe` [sum [1..10]]
    it "should debounce source" $ do
      let s = delayedSource [(1000, "a"), (1000, "b"), (200000, "c"), (1000, "d"), (1000, "e")]
      ret <- debMonoid 100000 s $$ CL.consume
      ret `shouldBe` ["ab", "cde"]
