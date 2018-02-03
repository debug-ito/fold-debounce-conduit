module Main (main) where

import Data.Conduit (ConduitT, yield, runConduit, (.|))
import qualified Data.Conduit.List as CL
import Data.Void (Void)
import Control.Concurrent (threadDelay)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Resource (ResourceT, runResourceT)

import qualified Data.Conduit.FoldDebounce as F

fastSource :: Int -> ConduitT () Int (ResourceT IO) ()
fastSource max_num = fastStream' 0 where
  fastStream' count = do
    yield count
    if count >= max_num
      then return ()
      else do
        liftIO $ threadDelay 100000
        fastStream' (count + 1)

printSink :: Show a => ConduitT a Void (ResourceT IO) ()
printSink = CL.mapM_ (liftIO . putStrLn . show)

main :: IO ()
main = do
  putStrLn "-- Before debounce"
  runResourceT $ runConduit $ fastSource 10 .| printSink
  let debouncer = F.debounce F.Args { F.cb = undefined, -- anything will do
                                      F.fold = (\list num -> list ++ [num]),
                                      F.init = [] }
                             F.def { F.delay = 500000 }
  putStrLn "-- After debounce"
  runResourceT $ runConduit $ debouncer (fastSource 10) .| printSink
