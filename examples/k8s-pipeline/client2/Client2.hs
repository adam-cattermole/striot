--import Control.Concurrent
import Network.Socket
import Striot.FunctionalIoTtypes
import Striot.FunctionalProcessing
import Striot.Nodes
import System.Environment
import System.IO

brokerPort =  "61613" :: ServiceName
connectPort = "9001" :: ServiceName

main :: IO ()
main = do
    podName <- getEnv "HOSTNAME"
    brokerHost <- getEnv "AMQ_STOMP_SERVICE_HOST"
    connectHost <- getEnv "HASKELL_SERVER_SERVICE_HOST"
    nodeLinkAmq (streamGraph1 podName) brokerHost brokerPort connectHost connectPort

streamGraph1 :: String -> Stream String -> Stream String
streamGraph1 podName = streamMap (\st-> podName ++ ": " ++ st)
