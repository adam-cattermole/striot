{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE AllowAmbiguousTypes #-}
module Striot.Nodes ( nodeSource
                    , nodeLink
                    , nodeLinkStateful
                    , nodeLink2
                    , nodeSink
                    , nodeSink2
                    , defaultConfig
                    , defaultSource
                    , defaultLink
                    , defaultSink
                    , sendStream -- REMOVE
                    , startPrometheus -- REMOVE
                    ) where

import           Control.Concurrent.Async                      (async)
import           Control.Concurrent.Chan.Unagi.Bounded         as U
import           Control.Lens
import           Control.Monad.IO.Class
import           Control.Monad.Reader
import           Control.Monad.State
import           Control.Monad.Trans.Control
import           Data.IORef
import           Data.Maybe
import           Data.Store                                    (Store)
import           Data.Text                                     as T (pack)
import           Data.Time                                     (getCurrentTime)
import           Network.Socket                                (HostName,
                                                                ServiceName)
import           Striot.FunctionalIoTtypes
import           Striot.Nodes.Kafka
import           Striot.Nodes.MQTT
import           Striot.Nodes.TCP
import           Striot.Nodes.Types                            hiding (nc,
                                                                readConf,
                                                                writeConf)
import           System.Exit                                   (exitFailure)
import           System.IO
import           System.IO.Unsafe
import           System.Metrics.Prometheus.Concurrent.Registry as PR (new, registerCounter,
                                                                      registerGauge,
                                                                      sample)
import           System.Metrics.Prometheus.Http.Scrape         (serveHttpTextMetrics)
import           System.Metrics.Prometheus.Metric.Counter      as PC (inc)
import           System.Metrics.Prometheus.MetricId            (addLabel)


-- NODE FUNCTIONS

nodeSource :: (Store alpha, Store beta)
           => StriotConfig
           -> IO alpha
           -> (Stream alpha -> Stream beta)
           -> IO ()
nodeSource config iofn streamOp =
    runReaderT (unStriotApp $ nodeSource' iofn streamOp) config


nodeSource' :: (Store alpha, Store beta,
               MonadReader r m,
               HasStriotConfig r,
               MonadIO m)
            => IO alpha
            -> (Stream alpha -> Stream beta) -> m ()
nodeSource' iofn streamOp = do
    c <- ask
    metrics <- liftIO $ startPrometheus (c ^. nodeName)
    stream <- liftIO $ readListFromSource iofn metrics
    let result = streamOp stream
    sendStream metrics result


nodeLink :: (Store alpha, Store beta)
         => StriotConfig
         -> (Stream alpha -> Stream beta)
         -> IO ()
nodeLink config streamOp =
    runReaderT (unStriotApp $ nodeLink' streamOp) config


nodeLink' :: (Store alpha, Store beta,
             MonadReader r m,
             HasStriotConfig r,
             MonadIO m)
          => (Stream alpha -> Stream beta)
          -> m ()
nodeLink' streamOp = do
    c <- ask
    metrics <- liftIO $ startPrometheus (c ^. nodeName)
    stream <- processInput metrics
    let result = streamOp stream
    sendStream metrics result


nodeLinkStateful :: (Store alpha, Store beta, Show gamma)
                 => StriotConfig
                 -> (Stream alpha -> App gamma (Stream beta))
                 -> IO ()
nodeLinkStateful config streamOp =
    evalStateT (runReaderT (unApp $ nodeLinkStateful' streamOp) config) defaultState


nodeLinkStateful' :: (Store alpha, Store beta, Show gamma, Show s,
                    MonadReader r m,
                    MonadState s m,
                    HasStriotState s gamma,
                    HasStriotConfig r,
                    MonadIO m,
                    MonadBaseControl IO m)
                 => (Stream alpha -> m (Stream beta))
                 -> m ()
nodeLinkStateful' streamOp = do
    c <- ask
    liftIO $ failFalse (matchConfig KAFKA (c ^. ingressConnConfig)) (matchConfig TCP (c ^. egressConnConfig))
    let ConnKafkaConfig kafkaConf = (c ^. ingressConnConfig)
    metrics <- liftIO $ startPrometheus (c ^. nodeName)
    (metrics, outChan, kc) <- liftIO $ do
            met <- startPrometheus (c ^. nodeName)
            (inChan, outChan) <- U.newChan (c ^. chanSize)
            consumer <- runKafkaConsumer' (c ^. nodeName)
                                          kafkaConf
                                          met
                                          inChan
            return (met, outChan, consumer)
    result <- streamOp =<< (liftIO $ U.getChanContents outChan)
    sendStream metrics result
    acc <- get
    liftIO $ print acc
    where
        failFalse False _     = print "No incoming KAFKA connection" >> exitFailure
        failFalse _     False = print "No outgoing KAFKA connection" >> exitFailure
        failFalse _     _     = return ()


-- matchConfig :: ConnectProtocol -> ConnectionConfig -> Bool
-- matchConfig TCP   cc =
--     case cc of
--         ConnTCPConfig _ -> True
--         _               -> False
-- matchConfig KAFKA cc =
--     case cc of
--         ConnKafkaConfig _ -> True
--         _                 -> False
-- matchConfig MQTT  cc =
--     case cc of
--         ConnMQTTConfig _ -> True
--         _                -> False


matchConfig :: ConnectProtocol -> ConnectionConfig -> Bool
matchConfig TCP   (ConnTCPConfig   _) = True
-- matchConfig TCP   _                   = False
matchConfig KAFKA (ConnKafkaConfig _) = True
-- matchConfig KAFKA _                   = False
matchConfig MQTT  (ConnMQTTConfig  _) = True
-- matchConfig MQTT  _                   = False
matchConfig _     _                   = False


-- Old style configless link with 2 inputs
nodeLink2 :: (Store alpha, Store beta, Store gamma)
          => (Stream alpha -> Stream beta -> Stream gamma)
          -> ServiceName
          -> ServiceName
          -> HostName
          -> ServiceName
          -> IO ()
nodeLink2 streamOp inputPort1 inputPort2 outputHost outputPort = do
    let nodeName = "node-link"
        (ConnTCPConfig ic1) = tcpConfig "" inputPort1
        (ConnTCPConfig ic2) = tcpConfig "" inputPort2
        (ConnTCPConfig ec)  = tcpConfig outputHost outputPort
    metrics <- startPrometheus nodeName
    putStrLn "Starting link ..."
    stream1 <- processSocket nodeName ic1 metrics
    stream2 <- processSocket nodeName ic2 metrics
    let result = streamOp stream1 stream2
    sendStreamTCP nodeName ec metrics result


nodeSink :: (Store alpha, Store beta)
         => StriotConfig
         -> (Stream alpha -> Stream beta)
         -> (Stream beta -> IO ())
         -> IO ()
nodeSink config streamOp iofn =
    runReaderT (unStriotApp $ nodeSink' streamOp iofn) config


nodeSink' :: (Store alpha, Store beta,
             MonadReader r m,
             HasStriotConfig r,
             MonadIO m)
          => (Stream alpha -> Stream beta)
          -> (Stream beta -> IO ())
          -> m ()
nodeSink' streamOp iofn = do
    c <- ask
    metrics <- liftIO $ startPrometheus (c ^. nodeName)
    stream <- processInput metrics
    let result = streamOp stream
    liftIO $ iofn result


-- Old style configless sink with 2 inputs
nodeSink2 :: (Store alpha, Store beta, Store gamma)
          => (Stream alpha -> Stream beta -> Stream gamma)
          -> (Stream gamma -> IO ())
          -> ServiceName
          -> ServiceName
          -> IO ()
nodeSink2 streamOp iofn inputPort1 inputPort2 = do
    let nodeName = "node-sink"
        (ConnTCPConfig ic1) = tcpConfig "" inputPort1
        (ConnTCPConfig ic2) = tcpConfig "" inputPort2
    metrics <- startPrometheus nodeName
    putStrLn "Starting sink ..."
    stream1 <- processSocket nodeName ic1 metrics
    stream2 <- processSocket nodeName ic2 metrics
    let result = streamOp stream1 stream2
    iofn result


--- CONFIG FUNCTIONS ---

defaultConfig :: String
              -> HostName
              -> ServiceName
              -> HostName
              -> ServiceName
              -> StriotConfig
defaultConfig = defaultConfig' TCP TCP


defaultSource :: HostName -> ServiceName -> StriotConfig
defaultSource = defaultConfig "striot-source" "" ""


defaultLink :: ServiceName -> HostName -> ServiceName -> StriotConfig
defaultLink = defaultConfig "striot-link" ""


defaultSink :: ServiceName -> StriotConfig
defaultSink port = defaultConfig "striot-sink" "" port "" ""


defaultConfig' :: ConnectProtocol
               -> ConnectProtocol
               -> String
               -> HostName
               -> ServiceName
               -> HostName
               -> ServiceName
               -> StriotConfig
defaultConfig' ict ect name inHost inPort outHost outPort =
    let ccf ct = case ct of
                    TCP   -> tcpConfig
                    KAFKA -> defaultKafkaConfig
                    MQTT  -> defaultMqttConfig
    in  baseConfig name (ccf ict inHost inPort) (ccf ect outHost outPort)


baseConfig :: String -> ConnectionConfig -> ConnectionConfig -> StriotConfig
baseConfig name icc ecc =
    StriotConfig
        { _nodeName          = name
        , _ingressConnConfig = icc
        , _egressConnConfig  = ecc
        , _chanSize          = 10
        -- , _stateful          = False
        }


tcpConfig :: HostName -> ServiceName -> ConnectionConfig
tcpConfig host port =
    ConnTCPConfig $ TCPConfig $ NetConfig host port


kafkaConfig :: String -> String -> HostName -> ServiceName -> ConnectionConfig
kafkaConfig topic conGroup host port =
    ConnKafkaConfig $ KafkaConfig (NetConfig host port) topic conGroup


defaultKafkaConfig :: HostName -> ServiceName -> ConnectionConfig
defaultKafkaConfig = kafkaConfig "striot-queue" "striot_consumer_group"


mqttConfig :: String -> HostName -> ServiceName -> ConnectionConfig
mqttConfig topic host port =
    ConnMQTTConfig $ MQTTConfig (NetConfig host port) topic


defaultMqttConfig :: HostName -> ServiceName -> ConnectionConfig
defaultMqttConfig = mqttConfig "StriotQueue"


defaultState :: (Show alpha) => StriotState alpha
defaultState = StriotState 0 undefined

--- INTERNAL OPS ---

processInput :: (Store alpha,
                MonadReader r m,
                HasStriotConfig r,
                MonadIO m)
             => Metrics
             -> m (Stream alpha)
processInput metrics = connectDispatch metrics >>= (liftIO . U.getChanContents)


connectDispatch :: (Store alpha,
                   MonadReader r m,
                   HasStriotConfig r,
                   MonadIO m)
                => Metrics
                -> m (U.OutChan (Event alpha))
connectDispatch metrics = do
    c <- ask
    liftIO $ do
        (inChan, outChan) <- U.newChan (c ^. chanSize)
        async $ connectDispatch' (c ^. nodeName)
                                 (c ^. ingressConnConfig)
                                 metrics
                                 inChan
        return outChan


connectDispatch' :: (Store alpha,
                    MonadIO m)
                 => String
                 -> ConnectionConfig
                 -> Metrics
                 -> U.InChan (Event alpha)
                 -> m ()
connectDispatch' name (ConnTCPConfig   cc) met chan = liftIO $ connectTCP       name cc met chan
connectDispatch' name (ConnKafkaConfig cc) met chan = liftIO $ runKafkaConsumer name cc met chan
connectDispatch' name (ConnMQTTConfig  cc) met chan = liftIO $ runMQTTSub       name cc met chan


sendStream :: (Store alpha,
              MonadReader r m,
              HasStriotConfig r,
              MonadIO m)
           => Metrics
           -> Stream alpha
           -> m ()
sendStream metrics stream = do
    c <- ask
    liftIO
        $ sendDispatch (c ^. nodeName)
                       (c ^. egressConnConfig)
                       metrics
                       stream


sendDispatch :: (Store alpha,
                MonadIO m)
             => String
             -> ConnectionConfig
             -> Metrics
             -> Stream alpha
             -> m ()
sendDispatch name (ConnTCPConfig   cc) met stream = liftIO $ sendStreamTCP   name cc met stream
sendDispatch name (ConnKafkaConfig cc) met stream = liftIO $ sendStreamKafka name cc met stream
sendDispatch name (ConnMQTTConfig  cc) met stream = liftIO $ sendStreamMQTT  name cc met stream


readListFromSource :: IO alpha -> Metrics -> IO (Stream alpha)
readListFromSource = go
  where
    go pay met = unsafeInterleaveIO $ do
        x  <- msg
        PC.inc (_ingressEvents met)
        xs <- go pay met
        return (x : xs)
      where
        msg = do
            now <- getCurrentTime
            Event Nothing (Just now) . Just <$> pay


--- PROMETHEUS ---

startPrometheus :: String -> IO Metrics
startPrometheus name = do
    reg <- PR.new
    let lbl = addLabel "node" (T.pack name) mempty
        registerFn fn mName = fn mName lbl reg
        rg = registerFn registerGauge
        rc = registerFn registerCounter
    async $ serveHttpTextMetrics 8080 ["metrics"] (PR.sample reg)
    Metrics
        <$> rg "striot_ingress_connection"
        <*> rc "striot_ingress_bytes_total"
        <*> rc "striot_ingress_events_total"
        <*> rg "striot_egress_connection"
        <*> rc "striot_egress_bytes_total"
        <*> rc "striot_egress_events_total"
