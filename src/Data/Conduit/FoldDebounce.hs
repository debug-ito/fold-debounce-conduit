-- |
-- Module: Data.Conduit.FoldDebounce
-- Description: Regulate input traffic from conduit Source with Control.FoldDebounce
-- Maintainer: Toshio Ito <debug.ito@gmail.com>
-- 
-- Synopsis:
--
-- > TODO
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
import Control.Applicative (Applicative)
import Control.Monad (void)
import Data.Monoid (Monoid)

import Control.FoldDebounce (Args(Args,cb,fold,init),
                             Opts, delay, alwaysResetTimer, def)
import qualified Control.FoldDebounce as F
import Data.Conduit (Source, Sink, await, yield, ($$))
import Control.Monad.Base (MonadBase)
import Control.Monad.Trans.Resource (MonadBaseControl, MonadThrow, 
                                     allocate, register, resourceForkIO, runResourceT)
import Control.Monad.Trans.Class (lift)
import Control.Monad.IO.Class (MonadIO, liftIO)
import Control.Concurrent.STM (newTChanIO, writeTChan, readTChan, atomically)

-- | Debounce conduit 'Source' with "Control.FoldDebounce". The data
-- stream from the original 'Source' (type @i@) is debounced and
-- folded into the data stream of the type @o@.
debounce :: (MonadThrow m, MonadBase IO m, MonadIO m, Applicative m, MonadBaseControl IO m)
            => Args i o -- ^ mandatory argument for FoldDebounce. 'cb'
                        -- field is ignored, so you can set anything
                        -- to that.
            -> Opts i o -- ^ optional argument for FoldDebounce
            -> Source m i -- ^ original 'Source'
            -> Source m o -- ^ debounced 'Source'
debounce args opts src = do
  out_chan <- liftIO $ newTChanIO
  let retSource = do
        mgot <- liftIO $ atomically $ readTChan out_chan
        case mgot of
          OutFinished -> return ()
          OutData got -> yield got >> retSource
  lift $ runResourceT $ do
    void $ register $ atomically $ writeTChan out_chan OutFinished
    (_, trig) <- allocate (F.new args { F.cb = atomically . writeTChan out_chan . OutData }
                                 opts)
                          (F.close)
    void $ resourceForkIO $ lift (src $$ trigSink trig)
  retSource

-- | Internal data type for output channel.
data OutData o = OutData o
               | OutFinished

trigSink :: (MonadIO m) => F.Trigger i o -> Sink i m ()
trigSink trig = trigSink' where
  trigSink' = do
    mgot <- await
    case mgot of
      Nothing -> return ()
      Just got -> do
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
