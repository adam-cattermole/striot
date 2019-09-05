-- node2
import           Control.Concurrent
import           Data.List
import           Data.Time
import           Striot.FunctionalIoTtypes
import           Striot.FunctionalProcessing
import           Striot.Nodes
import           System.Environment
import           Taxi

main :: IO ()
-- main = nodeLink streamGraphFn "9001" "node3" "9001"
main = do
    podName <- getEnv "HOSTNAME"
    brokerHost <- getEnv "AMQ_BROKER_SERVICE_HOST"
    kafkaHost <- getEnv "KAFKA_SERVICE_HOST"
    connectHost <- getEnv "STRIOT_SINK_SERVICE_HOST"
    let shortPodName = intercalate "-" (drop 2 $ wordsWhen (=='-') podName)
    putStrLn $ "HOSTNAME: " ++ shortPodName
    putStrLn $ "AMQ_BROKER_SERVICE_HOST: " ++ brokerHost
    threadDelay (1 * 1000 * 1000)

    nodeLinkKafka streamGraphFn podName kafkaHost "9092" connectHost "9001"


wordsWhen :: (Char -> Bool) -> String -> [String]
wordsWhen p s =  case dropWhile p s of
                      "" -> []
                      s' -> w : wordsWhen p s''
                            where (w, s'') = break p s'


-- streamGraphFn :: Stream String -> Stream String
-- streamGraphFn = streamMap Prelude.id

streamGraphFn :: Stream (Int,[Journey]) -> Stream (Int,((UTCTime,UTCTime),[(Journey,Int)]))
streamGraphFn = streamMap (\(i,w) -> (let lj = last w in (i,((pickupTime lj, dropoffTime lj), topk 10 w))))
