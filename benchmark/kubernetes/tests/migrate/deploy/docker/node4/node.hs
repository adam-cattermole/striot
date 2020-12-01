{-# LANGUAGE FlexibleContexts #-}
-- node4
import Striot.FunctionalIoTtypes
import Striot.FunctionalProcessing
import Striot.Nodes
import Control.Concurrent
import System.IO
import Taxi
import Data.Time                   (getCurrentTime, diffUTCTime, UTCTime (..), NominalDiffTime (..))


sink1 :: Show a => Stream a -> IO ()
sink1 s = do
    hdl <- openFile  "output.txt" WriteMode
    hSetBuffering hdl NoBuffering
    mapM_ (hPutStrLn hdl . show) s


sinkLatencyFile :: Stream (UTCTime, (UTCTime, UTCTime), [(Journey, Int)]) -> IO ()
sinkLatencyFile stream = do
    hdl <- openFile  "output.txt" WriteMode
    hSetBuffering hdl NoBuffering
    mapM_ (\event -> do
        diff <- getLatency event
        hPutStrLn hdl . show $ diff
        ) stream

sinkLatency :: Stream (UTCTime, (UTCTime, UTCTime), [(Journey, Int)]) -> IO ()
sinkLatency =
    mapM_ (\event -> do
        diff <- getLatency event
        print diff)

getLatency :: Event (UTCTime, (UTCTime, UTCTime), [(Journey, Int)]) -> IO NominalDiffTime
getLatency (Event _ _ _ (Just (t,_,_))) = do
    (diffUTCTime <$> getCurrentTime) <*> pure t


sink2 :: Show a => Stream a -> IO ()
sink2 = mapM_ print



streamGraphFn :: Stream (UTCTime, (UTCTime, UTCTime), [(Journey, Int)]) -> Stream (UTCTime, (UTCTime, UTCTime), [(Journey, Int)])
streamGraphFn = id

-- streamGraphLatency :: Stream (UTCTime, (UTCTime, UTCTime), [(Journey, Int)]) -> Stream NominalDiffTime
-- streamGraphLatency stream = do
--     streamMap (\(t,_,_) -> do
--         now <- getCurrentTime
--         let diff = diffUTCTime now t
--         return diff
--         ) stream


streamGraphFn' :: Stream (UTCTime, Trip) -> Stream (UTCTime, Trip)
streamGraphFn' = id


-- journeyChangesM :: (MonadState s m,
--                    HasStriotState s ((UTCTime, UTCTime),[(Journey, Int)]),
--                    MonadIO m,
--                    MonadBaseControl IO m)
--                 => Stream ((UTCTime, UTCTime),[(Journey, Int)]) -> m (Stream ((UTCTime, UTCTime),[(Journey, Int)]))
-- journeyChangesM :: (MonadState s m, HasStriotState s (a, b), MonadIO m, MonadBaseControl IO m, Eq b) => Stream (a, b) -> m (Stream (a, b))

journeyChanges (Event _ _ _ (Just val):r) = streamFilterAccM (\acc h -> if snd h == snd acc then acc else h) val (\h acc -> snd h /= snd acc) r

main :: IO ()
main = nodeSink (defaultSink "9001") streamGraphFn sinkLatencyFile


