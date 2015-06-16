-- |
-- Module: Data.Conduit.FoldDebounce
-- Description: Debounce conduit Source with Control.FoldDebounce
-- Maintainer: Toshio Ito <debug.ito@gmail.com>
-- 
module Data.Conduit.FoldDebounce (
  
) where

import Prelude hiding (init)
import Control.Applicative (Applicative)
import Control.Monad (void)

import Control.FoldDebounce (Args(Args,cb,fold,init),
                             Opts, delay, alwaysResetTimer, def)
import Data.Conduit (Source, Sink, await, yield, ($$))
import Control.Monad.Base (MonadBase)
import Control.Monad.Trans.Resource (MonadBaseControl, MonadThrow, 
                                     allocate, register, resourceForkIO, runResourceT)
import Control.Monad.Trans.Class (lift)
import Control.Monad.IO.Class (MonadIO, liftIO)
import Control.Concurrent.STM (newTChanIO, writeTChan, readTChan, atomically)

import Control.Concurrent (threadDelay)
import qualified Data.Conduit.List as CL

-- | 
debounceSource :: (MonadThrow m, MonadBase IO m, MonadIO m, Applicative m, MonadBaseControl IO m)
                  => Args i o -- ^ mandatory argument for FoldDebounce
                  -> Opts i o -- ^ optional argument for FoldDebounce
                  -> Source m i -- ^ original 'Source'
                  -> Source m o -- ^ debounced 'Source'
debounceSource = undefined

