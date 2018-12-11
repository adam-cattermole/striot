-- node2
import Striot.FunctionalIoTtypes
import Striot.FunctionalProcessing
import Striot.Nodes
import Control.Concurrent
import Data.Time (UTCTime)
import TaxiUtil

streamGraphFn :: Stream [Journey] -> Stream ((UTCTime, UTCTime),[(Journey, Int)])
streamGraphFn = streamMap (\w -> (let lj = last w in (pickupTime lj, dropoffTime lj), topk 10 w))

main :: IO ()
main = nodeLink streamGraphFn "9001" "node3" "9001"
