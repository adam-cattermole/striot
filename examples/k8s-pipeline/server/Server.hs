import System.IO
import System.IO.Unsafe (unsafeInterleaveIO)
import Data.List
import Data.List.Split
import Data.Maybe

import Striot.FunctionalProcessing
import Striot.FunctionalIoTtypes
import Striot.Nodes
import Taxi
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
fileName = "output-log.txt"


main :: IO ()
main = do
    chan <- newTChanIO
    writeFile fileName ""
    hdl <- openFile fileName WriteMode
    hSetBuffering hdl NoBuffering
    _ <- forkFinally (writeToFile hdl chan) (\_ -> hClose hdl)
    nodeSink streamGraphid (sinkToChan chan) listenPort


streamGraphid :: Stream ((UTCTime,UTCTime),[(Journey,Int)]) -> Stream ((UTCTime,UTCTime),[(Journey,Int)])
streamGraphid = streamMap Prelude.id


streamGraphFn :: Stream ((UTCTime,UTCTime),[(Journey,Int)]) -> Stream ((UTCTime,UTCTime),[(Journey,Int)])
streamGraphFn n1 = let
    n2 = (\s -> streamFilterAcc (\acc h -> if snd h == snd acc then acc else h) (fromJust (value (head s))) (\h acc -> snd h /= snd acc) (tail s)) n1
    in n2


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


mapTime :: Stream alpha -> IO (Stream (alpha, UTCTime))
mapTime (e@(Event eid t (Just v)):r) = unsafeInterleaveIO $ do
    x <- msg e v
    xs <- mapTime r
    return (x:xs)
  where
    msg x v = do
        now <- getCurrentTime
        return x { value = Just (v, now) }


hPutLines'' :: ToJSON alpha => Handle -> Stream alpha -> IO ()
hPutLines'' handle (x:xs) = do
    writable <- hIsWritable handle
    when writable $ do
        BLC.hPutStrLn handle (encode x)
        hFlush handle
        hPutLines'' handle xs
