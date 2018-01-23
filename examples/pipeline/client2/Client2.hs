--import Control.Concurrent
import System.IO
import Striot.FunctionalProcessing
import Striot.FunctionalIoTtypes
import Striot.Nodes
import Network
import Control.DeepSeq

listenPort =  9002 :: PortNumber
connectPort = 9001 :: PortNumber
connectHost = "haskellserver" :: HostName

main :: IO ()
main = nodeLink streamGraphLoad listenPort connectHost connectPort

streamGraphid :: Stream String -> Stream String
streamGraphid = Prelude.id

streamGraphLoad :: Stream String -> Stream String
streamGraphLoad = streamMap (\x -> factorial 213000 `deepseq` x)

factorial :: Integer -> Integer
factorial 0 = 1
factorial n = n * factorial (n - 1)
