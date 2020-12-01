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
import           Taxi
import           Data.Time                   (UTCTime (..))


-- streamGraphFnM :: (MonadState s m,
--                   HasStriotState s Int,
--                   MonadIO m,
--                   MonadBaseControl IO m)
--                => Stream Int -> m (Stream Int)
-- streamGraphFnM = streamScanM (\acc _ -> (+5) acc) (-1)
-- -- (-1) matches the IDs of the messages
-- -- setting to 0 shows an actual counter of how many messages we received (assuming succ)


-- streamGraphFnM' :: (MonadState s m,
--                   HasStriotState s (Stream Int),
--                   MonadIO m,
--                   MonadBaseControl IO m)
--                => Stream Int -> m (Stream [Int])
-- streamGraphFnM' = streamWindowM (slidingTimeM 12000)
--                 <$> streamFilter (>3)
--                 <$> streamMap id

-- streamGraphFn :: Stream (UTCTime, Trip) -> Stream (UTCTime, Trip)
-- streamGraphFn = id

streamGraphFn :: Stream (UTCTime, Trip) -> Stream (UTCTime, Journey)
streamGraphFn s = streamFilter (\(t,j) -> inRangeQ1 (start j) && inRangeQ1 (end j))
                $ streamMap (\(t,v) -> (t, tripToJourney v)) s


main :: IO ()
main = do
    conf <- decodeEnv :: IO (Either String StriotConfig)
    case conf of
        Left _  -> print "Could not read from env"
        Right c -> nodeLink c streamGraphFn
