{-# LANGUAGE FlexibleContexts #-}

-- node3
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

streamGraphFn :: Stream (UTCTime, Trip) -> Stream (UTCTime, Trip)
streamGraphFn = id


-- streamGraphFnM :: (MonadState s m,
--                   HasStriotState s ((UTCTime, UTCTime), [(Journey, Int)]),
--                   MonadIO m,
--                   MonadBaseControl IO m)
--                => Stream Trip -> m (Stream ((UTCTime, UTCTime), [(Journey, Int)]))
-- streamGraphFnM s = journeyChangesM
--                  $ streamMap (\w -> (let lj = last w in (pickupTime lj, dropoffTime lj), topk 10 w))
--                  $ streamWindow (slidingTime 1800000)
--                  $ streamFilter (\j -> inRangeQ1 (start j) && inRangeQ1 (end j))
--                  $ streamMap    tripToJourney s


-- streamGraphFnM :: (MonadState s m,
--                   HasStriotState s (Stream [Journey]),
--                   MonadIO m,
--                   MonadBaseControl IO m)
--                => Stream Trip -> m ([Stream [Journey]])
--                => Stream Trip -> m (Stream ((UTCTime, UTCTime), [(Journey, Int)]))


-- streamGraphFnM :: (MonadState s m,
--                    HasStriotState s (Stream (UTCTime, Journey)),
--                    MonadIO m,
--                    MonadBaseControl IO m)
--                => Stream (UTCTime, Trip) -> m (Stream [(UTCTime, Journey)])
-- streamGraphFnM = streamWindowM (slidingTimeM 1800000)
--                <$> streamFilter (\(t,j) -> inRangeQ1 (start j) && inRangeQ1 (end j))
--                <$> streamMap (\(t,v) -> (t, tripToJourney v))
-- streamMap (\w -> (let lj = last w in (pickupTime lj, dropoffTime lj), topk 10 w))

streamGraphFnM' :: (MonadState s m,
                   HasStriotState s (Stream (UTCTime, Journey)),
                   MonadIO m,
                   MonadBaseControl IO m)
               => Stream (UTCTime, Journey) -> m (Stream (UTCTime, (UTCTime, UTCTime), [(Journey, Int)]))
streamGraphFnM' s = streamMap (windowTopk)
                 <$> streamWindowM (slidingTimeM 180000) s
                 -- 1800000 = 30m


-- journeyChangesM :: (MonadState s m,
--                    HasStriotState s ((UTCTime, UTCTime),[(Journey, Int)]),
--                    MonadIO m,
--                    MonadBaseControl IO m)
--                 => Stream ((UTCTime, UTCTime),[(Journey, Int)]) -> m (Stream ((UTCTime, UTCTime),[(Journey, Int)]))
-- -- journeyChangesM :: (MonadState s m, HasStriotState s (a, b), MonadIO m, MonadBaseControl IO m, Eq b) => Stream (a, b) -> m (Stream (a, b))
-- journeyChangesM (Event _ _ _ (Just val):r) = streamFilterAccM (\acc h -> if snd h == snd acc then acc else h) val (\h acc -> snd h /= snd acc) r


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
        Right c -> nodeLinkStateful c streamGraphFnM'
