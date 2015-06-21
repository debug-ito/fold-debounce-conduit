-- |
-- Module: Data.Conduit.FoldDebounce
-- Description: Regulate input traffic from conduit Source with Control.FoldDebounce
-- Maintainer: Toshio Ito <debug.ito@gmail.com>
-- 
-- Synopsis:
--
-- > module Main (main) where
-- > 
-- > import Data.Conduit (Source, Sink, yield, ($$))
-- > import qualified Data.Conduit.List as CL
-- > import Control.Concurrent (threadDelay)
-- > import Control.Monad.IO.Class (liftIO)
-- > import Control.Monad.Trans.Resource (ResourceT, runResourceT)
-- > 
-- > import qualified Data.Conduit.FoldDebounce as F
-- > 
-- > fastSource :: Int -> Source (ResourceT IO) Int
-- > fastSource max_num = fastStream' 0 where
-- >   fastStream' count = do
-- >     yield count
-- >     if count >= max_num
-- >       then return ()
-- >       else do
-- >         liftIO $ threadDelay 100000
-- >         fastStream' (count + 1)
-- > 
-- > printSink :: Show a => Sink a (ResourceT IO) ()
-- > printSink = CL.mapM_ (liftIO . putStrLn . show)
-- > 
-- > main :: IO ()
-- > main = do
-- >   putStrLn "-- Before debounce"
-- >   runResourceT $ fastSource 10 $$ printSink
-- >   let debouncer = F.debounce F.Args { F.cb = undefined, -- anything will do
-- >                                       F.fold = (\list num -> list ++ [num]),
-- >                                       F.init = [] }
-- >                              F.def { F.delay = 500000 }
-- >   putStrLn "-- After debounce"
-- >   runResourceT $ debouncer (fastSource 10) $$ printSink
--
-- Result:
--
-- > -- Before debounce
-- > 0
-- > 1
-- > 2
-- > 3
-- > 4
-- > 5
-- > 6
-- > 7
-- > 8
-- > 9
-- > 10
-- > -- After debounce
-- > [0,1,2,3,4]
-- > [5,6,7,8,9]
-- > [10]
--
-- This module regulates (slows down) data stream from conduit
-- 'Source' using "Control.FoldDebounce".
--
-- The data from the original 'Source' (type @i@) are pulled and
-- folded together to create an output data (type @o@). The output
-- data then comes out of the debounced 'Source' in a predefined
-- interval (specified by 'alwaysResetTimer' option).
--
-- See "Control.FoldDebounce" for detail.
module Data.Conduit.FoldDebounce (
  debounce,
  -- * Re-exports
  Args(..),
  Opts,
  -- ** Accessors for 'Opts'
  delay,
  alwaysResetTimer,
  def,
  -- * Preset parameters
  forStack, forMonoid, forVoid
) where

import Prelude hiding (init)
import Control.Monad (void)
import Data.Monoid (Monoid)

import Control.FoldDebounce (Args(Args,cb,fold,init),
                             Opts, delay, alwaysResetTimer, def)
import qualified Control.FoldDebounce as F
import Data.Conduit (Source, Sink, await, yieldOr, ($$))
import Control.Monad.Trans.Resource (MonadResource, MonadBaseControl,
                                     allocate, register, release, resourceForkIO, runResourceT)
import Control.Monad.Trans.Class (lift)
import Control.Monad.IO.Class (MonadIO, liftIO)
import Control.Concurrent.STM (newTChanIO, writeTChan, readTChan,
                               atomically,
                               TVar, readTVar, newTVarIO, writeTVar)

-- | Debounce conduit 'Source' with "Control.FoldDebounce". The data
-- stream from the original 'Source' (type @i@) is debounced and
-- folded into the data stream of the type @o@.
--
-- Note that the original 'Source' is connected to a 'Sink' in another
-- thread. You may need some synchronization if the original 'Source'
-- has side-effects.
debounce :: (MonadResource m, MonadBaseControl IO m)
            => Args i o -- ^ mandatory argument for FoldDebounce. 'cb'
                        -- field is ignored, so you can set anything
                        -- to that.
            -> Opts i o -- ^ optional argument for FoldDebounce
            -> Source m i -- ^ original 'Source'
            -> Source m o -- ^ debounced 'Source'
debounce args opts src = do
  out_chan <- liftIO $ newTChanIO
  (out_termed_key, out_termed) <- allocate (liftIO $ newTVarIO False) (liftIO . atomically . flip writeTVar True)
  let retSource = do
        mgot <- liftIO $ atomically $ readTChan out_chan
        case mgot of
          OutFinished -> return ()
          OutData got -> yieldOr got (release out_termed_key) >> retSource
  lift $ runResourceT $ do
    void $ register $ atomically $ writeTChan out_chan OutFinished
    (_, trig) <- allocate (F.new args { F.cb = atomically . writeTChan out_chan . OutData }
                                 opts)
                          (F.close)
    void $ resourceForkIO $ lift (src $$ trigSink trig out_termed)
  retSource

-- | Internal data type for output channel.
data OutData o = OutData o
               | OutFinished

trigSink :: (MonadIO m) => F.Trigger i o -> TVar Bool -> Sink i m ()
trigSink trig out_termed = trigSink' where
  trigSink' = do
    mgot <- await
    termed <- liftIO $ atomically $ readTVar out_termed
    case (termed, mgot) of
      (True, _) -> return ()
      (False, Nothing) -> return ()
      (False, Just got) -> do
        liftIO $ F.send trig got
        trigSink'


-- | 'Args' for stacks. Input events are accumulated in a stack, i.e.,
-- the last event is at the head of the list.
forStack :: Args i [i]
forStack = F.forStack undefined

-- | 'Args' for monoids. Input events are appended to the tail.
forMonoid :: Monoid i => Args i i
forMonoid = F.forMonoid undefined

-- | 'Args' that discards input events. The data stream from the
-- debounced 'Source' indicates the presence of data from the original
-- 'Source'.
forVoid :: Args i ()
forVoid = F.forVoid undefined
