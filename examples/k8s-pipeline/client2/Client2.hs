--import Control.Concurrent
import Network.Socket
import Striot.FunctionalIoTtypes
import Striot.FunctionalProcessing
import Striot.Nodes
import System.Environment
import System.IO
import Control.DeepSeq
import Data.List
import Data.List.Split
import Data.Time
import Data.Maybe
import Taxi


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
    nodeLinkAmqMqtt streamGraphFn shortPodName brokerHost brokerPort connectHost connectPort


wordsWhen :: (Char -> Bool) -> String -> [String]
wordsWhen p s =  case dropWhile p s of
                      "" -> []
                      s' -> w : wordsWhen p s''
                            where (w, s'') = break p s'


streamGraphFn :: Stream [Journey] -> Stream ((UTCTime,UTCTime),[(Journey,Int)])
streamGraphFn n1 = let
    n2 = (\s -> streamMap (\w -> (let lj = last w in (pickupTime lj, dropoffTime lj), topk 10 w)) s) n1
    in n2


streamGraphid :: Stream [Journey] -> Stream [Journey]
streamGraphid = Prelude.id
