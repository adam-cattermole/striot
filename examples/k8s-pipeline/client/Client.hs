import Control.Concurrent
import Network.Socket
import Striot.FunctionalIoTtypes
import Striot.FunctionalProcessing
import Striot.Nodes
import System.Environment
import System.IO

portNum  = "61613"::ServiceName

main :: IO ()
main = do
   hostName <- getEnv "AMQ_BROKER_SERVICE_HOST"
   threadDelay (1 * 1000 * 1000)
   nodeSourceAmq src1 streamGraph2 hostName portNum -- processes source before sending it to another node

streamGraph2 :: Stream String -> Stream String
streamGraph2 s = streamMap (\st-> st++st) s

src1:: IO String
src1 = clockStreamNamed "Hello from Client!" 1000

clockStreamNamed:: String -> Int -> IO String -- returns the (next) payload to be added into an event and sent to a server
clockStreamNamed message period = do -- period is in ms
                                    threadDelay (period*1000)
                                    return message