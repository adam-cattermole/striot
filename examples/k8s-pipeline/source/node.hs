-- node1
import           Control.Concurrent
import           Data.List
import qualified Data.List.Split             as S
import           Data.Maybe                  (fromJust)
import           Striot.FunctionalIoTtypes
import           Striot.FunctionalProcessing
import           Striot.Nodes
import           System.Environment
import           System.IO
import           Taxi



main :: IO ()
-- main = nodeSource src1 streamGraphFn "node2" "9001"
main = do
    podName <- getEnv "HOSTNAME"
    brokerHost <- getEnv "AMQ_BROKER_SERVICE_HOST"
    kafkaHost <- getEnv "KAFKA_SERVICE_HOST"
    let shortPodName = intercalate "-" (drop 2 $ wordsWhen (=='-') podName)
    putStrLn $ "HOSTNAME: " ++ shortPodName
    putStrLn $ "AMQ_BROKER_SERVICE_HOST: " ++ brokerHost
    threadDelay (1 * 1000 * 1000)

    nodeSourceKafka src1 streamGraphFn podName kafkaHost "9092"


wordsWhen :: (Char -> Bool) -> String -> [String]
wordsWhen p s =  case dropWhile p s of
                      "" -> []
                      s' -> w : wordsWhen p s''
                            where (w, s'') = break p s'

tripParse :: Event String -> Event Trip
tripParse e@(Event eid _ (Just v)) =
    let t = stringsToTrip $ S.splitOn "," v
    in  e { eventId = eid
          , time    = Just $ dropoffDatetime t
          , value   = Just t }

-- src1 = do
-- --    threadDelay (1000*1000)
--     return "out-message"

src1 :: IO Trip
src1 = loop
    where loop = do
            done <- isEOF
            if done
            then loop
            else stringsToTrip . S.splitOn "," <$> getLine


-- streamGraphFn :: Stream String -> Stream String
-- streamGraphFn = streamMap Prelude.id


streamGraphFn :: Stream Trip -> Stream (Int,[Journey])
streamGraphFn n1 = let
    n2 = (\s -> streamWindow tripTimes s) n1
    n3 = (\s -> streamExpand s) n2
    -- n3 = map tripParse n1
    n4 = (\s -> streamMap tripToJourney s) n3
    n5 = (\s -> streamFilter (\j -> inRangeQ1 (start j)) s) n4
    n6 = (\s -> streamFilter (\j -> inRangeQ1 (end j)) s) n5
    -- n7 = (\s -> streamWindow (slidingTime 1800000) s) n6
    n7 = (\s -> streamWindow (sliding 5000) s) n6
    n8 = (\s -> streamScan (\(i,_) a -> (i+1,a)) (-1,mempty) s) n7
    in n8
