import Control.Concurrent
import Network.Socket
import Striot.FunctionalIoTtypes
import Striot.FunctionalProcessing
import Striot.Nodes
import System.Environment
import System.IO
import Data.List
import Data.List.Split
import Taxi


portNum  = "61616"::ServiceName


main :: IO ()
main = do
    podName <- getEnv "HOSTNAME"
    brokerHost <- getEnv "AMQ_BROKER_SERVICE_HOST"
    let shortPodName = intercalate "-" (drop 2 $ wordsWhen (=='-') podName)
    putStrLn $ "HOSTNAME: " ++ shortPodName
    putStrLn $ "AMQ_BROKER_SERVICE_HOST: " ++ brokerHost
    threadDelay (1 * 1000 * 1000)
    nodeSourceAmqMqtt src1 streamGraphFn shortPodName brokerHost portNum -- processes source before sending it to another node


wordsWhen :: (Char -> Bool) -> String -> [String]
wordsWhen p s =  case dropWhile p s of
                      "" -> []
                      s' -> w : wordsWhen p s''
                            where (w, s'') = break p s'


streamGraphid :: Stream String -> Stream String
streamGraphid = streamMap Prelude.id


src1 = do
   line <- getLine;
   return $ stringsToTrip $ splitOn "," line


streamGraphFn :: Stream Trip -> Stream [Journey]
streamGraphFn n1 = let
    n2 = (\s -> streamMap tripToJourney s) n1
    n3 = (\s -> streamFilter (\j -> inRangeQ1 (start j)) s) n2
    n4 = (\s -> streamFilter (\j -> inRangeQ1 (end j)) s) n3
    n5 = (\s -> streamWindow (slidingJourneyTime 1800000) s) n4
    in n5
