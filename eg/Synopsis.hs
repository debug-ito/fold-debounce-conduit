module Main (main) where

import Data.Conduit (Source, Sink, yield, await, ($$))
import Control.Concurrent (threadDelay)
import Control.Monad.IO.Class (liftIO)

import qualified Data.Conduit.FoldDebounce as F

fastSource :: Source IO Int
fastSource = fastStream' 0 where
  fastStream' count = do
    yield count
    liftIO $ threadDelay 100000
    fastStream' (count + 1)

printSink :: Int -> Sink Int IO ()
printSink end_count = do
  mgot <- await
  case mgot of
    Nothing -> return ()
    Just got -> do
      liftIO $ putStrLn (show got)
      if got >= end_count
        then return ()
        else printSink end_count

main :: IO ()
main = do
  fastSource $$ printSink 20
  let debouncer = F.debounce F.Args { F.cb = undefined, -- not used
                                      F.fold = (+),
                                      F.init = 0 }
                             F.def { F.delay = 500000 }
  debouncer fastSource $$ printSink 20
