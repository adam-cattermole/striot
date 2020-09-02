{-# LANGUAGE FlexibleContexts #-}

-- node2
import           Control.Concurrent
import           Control.Monad.State
import           Control.Monad.Trans.Control
import           Striot.FunctionalIoTtypes
import           Striot.FunctionalProcessing
import           Striot.Nodes
import           Striot.Nodes.Types
import           System.Envy


streamGraphFnM :: (MonadState s m,
                  HasStriotState s Int,
                  MonadIO m,
                  MonadBaseControl IO m)
               => Stream String -> m (Stream Int)
streamGraphFnM = streamScanM (\acc _ -> (+5) acc) (-1)
-- streamGraphFnM = streamWindowM chopM 10
-- (-1) matches the IDs of the messages
-- setting to 0 shows an actual counter of how many messages we received (assuming succ)




main :: IO ()
main = do
    conf <- decodeEnv :: IO (Either String StriotConfig)
    case conf of
        Left _  -> print "Could not read from env"
        Right c -> nodeLinkStateful c streamGraphFnM
