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
import           Control.Concurrent.Async              (async, concurrently)
import qualified Control.Concurrent.Chan.Unagi.Bounded as U
import           Control.Concurrent.STM
import           Control.DeepSeq                       (force)
import           Control.Exception                     (evaluate, catch)
import           Control.Monad                         (forever, liftM2, void,
                                                        when)
import           Data.Aeson
import qualified Data.Attoparsec.ByteString.Char8      as A
import qualified Data.ByteString                       as B
import qualified Data.ByteString.Char8                 as BC
import qualified Data.ByteString.Lazy.Char8            as BLC
import           Data.Conduit.Network
import qualified Network.Socket                        as S
import qualified Data.Conduit.Text                     as CT
import           Data.Maybe
import qualified Data.Text                             as T
import           Data.Time                             (getCurrentTime)
import qualified Network.MQTT                          as MQTT
import           Network.MQTT.Client
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
    sock <- listenSocket (show inputPort)
    stream <- processSocket sock
    -- stream <- processSocketC inputPort
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
    sock <- listenSocket (show inputPort)
    stream <- processSocket sock
    -- stream <- processSocketC inputPort
    let result = streamOp stream
    sendStream result outputHost outputPort


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
    sendStream result host port -- or printStream if it's a completely self contained streamGraph


--- LINK FUNCTIONS - AcitveMQ ---


nodeLinkMqtt :: (FromJSON alpha, ToJSON beta) => (Stream alpha -> Stream beta) -> String -> HostName -> PortNumber -> HostName -> PortNumber -> IO ()
nodeLinkMqtt streamOp podName inputHost inputPort outputHost outputPort = do
    putStrLn "Starting link ..."
    hFlush stdout
    stream <- processSocketMqtt podName inputHost inputPort
    let result = streamOp stream
    sendStream result outputHost outputPort


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


sendStream :: ToJSON alpha => Stream alpha -> HostName -> PortNumber -> IO ()
sendStream []     _    _    = return ()
sendStream stream host port = do
    sock <- connectSocket host (show port)
    handle <- S.socketToHandle sock ReadWriteMode
    -- putStrLn "Open output connection"
    hPutLines' handle stream

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

sendStreamMqtt :: ToJSON alpha => Stream alpha -> String -> HostName -> PortNumber -> IO ()
sendStreamMqtt stream podName host port = do
    mc <- runMqttPub podName host port
    mapM_ (\x -> do
                val <- evaluate . force . encode $ x
                publishq mc (head netmqttTopics) val False QoS0) stream

sendStreamMqtt' :: ToJSON alpha => Stream alpha -> String -> HostName -> PortNumber -> IO ()
sendStreamMqtt' stream podName host port = do
    (conf, _) <- mqttConf (T.pack podName) host port
    async $ runMqtt' (return ()) conf
    mapM_ (\x -> do
                val <- evaluate . force . encode $ x
                MQTT.publish conf MQTT.NoConfirm False (head mqttTopics) $ BLC.toStrict val) stream


sendStreamMqttMulti :: ToJSON alpha => Stream alpha -> String -> HostName -> PortNumber -> IO ()
sendStreamMqttMulti stream podName host port = do
    (inChan, outChan) <- U.newChan chanSize
    mapM_ (\x ->
        async $ do
            mc <- runMqttPub (podName++show x) host port
            vals <- U.getChanContents outChan
            mapM_ (\x -> do
                        val <- evaluate . force . encode $ x
                        publishq mc (head netmqttTopics) val False QoS0) vals) [1..numThreads]
    U.writeList2Chan inChan stream

sendStreamMqttMulti' :: ToJSON alpha => Stream alpha -> String -> HostName -> PortNumber -> IO ()
sendStreamMqttMulti' stream podName host port = do
    (inChan, outChan) <- U.newChan chanSize
    mapM_ (\x ->
        async $ do
            (conf, _) <- mqttConf (T.pack $ podName ++ show x) host port
            async $ runMqtt' (return ()) conf
            vals <- U.getChanContents outChan
            mapM_ (\x -> do
                        val <- evaluate . force . encode $ x
                        MQTT.publish conf MQTT.NoConfirm False (head mqttTopics) $ BLC.toStrict val) vals) [1..numThreads]
    U.writeList2Chan inChan stream


sendStreamMqttC :: ToJSON alpha => Stream alpha -> String -> HostName -> PortNumber -> IO ()
sendStreamMqttC stream podName host port = do
    mc <- runMqttPub podName host port
    runConduit
        $ yieldMany stream
       .| mapMC (evaluate . force . encode)
       .| mapM_C (\x -> publishq mc (head netmqttTopics) x False QoS0)


sendStreamMqttMultiC :: ToJSON alpha => Stream alpha -> String -> HostName -> PortNumber -> IO ()
sendStreamMqttMultiC stream podName host port = do
    (inChan, outChan) <- U.newChan chanSize
    mapM_ (\x ->
        async $ do
            mc <- runMqttPub (podName++show x) host port
            runConduit
                $ sourceUChanYield outChan
               .| mapMC (evaluate . force . encode)
               .| mapM_C (\x -> publishq mc (head netmqttTopics) x False QoS0)) [1..numThreads]
    runConduit
        $ yieldMany stream
       -- .| mapMC (evaluate . force . encode)
       .| mapM_C (U.writeChan inChan)


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
    byteStream <- map (MQTT.payload . MQTT.body) <$> getChanLazy pubChan
    U.writeList2Chan ch $ mapMaybe decodeStrict byteStream
    -- U.writeList2Chan ch =<< mapMaybe decodeStrict $ getChanLazy pubChan


getChanLazy :: TChan a -> IO [a]
getChanLazy ch = unsafeInterleaveIO (do
                            x  <- unsafeInterleaveIO $ atomically . readTChan $ ch
                            xs <- getChanLazy ch
                            return (x:xs)
                        )


runMqttSubC :: FromJSON alpha => T.Text -> [MQTT.Topic] -> HostName -> PortNumber -> U.InChan (Event alpha) -> IO ()
runMqttSubC podName topics host port ch = do
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


sourceUChanYield :: MonadIO m => U.OutChan alpha -> ConduitT i alpha m ()
sourceUChanYield ch = loop
    where
        loop = do
            ms <- liftIO $ U.readChan ch
            yield ms
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

-- Old connection stuff

{- processSocket is a wrapper function that handles concurrently
accepting and handling connections on the socket and reading all of the strings
into an event Stream -}
processSocket :: FromJSON alpha => S.Socket -> IO (Stream alpha)
processSocket sock = U.getChanContents =<< acceptConnections sock


{- acceptConnections takes a socket as an argument and spins up a new thread to
process the data received. The returned TChan object contains the data from
the socket -}
acceptConnections :: FromJSON alpha => S.Socket -> IO (U.OutChan (Event alpha))
acceptConnections sock = do
    (inChan, outChan) <- U.newChan chanSize
    async $ connectionHandler sock inChan
    return outChan


{- connectionHandler sits accepting any new connections. Once
accepted, it is converted to a handle and a new thread is forked to handle all
reading. The function then loops to accept a new connection. forkFinally is used
to ensure the thread closes the handle before it exits -}
connectionHandler :: FromJSON alpha => S.Socket -> U.InChan (Event alpha) -> IO ()
connectionHandler sockIn eventChan = forever $ do
    -- putStrLn "Awaiting new connection"
    (sock, _) <- S.accept sockIn
    hdl <- S.socketToHandle sock ReadWriteMode
    -- putStrLn "Forking to process new connection"
    forkFinally (processHandle hdl eventChan) (\_ -> hClose hdl)


{- processHandle takes a Handle and TChan. All of the events are read through
hGetLines' with the IO deferred lazily. The string list is mapped to a Stream
and passed to writeEventsTChan -}
processHandle :: FromJSON alpha => Handle -> U.InChan (Event alpha) -> IO ()
processHandle handle eventChan = do
    byteStream <- hGetLines' handle
    U.writeList2Chan eventChan $ mapMaybe decodeStrict byteStream


{- hGetLines' creates a list of Strings from a Handle, where the IO computation
is deferred lazily until the values are requested -}
hGetLines' :: Handle -> IO [B.ByteString]
hGetLines' handle = System.IO.Unsafe.unsafeInterleaveIO $ do
    readable <- hIsReadable handle
    eof      <- hIsEOF handle
    if not eof && readable
        then do
            x  <- B.hGetLine handle
            xs <- hGetLines' handle
            -- BC.putStrLn x
            return (x : xs)
        else return []

hPutLines' :: ToJSON alpha => Handle -> Stream alpha -> IO ()
hPutLines' handle [] = do
    hClose handle
    -- putStrLn "Closed output handle"
    return ()
hPutLines' handle (x:xs) = do
    writeable <- hIsWritable handle
    open      <- hIsOpen handle
    when (open && writeable) $ do
        -- BLC.putStrLn (encode x)
        BLC.hPutStrLn    handle (encode x)
        hPutLines' handle xs

--- SOCKETS ---


listenSocket :: S.ServiceName -> IO S.Socket
listenSocket port = do
    let hints = S.defaultHints { S.addrFlags = [S.AI_PASSIVE],
                               S.addrSocketType = S.Stream }
    (sock, addr) <- createSocket [] port hints
    S.setSocketOption sock S.ReuseAddr 1
    S.bind sock $ S.addrAddress addr
    S.listen sock maxQConn
    return sock
    where maxQConn = 10


connectSocket :: S.HostName -> S.ServiceName -> IO S.Socket
connectSocket host port = do
    let hints = S.defaultHints { S.addrSocketType = S.Stream }
    (sock, addr) <- createSocket host port hints
    S.setSocketOption sock S.KeepAlive 1
    S.connect sock $ S.addrAddress addr
    return sock


createSocket :: S.HostName -> S.ServiceName -> S.AddrInfo -> IO (S.Socket, S.AddrInfo)
createSocket host port hints = do
    addr <- resolve host port hints
    sock <- getSocket addr
    return (sock, addr)
  where
    resolve host port hints = do
        addr:_ <- S.getAddrInfo (Just hints) (isHost host) (Just port)
        return addr
    getSocket addr = S.socket (S.addrFamily addr) (S.addrSocketType addr) (S.addrProtocol addr)
    isHost h
        | null h    = Nothing
        | otherwise = Just h
