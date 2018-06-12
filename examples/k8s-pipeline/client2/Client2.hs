--import Control.Concurrent
import Network.Socket
import Striot.FunctionalIoTtypes
import Striot.FunctionalProcessing
import Striot.Nodes
import System.Environment
import System.IO
import Control.DeepSeq

brokerPort =  "61613" :: ServiceName
connectPort = "9001" :: ServiceName

-- brokerHost = "amq-stomp.default.svc.cluster.local" :: HostName
-- connectHost = "haskell-server.default.svc.cluster.local" :: HostName

main :: IO ()
main = do
    podName <- getEnv "HOSTNAME"
    brokerHost <- getEnv "AMQ_STOMP_SERVICE_HOST"
    connectHost <- getEnv "HASKELL_SERVER_SERVICE_HOST"
    nodeLinkAmq streamGraphid brokerHost brokerPort connectHost connectPort

streamGraph1 :: String -> Stream String -> Stream String
streamGraph1 podName = streamMap (\st-> podName ++ ": " ++ st)

streamGraphid :: Stream String -> Stream String
streamGraphid = Prelude.id

streamGraphLoad :: Stream String -> Stream String
streamGraphLoad = streamMap (\x -> factorial 213000 `deepseq` x)

factorial :: Integer -> Integer
factorial 0 = 1
factorial n = n * factorial (n - 1)
