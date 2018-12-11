-- node3
import Striot.FunctionalIoTtypes
import Striot.FunctionalProcessing
import Striot.Nodes
import Control.Concurrent
import qualified Data.Map as Map
import TaxiUtil


sink1 :: Show a => Stream a -> IO ()
sink1 = mapM_ print

streamGraphFn :: Stream [(Map.Map Cell Dollars, Int)] -> Stream [(Map.Map Cell Dollars, Int)]
streamGraphFn = changes

main :: IO ()
main = nodeSink streamGraphFn sink1 "9001"
