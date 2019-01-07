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


main :: IO ()
main = do
    podName <- getEnv "HOSTNAME"
    brokerHost <- getEnv "AMQ_BROKER_SERVICE_HOST"
    connectHost <- getEnv "HASKELL_SERVER_SERVICE_HOST"
    let shortPodName = intercalate "-" (drop 2 $ wordsWhen (=='-') podName)
    putStrLn $ "HOSTNAME: " ++ shortPodName
    putStrLn $ "AMQ_BROKER_SERVICE_HOST: " ++ brokerHost
    putStrLn $ "HASKELL_SERVER_SERVICE_HOST: " ++ connectHost
    nodeLinkAmqMqtt streamGraphid shortPodName brokerHost brokerPort connectHost connectPort

wordsWhen :: (Char -> Bool) -> String -> [String]
wordsWhen p s =  case dropWhile p s of
                      "" -> []
                      s' -> w : wordsWhen p s''
                            where (w, s'') = break p s'

streamGraph1 :: String -> Stream String -> Stream String
streamGraph1 podName = streamMap (\st-> podName ++ ": " ++ st)

streamGraphid :: Stream String -> Stream String
streamGraphid = Prelude.id
