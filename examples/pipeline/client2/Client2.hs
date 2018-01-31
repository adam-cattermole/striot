--import Control.Concurrent
import System.IO
import Striot.FunctionalProcessing
import Striot.FunctionalIoTtypes
import Striot.Nodes
import Network

import System.Environment
import Control.DeepSeq

listenPort =  9002 :: PortNumber
connectPort = 9001 :: PortNumber

main :: IO ()
main = do
    podName <- getEnv "HOSTNAME"
    connectHost <- getEnv "HASKELL_SERVER_SERVICE_HOST"
    nodeLink (streamGraphLoad podName) listenPort connectHost connectPort

streamGraphid :: Stream String -> Stream String
streamGraphid = Prelude.id

streamGraphLoad :: String -> Stream String -> Stream (String, String)
streamGraphLoad podName = streamMap (\x -> factorial 127000 `deepseq` (podName, x))

factorial :: Integer -> Integer
factorial 0 = 1
factorial n = n * factorial (n - 1)
