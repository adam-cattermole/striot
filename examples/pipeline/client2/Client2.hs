--import Control.Concurrent
import System.IO
import Striot.FunctionalProcessing
import Striot.FunctionalIoTtypes
import Striot.Nodes
import Network

import System.Environment

listenPort =  9002 :: PortNumber
connectPort = 9001 :: PortNumber

main :: IO ()
main = do
    podName <- getEnv "HOSTNAME"
    connectHost <- getEnv "HASKELL_SERVER_SERVICE_HOST"
    nodeLink streamGraph1 listenPort connectHost connectPort

streamGraph1 :: Stream Int -> Stream [Int]
streamGraph1 = streamWindowAggregate (slidingTime 1) fn

fn :: [Int] -> [Int]
fn ys@(x:xs) = [x, length ys]
