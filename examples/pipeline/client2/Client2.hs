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
    nodeLink streamGraphid listenPort connectHost connectPort

streamGraphid :: Stream String -> Stream String
streamGraphid = Prelude.id
