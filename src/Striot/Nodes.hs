{-# LANGUAGE DataKinds         #-}
{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedStrings #-}
module Striot.Nodes ( nodeSink
                    , nodeSink2
                    , nodeLink
                    , nodeLink2
                    , nodeSource
                    -- , nodeSourceAmq
                    , nodeSourceMqtt
                    -- , nodeLinkAmq
                    , nodeLinkMqtt
                    ) where

import           Conduit                                       hiding (connect)
import           Control.Concurrent                            (forkFinally,
                                                                yield)
import           Control.Concurrent.Async                      (async,
                                                                concurrently)
import           Control.Concurrent.Chan.Unagi.Bounded         as U
import           Control.Concurrent.STM
import           Control.DeepSeq                               (force)
import qualified Control.Exception                             as E (bracket,
                                                                     catch,
                                                                     evaluate)
import           Control.Monad                                 (forever, liftM2,
                                                                unless, void,
                                                                when)
-- import           Data.Aeson hiding (encode, decode)
import qualified Data.Attoparsec.ByteString.Char8              as A
import qualified Data.ByteString                               as B (ByteString,
                                                                     length,
                                                                     null)
import qualified Data.ByteString.Char8                         as BC
import qualified Data.ByteString.Lazy.Char8                    as BLC
import           Data.Conduit.Network
import qualified Data.Conduit.Text                             as CT
import           Data.Maybe
import           Data.Store                                    (Store, encode, decode)
import qualified Data.Store.Streaming                          as SS
import           Data.Text                                     as T (Text, pack)
import           Data.Time                                     (getCurrentTime)
import qualified Network.MQTT                                  as MQTT
import           Network.MQTT.Client
import           Network.Socket
import           Network.Socket.ByteString
import           Striot.FunctionalIoTtypes
import           System.Exit                                   (exitFailure)
import           System.IO
import           System.IO.ByteBuffer                          as BB
import           System.IO.Unsafe
import           System.Metrics.Prometheus.Concurrent.Registry as PR (new, registerCounter,
                                                                      registerGauge,
                                                                      sample)
import           System.Metrics.Prometheus.Http.Scrape         (serveHttpTextMetrics)
import           System.Metrics.Prometheus.Metric.Counter      as PC (Counter,
                                                                      add, inc)
import           System.Metrics.Prometheus.Metric.Gauge        as PG (Gauge,
                                                                      dec, inc)
import           System.Metrics.Prometheus.MetricId            (addLabel)

-- type HostName   = String
-- type PortNumber = Int

data Metrics = Metrics { _ingressConn   :: Gauge
                       , _ingressBytes  :: Counter
                       , _ingressEvents :: Counter
                       , _egressConn    :: Gauge
                       , _egressBytes   :: Counter
                       , _egressEvents  :: Counter }


--- SINK FUNCTIONS ---

nodeSink :: (Store alpha, Store beta)
         => (Stream alpha -> Stream beta)
         -> (Stream beta -> IO ())
         -> ServiceName
         -> IO ()
nodeSink streamOp iofn inputPort = do
    sock <- listenSocket inputPort
    metrics <- startPrometheus "node-sink"
    putStrLn "Starting server ..."
    stream <- processSocket metrics sock
    let result = streamOp stream
    iofn result

-- A Sink with 2 inputs
nodeSink2 :: (Store alpha, Store beta, Store gamma)
          => (Stream alpha -> Stream beta -> Stream gamma)
          -> (Stream gamma -> IO ())
          -> ServiceName
          -> ServiceName
          -> IO ()
nodeSink2 streamOp iofn inputPort1 inputPort2 = do
    sock1 <- listenSocket inputPort1
    sock2 <- listenSocket inputPort2
    metrics <- startPrometheus "node-sink"
    putStrLn "Starting server ..."
    stream1 <- processSocket metrics sock1
    stream2 <- processSocket metrics sock2
    let result = streamOp stream1 stream2
    iofn result


--- LINK FUNCTIONS ---

nodeLink :: (Store alpha, Store beta)
         => (Stream alpha -> Stream beta)
         -> ServiceName
         -> HostName
         -> ServiceName
         -> IO ()
nodeLink streamOp inputPort outputHost outputPort = do
    sock <- listenSocket inputPort
    metrics <- startPrometheus "node-link"
    putStrLn "Starting link ..."
    stream <- processSocket metrics sock
    let result = streamOp stream
    sendStream result metrics outputHost outputPort


-- A Link with 2 inputs
nodeLink2 :: (Store alpha, Store beta, Store gamma)
          => (Stream alpha -> Stream beta -> Stream gamma)
          -> ServiceName
          -> ServiceName
          -> HostName
          -> ServiceName
          -> IO ()
nodeLink2 streamOp inputPort1 inputPort2 outputHost outputPort = do
    sock1 <- listenSocket inputPort1
    sock2 <- listenSocket inputPort2
    metrics <- startPrometheus "node-link"
    putStrLn "Starting link ..."
    stream1 <- processSocket metrics sock1
    stream2 <- processSocket metrics sock2
    let result = streamOp stream1 stream2
    sendStream result metrics outputHost outputPort


--- SOURCE FUNCTIONS ---

nodeSource :: Store beta
           => IO alpha
           -> (Stream alpha -> Stream beta)
           -> HostName
           -> ServiceName
           -> IO ()
nodeSource pay streamGraph host port = do
    metrics <- startPrometheus "node-source"
    putStrLn "Starting source ..."
    stream <- readListFromSource pay metrics
    let result = streamGraph stream
    sendStream result metrics host port -- or printStream if it's a completely self contained streamGraph


--- LINK FUNCTIONS - AcitveMQ ---


nodeLinkMqtt :: (Store alpha, Store beta) => (Stream alpha -> Stream beta) -> String -> HostName -> ServiceName -> HostName -> ServiceName -> IO ()
nodeLinkMqtt streamOp podName inputHost inputPort outputHost outputPort = do
    metrics <- startPrometheus podName
    putStrLn "Starting link ..."
    stream <- processSocketMqtt podName inputHost (read inputPort)
    let result = streamOp stream
    sendStream result metrics outputHost outputPort


--- SOURCE FUNCTIONS - ActiveMQ ---


nodeSourceMqtt :: Store beta => IO alpha -> (Stream alpha -> Stream beta) -> String -> HostName -> ServiceName -> IO ()
nodeSourceMqtt pay streamOp podName host port = do
    metrics <- startPrometheus podName
    putStrLn "Starting source ..."
    stream <- readListFromSource pay metrics
    let result = streamOp stream
    sendStreamMqtt result metrics podName host (read port)


--- UTILITY FUNCTIONS ---

readListFromSource :: IO alpha -> Metrics -> IO (Stream alpha)
readListFromSource = go 0
  where
    go i pay met = unsafeInterleaveIO $ do
        x  <- msg i
        PC.inc (_ingressEvents met)
        xs <- go (i + 1) pay met    -- This will overflow eventually
        return (x : xs)
      where
        msg x = do
            now     <- getCurrentTime
            Event x (Just now) . Just <$> pay


--- AMQ MQTT ---

processSocketMqtt :: Store alpha => String -> HostName -> PortNumber -> IO (Stream alpha)
processSocketMqtt podName host port = U.getChanContents =<< acceptConnectionsMqtt podName host port


acceptConnectionsMqtt :: Store alpha => String -> HostName -> PortNumber -> IO (U.OutChan (Event alpha))
acceptConnectionsMqtt podName host port = do
    (inChan, outChan) <- U.newChan chanSize
    async $ runMqttSub (T.pack podName) mqttTopics host port inChan
    -- async $ runMqttSub podName host port inChan
    return outChan


sendStreamMqtt :: Store alpha => Stream alpha -> Metrics -> String -> HostName -> PortNumber -> IO ()
sendStreamMqtt stream met podName host port = do
    mc <- runMqttPub podName host port
    mapM_ (\x -> do
                    val <- E.evaluate . force . encode $ x
                    PC.inc (_egressEvents met)
                        >> PC.add (B.length val) (_egressBytes met)
                        >> publishq mc (head netmqttTopics) (BLC.fromStrict val) False QoS0) stream


sendStreamMqtt' :: Store alpha => Stream alpha -> Metrics -> String -> HostName -> PortNumber -> IO ()
sendStreamMqtt' stream met podName host port = do
    (conf, _) <- mqttConf (T.pack podName) host port
    async $ runMqtt' (return ()) conf
    mapM_ (\x -> do
                    val <- E.evaluate . force . encode $ x
                    PC.inc (_egressEvents met)
                        >> PC.add (B.length val) (_egressBytes met)
                        >> MQTT.publish conf MQTT.NoConfirm False (head mqttTopics) val) stream


sendStreamMqttMulti :: Store alpha => Stream alpha -> Metrics -> String -> HostName -> PortNumber -> IO ()
sendStreamMqttMulti stream met podName host port = do
    (inChan, outChan) <- U.newChan chanSize
    mapM_ (\x ->
        async $ do
            mc <- runMqttPub (podName++show x) host port
            vals <- U.getChanContents outChan
            mapM_ (\x -> let val = encode x
                         in  PC.inc (_egressEvents met)
                             >> PC.add (B.length val) (_egressBytes met)
                             >> publishq mc (head netmqttTopics) (BLC.fromStrict val) False QoS0) vals) [1..numThreads]
    U.writeList2Chan inChan stream

sendStreamMqttMulti' :: Store alpha => Stream alpha -> Metrics -> String -> HostName -> PortNumber -> IO ()
sendStreamMqttMulti' stream met podName host port = do
    (inChan, outChan) <- U.newChan chanSize
    mapM_ (\x ->
        async $ do
            (conf, _) <- mqttConf (T.pack $ podName ++ show x) host port
            async $ runMqtt' (return ()) conf
            vals <- U.getChanContents outChan
            mapM_ (\x -> let val = encode x
                         in  PC.inc (_egressEvents met)
                             >> PC.add (B.length val) (_egressBytes met)
                             >> MQTT.publish conf MQTT.NoConfirm False (head mqttTopics)  val) vals) [1..numThreads]
    U.writeList2Chan inChan stream


numThreads :: Int
numThreads = 4

-- NET-MQTT

netmqttTopics :: [Topic]
netmqttTopics = ["StriotQueue"]


runMqttPub :: String -> HostName -> PortNumber -> IO MQTTClient
runMqttPub podName host port =
    runClient $ netmqttConf podName host port Nothing


-- runMqttSub :: String -> HostName -> PortNumber -> U.InChan (Event alpha) -> IO ()
-- -- runMqttSub :: (FromJSON alpha) => String -> HostName -> PortNumber -> U.InChan (Event alpha) -> IO ()
-- runMqttSub podName host port inChan = do
--     print "Run client..."
--     mc <- runClient $ mqttConf podName host port (Just msgReceived)
--     print "Subscribing..."
--     print =<< subscribe mc [(head mqttTopics, QoS0)]
--     -- print "Wait for client..."
--     print =<< waitForClient mc   -- wait for the the client to disconnect
--         where
--             -- msgReceived _ _ m = case decode m of
--                                     -- Just val -> U.writeChan inChan val
--                                     -- Nothing  -> return ()
--             msgReceived _ t m = print (t,m)
--
--
netmqttConf :: String -> HostName -> PortNumber -> Maybe (MQTTClient -> Topic -> BLC.ByteString -> IO ()) -> MQTTConfig
netmqttConf podName host port msgCB = mqttConfig{_hostname = host
                                                ,_port     = fromIntegral port
                                                ,_connID   = podName
                                                ,_username = Just "admin"
                                                ,_password = Just "yy^U#Fca!52Y"
                                                ,_msgCB    = msgCB}


-- MQTT-HS

mqttTopics :: [MQTT.Topic]
mqttTopics = ["StriotQueue"]


runMqttSub :: Store alpha => T.Text -> [MQTT.Topic] -> HostName -> PortNumber -> U.InChan (Event alpha) -> IO ()
runMqttSub podName topics host port ch = do
    (conf, pubChan) <- mqttConf podName host port
    async $ runMqtt' (mqttSub conf pubChan topics) conf
    byteStream <- map (MQTT.payload . MQTT.body) <$> getChanLazy pubChan
    U.writeList2Chan ch $ mapRight decode byteStream
    -- U.writeList2Chan ch =<< mapMaybe decodeStrict $ getChanLazy pubChan

mapRight :: (a -> Either c b) -> [a] -> [b]
mapRight _ []     = []
mapRight f (x:xs) =
 let rs = mapRight f xs in
 case f x of
  Left _ -> rs
  Right r  -> r:rs

getChanLazy :: TChan a -> IO [a]
getChanLazy ch = unsafeInterleaveIO (do
                            x  <- unsafeInterleaveIO $ atomically . readTChan $ ch
                            xs <- getChanLazy ch
                            return (x:xs)
                        )


runMqtt' :: IO () -> MQTT.Config -> IO ()
runMqtt' op conf =
    forever $
        E.catch
            (op >> MQTT.run conf >>= print)
            (\e -> do
                let err = show (e :: IOError)
                hPutStr stderr $ "MQTT failed with message: " ++ err ++ "\n"
                return ())


mqttConf :: T.Text -> HostName -> PortNumber -> IO (MQTT.Config, TChan (MQTT.Message 'MQTT.PUBLISH))
mqttConf podName host port = do
    pubChan <- newTChanIO
    cmds <- MQTT.mkCommands
    let conf = (MQTT.defaultConfig cmds pubChan)
                    { MQTT.cHost = host
                    , MQTT.cPort = fromIntegral port
                    , MQTT.cUsername = Just "admin"
                    , MQTT.cPassword = Just "yy^U#Fca!52Y"
                    , MQTT.cClientID = podName
                    , MQTT.cKeepAlive = Just 64000
                    , MQTT.cClean = True}
    return (conf, pubChan)


mqttSub :: MQTT.Config -> TChan (MQTT.Message 'MQTT.PUBLISH) -> [MQTT.Topic] -> IO ()
mqttSub conf pubChan topics = do
    async $ do
        putStrLn "Subscribe to topics"
        qosGranted <- MQTT.subscribe conf $ map (\x -> (x, MQTT.NoConfirm)) topics
        let isHs x =
                case x of
                    MQTT.NoConfirm -> True
                    _              -> False
        if length (filter isHs qosGranted) == length topics
            then putStrLn "Topic Handshake Success!"
            else do
                hPutStrLn stderr $ "Wanted QoS Handshake, got " ++ show qosGranted
                exitFailure
    return ()


-- Old connection stuff

{- processSocket is a wrapper function that handles concurrently
accepting and handling connections on the socket and reading all of the strings
into an event Stream -}
processSocket :: Store alpha => Metrics -> Socket -> IO (Stream alpha)
processSocket met sock = U.getChanContents =<< acceptConnections met sock


{- acceptConnections takes a socket as an argument and spins up a new thread to
process the data received. The returned TChan object contains the data from
the socket -}
acceptConnections :: Store alpha => Metrics -> Socket -> IO (U.OutChan (Event alpha))
acceptConnections met sock = do
    (inChan, outChan) <- U.newChan chanSize
    async $ connectionHandler met sock inChan
    return outChan


{- We are using a bounded queue to prevent extreme memory usage when
input rate > consumption rate. This value may need to be increased to achieve
higher throughput when computation costs are low -}
chanSize :: Int
chanSize = 10


{- connectionHandler sits accepting any new connections. Once accepted, a new
thread is forked to read from the socket. The function then loops to accept any
subsequent connections -}
connectionHandler :: Store alpha => Metrics -> Socket -> U.InChan (Event alpha) -> IO ()
connectionHandler met sockIn eventChan = forever $ do
    (conn, _) <- accept sockIn
    forkFinally (PG.inc (_ingressConn met)
                 >> processData met conn eventChan)
                (\_ -> PG.dec (_ingressConn met)
                       >> close conn)


{- processData takes a Socket and UChan. All of the events are read through
use of a ByteBuffer and recv. The events are decoded by using store-streaming
and added to the chan  -}
processData :: Store alpha => Metrics -> Socket -> U.InChan (Event alpha) -> IO ()
processData met conn eventChan =
    BB.with Nothing $ \buffer -> forever $ do
        event <- decodeMessageBS' met buffer (readFromSocket conn)
        case event of
            Just m  -> do
                        PC.inc (_ingressEvents met)
                        U.writeChan eventChan $ SS.fromMessage m
            Nothing -> print "decode failed"


{- This is a rewrite of Data.Store.Streaming decodeMessageBS, passing in
Metrics so that we can calculate ingressBytes while decoding -}
decodeMessageBS' :: Store a
                 => Metrics -> BB.ByteBuffer
                 -> IO (Maybe B.ByteString) -> IO (Maybe (SS.Message a))
decodeMessageBS' met = SS.decodeMessage (\bb _ bs -> PC.add (B.length bs)
                                                            (_ingressBytes met)
                                                     >> BB.copyByteString bb bs)

{- Read up to 4096 bytes from the socket at a time, packing into a Maybe
structure. As we use TCP sockets recv should block, and so if msg is empty
the connection has been closed -}
readFromSocket :: Socket -> IO (Maybe B.ByteString)
readFromSocket conn = do
    msg <- recv conn 4096
    if B.null msg
        then error "Upstream connection closed"
        else return $ Just msg


{- Connects to socket within a bracket to ensure the socket is closed if an
exception occurs -}
sendStream :: Store alpha => Stream alpha -> Metrics -> HostName -> ServiceName -> IO ()
sendStream []     _   _    _    = return ()
sendStream stream met host port =
    E.bracket (PG.inc (_egressConn met)
               >> connectSocket host port)
              (\conn -> PG.dec (_egressConn met)
                        >> close conn)
              (\conn -> writeSocket conn met stream)


{- Encode messages and send over the socket -}
writeSocket :: Store alpha => Socket -> Metrics -> Stream alpha -> IO ()
writeSocket conn met =
    mapM_ (\event ->
            let val = SS.encodeMessage . SS.Message $ event
            in  PC.inc (_egressEvents met)
                >> PC.add (B.length val) (_egressBytes met)
                >> sendAll conn val)


--- PROMETHEUS ---

startPrometheus :: String -> IO Metrics
startPrometheus nodeName = do
    reg <- PR.new
    let lbl = addLabel "node" (T.pack nodeName) mempty
        registerFn fn name = fn name lbl reg
    ingressConn   <- registerFn registerGauge   "striot_ingress_connection"
    ingressBytes  <- registerFn registerCounter "striot_ingress_bytes_total"
    ingressEvents <- registerFn registerCounter "striot_ingress_events_total"
    egressConn    <- registerFn registerGauge   "striot_egress_connection"
    egressBytes   <- registerFn registerCounter "striot_egress_bytes_total"
    egressEvents  <- registerFn registerCounter "striot_egress_events_total"
    async $ serveHttpTextMetrics 8080 ["metrics"] (PR.sample reg)
    return Metrics { _ingressConn   = ingressConn
                   , _ingressBytes  = ingressBytes
                   , _ingressEvents = ingressEvents
                   , _egressConn    = egressConn
                   , _egressBytes   = egressBytes
                   , _egressEvents  = egressEvents }

--- SOCKETS ---


listenSocket :: ServiceName -> IO Socket
listenSocket port = do
    let hints = defaultHints { addrFlags = [AI_PASSIVE],
                               addrSocketType = Stream }
    (sock, addr) <- createSocket [] port hints
    setSocketOption sock ReuseAddr 1
    bind sock $ addrAddress addr
    listen sock maxQConn
    return sock
    where maxQConn = 10


connectSocket :: HostName -> ServiceName -> IO Socket
connectSocket host port = do
    let hints = defaultHints { addrSocketType = Stream }
    (sock, addr) <- createSocket host port hints
    setSocketOption sock KeepAlive 1
    connect sock $ addrAddress addr
    return sock


createSocket :: HostName -> ServiceName -> AddrInfo -> IO (Socket, AddrInfo)
createSocket host port hints = do
    addr <- resolve host port hints
    sock <- getSocket addr
    return (sock, addr)
  where
    resolve host port hints = do
        addr:_ <- getAddrInfo (Just hints) (isHost host) (Just port)
        return addr
    getSocket addr = socket (addrFamily addr)
                            (addrSocketType addr)
                            (addrProtocol addr)
    isHost h
        | null h    = Nothing
        | otherwise = Just h
