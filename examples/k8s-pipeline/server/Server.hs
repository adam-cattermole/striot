{-# LANGUAGE FlexibleContexts #-}
import System.IO
import System.IO.Unsafe (unsafeInterleaveIO)
import Data.List

import Striot.FunctionalProcessing
import Striot.FunctionalIoTtypes
import Striot.Nodes
import Network.Socket (ServiceName)

import Data.Time (getCurrentTime)
import Data.Time.Clock (UTCTime)
import qualified Data.ByteString.Lazy.Char8 as BLC (hPutStrLn)
import Data.Aeson
import qualified Data.Text as T
import Control.Monad (when)
import Control.Concurrent
import Control.Concurrent.STM

listenPort = "9001" :: ServiceName
fileName = "sw-log.txt"


main :: IO ()
main = do
    chan <- newTChanIO
    writeFile fileName ""
    hdl <- openFile fileName WriteMode
    hSetBuffering hdl NoBuffering
    _ <- forkFinally (writeToFile hdl chan) (\_ -> hClose hdl)
    nodeSink streamGraphid (sinkToChan chan) listenPort
    -- nodeSink streamGraphid printStream listenPort


streamGraphid :: Stream T.Text -> Stream T.Text
streamGraphid = streamMap (\x -> Prelude.id x)


sinkToChan :: (ToJSON alpha) => TChan (Event (alpha, UTCTime)) -> Stream alpha -> IO ()
sinkToChan chan stream = do
    out <- mapTime stream
    mapM_ (writeEvent chan) out
  where
      writeEvent chan x = atomically $ writeTChan chan x


writeToFile :: (ToJSON alpha) => Handle -> TChan (Event (alpha, UTCTime)) -> IO ()
writeToFile hdl chan = do
    stream <- readEventsTChan chan
    hPutLines'' hdl stream


readEventsTChan :: ToJSON alpha => TChan (Event (alpha, UTCTime)) -> IO (Stream (alpha, UTCTime))
readEventsTChan eventChan = System.IO.Unsafe.unsafeInterleaveIO $ do
    x <- atomically $ readTChan eventChan
    xs <- readEventsTChan eventChan
    return (x : xs)


-- printStreamDelay :: (ToJSON alpha, Show alpha) => Stream alpha -> IO ()
-- printStreamDelay stream = do
--     hdl <- openFile fileName WriteMode
--     hSetBuffering hdl NoBuffering
--     output <- mapTime stream
--     hPutLines'' hdl output


mapTime :: Stream alpha -> IO (Stream (alpha, UTCTime))
mapTime (e@(E id t v):r) = unsafeInterleaveIO $ do
    x <- msg e v
    xs <- mapTime r
    return (x:xs)
  where
    msg x v = do
        now <- getCurrentTime
        return x { value = (v, now) }


hPutLines'' :: ToJSON (Event alpha) => Handle -> Stream alpha -> IO ()
hPutLines'' handle (x:xs) = do
    writable <- hIsWritable handle
    when writable $ do
        BLC.hPutStrLn handle (encode x)
        hFlush handle
        hPutLines'' handle xs