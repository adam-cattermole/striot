-- node1
import Striot.FunctionalIoTtypes
import Striot.FunctionalProcessing
import Striot.Nodes
import Striot.Nodes.Types
import System.Envy
import Control.Concurrent
import Taxi
import           Data.Time                   (UTCTime (..))


-- src1 = simulateData "data/sorteddata_large.csv"
src1 = simulateData "data/sorteddata-0-25000.csv"


streamGraphFn :: Stream (UTCTime, Trip) -> Stream (UTCTime, Trip)
streamGraphFn = id


main :: IO ()
main = do
    conf <- decodeEnv :: IO (Either String StriotConfig)
    case conf of
        Left _  -> print "Could not read from env"
        Right c -> nodeSourceC c src1 streamGraphFn