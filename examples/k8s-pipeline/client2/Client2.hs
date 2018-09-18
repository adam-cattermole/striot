--import Control.Concurrent
import Network.Socket
import Striot.FunctionalIoTtypes
import Striot.FunctionalProcessing
import Striot.Nodes
import System.Environment
import System.IO
import Control.DeepSeq
import Data.List

brokerPort =  "61616" :: ServiceName
connectPort = "9001" :: ServiceName

-- brokerHost = "amq-stomp.default.svc.cluster.local" :: HostName
-- connectHost = "haskell-server.default.svc.cluster.local" :: HostName

main :: IO ()
main = do
    podName <- getEnv "HOSTNAME"
    brokerHost <- getEnv "AMQ_BROKER_SERVICE_HOST"
    connectHost <- getEnv "HASKELL_SERVER_SERVICE_HOST"
    let shortPodName = intercalate "-" (drop 2 $ wordsWhen (=='-') podName)
    putStrLn $ "HOSTNAME: " ++ shortPodName
    putStrLn $ "AMQ_BROKER_SERVICE_HOST: " ++ brokerHost
    putStrLn $ "HASKELL_SERVER_SERVICE_HOST: " ++ connectHost
    -- nodeLinkAmqMqtt streamGraphid shortPodName brokerHost brokerPort connectHost connectPort
    nodeLinkAmqMqtt streamGraphLoad shortPodName brokerHost brokerPort connectHost connectPort
    -- nodeLinkAmq streamGraphid brokerHost brokerPort connectHost connectPort
    -- nodeLinkAmq streamGraphLoad brokerHost brokerPort connectHost connectPort

wordsWhen :: (Char -> Bool) -> String -> [String]
wordsWhen p s =  case dropWhile p s of
                      "" -> []
                      s' -> w : wordsWhen p s''
                            where (w, s'') = break p s'

streamGraph1 :: String -> Stream String -> Stream String
streamGraph1 podName = streamMap (\st-> podName ++ ": " ++ st)

streamGraphid :: Stream String -> Stream String
streamGraphid = Prelude.id

streamGraphLoad :: Stream String -> Stream String
-- streamGraphLoad = streamMap (\x -> factorial 2325 `deepseq` x)
-- streamGraphLoad = streamMap (\x -> factorial 4910 `deepseq` x)
-- streamGraphLoad = streamMap (\x -> factorial 6900 `deepseq` x)
streamGraphLoad = streamMap (\x -> factorial 14085 `deepseq` x)


factorial :: Integer -> Integer
factorial 0 = 1
factorial n = n * factorial (n - 1)


-- haskell-client2-5876447676-x2h4x
