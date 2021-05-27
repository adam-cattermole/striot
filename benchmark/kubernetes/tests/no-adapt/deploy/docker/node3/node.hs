{-# LANGUAGE FlexibleContexts #-}

-- node3
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


streamGraphFnid :: Stream (UTCTime, Trip) -> Stream (UTCTime, Trip)
streamGraphFnid = id


streamGraphFnM' :: (MonadState s m,
                   HasStriotState s (Stream (UTCTime, Journey)),
                   MonadIO m,
                   MonadBaseControl IO m)
               => Stream (UTCTime, Journey) -> m (Stream (UTCTime, (UTCTime, UTCTime), [(Journey, Int)]))
streamGraphFnM' s = streamMap (windowTopk)
                 <$> streamWindowM (slidingTimeM 180000) s
                 --   60000 = 1m
                 --  180000 = 3m
                 -- 1800000 = 30m


streamGraphFn :: Stream (UTCTime, Journey) -> Stream (UTCTime, (UTCTime, UTCTime), [(Journey, Int)])
streamGraphFn s = streamMap (windowTopk)
                $ streamWindow (slidingTime 180000) s


windowTopk :: [(UTCTime, Journey)] -> (UTCTime, (UTCTime, UTCTime), [(Journey, Int)])
windowTopk win =
    let (t, j)   = unzip win
        (lt, lj) = last win
    in  (lt, (pickupTime lj, dropoffTime lj), topk 10 j)


notopkwindowonly :: Stream (UTCTime, Journey) -> Stream [(UTCTime, Journey)]
notopkwindowonly s = streamWindow (slidingTime 180000) s

main :: IO ()
main = do
    conf <- decodeEnv :: IO (Either String StriotConfig)
    case conf of
        Left _  -> print "Could not read from env"
        Right c -> nodeLink c streamGraphFn
        -- Right c -> nodeLink c notopkwindowonly
