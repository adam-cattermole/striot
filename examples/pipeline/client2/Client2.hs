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
    podName <- getEnv "HOSTNAME"
    connectHost <- getEnv "HASKELL_SERVER_SERVICE_HOST"
    nodeLink (streamGraph1 podName)  listenPort connectHost connectPort

streamGraph1 :: Stream String -> String -> Stream String
streamGraph1 stream s = streamMap (++) s
