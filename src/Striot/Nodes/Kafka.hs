{-# LANGUAGE OverloadedStrings #-}
module Striot.Nodes.Kafka
( sendStreamKafka
, runKafkaConsumer
, runKafkaConsumer'
) where

import           Control.Concurrent                       (threadDelay)
import           Control.Concurrent.Async                 (async)
import           Control.Concurrent.Chan.Unagi.Bounded    as U
import qualified Control.Exception                        as E (bracket)
import           Control.Lens
import           Control.Monad                            (forever, void)
import qualified Data.ByteString                          as B (ByteString,
                                                                length)
import           Data.Store                               (Store, decode,
                                                           encode)
import           Data.Text                                as T (Text, pack)
import           Kafka.Consumer                           as KC
import           Kafka.Producer                           as KP
import           Striot.FunctionalIoTtypes
import           Striot.Nodes.Types
import           Striot.Nodes.Kafka.Types
import           Striot.Nodes.TCP                               (connectTCP')
import           System.Metrics.Prometheus.Metric.Counter as PC (add, inc)
import           System.Metrics.Prometheus.Metric.Gauge   as PG (dec, inc)


sendStreamKafka :: Store alpha => String -> KafkaConfig -> Metrics -> Maybe (KafkaConsumer, [(Int, KafkaRecord)]) -> Stream alpha -> IO ()
sendStreamKafka name conf met kset stream =
    E.bracket mkProducer clProducer runHandler >>= print
        where
          mkProducer              = PG.inc (_egressConn met)
                                    >> print "create new producer"
                                    >> newProducer (producerProps conf)
          clProducer (Left _)     = print "error close producer"
                                    >> return ()
          clProducer (Right prod) = PG.dec (_egressConn met)
                                    >> closeProducer prod
                                    >> print "close producer"
          runHandler (Left err)   = return $ Left err
          runHandler (Right prod) = print "runhandler producer"
                                    >> sendMessagesKafka prod (TopicName . T.pack $ conf ^. kafkaTopic) met kset stream


kafkaConnectDelayMs :: Int
kafkaConnectDelayMs = 300000


producerProps :: KafkaConfig -> ProducerProperties
producerProps conf =
    KP.brokersList [BrokerAddress $ brokerAddress conf]
       <> KP.logLevel KafkaLogDebug


sendMessagesKafka :: Store alpha => KafkaProducer -> TopicName -> Metrics -> Maybe (KafkaConsumer, [(Int, KafkaRecord)]) -> Stream alpha -> IO (Either KafkaError ())
sendMessagesKafka prod topic met Nothing stream = do
    mapM_ (\event -> do
            let val = encode event
            produceMessage prod (mkMessage topic Nothing (Just val))
                >> PC.inc (_egressEvents met)
                >> PC.add (B.length val) (_egressBytes met)
          ) stream
    return $ Right ()
-- memory leak (kr never reduces in size)
-- sendMessagesKafka prod topic met (Just (kc, kr)) stream = do
--     mapM_ (\event -> do
--             let val = encode . tailManage $ event
--                 -- get all KafkaRecord structures <= current eventId
--                 rtc = map snd $ takeWhile (\x -> eventId event >= fst x) kr
--             produceMessage prod (mkMessage topic Nothing (Just val))
--                 >> PC.inc (_egressEvents met)
--                 >> PC.add (B.length val) (_egressBytes met)
--             mapM_ (storeOffsetMessage kc) rtc
--             ) stream
--     return $ Right ()
sendMessagesKafka prod topic met (Just (kc, kr)) (event:xs) = do
    let val = encode . tailManage $ event
        (artc, rest) = span (\x -> eventId event >= fst x) kr
        rtc = map snd artc
    produceMessage prod (mkMessage topic Nothing (Just val))
        >> PC.inc (_egressEvents met)
        >> PC.add (B.length val) (_egressBytes met)
    mapM_ (storeOffsetMessage kc) rtc
    sendMessagesKafka prod topic met (Just (kc, rest)) xs
    return $ Right ()



mkMessage :: TopicName -> Maybe B.ByteString -> Maybe B.ByteString -> ProducerRecord
mkMessage topic k v =
    ProducerRecord
        { prTopic     = topic
        , prPartition = UnassignedPartition
        , prKey       = k
        , prValue     = v
        }


runKafkaConsumer :: Store alpha => String -> KafkaConfig -> Metrics -> U.InChan (Event alpha) -> IO ()
runKafkaConsumer name conf met chan =
    E.bracket
        (mkConsumer conf met)
        (clConsumer met)
        (runHandler met chan)
    -- where
    --     mkConsumer                 = PG.inc (_ingressConn met)
    --                                  >> print "create new consumer"
    --                                  >> newConsumer (consumerProps conf)
    --                                                 (consumerSub $ TopicName . T.pack $ conf ^. kafkaTopic)
    --     clConsumer      (Left err) = print "error close consumer"
    --                                  >> return ()
    --     clConsumer      (Right kc) = void $ closeConsumer kc
    --                                       >> PG.dec (_ingressConn met)
    --                                       >> print "close consumer"
    --     runHandler _    (Left err) = print "error handler close consumer"
    --                                  >> return ()
    --     runHandler chan (Right kc) = print "runhandler consumer"
    --                                  >> processKafkaMessages met kc chan


runKafkaConsumer' :: Store alpha
                  => String
                  -> KafkaConfig
                  -> Metrics
                  -> U.InChan (KafkaRecord, (Event alpha))
                  -> IO (Either KafkaError KafkaConsumer)
runKafkaConsumer' name conf met chan = do
    kc <- mkConsumer conf met
    async $ runHandler' met chan kc
          >> clConsumer met kc
    async $ connectTCP' name defaultTCPConfig met chan
    return kc


mkConsumer :: KafkaConfig -> Metrics -> IO (Either KafkaError KafkaConsumer)
mkConsumer conf met = PG.inc (_ingressConn met)
                    >> print "create new consumer"
                    >> newConsumer (consumerProps conf)
                                (consumerSub $ TopicName . T.pack $ conf ^. kafkaTopic)

clConsumer :: Metrics -> Either KafkaError KafkaConsumer -> IO ()
clConsumer met (Left err) = print "error close consumer"
                                     >> return ()
clConsumer met (Right kc) = void
                          $ closeConsumer kc
                            >> PG.dec (_ingressConn met)
                            >> print "close consumer"

runHandler :: Store alpha
           => Metrics
           -> U.InChan (Event alpha)
           -> Either KafkaError KafkaConsumer
           -> IO ()
runHandler _   _    (Left err) = print "error handler close consumer"
                               >> return ()
runHandler met chan (Right kc) = print "runhandler consumer"
                               >> threadDelay kafkaConnectDelayMs
                               >> processKafkaMessages met kc chan


processKafkaMessages :: Store alpha => Metrics -> KafkaConsumer -> U.InChan (Event alpha) -> IO ()
processKafkaMessages met kc chan = forever $ do
    threadDelay kafkaConnectDelayMs
    msg <- pollMessage kc (Timeout 50)
    either (\_ -> return ()) extractValue msg
      where
        extractValue m = maybe (print "kafka-error: crValue Nothing") writeRight (crValue m)
        writeRight   v = either (\err -> print $ "decode-error: " ++ show err)
                                (\x -> do
                                    PC.inc (_ingressEvents met)
                                        >> PC.add (B.length v) (_ingressBytes met)
                                    U.writeChan chan x)
                                (decode v)


runHandler' :: Store alpha
           => Metrics
           -> U.InChan (KafkaRecord, (Event alpha))
           -> Either KafkaError KafkaConsumer
           -> IO ()
runHandler' _   _    (Left err) = print "error handler close consumer"
                                   >> return ()
runHandler' met chan (Right kc) = print "runhandler consumer"
                                   >> threadDelay kafkaConnectDelayMs
                                -- >> threadDelay 30000000
                                -- >> pollMessage kc (Timeout 50)
                                -- >> threadDelay 30000000
                                   >> processKafkaMessages' met kc chan




processKafkaMessages' :: Store alpha => Metrics -> KafkaConsumer -> U.InChan (KafkaRecord, (Event alpha)) -> IO ()
processKafkaMessages' met kc chan = forever $ do
    msg <- pollMessage kc (Timeout 50)
    either (\_ -> return ()) writeKR msg
    -- processKafkaMessages' met kc chan
      where
        writeKR m =
            let (Just v) = crValue m
            in  either  (\err -> do
                            print $ "decode-error: " ++ show err)
                        (\x -> do
                            PC.inc (_ingressEvents met)
                                >> PC.add (B.length v) (_ingressBytes met)
                            U.writeChan chan (m, x))
                        (decode v)


consumerProps :: KafkaConfig -> ConsumerProperties
consumerProps conf =
    KC.brokersList [BrokerAddress $ brokerAddress conf]
        <> groupId (ConsumerGroupId . T.pack $ conf ^. kafkaConGroup)
        <> KC.logLevel KafkaLogInfo
        -- <> KC.debugOptions [DebugAll]
        -- test no auto commit
        -- THIS HAS TO BE BEFORE CALLBACKPOLLMODE FOR SOME REASON
        -- <> KC.noAutoCommit
        <> KC.noAutoOffsetStore
        -- <> extraProp "session.timeout.ms" "120000"
        -- <> (KC.setCallback $ rebalanceCallback rbCallBack)
        -- <> (KC.setCallback $ offsetCommitCallback ocCallBack)
        -- WE CAN NOT ADD OPTIONS AFTER THIS LAST ONE
        -- (OR AT LEAST NOAUTOCOMMIT / NOAUTOOFFSETSTORE)
        -- DO NOT WORK BELOW THIS LINE FOR SOME REASON
        <> KC.callbackPollMode CallbackPollModeSync


-- rbCallBack :: KafkaConsumer -> RebalanceEvent -> IO ()
-- rbCallBack kc e@(RebalanceBeforeAssign xs) = print ("REB_CALLBACK: " ++ show e)
-- rbCallBack kc e@(RebalanceAssign       xs) = print ("REB_CALLBACK: " ++ show e)
-- rbCallBack kc e@(RebalanceBeforeRevoke xs) = print ("REB_CALLBACK: " ++ show e)
-- rbCallBack kc e@(RebalanceRevoke       xs) = print ("REB_CALLBACK: " ++ show e)

-- ocCallBack :: KafkaConsumer -> KafkaError -> [TopicPartition] -> IO ()
-- ocCallBack kc ke xs = print ("OC_CALLBACK: " ++ show ke ++ " XS: " ++ show xs)

consumerSub :: TopicName -> Subscription
consumerSub topic = topics [topic]
                    <> offsetReset Earliest


brokerAddress :: KafkaConfig -> T.Text
brokerAddress conf = T.pack $ (conf ^. kafkaConn . host) ++ ":" ++ (conf ^. kafkaConn . port)


defaultTCPConfig :: TCPConfig
defaultTCPConfig = TCPConfig $ NetConfig "" "9001"