{-# LANGUAGE FlexibleContexts #-}

-- node2
import           Control.Concurrent
import           Control.Monad.State
import           Control.Monad.Trans.Control
import           Striot.FunctionalIoTtypes
import           Striot.FunctionalProcessing
import           Striot.Nodes
import           Striot.Nodes.Types
import           System.Envy
import           Taxi
import           Data.Time                   (UTCTime (..))


-- streamGraphFn :: Stream (UTCTime, Trip) -> Stream (UTCTime, Trip)
-- streamGraphFn = id

streamGraphFn :: Stream (UTCTime, Trip) -> Stream (UTCTime, Journey)
streamGraphFn s = streamFilter (\(t,j) -> inRangeQ1 (start j) && inRangeQ1 (end j))
                $ streamMap (\(t,v) -> (t, tripToJourney v)) s


main :: IO ()
main = do
    conf <- decodeEnv :: IO (Either String StriotConfig)
    case conf of
        Left _  -> print "Could not read from env"
        Right c -> nodeLink c streamGraphFn
