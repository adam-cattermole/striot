-- node3
import Striot.FunctionalIoTtypes
import Striot.FunctionalProcessing
import Striot.Nodes
import Control.Concurrent
import TaxiUtil


sink1 :: Show a => Stream a -> IO ()
sink1 = mapM_ print

main :: IO ()
main = nodeSink journeyChanges sink1 "9001"
