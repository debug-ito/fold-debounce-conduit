-- |
-- Module: Data.Conduit.FoldDebounce
-- Description: Debounce conduit Source with Control.FoldDebounce
-- Maintainer: Toshio Ito <debug.ito@gmail.com>
-- 
module Data.Conduit.FoldDebounce (
  debounceSource,
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

import Control.Concurrent (threadDelay)
import qualified Data.Conduit.List as CL

-- | Debounce conduit 'Source' with "Control.FoldDebounce". The data
-- stream from the original 'Source' (type @i@) is debounced and
-- folded into the data stream of the type @o@.
debounceSource :: (MonadThrow m, MonadBase IO m, MonadIO m, Applicative m, MonadBaseControl IO m)
                  => Args i o -- ^ mandatory argument for
                              -- FoldDebounce. 'cb' field is ignored,
                              -- so you can set anything to that.
                  -> Opts i o -- ^ optional argument for FoldDebounce
                  -> Source m i -- ^ original 'Source'
                  -> Source m o -- ^ debounced 'Source'
debounceSource = undefined

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
