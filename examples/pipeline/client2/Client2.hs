--import Control.Concurrent
import System.IO
import Striot.FunctionalProcessing
import Striot.FunctionalIoTtypes
import Striot.Nodes
import Network

listenPort =  9002 :: PortNumber
connectPort = 9001 :: PortNumber
connectHost = "127.0.0.1" :: HostName

main :: IO ()
main = nodeLink streamGraphid listenPort connectHost connectPort

streamGraph1 :: Stream Int -> Stream [Int]
streamGraph1 = streamWindowAggregate (slidingTime 1) fn

fn :: [Int] -> [Int]
fn ys@(x:xs) = [x, length ys]
