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
import           Control.Concurrent                            (threadDelay)
import           Control.Concurrent.Chan.Unagi.Bounded         as U
import           Control.Lens
import           Control.Monad.IO.Class
import           Control.Monad.Reader
import           Control.Monad.State
import           Control.Monad.Trans.Control
import qualified Control.Exception                        as E (bracket)
import           Kafka.Consumer                                as KC
import           Data.IORef
import           Data.Maybe
import           Data.Either                                   (fromRight)
import           Data.Store                                    (Store, encode, decodeEx)
import           Data.Text                                     as T (pack)
import           Data.Time                                     (getCurrentTime)
import           Network.Socket                                (HostName,
                                                                ServiceName)
import           Striot.FunctionalIoTtypes
import           Striot.Nodes.Kafka
import           Striot.Nodes.Kafka.Types
import           Striot.Nodes.MQTT
import           Striot.Nodes.TCP
import           Striot.Nodes.Types                            hiding (nc,
                                                                readConf,
                                                                writeConf)
import           System.Exit                                   (exitFailure, exitSuccess, ExitCode(..))
import           System.IO
import           System.IO.Unsafe
import           System.Metrics.Prometheus.Concurrent.Registry as PR (new, registerCounter,
                                                                      registerGauge,
                                                                      sample)
import           System.Metrics.Prometheus.Http.Scrape         (serveMetrics)
import           System.Metrics.Prometheus.Metric.Counter      as PC (inc)
import           System.Metrics.Prometheus.MetricId            (addLabel)
import qualified Database.Redis                                as R
import           System.Posix.Process                          (exitImmediately)


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
    sendStream metrics Nothing result


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
    (stream, kset) <- processInput metrics
    let result = streamOp stream
    sendStream metrics kset result


nodeLinkStateful :: (Store alpha, Store beta, Show gamma, Store gamma)
                 => StriotConfig
                 -> (Stream alpha -> App gamma (Stream beta))
                 -> IO ()
nodeLinkStateful config streamOp =
    evalStateT (runReaderT (unApp $ nodeLinkStateful' streamOp) config) defaultState


nodeLinkStateful' :: (Store alpha, Store beta, Show gamma, Show s, Store gamma,
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
    case (c ^. stateInit) of
        True      -> retrieveState (c ^. stateKey)
        otherwise -> return ()
    acc <- get
    liftIO $ print ("init new to : " ++ show acc)
    -- Check that input is KAFKA
    liftIO $ failFalse (matchConfig KAFKA (c ^. ingressConnConfig)) (matchConfig TCP (c ^. egressConnConfig))
    -- process stream
    metrics <- liftIO $ startPrometheus (c ^. nodeName)
    (stream, kset) <- processInput metrics
    -- perform streamop
    result <- streamOp stream
    sendStream metrics kset result
    -- If the stream ever ends we know that the acc must have been set
    acc <- get
    liftIO $ print acc
    -- Store the state in redis
    storeState
    -- liftIO $ threadDelay (1000*1000*120)
    liftIO $ exitImmediately ExitSuccess
    where
        failFalse False _     = print "No incoming KAFKA connection" >> exitFailure
        failFalse _     False = print "No outgoing KAFKA connection" >> exitFailure
        failFalse _     _     = return ()



matchConfig :: ConnectProtocol -> ConnectionConfig -> Bool
matchConfig TCP   (ConnTCPConfig   _) = True
matchConfig KAFKA (ConnKafkaConfig _) = True
matchConfig MQTT  (ConnMQTTConfig  _) = True
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
    -- should manually commit offsets once processed by iofn
    (stream, _) <- processInput metrics
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
        , _stateStore        = defaultStateStore
        , _stateInit         = False
        , _stateKey          = ""
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
defaultState = StriotState "" Nothing


defaultStateStore :: NetConfig
defaultStateStore = NetConfig "striot-redis" "6379"

--- INTERNAL OPS ---

processInput :: (Store alpha,
                MonadReader r m,
                HasStriotConfig r,
                MonadIO m)
             => Metrics
             -> m (Stream alpha, Maybe (KafkaConsumer, [(Int, KafkaRecord)]))
processInput metrics = connectDispatch metrics


connectDispatch :: (Store alpha,
                   MonadReader r m,
                   HasStriotConfig r,
                   MonadIO m)
                => Metrics
                -> m (Stream alpha, Maybe (KafkaConsumer, [(Int, KafkaRecord)]))
connectDispatch metrics = do
    c <- ask
    liftIO $ connectDispatch' (c ^. nodeName)
                              (c ^. ingressConnConfig)
                              metrics
                              (c ^. chanSize)


connectDispatch' :: (Store alpha,
                    MonadIO m)
                 => String
                 -> ConnectionConfig
                 -> Metrics
                 -> Int
                 -> m (Stream alpha, Maybe (KafkaConsumer, [(Int, KafkaRecord)]))
connectDispatch' name (ConnTCPConfig   cc) met chanSize =
    liftIO $ do
        (inChan, outChan) <- U.newChan chanSize
        async $ connectTCP name cc met inChan
        stream <- U.getChanContents outChan
        return (stream, Nothing)
connectDispatch' name (ConnKafkaConfig cc) met chanSize = do
    liftIO $ do
        (inChan, outChan) <- U.newChan chanSize
        consumer <- runKafkaConsumer' name cc met inChan
        (stream, kr) <- extractMessages outChan
        let kc = either (const Nothing) Just consumer
        return (stream, (,) <$> kc <*> pure kr)
        -- runKafkaConsumer name cc met chan
connectDispatch' name (ConnMQTTConfig  cc) met chanSize =
    liftIO $ do
        (inChan, outChan) <- U.newChan chanSize
        async $ runMQTTSub name cc met inChan
        stream <- U.getChanContents outChan
        return (stream, Nothing)


sendStream :: (Store alpha,
              MonadReader r m,
              HasStriotConfig r,
              MonadIO m)
           => Metrics
           -> Maybe (KafkaConsumer, [(Int, KafkaRecord)])
           -> Stream alpha
           -> m ()
sendStream metrics kset stream = do
    c <- ask
    liftIO
        $ sendDispatch (c ^. nodeName)
                       (c ^. egressConnConfig)
                       metrics
                       kset
                       stream


sendDispatch :: (Store alpha,
                MonadIO m)
             => String
             -> ConnectionConfig
             -> Metrics
             -> Maybe (KafkaConsumer, [(Int, KafkaRecord)])
             -> Stream alpha
             -> m ()
sendDispatch name (ConnTCPConfig   cc) met (Just kset) stream = liftIO $ sendStreamTCPS   name cc met kset stream
sendDispatch name (ConnTCPConfig   cc) met Nothing     stream = liftIO $ sendStreamTCP    name cc met      stream
sendDispatch name (ConnKafkaConfig cc) met _           stream = liftIO $ sendStreamKafka  name cc met      stream
sendDispatch name (ConnMQTTConfig  cc) met _           stream = liftIO $ sendStreamMQTT   name cc met      stream
-- sendDispatch name (ConnKafkaConfig cc) met (Just kc) stream = liftIO $ sendStreamKafkaS name cc met stream
-- sendDispatch name (ConnKafkaConfig cc) met Nothing   stream = liftIO $ sendStreamKafka  name cc met stream
-- sendDispatch name (ConnMQTTConfig  cc) met (Just kc) stream = liftIO $ sendStreamMQTTS  name cc met stream
-- sendDispatch name (ConnMQTTConfig  cc) met Nothing   stream = liftIO $ sendStreamMQTT   name cc met stream


readListFromSource :: IO alpha -> Metrics -> IO (Stream alpha)
readListFromSource = go 0
  where
    go i pay met = unsafeInterleaveIO $ do
        x  <- msg
        PC.inc (_ingressEvents met)
        xs <- go (i + 1) pay met
        return (x : xs)
      where
        msg = do
            now <- getCurrentTime
            Event i Nothing (Just now) . Just <$> pay


extractMessages :: U.OutChan (KafkaRecord, Event alpha) -> IO (Stream alpha, [(Int, KafkaRecord)])
extractMessages outChan = do
    -- Retrieve a stream of both the KafkaRecords (for offset commits)
    -- and the stream
    input <- liftIO $ U.getChanContents outChan
    let mapped = assignIds 0 input
    let kr     = map fst mapped
        stream = map snd mapped
    return (stream, kr)
    where
        assignIds i ((x,y):xs) = ((i, x), y {eventId = i}) : assignIds (i+1) xs

--- PROMETHEUS ---

startPrometheus :: String -> IO Metrics
startPrometheus name = do
    reg <- PR.new
    let lbl = addLabel "node" (T.pack name) mempty
        registerFn fn mName = fn mName lbl reg
        rg = registerFn registerGauge
        rc = registerFn registerCounter
    async $ serveMetrics 8080 ["metrics"] (PR.sample reg)
    Metrics
        <$> rg "striot_ingress_connection"
        <*> rc "striot_ingress_bytes_total"
        <*> rc "striot_ingress_events_total"
        <*> rg "striot_egress_connection"
        <*> rc "striot_egress_bytes_total"
        <*> rc "striot_egress_events_total"


--- REDIS ---

storeState :: (Store alpha,
               MonadReader r m,
               MonadState s m,
               HasStriotState s alpha,
               HasStriotConfig r,
               MonadIO m)
           => m ()
storeState = do
    s <- get
    connInfo <- getConnectInfo
    liftIO $ runRedis connInfo $ R.set (encode $ s ^. accKey) (encode $ s ^. accValue)
           >> return ()


retrieveState :: (Store alpha,
                  MonadReader r m,
                  MonadState s m,
                  HasStriotState s alpha,
                  HasStriotConfig r,
                  MonadIO m)
              => String
              -> m ()
retrieveState k = do
    connInfo <- getConnectInfo
    s <- liftIO $ do
            runRedis connInfo $ (decodeEx . fromJust . fromRight Nothing <$> R.get (encode k))
    accKey .= k >> accValue .= s


getConnectInfo :: (MonadReader r m,
                  HasStriotConfig r)
               => m (R.ConnectInfo)
getConnectInfo = do
    c <- ask
    return $ R.defaultConnectInfo { R.connectHost = (c ^. stateStore . host)
                                  , R.connectPort = (R.PortNumber $ read $ c ^. stateStore . port) }


runRedis :: R.ConnectInfo -> R.Redis a -> IO a
runRedis connInfo r = E.bracket (R.checkedConnect connInfo)
                                (R.disconnect)
                                (\conn -> R.runRedis conn $ r)
