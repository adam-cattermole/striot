-- node3
import           Control.Concurrent
import           Striot.FunctionalIoTtypes
import           Striot.FunctionalProcessing
import           Striot.Nodes
-- import Control.DeepSeq (force)
import           Control.Exception           (evaluate)
import           Data.Maybe
import           Data.Time
import           Taxi

sink1 :: Show a => Stream a -> IO ()
sink1 = mapM_ evaluate


main :: IO ()
main = nodeSink streamGraphFn sink1 "9001"


-- streamGraphFn :: Stream String -> Stream String
-- streamGraphFn :: Stream (Int,((UTCTime,UTCTime),[(Journey,Int)])) -> Stream (Int,((UTCTime,UTCTime),[(Journey,Int)]))
-- streamGraphFn = streamMap Prelude.id

streamGraphFn :: Stream (Int,((UTCTime,UTCTime),[(Journey,Int)])) -> Stream ((UTCTime,UTCTime),[(Journey,Int)])
streamGraphFn n1 = let
    n2 = orderEvents n1
    -- n2 = streamMap snd n1
    n3 = (\s -> streamFilterAcc (\acc h -> if snd h == snd acc then acc else h) (fromJust (value (head s))) (\h acc -> snd h /= snd acc) (tail s)) n2
    in n2


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
