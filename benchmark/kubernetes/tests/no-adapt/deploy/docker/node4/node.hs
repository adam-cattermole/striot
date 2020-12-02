{-# LANGUAGE FlexibleContexts #-}
-- node4
import Striot.FunctionalIoTtypes
import Striot.FunctionalProcessing
import Striot.Nodes
import Control.Concurrent
import System.IO
import Taxi
import Data.Time
import Control.Exception (bracket)
import Control.Monad (forever)


sink1 :: Show a => Stream a -> IO ()
sink1 s = do
    now <- getCurrentTime
    let fileName = "data/no-adapt_" ++ (formatTime defaultTimeLocale "%d-%m-%Y_%H%M%S" now) ++ ".txt"
    hdl <- openFile fileName WriteMode
    hSetBuffering hdl NoBuffering
    mapM_ (hPutStrLn hdl . show) s


sinkLatencyFile :: Stream (UTCTime, (UTCTime, UTCTime), [(Journey, Int)]) -> IO ()
sinkLatencyFile stream = do
    now <- getCurrentTime
    let fileName = "output/no-adapt_" ++ (formatTime defaultTimeLocale "%d-%m-%Y_%H%M%S" now) ++ ".txt"
    sinkLatencyFile' fileName stream
    -- hdl <- openFile fileName WriteMode
    -- hSetBuffering hdl NoBuffering
    -- mapM_ (\event -> do
    --     diff <- getLatency event
    --     hPutStrLn hdl . show $ diff
    --     ) stream

sinkLatencyFile' :: String -> Stream (UTCTime, (UTCTime, UTCTime), [(Journey, Int)]) -> IO ()
sinkLatencyFile' fileName stream = forever $ do
    bracket
        (do
            hdl <- openFile fileName WriteMode
            hSetBuffering hdl NoBuffering
            return hdl)
        (hClose)
        (\hdl -> do
            mapM_ (\event -> do
                diff <- getLatency event
                hPutStrLn hdl . show $ diff
                ) stream)

sinkLatency :: Stream (UTCTime, (UTCTime, UTCTime), [(Journey, Int)]) -> IO ()
sinkLatency =
    mapM_ (\event -> do
        diff <- getLatency event
        print diff)

getLatency :: Event (UTCTime, (UTCTime, UTCTime), [(Journey, Int)]) -> IO (UTCTime, NominalDiffTime)
getLatency (Event _ _ _ (Just (t,_,_))) = do
    now <- getCurrentTime
    return (now, diffUTCTime now t)


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


