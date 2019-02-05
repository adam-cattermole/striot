import Control.Concurrent
import Striot.FunctionalIoTtypes
import Striot.FunctionalProcessing
import Striot.Nodes
import System.Environment
import System.IO
import Data.List
import qualified Data.List.Split as S
import Data.Maybe (fromJust)
import Taxi


portNum  = 61616 :: Int
-- portNum  = "9002"::ServiceName
-- linkHost = "127.0.0.1"::HostName


main :: IO ()
main = do
    podName <- getEnv "HOSTNAME"
    brokerHost <- getEnv "AMQ_BROKER_SERVICE_HOST"
    let shortPodName = intercalate "-" (drop 2 $ wordsWhen (=='-') podName)
    putStrLn $ "HOSTNAME: " ++ shortPodName
    putStrLn $ "AMQ_BROKER_SERVICE_HOST: " ++ brokerHost
    threadDelay (1 * 1000 * 1000)
    -- hdl <- openFile "sorteddata.csv" ReadMode
    -- hSetBuffering hdl LineBuffering
    nodeSourceMqtt (src1) streamGraphFn shortPodName brokerHost portNum -- processes source before sending it to another node
    -- nodeSource (hGetLine hdl) streamGraphFn linkHost portNum




wordsWhen :: (Char -> Bool) -> String -> [String]
wordsWhen p s =  case dropWhile p s of
                      "" -> []
                      s' -> w : wordsWhen p s''
                            where (w, s'') = break p s'


streamGraphid :: Stream String -> Stream String
streamGraphid = streamMap Prelude.id


tripParse :: Event String -> Event Trip
tripParse e@(Event eid _ (Just v)) =
    let t = stringsToTrip $ S.splitOn "," v
    in  e { eventId = eid
          , time    = Just $ dropoffDatetime t
          , value   = Just t }

-- src1 :: IO Trip
src1 = stringsToTrip . S.splitOn "," <$> getLine

streamGraphFn :: Stream Trip -> Stream [Journey]
streamGraphFn n1 = let
    n2 = (\s -> streamWindow tripTimes s) n1
    n3 = (\s -> streamExpand s) n2
    -- n3 = map tripParse n1
    n4 = (\s -> streamMap tripToJourney s) n3
    n5 = (\s -> streamFilter (\j -> inRangeQ1 (start j)) s) n4
    n6 = (\s -> streamFilter (\j -> inRangeQ1 (end j)) s) n5
    n7 = (\s -> streamWindow (slidingTime 1800000) s) n6
    in n7
