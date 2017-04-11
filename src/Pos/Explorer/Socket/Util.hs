module Pos.Explorer.Socket.Util
    ( EventName (..)
    , emit
    , emitJSON
    , emitTo
    , emitJSONTo
    , on_
    , on

    , runPeriodicallyUnless
    , forkAccompanion
    ) where

import qualified Control.Concurrent.STM      as STM
import           Control.Concurrent.STM.TVar (readTVarIO, writeTVar)
import           Control.Monad.Catch         (MonadCatch)
import           Control.Monad.Reader        (MonadReader)
import           Control.Monad.State         (MonadState)
import           Control.Monad.Trans         (MonadIO)
import           Data.Aeson.Types            (Array, FromJSON, ToJSON)
import           Data.Text                   (Text)
import           Data.Time.Units             (TimeUnit (..))
import           Formatting                  (sformat, shown, (%))

import           Mockable                    (Fork, Mockable, fork)
import qualified Network.SocketIO            as S
import           Serokell.Util.Concurrent    (threadDelay)
import           Snap.Core                   (Snap)
import           System.Wlog                 (CanLog (..), WithLogger, logWarning)
import           Universum                   hiding (on)

-- * Provides type-safity for event names in some socket-io functions.

class EventName a where
    toName :: a -> Text

-- ** Socket-io functions which works with `EventName name` rather than
-- with plain `Text`.

emit
    :: (ToJSON event, EventName name, MonadReader S.Socket m, MonadIO m)
    => name -> event -> m ()
emit eventName =
    S.emit $ toName eventName
    -- logDebug . sformat ("emit "%stext) $ toName eventName

emitTo
    :: (ToJSON event, EventName name, MonadIO m)
    => S.Socket -> name -> event -> m ()
emitTo sock eventName = S.emitTo sock (toName eventName)

emitJSON
    :: (EventName name, MonadReader S.Socket m, MonadIO m)
    => name -> Array -> m ()
emitJSON eventName = S.emitJSON (toName eventName)

emitJSONTo
    :: (EventName name, MonadIO m)
    => S.Socket -> name -> Array -> m ()
emitJSONTo sock eventName = S.emitJSONTo sock (toName eventName)

on_ :: (MonadState S.RoutingTable m, EventName name)
    => name -> S.EventHandler a -> m ()
on_ eventName = S.on (toName eventName)

on :: (MonadState S.RoutingTable m, FromJSON event, EventName name)
   => name -> (event -> S.EventHandler a) -> m ()
on eventName = S.on (toName eventName)

-- * Instances

instance CanLog Snap where
    dispatchMessage logName sev msg = liftIO $ dispatchMessage logName sev msg

-- * Misc

-- | Runs an action periodically.
-- It's provided with a flag whether repetition should be stopped.
-- Action is launched with state. If action fails, state remains unmodified.
runPeriodicallyUnless
    :: (MonadIO m, MonadCatch m, WithLogger m, TimeUnit t)
    => t -> m Bool -> s -> StateT s m () -> m ()
runPeriodicallyUnless delay stop initState action =
    let loop st = unlessM stop $ do
            st' <- execStateT action st
                `catchAll` \e -> handler e $> st
            threadDelay delay
            loop st'
    in  loop initState
  where
    handler = logWarning . sformat ("Periodic action failed: "%shown)

-- | Fork a side action.
-- It's given a flag, whether main action has completed.
forkAccompanion
    :: (MonadIO m, MonadMask m, Mockable Fork m)
    => (m Bool -> m ()) -> m a -> m a
forkAccompanion accompanion main = do
    stopped <- liftIO $ STM.newTVarIO False
    let whetherStopped = liftIO $ readTVarIO stopped
    bracket_ (fork $ accompanion whetherStopped)
             (atomically $ writeTVar stopped True)
             main