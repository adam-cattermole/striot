--import Control.Concurrent
import System.IO
import Striot.FunctionalProcessing
import Striot.FunctionalIoTtypes
import Striot.Nodes
import Network

listenPort =  9001 :: PortNumber
connectPort = 9001 :: PortNumber
connectHost = "haskellserver" :: HostName

main :: IO ()
main = nodeLink streamGraph1 listenPort connectHost connectPort

streamGraph1 :: Stream Int -> Stream [Int]
streamGraph1 = streamWindowAggregate (slidingTime 1) fn

fn :: [Int] -> [Int]
fn ys@(x:xs) = [x, length ys]
