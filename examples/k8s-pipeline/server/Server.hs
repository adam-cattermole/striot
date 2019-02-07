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


listenPort = 9001 :: Int
fileName = "output-log.txt"


main :: IO ()
main = do
    chan <- newTChanIO
    writeFile fileName ""
    hdl <- openFile fileName WriteMode
    hSetBuffering hdl NoBuffering
    _ <- forkFinally (writeToFile hdl chan) (\_ -> hClose hdl)
    nodeSink streamGraphFn (sinkToChan chan) listenPort


type OrderAcc alpha = (Int, [alpha], [(Int, alpha)])

-- orderEvents takes a stream of events consisting of a sequence number and data (alpha)
--- and orders the events according to the sequence number, also removing that number.
--- It can be used to order a stream of events that have been spread across a set of nodes
--- for parallel processing (e.g. of map and filter operators)

orderEvents:: Stream (Int, alpha) -> Stream alpha
orderEvents s = streamExpand                             $
                streamMap    (\(_,payload,_) -> payload) $
                streamScan   orderIps (0,[],[])          s -- issue: throws away timestamps --- does that matter?

-- inserts a sequence number + data pair into a list of such pairs so as to maintain the order of the list
insertInto:: (Int, alpha) -> [(Int, alpha)] -> [(Int, alpha)]
insertInto (i,v) []                        = [(i,v)]
insertInto (i,v) acc@((k,w):u) | i<k       = (i,v):acc
                               | otherwise = (k,w):insertInto (i,v) u

-- orderIps takes a tuple (nextSequence number in the order, list of data to be emitted in events, ordered list of sequence numbers and data)
--- and the contents of the next event (with its sequence number)
orderIps:: OrderAcc alpha -> (Int, alpha) -> OrderAcc alpha
orderIps (nextSeqNumber,_,results) e@(s,val) | s == nextSeqNumber   = let (newSeqNumber,restOfSequence,remainingResults) = processResults (s+1) [] results in (newSeqNumber,val:restOfSequence,remainingResults)
                                             | otherwise            = (nextSeqNumber,[],insertInto e results)

processResults:: Int -> [alpha] -> [(Int, alpha)] -> OrderAcc alpha -- Sequence number -> results waiting to be sent out -> results waiting in ordered list until their sequence number is next
                                                                                --  -> (next sequence number,results to be sent out, results waiting in ordered list)
processResults nextSeq restOfSeq []                          = (nextSeq,restOfSeq,[])
processResults nextSeq restOfSeq res@((j,k):r)  | nextSeq == j = processResults (nextSeq+1) (restOfSeq++[k]) r
                                                | otherwise    = (nextSeq,restOfSeq,res)


streamGraphid :: Stream ((UTCTime,UTCTime),[(Journey,Int)]) -> Stream ((UTCTime,UTCTime),[(Journey,Int)])
streamGraphid = streamMap Prelude.id


streamGraphFn :: Stream (Int,((UTCTime,UTCTime),[(Journey,Int)])) -> Stream ((UTCTime,UTCTime),[(Journey,Int)])
streamGraphFn n1 = let
    n2 = orderEvents n1
    n3 = (\s -> streamFilterAcc (\acc h -> if snd h == snd acc then acc else h) (fromJust (value (head s))) (\h acc -> snd h /= snd acc) (tail s)) n2
    in n3


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
