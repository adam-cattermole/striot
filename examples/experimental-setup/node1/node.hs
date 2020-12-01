-- node1
import Striot.FunctionalIoTtypes
import Striot.FunctionalProcessing
import Striot.Nodes
import Striot.Nodes.Types
import System.Envy
import Control.Concurrent
import Taxi
import           Data.Time                   (UTCTime (..))


src1 = simulateData "data/sorteddata-0-25000.csv"
-- src1 = simulateData "data/sorteddata_large.csv"

-- streamGraphFn :: Stream String -> Stream String
-- streamGraphFn n1 = let
--     n2 = (\s -> streamMap (\st->st++st) s) n1
--     in n2


-- streamGraphFn' :: Stream String -> Stream Int
-- streamGraphFn' = streamScan (\acc _ -> (+1) acc) (-1)

streamGraphFn :: Stream (UTCTime, Trip) -> Stream (UTCTime, Trip)
streamGraphFn = id


main :: IO ()
main = do
    conf <- decodeEnv :: IO (Either String StriotConfig)
    case conf of
        Left _  -> print "Could not read from env"
        Right c -> nodeSourceC c src1 streamGraphFn