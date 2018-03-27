--import Control.Concurrent
import           Network
import           Striot.FunctionalIoTtypes
import           Striot.FunctionalProcessing
import           Striot.Nodes

import           Control.DeepSeq
import           System.Environment

listenPort =  9001 :: PortNumber
connectPort = 9001 :: PortNumber
-- connectHost = "haskellserver" :: HostName

main :: IO ()
main = do
    connectHost <- getEnv "HASKELL_SERVER_SERVICE_HOST"
    nodeLink streamGraphid listenPort connectHost connectPort

streamGraphid :: Stream String -> Stream String
streamGraphid = Prelude.id

streamGraphLoad :: Stream String -> Stream String
streamGraphLoad = streamMap (\x -> factorial 213000 `deepseq` x)

factorial :: Integer -> Integer
factorial 0 = 1
factorial n = n * factorial (n - 1)
