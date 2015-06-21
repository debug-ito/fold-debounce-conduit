module Main (main) where

import Data.Conduit (Source, Sink, yield, await, ($$), (=$))
import qualified Data.Conduit.List as CL
import Control.Concurrent (threadDelay)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Resource (ResourceT, runResourceT)

import qualified Data.Conduit.FoldDebounce as F

fastSource :: Source (ResourceT IO) Int
fastSource = fastStream' 0 where
  fastStream' count = do
    yield count
    liftIO $ threadDelay 100000
    fastStream' (count + 1)

printSink :: Int -> Sink Int (ResourceT IO) ()
printSink num = CL.isolate num =$ CL.mapM_ (liftIO . putStrLn . show)

main :: IO ()
main = do
  putStrLn "-- Before debounce"
  runResourceT $ fastSource $$ printSink 20
  let debouncer = F.debounce F.Args { F.cb = undefined, -- not used
                                      F.fold = (+),
                                      F.init = 0 }
                             F.def { F.delay = 500000 }
  putStrLn "-- After debounce"
  runResourceT $ debouncer fastSource $$ printSink 20
