--import Control.Concurrent
import           Network
import           Striot.FunctionalIoTtypes
import           Striot.FunctionalProcessing
import           Striot.Nodes
import           System.Environment
import           System.IO

listenPort =  9001 :: PortNumber
connectPort = 9001 :: PortNumber

main :: IO ()
main = do
    connectHost <- getEnv "HASKELL_SERVER_SERVICE_HOST"
    nodeLink streamGraph1 listenPort connectHost connectPort

streamGraph1 :: Stream String -> Stream String
streamGraph1 s = streamMap (\st-> reverse st) s
