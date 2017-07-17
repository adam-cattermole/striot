--import Control.Concurrent
import System.IO
import Striot.FunctionalProcessing
import Striot.FunctionalIoTtypes
import Striot.Nodes
import Network

import System.Environment

listenPort =  9002 :: PortNumber
connectPort = 9001 :: PortNumber
--connectHost = "haskellserver" :: HostName

main :: IO ()
main = do
    connectHost <- getEnv "HASKELL_SERVER_SERVICE_HOST"
    nodeLink streamGraph1 listenPort connectHost connectPort

streamGraph1 :: Stream String -> Stream String
streamGraph1 = streamMap reverse
