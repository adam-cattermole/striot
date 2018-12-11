-- node1
import Striot.FunctionalIoTtypes
import Striot.FunctionalProcessing
import Striot.Nodes
import Control.Concurrent
import System.IO
import qualified Data.Map as Map
import TaxiUtil


streamFn :: Stream String -> Stream [Map.Map Cell Dollars]
streamFn xs = streamWindow (slidingTime 1800000)
            $ streamJoinW (slidingTime 900000) (slidingTime 1800000)
                          (\a b -> profitability (emptyTaxisPerCell b) (cellProfit a)) processedStream processedStream
                where processedStream = streamFilter (\(_, j) -> inRangeQ2 (start j) && inRangeQ2 (end j))
                                      $ streamMap (\t -> (t, tripToJourney t))
                                      $ map tripParse xs


main :: IO ()
main = do
    hdl <- openFile "sorteddata.csv" ReadMode
    nodeSource (hGetLine hdl) streamFn "node2" "9001"
