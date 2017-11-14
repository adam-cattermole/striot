--import Control.Concurrent
import System.IO
import Striot.FunctionalProcessing
import Striot.FunctionalIoTtypes
import Striot.Nodes
import Network

listenPort =  9004 :: PortNumber
connectPort = 9003 :: PortNumber
connectHost = "haskelllink2" :: HostName

main :: IO ()
main = nodeLink streamGraphid listenPort connectHost connectPort

streamGraphid :: Stream (Int, Int) -> Stream (Int, Int)
streamGraphid = Prelude.id

-- streamGraph1 :: Stream Int -> Stream [Int]
-- streamGraph1 = streamWindowAggregate (slidingTime 1) fn

-- fn :: [Int] -> [Int]
-- fn ys@(x:xs) = [x, length ys]
