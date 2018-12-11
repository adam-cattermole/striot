-- node1
import Striot.FunctionalIoTtypes
import Striot.FunctionalProcessing
import Striot.Nodes
import Control.Concurrent
import System.IO
import TaxiUtil


streamFn :: Stream String -> Stream [Journey]
streamFn xs = streamWindow (slidingTime 1800000)
            $ streamFilter (\j -> inRangeQ1 (start j) && inRangeQ1 (end j))
            $ streamMap tripToJourney
            $ map tripParse xs


main :: IO ()
main = do
    hdl <- openFile "sorteddata.csv" ReadMode
    nodeSource (hGetLine hdl) streamFn "node2" "9001"
