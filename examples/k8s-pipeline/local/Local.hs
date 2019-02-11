import           Conduit
import           Data.List
import           Data.List.Split
import           Data.Maybe
import           System.IO
import           System.IO.Unsafe            (unsafeInterleaveIO)

import           Striot.FunctionalIoTtypes
import           Striot.FunctionalProcessing
import           Taxi

import           Conduit
import           Control.Concurrent.Async    (async)
import           Control.Concurrent.STM
import           Control.Monad               (when)
import           Data.Aeson
import qualified Data.ByteString.Char8       as BC (snoc)
import qualified Data.ByteString.Lazy.Char8  as BLC (hPutStrLn, toStrict)
import qualified Data.List.Split             as S (splitOn)
import qualified Data.Text                   as T
import           Data.Time                   (getCurrentTime)
import           Data.Time.Clock             (UTCTime)


fileName = "output-log.txt"


main :: IO ()
main = do
    chan <- newTChanIO
    writeFile fileName ""
    async $ writeToFile fileName chan

    input <- readListFromSource src1
    let n1 = sourceStreamFn input
        n2 = linkStreamFn n1
        n3 = sinkStreamFn n2

    sinkToChan chan n3


-- Client.hs

tripParse :: Event String -> Event Trip
tripParse e@(Event eid _ (Just v)) =
    let t = stringsToTrip $ S.splitOn "," v
    in  e { eventId = eid
          , time    = Just $ dropoffDatetime t
          , value   = Just t }

src1 :: IO Trip
src1 = stringsToTrip . S.splitOn "," <$> getLine

sourceStreamFn :: Stream Trip -> Stream [Journey]
sourceStreamFn n1 = let
    n2 = (\s -> streamWindow tripTimes s) n1
    n3 = (\s -> streamExpand s) n2
    -- n3 = map tripParse n1
    n4 = (\s -> streamMap tripToJourney s) n3
    n5 = (\s -> streamFilter (\j -> inRangeQ1 (start j)) s) n4
    n6 = (\s -> streamFilter (\j -> inRangeQ1 (end j)) s) n5
    n7 = (\s -> streamWindow (slidingTime 1800000) s) n6
    in n7


-- Client2.hs

linkStreamFn :: Stream ([Journey]) -> Stream ((UTCTime,UTCTime),[(Journey,Int)])
linkStreamFn = streamMap (\w -> (let lj = last w in ((pickupTime lj, dropoffTime lj), topk 10 w)))


-- Server.hs

sinkStreamFn :: Stream ((UTCTime,UTCTime),[(Journey,Int)]) -> Stream ((UTCTime,UTCTime),[(Journey,Int)])
sinkStreamFn n1 = let
    n2 = (\s -> streamFilterAcc (\acc h -> if snd h == snd acc then acc else h) (fromJust (value (head s))) (\h acc -> snd h /= snd acc) (tail s)) n1
    in n2

-- Utility


readListFromSource :: IO alpha -> IO (Stream alpha)
readListFromSource = go 0
  where
    go i pay = unsafeInterleaveIO $ do
        x  <- msg i
        xs <- go (i + 1) pay    -- This will overflow eventually
        return (x : xs)
      where
        msg x = do
            now     <- getCurrentTime
            Event x (Just now) . Just <$> pay

sinkToChan :: (ToJSON alpha) => TChan (Event (alpha, UTCTime)) -> Stream alpha -> IO ()
sinkToChan chan stream =
    runConduit
        $ yieldMany stream
       .| mapMC (\x@(Event _ _ (Just v)) -> do
                now <- getCurrentTime
                return x { value = Just (v, now) }
                )
       .| mapM_C (atomically . writeTChan chan)


writeToFile :: (ToJSON alpha) => String -> TChan (Event (alpha, UTCTime)) -> IO ()
writeToFile fName chan =
    runConduitRes
        $ sourceTChanYield chan
       .| mapC ((`BC.snoc` '\n') . BLC.toStrict . encode)
       .| sinkFile fName


sourceTChanYield :: MonadIO m => TChan a -> ConduitT i a m ()
sourceTChanYield ch = loop
    where
        loop = do
            ms <- liftIO . atomically $ readTChan ch
            yield ms
            loop


-- Ordering Events

type OrderAcc alpha = (Int, [alpha], [(Int, alpha)])

-- orderEvents takes a stream of events consisting of a sequence number and data (alpha)
--- and orders the events according to the sequence number, also removing that number.
--- It can be used to order a stream of events that have been spread across a set of nodes
--- for parallel processing (e.g. of map and filter operators)

orderEvents :: Stream (Int, alpha) -> Stream alpha
orderEvents s = streamExpand                             $
                streamMap    (\(_,payload,_) -> payload) $
                streamScan   orderIps (0,[],[])          s -- issue: throws away timestamps --- does that matter?

-- inserts a sequence number + data pair into a list of such pairs so as to maintain the order of the list
insertInto :: (Int, alpha) -> [(Int, alpha)] -> [(Int, alpha)]
insertInto (i,v) []                        = [(i,v)]
insertInto (i,v) acc@((k,w):u) | i<k       = (i,v):acc
                               | otherwise = (k,w):insertInto (i,v) u

-- orderIps takes a tuple (nextSequence number in the order, list of data to be emitted in events, ordered list of sequence numbers and data)
--- and the contents of the next event (with its sequence number)
orderIps :: OrderAcc alpha -> (Int, alpha) -> OrderAcc alpha
orderIps (nextSeqNumber,_,results) e@(s,val) | s == nextSeqNumber   = let (newSeqNumber,restOfSequence,remainingResults) = processResults (s+1) [] results in (newSeqNumber,val:restOfSequence,remainingResults)
                                             | otherwise            = (nextSeqNumber,[],insertInto e results)

processResults :: Int -> [alpha] -> [(Int, alpha)] -> OrderAcc alpha -- Sequence number -> results waiting to be sent out -> results waiting in ordered list until their sequence number is next
                                                                                --  -> (next sequence number,results to be sent out, results waiting in ordered list)
processResults nextSeq restOfSeq []                          = (nextSeq,restOfSeq,[])
processResults nextSeq restOfSeq res@((j,k):r)  | nextSeq == j = processResults (nextSeq+1) (restOfSeq++[k]) r
                                                | otherwise    = (nextSeq,restOfSeq,res)
