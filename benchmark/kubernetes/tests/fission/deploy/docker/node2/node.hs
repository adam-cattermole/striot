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


-- streamGraphFn :: Stream (UTCTime, Trip) -> Stream (UTCTime, Trip)
-- streamGraphFn = id

streamGraphFn :: Stream (UTCTime, Trip) -> Stream (UTCTime, Journey)
streamGraphFn s = streamFilter (\(t,j) -> inRangeQ1 (start j) && inRangeQ1 (end j))
                $ streamMap (\(t,v) -> (t, tripToJourney v)) s


streamGraphFnM :: (MonadState s m,
                   HasStriotState s (Stream (UTCTime, Journey)),
                   MonadIO m,
                   MonadBaseControl IO m)
               => Stream (UTCTime, Trip) -> m (Stream (UTCTime, (UTCTime, UTCTime), [(Journey, Int)]))
streamGraphFnM s = streamMap (windowTopk)
                <$> (streamWindowM (slidingTimeM 180000)
                 $ streamFilter (\(t,j) -> inRangeQ1 (start j) && inRangeQ1 (end j))
                 $ streamMap (\(t,v) -> (t, tripToJourney v)) s)

windowTopk :: [(UTCTime, Journey)] -> (UTCTime, (UTCTime, UTCTime), [(Journey, Int)])
windowTopk win =
    let (t, j)   = unzip win
        (lt, lj) = last win
    in  (lt, (pickupTime lj, dropoffTime lj), topk 10 j)


main :: IO ()
main = do
    conf <- decodeEnv :: IO (Either String StriotConfig)
    case conf of
        Left _  -> print "Could not read from env"
        Right c -> nodeLinkStateful c streamGraphFnM