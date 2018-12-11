-- node2
import Striot.FunctionalIoTtypes
import Striot.FunctionalProcessing
import Striot.Nodes
import Control.Concurrent
import qualified Data.Map as Map
import TaxiUtil

streamGraphFn :: Stream [Map.Map Cell Dollars] -> Stream [(Map.Map Cell Dollars, Int)]
streamGraphFn = streamMap (topk 10)

main :: IO ()
main = nodeLink streamGraphFn "9001" "node3" "9001"
