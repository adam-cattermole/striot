import           Conduit
import           Control.Concurrent.Async    (async)
import           Control.Concurrent.STM
import           Control.DeepSeq             (force)
import           Control.Exception           (evaluate)
import           Control.Monad               (when, forever)
import           Data.Aeson
import qualified Data.ByteString.Char8       as BC (snoc)
import qualified Data.ByteString.Lazy.Char8  as BLC (ByteString, hPutStrLn,
                                                     toStrict)
import           Data.List
import           Data.List.Split
import           Data.Maybe
import qualified Data.Text                   as T
import           Data.Time                   (getCurrentTime)
import           Data.Time.Clock             (UTCTime)
import           Striot.FunctionalIoTtypes
import           Striot.FunctionalProcessing
import           Striot.Nodes
import           System.IO
import           System.IO.Unsafe            (unsafeInterleaveIO)
import           Taxi


listenPort = 9001 :: Int
fileName = "output-log.txt"


main :: IO ()
main = do
    chan <- newTChanIO
    writeFile fileName ""
    hdl <- openFile fileName WriteMode
    hSetBuffering hdl NoBuffering
    async $ writeToFile'' hdl chan
    nodeSink streamGraphid' (sinkToChan chan) listenPort


printFromChan :: Show a => TChan a -> IO ()
printFromChan chan = forever $ print =<< (atomically . readTChan $ chan)

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


streamGraphid' :: Stream String -> Stream String
streamGraphid' = Prelude.id

streamGraphid :: Stream ((UTCTime,UTCTime),[(Journey,Int)]) -> Stream ((UTCTime,UTCTime),[(Journey,Int)])
streamGraphid = streamMap Prelude.id


streamGraphFn :: Stream (Int,((UTCTime,UTCTime),[(Journey,Int)])) -> Stream ((UTCTime,UTCTime),[(Journey,Int)])
streamGraphFn n1 = let
    n2 = orderEvents n1
    n3 = (\s -> streamFilterAcc (\acc h -> if snd h == snd acc then acc else h) (fromJust (value (head s))) (\h acc -> snd h /= snd acc) (tail s)) n2
    in n3


sinkToChan :: (ToJSON alpha) => TChan BLC.ByteString -> Stream alpha -> IO ()
sinkToChan chan stream =
    runConduit
        $ yieldMany stream
       .| mapMC (\x@(Event _ _ (Just v)) -> do
                now <- getCurrentTime
                return x { value = Just (v, now) }
                )
       .| mapMC (evaluate . force . encode)
       .| mapM_C (atomically . writeTChan chan)


writeToFile :: Handle -> TChan BLC.ByteString -> IO ()
writeToFile hdl chan =
    runConduitRes
        $ sourceTChanYield chan
       .| mapC ((`BC.snoc` '\n') . BLC.toStrict)
       .| sinkHandle hdl

writeToFile' :: String -> TChan BLC.ByteString -> IO ()
writeToFile' fName chan =
    runConduitRes
        $ sourceTChanYield chan
       .| mapC ((`BC.snoc` '\n') . BLC.toStrict)
       .| sinkFile fName

writeToFile'' :: Handle -> TChan BLC.ByteString -> IO ()
writeToFile'' hdl chan = forever $ do
    BLC.hPutStrLn hdl =<< (atomically . readTChan $ chan)
    hFlush hdl

sourceTChanYield :: MonadIO m => TChan a -> ConduitT i a m ()
sourceTChanYield ch = loop
    where
        loop = do
            ms <- liftIO . atomically $ readTChan ch
            yield ms
            loop
