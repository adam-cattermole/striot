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
                    -- , nodeSourceMqttC
                    -- , nodeLinkAmq
                    , nodeLinkMqtt
                    ) where

import           Conduit                               hiding (connect)
import           Control.Concurrent                    hiding (yield)
import           Control.Concurrent.Async              (concurrently, async)
import qualified Control.Concurrent.Chan.Unagi.Bounded as U
import           Control.Concurrent.STM
import           Control.DeepSeq
import           Control.Exception
import           Control.Monad                         (forever, liftM2, void,
                                                        when)
import           Data.Aeson
import qualified Data.Attoparsec.ByteString.Char8      as A
import qualified Data.ByteString                       as B
import qualified Data.ByteString.Char8                 as BC
import qualified Data.ByteString.Lazy.Char8            as BLC
import           Data.Conduit.Network
import qualified Data.Conduit.Text                     as CT
import           Data.Maybe
import qualified Data.Text                             as T
import           Data.Time                             (getCurrentTime)
import           Network.MQTT.Client
import qualified Network.MQTT                          as MQTT
import           Striot.FunctionalIoTtypes
import           System.Exit                           (exitFailure)
import           System.IO
import           System.IO.Unsafe

type HostName   = String
type PortNumber = Int

--- SINK FUNCTIONS ---

nodeSink :: (FromJSON alpha, ToJSON beta) => (Stream alpha -> Stream beta) -> (Stream beta -> IO ()) -> PortNumber -> IO ()
nodeSink streamOp iofn inputPort = do
    putStrLn "Starting server ..."
    stream <- processSocketC inputPort
    let result = streamOp stream
    iofn result

-- A Sink with 2 inputs
nodeSink2 :: (FromJSON alpha, FromJSON beta, ToJSON gamma) => (Stream alpha -> Stream beta -> Stream gamma) -> (Stream gamma -> IO ()) -> PortNumber -> PortNumber -> IO ()
nodeSink2 streamOp iofn inputPort1 inputPort2 =do
    putStrLn "Starting server ..."
    stream1 <- processSocketC inputPort1
    stream2 <- processSocketC inputPort2
    let result = streamOp stream1 stream2
    iofn result


--- LINK FUNCTIONS ---

nodeLink :: (Show alpha, FromJSON alpha, ToJSON beta) => (Stream alpha -> Stream beta) -> PortNumber -> HostName -> PortNumber -> IO ()
nodeLink streamOp inputPort outputHost outputPort = do
    putStrLn "Starting link ..."
    stream <- processSocketC inputPort
    let result = streamOp stream
    sendStreamC result outputHost outputPort


-- A Link with 2 inputs
nodeLink2 :: (FromJSON alpha, FromJSON beta, ToJSON gamma) => (Stream alpha -> Stream beta -> Stream gamma) -> PortNumber -> PortNumber -> HostName -> PortNumber -> IO ()
nodeLink2 streamOp inputPort1 inputPort2 outputHost outputPort = do
    putStrLn "Starting link ..."
    stream1 <- processSocketC inputPort1
    stream2 <- processSocketC inputPort2
    let result = streamOp stream1 stream2
    sendStreamC result outputHost outputPort


--- SOURCE FUNCTIONS ---

nodeSource :: ToJSON beta => IO alpha -> (Stream alpha -> Stream beta) -> HostName -> PortNumber -> IO ()
nodeSource pay streamGraph host port = do
    putStrLn "Starting source ..."
    stream <- readListFromSource pay
    let result = streamGraph stream
    sendStreamC result host port -- or printStream if it's a completely self contained streamGraph


--- LINK FUNCTIONS - AcitveMQ ---


nodeLinkMqtt :: (FromJSON alpha, ToJSON beta) => (Stream alpha -> Stream beta) -> String -> HostName -> PortNumber -> HostName -> PortNumber -> IO ()
nodeLinkMqtt streamOp podName inputHost inputPort outputHost outputPort = do
    putStrLn "Starting link ..."
    hFlush stdout
    stream <- processSocketMqtt podName inputHost inputPort
    let result = streamOp stream
    sendStreamC result outputHost outputPort


--- SOURCE FUNCTIONS - ActiveMQ ---


nodeSourceMqtt :: ToJSON beta => IO alpha -> (Stream alpha -> Stream beta) -> String -> HostName -> PortNumber -> IO ()
nodeSourceMqtt pay streamGraph podName host port = do
    putStrLn "Starting source ..."
    stream <- readListFromSource pay
    let result = streamGraph stream
    sendStreamMqttC result podName host port


--- UTILITY FUNCTIONS ---


readListFromSource :: IO alpha -> IO (Stream alpha)
readListFromSource = go 0
  where
    go i pay = unsafeInterleaveIO $ do
        x  <- msg i
        xs <- go (i + 1) pay    -- This will overflow eventually
        return (x : xs)
      where
        msg x = do
            now     <- getCurrentTime
            Event x (Just now) . Just <$> pay


{- Handler to receive a lazy list of Events from the socket, where the
events are read from the socket one by one in constant memory -}
processSocketC :: FromJSON alpha => PortNumber -> IO (Stream alpha)
processSocketC inputPort = U.getChanContents =<< acceptConnectionsC inputPort


{- Reads from source node, parses, deserialises, and writes to the channel,
without introducing laziness -}
acceptConnectionsC :: FromJSON alpha => PortNumber -> IO (U.OutChan (Event alpha))
acceptConnectionsC port = do
    (inChan, outChan) <- U.newChan chanSize
    async $
        runTCPServer (serverSettings port "*") $ \source ->
          runConduit
          $ appSource source
         .| parseEvents
         .| deserialise
         .| mapM_C (U.writeChan inChan)
    return outChan


{- Send stream to downstream one event at a time -}
sendStreamC :: ToJSON alpha => Stream alpha -> HostName -> PortNumber -> IO ()
sendStreamC []     _    _    = return ()
sendStreamC stream host port =
    runTCPClient (clientSettings port (BC.pack host)) $ \sink ->
        runConduit
      $ yieldMany stream
     .| serialise
     .| mapC (`BC.snoc` eventTerminationChar)
     .| appSink sink


{- Conduit to serialise with aeson -}
serialise :: (Monad m, ToJSON a) => ConduitT a BC.ByteString m ()
serialise = awaitForever $ yield . BLC.toStrict . encode


{- Conduit to deserialise with aeson -}
deserialise :: (Monad m, FromJSON b) => ConduitT BC.ByteString b m ()
deserialise = awaitForever (\x -> case decodeStrict x of
                                        Just v  -> yield v
                                        Nothing -> return ())


{- Keep reading from upstream conduit and parsing for end of event character.
This is required for large events > 4096 bytes -}
parseEvents :: (Monad m) => ConduitT BC.ByteString BC.ByteString m ()
parseEvents = go BC.empty
    where
        go st = await >>= \case
                    Nothing -> go st
                    Just x  ->
                        let p = A.parse parseEventTermination x
                        in  case p of
                                A.Partial _ -> go (BC.append st x)
                                A.Done i r  -> yield (BC.append st r) >> go i


{- attoparsec parser to search for end of string character -}
parseEventTermination :: A.Parser BC.ByteString
parseEventTermination = do
    x <- A.takeWhile (/= eventTerminationChar)
    A.anyChar
    return x


{- This defines the character that we append after each event-}
eventTerminationChar :: Char
eventTerminationChar = '\NUL'


{- We are using a bounded queue to prevent extreme memory usage when
input rate > consumption rate. This value may need to be increased to achieve
higher throughput when computation costs are low -}
chanSize :: Int
chanSize = 10


--- AMQ MQTT ---

processSocketMqtt :: FromJSON alpha => String -> HostName -> PortNumber -> IO (Stream alpha)
processSocketMqtt podName host port = U.getChanContents =<< acceptConnectionsMqtt podName host port


acceptConnectionsMqtt :: FromJSON alpha => String -> HostName -> PortNumber -> IO (U.OutChan (Event alpha))
acceptConnectionsMqtt podName host port = do
    (inChan, outChan) <- U.newChan chanSize
    async $ runMqttSub (T.pack podName) mqttTopics host port inChan
    -- async $ runMqttSub podName host port inChan
    return outChan

sendStreamMqttC :: ToJSON alpha => Stream alpha -> String -> HostName -> PortNumber -> IO ()
sendStreamMqttC stream podName host port = do
    mc <- runMqttPub podName host port
    runConduit
        $ yieldMany stream
       .| mapMC (evaluate . force . encode)
       .| mapM_C (\x -> publishq mc (head netmqttTopics) x False QoS0)

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
                                             ,_port     = port
                                             ,_connID   = podName
                                             ,_username = Just "admin"
                                             ,_password = Just "yy^U#Fca!52Y"
                                             ,_msgCB    = msgCB}


-- MQTT-HS

mqttTopics :: [MQTT.Topic]
mqttTopics = ["StriotQueue"]


runMqttSub :: FromJSON alpha => T.Text -> [MQTT.Topic] -> HostName -> PortNumber -> U.InChan (Event alpha) -> IO ()
runMqttSub podName topics host port ch = do
    (conf, pubChan) <- mqttConf podName host port
    async $ runMqtt' (mqttSub conf pubChan topics) conf
    runConduit
        $ sourceTChanYield pubChan
       .| deserialise
       .| mapM_C (U.writeChan ch)


sourceTChanYield :: MonadIO m => TChan (MQTT.Message 'MQTT.PUBLISH) -> ConduitT i BC.ByteString m ()
sourceTChanYield ch = loop
    where
        loop = do
            ms <- liftIO . atomically $ readTChan ch
            yield (MQTT.payload . MQTT.body $ ms)
            loop


runMqtt' :: IO () -> MQTT.Config -> IO ()
runMqtt' op conf =
    forever $
        catch
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



-- retrieveMessagesMqtt :: (FromJSON alpha) => TChan (MQTT.Message 'MQTT.PUBLISH) -> IO (Stream alpha)
-- retrieveMessagesMqtt messageChan = unsafeInterleaveIO $ do
--     x <- decodeStrict . MQTT.payload . MQTT.body <$> atomically (readTChan messageChan)
--     xs <- retrieveMessagesMqtt messageChan
--     case x of
--         Just newe -> return (newe:xs)
--         Nothing   -> return xs
--

-- sendStreamMqtt :: ToJSON alpha => Stream alpha -> String -> HostName -> PortNumber -> IO ()
-- sendStreamMqtt stream podName host port = do
--     mc <- runMqttPub podName host port
--     mapM_ (\x -> do
--             val <- evaluate . force . encode $ x
--             publishq mc (head mqttTopics) val False QoS0) stream


-- sendStreamAmqMqtt :: ToJSON alpha => String -> Stream alpha -> HostName -> PortNumber -> IO ()
-- sendStreamAmqMqtt podName stream host port = do
--     (conf, pubChan) <- runMqttPub (T.pack podName) mqttTopics host (read port)
--     -- mapM_  (print . encode) stream
--     -- _ <- forkIO $ forever $ do
--     --     x <- MQTT.payload . MQTT.body <$> atomically (readTChan pubChan)
--     --     print x
--     let publish x = MQTT.publish conf MQTT.NoConfirm True (head mqttTopics) $ BLC.toStrict . encode $ x
--     mapM_ publish stream
