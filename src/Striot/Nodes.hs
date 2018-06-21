{-# LANGUAGE DataKinds         #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE FlexibleContexts #-}
module Striot.Nodes ( nodeSink
                    , nodeSink2
                    , nodeLink
                    , nodeLinkWhisk
                    , nodeLink2
                    , nodeSource
                    , nodeMqttSource
                    , nodeMqttByTopicSource
                    ) where

import           Control.Concurrent
import           Control.Concurrent.STM
import           Control.Concurrent.Chan.Unagi as U
import           Control.Monad              (forever, when)
import           Data.Aeson
import qualified Data.ByteString            as B -- (unpack)
import qualified Data.ByteString.Char8      as BC (putStrLn)
import qualified Data.ByteString.Lazy.Char8 as BLC (hPutStrLn, putStrLn)
import           Data.Char                     (chr)
import           Data.List
import           Data.Text                     (Text)
import           Data.Maybe
import           Data.Time                  (getCurrentTime)
import qualified Network.MQTT                  as MQTT
import           Network.Socket
import           Striot.FunctionalIoTtypes
import           System.Exit                   (exitFailure)
import           System.IO
import           System.IO.Unsafe
import           WhiskRest.WhiskConnect
import           WhiskRest.WhiskJsonConversion

----- START: WHISK LINK -----

nodeLinkWhisk :: Read alpha => (Show beta, Read beta) => (Stream alpha -> Stream beta) -> PortNumber -> HostName -> PortNumber -> IO ()
nodeLinkWhisk fn portNumInput1 hostNameOutput portNumOutput = withSocketsDo $ do
    sockIn <- listenOn $ PortNumber portNumInput1
    putStrLn "Starting (WHISK) link ..."
    hFlush stdout
    nodeLinkWhisk' sockIn fn hostNameOutput portNumOutput

nodeLinkWhisk' :: Read alpha => (Show beta, Read beta) => Socket -> (Stream alpha -> Stream beta) -> HostName -> PortNumber -> IO ()
nodeLinkWhisk' sock fn host port = do
    -- activationChan <- newTChanIO
    -- outputChan <- newTChanIO
    (handle, stream) <- readEventStreamFromSocket sock   -- read stream of Strings from socket
    -- _ <- forkIO $ forever $ handleActivations activationChan outputChan
    let output = fn stream
    -- Result is generated and continually recurses while sendStream recursively
    -- sends the output onwards
    result <- whiskRunner' output
    sendStream result host port

    hClose handle
    nodeLinkWhisk' sock fn host port


whiskRunner :: (Show alpha, Read alpha) => Stream alpha -> TChan Text -> TChan (Event alpha) -> IO (Stream alpha)
whiskRunner [] activationChan outputChan = do
    return []
whiskRunner (e:r) activationChan outputChan = do
    -- Activate and add to TChan
    actId <- invokeAction e
    atomically $ writeTChan activationChan actId

    -- Check if we have output
    pay <- atomically $ tryReadTChan outputChan
    go pay
    where
        go pay =
            if isJust pay then do
                let (Just msg) = pay
                wr <- System.IO.Unsafe.unsafeInterleaveIO (whiskRunner r activationChan outputChan)
                return (msg:wr)
            else
                whiskRunner r activationChan outputChan

whiskRunner' :: (Show alpha, Read alpha) => Stream alpha -> IO (Stream alpha)
whiskRunner' [] = return []
whiskRunner' [e] = System.IO.Unsafe.unsafeInterleaveIO $ do
    x <- whiskRunner'' e
    return [x]
whiskRunner' (e:r) = System.IO.Unsafe.unsafeInterleaveIO $ do
    x <- whiskRunner'' e
    xs <- whiskRunner' r
    return (x:xs)

whiskRunner'' :: (Show alpha, Read alpha) => Event alpha -> IO (Event alpha)
whiskRunner'' e = do
    actId <- invokeAction e
    eJson <- getActivationRetry 60 actId
    return $ fromEventJson eJson


-- hGetLines' :: Handle -> IO [String]
-- hGetLines' handle = System.IO.Unsafe.unsafeInterleaveIO $ do
--     readable <- hIsReadable handle
--     eof <- hIsEOF handle
--     if not eof && readable
--         then do
--             x <- hGetLine handle
--             xs <- hGetLines' handle
--             -- print x
--             return (x:xs)
--      else return []

handleActivations :: (Read alpha) => TChan Text -> TChan (Event alpha) -> IO ()
handleActivations activationChan outputChan = do
    actId <- atomically $ readTChan activationChan
    eJson <- getActivationRetry 60 actId
    atomically $ writeTChan outputChan (fromEventJson eJson)


----- END: WHISK LINK -----


--- SINK FUNCTIONS ---

nodeSink :: (FromJSON (Event alpha), ToJSON (Event beta)) => (Stream alpha -> Stream beta) -> (Stream beta -> IO ()) -> ServiceName -> IO ()
nodeSink streamGraph iofn portNumInput1 = withSocketsDo $ do
    sock <- listenSocket portNumInput1
    putStrLn "Starting server ..."
    hFlush stdout
    nodeSink' sock streamGraph iofn


nodeSink' :: (FromJSON (Event alpha), ToJSON (Event beta)) => Socket -> (Stream alpha -> Stream beta) -> (Stream beta -> IO ()) -> IO ()
nodeSink' sock streamOps iofn = do
    stream <- processSocket sock
    let result = streamOps stream
    iofn result


-- A Sink with 2 inputs
nodeSink2 :: (FromJSON (Event alpha), FromJSON (Event beta), ToJSON (Event gamma)) => (Stream alpha -> Stream beta -> Stream gamma) -> (Stream gamma -> IO ()) -> ServiceName -> ServiceName -> IO ()
nodeSink2 streamGraph iofn portNumInput1 portNumInput2= withSocketsDo $ do
    sock1 <- listenSocket portNumInput1
    sock2 <- listenSocket portNumInput2
    putStrLn "Starting server ..."
    hFlush stdout
    nodeSink2' sock1 sock2 streamGraph iofn


nodeSink2' :: (FromJSON (Event alpha), FromJSON (Event beta), ToJSON (Event gamma)) => Socket -> Socket -> (Stream alpha -> Stream beta -> Stream gamma) -> (Stream gamma -> IO ()) -> IO ()
nodeSink2' sock1 sock2 streamOps iofn = do
    stream1 <- processSocket sock1
    stream2 <- processSocket sock2
    let result = streamOps stream1 stream2
    iofn result


--- LINK FUNCTIONS ---

nodeLink :: (FromJSON (Event alpha), ToJSON (Event beta)) => (Stream alpha -> Stream beta) -> ServiceName -> HostName -> ServiceName -> IO ()
nodeLink streamGraph portNumInput1 hostNameOutput portNumOutput = withSocketsDo $ do
    sockIn <- listenSocket portNumInput1
    putStrLn "Starting link ..."
    hFlush stdout
    nodeLink' sockIn streamGraph hostNameOutput portNumOutput


nodeLink' :: (FromJSON (Event alpha), ToJSON (Event beta)) => Socket -> (Stream alpha -> Stream beta) -> HostName -> ServiceName -> IO ()
nodeLink' sock streamOps host port = do
    stream <- processSocket sock
    let result = streamOps stream
    sendStream result host port


-- A Link with 2 inputs
nodeLink2 :: (FromJSON (Event alpha), FromJSON (Event beta), ToJSON (Event gamma)) => (Stream alpha -> Stream beta -> Stream gamma) -> ServiceName -> ServiceName -> HostName -> ServiceName -> IO ()
nodeLink2 streamGraph portNumInput1 portNumInput2 hostName portNumOutput = withSocketsDo $ do
    sock1 <- listenSocket portNumInput1
    sock2 <- listenSocket portNumInput2
    putStrLn "Starting link ..."
    hFlush stdout
    nodeLink2' sock1 sock2 streamGraph hostName portNumOutput


nodeLink2' :: (FromJSON (Event alpha), FromJSON (Event beta), ToJSON (Event gamma)) => Socket -> Socket -> (Stream alpha -> Stream beta -> Stream gamma) -> HostName -> ServiceName -> IO ()
nodeLink2' sock1 sock2 streamOps host port = do
    stream1 <- processSocket sock1
    stream2 <- processSocket sock2
    let result = streamOps stream1 stream2
    sendStream result host port


--- SOURCE FUNCTIONS ---

nodeSource :: ToJSON (Event beta) => IO alpha -> (Stream alpha -> Stream beta) -> HostName -> ServiceName -> IO ()
nodeSource pay streamGraph host port = do
    putStrLn "Starting source ..."
    stream <- readListFromSource pay
    let result = streamGraph stream
    sendStream result host port -- or printStream if it's a completely self contained streamGraph



----- START: MQTT SOURCE -----

nodeMqttSource :: Read alpha => Show beta => HostName -> [MQTT.Topic] -> (Stream alpha -> Stream beta) -> HostName -> PortNumber -> IO ()
nodeMqttSource mqttHost topics fn host port = do
    pubChan <- setupMqtt topics mqttHost
    nodeSource (getMqttMsg pubChan) fn host port

nodeMqttByTopicSource :: Read alpha => Show beta => HostName -> [MQTT.Topic] -> MQTT.Topic -> (Stream alpha -> Stream beta) -> HostName -> PortNumber -> IO ()
nodeMqttByTopicSource mqttHost topics selectT fn host port = do
    pubChan <- setupMqtt topics mqttHost
    nodeSource (getMqttMsgByTopic pubChan selectT) fn host port

-- TChan (MQTT.Message 'MQTT.PUBLISH) ->
setupMqtt :: [MQTT.Topic] -> HostName -> IO (TChan (MQTT.Message 'MQTT.PUBLISH))
setupMqtt topics mqttHost = do
    pubChan <- newTChanIO
    cmds <- MQTT.mkCommands
    let conf = (MQTT.defaultConfig cmds pubChan)
                  { MQTT.cHost = mqttHost
                  , MQTT.cUsername = Just "mqtt-hs" }

    -- Attempt to subscribe to individual topics
    _ <- forkIO $ do
        qosGranted <- MQTT.subscribe conf $ map (\x -> (x, MQTT.Handshake)) topics
        case qosGranted of
            hs -> putStrLn "Topic Handshake Success!" -- forever $ atomically (readTChan pubChan) >>= handleMsg
                where hs = map (const MQTT.Handshake) topics
            _ -> do
                hPutStrLn stderr $ "Wanted QoS Handshake, got " ++ show qosGranted
                exitFailure

      -- this will throw IOExceptions
    _ <- forkIO $ do
        terminated <- MQTT.run conf
        print terminated
    threadDelay (1 * 1000 * 1000)
    return pubChan

getMqttMsg :: Read alpha => TChan (MQTT.Message 'MQTT.PUBLISH) -> IO alpha
getMqttMsg pubChan = do
    message <- atomically (readTChan pubChan) >>= handleMsg
    return $ read message

handleMsg :: MQTT.Message 'MQTT.PUBLISH -> IO String
handleMsg msg =
    let (t,p,l) = extractMsg msg
    in return $ convertBsToString p

getMqttMsgByTopic :: Read alpha => TChan (MQTT.Message 'MQTT.PUBLISH) -> MQTT.Topic -> IO alpha
getMqttMsgByTopic pubChan topic = do
    message <- atomically (readTChan pubChan) >>= handleMsgByTopic topic
    case message of
        Just m  -> return $ read m
        Nothing -> getMqttMsgByTopic pubChan topic

handleMsgByTopic :: MQTT.Topic -> MQTT.Message 'MQTT.PUBLISH -> IO (Maybe String)
handleMsgByTopic topic msg =
    let (t,p,l) = extractMsg msg
    in if topic == t then
        return $ Just $ convertBsToString p
    else
        return Nothing

extractMsg :: MQTT.Message 'MQTT.PUBLISH -> (MQTT.Topic, ByteString, [Text])
extractMsg msg =
    let t = MQTT.topic $ MQTT.body msg
        p = MQTT.payload $ MQTT.body msg
        l = MQTT.getLevels t
    in (t,p,l)


---- HELPER FUNCTIONS ----

convertBsToString :: ByteString -> String
convertBsToString = map (chr. fromEnum) . unpack

----- END: MQTT SOURCE -----

--- UTILITY FUNCTIONS ---

readListFromSource :: IO alpha -> IO (Stream alpha)
readListFromSource = go 0
  where
    go i pay = System.IO.Unsafe.unsafeInterleaveIO $ do
        x  <- msg i
        xs <- go (i + 1) pay    -- This will overflow eventually
        return (x : xs)
      where
        msg x = do
            now     <- getCurrentTime
            payload <- pay
            return (E x now payload)


{- processSocket is a wrapper function that handles concurrently
accepting and handling connections on the socket and reading all of the strings
into an event Stream -}
processSocket :: FromJSON (Event alpha) => Socket -> IO (Stream alpha)
processSocket sock = acceptConnections sock >>= readEventsTChan


{- acceptConnections takes a socket as an argument and spins up a new thread to
process the data received. The returned TChan object contains the data from
the socket -}
acceptConnections :: FromJSON (Event alpha) => Socket -> IO (U.OutChan (Event alpha))
acceptConnections sock = do
    (inChan, outChan) <- U.newChan
    _         <- forkIO $ connectionHandler sock inChan
    return outChan


{- connectionHandler sits accepting any new connections. Once
accepted, it is converted to a handle and a new thread is forked to handle all
reading. The function then loops to accept a new connection. forkFinally is used
to ensure the thread closes the handle before it exits -}
connectionHandler :: FromJSON (Event alpha) => Socket -> U.InChan (Event alpha) -> IO ()
connectionHandler sockIn eventChan = forever $ do
    -- putStrLn "Awaiting new connection"
    (sock, _) <- accept sockIn
    hdl <- socketToHandle sock ReadWriteMode
    -- putStrLn "Forking to process new connection"
    forkFinally   (processHandle hdl eventChan) (\_ -> hClose hdl)


{- processHandle takes a Handle and TChan. All of the events are read through
hGetLines' with the IO deferred lazily. The string list is mapped to a Stream
and passed to writeEventsTChan -}
processHandle :: FromJSON (Event alpha) => Handle -> U.InChan (Event alpha) -> IO ()
processHandle handle eventChan = do
    byteStream <- hGetLines' handle
    let eventStream = mapMaybe decodeStrict byteStream
    U.writeList2Chan eventChan eventStream


{- writeEventsTChan takes a TChan and Stream of the same type, and recursively
writes the events atomically to the TChan, until an empty list -}
writeEventsTChan :: FromJSON (Event alpha) => U.InChan (Event alpha) -> Stream alpha -> IO ()
writeEventsTChan eventChan = mapM_ (U.writeChan eventChan)

{- readEventsTChan creates a stream of events from reading the next element from
a TChan, but the IO is deferred lazily. Only when the next value of the Stream
is evaluated does the IO computation take place -}
readEventsTChan :: FromJSON (Event alpha) => U.OutChan (Event alpha) -> IO (Stream alpha)
readEventsTChan eventChan = System.IO.Unsafe.unsafeInterleaveIO $ do
    x <- U.readChan eventChan
    xs <- readEventsTChan eventChan
    return (x : xs)


readListFromSocket :: Socket -> IO [B.ByteString]
readListFromSocket sock = do
    (_, stream) <- readListFromSocket' sock
    return stream


readListFromSocket' :: Socket -> IO (Handle, [B.ByteString])
readListFromSocket' sockIn = do
    (sock,_) <- accept sockIn
    hdl <- socketToHandle sock ReadWriteMode
    -- putStrLn "Open input connection"
    stream <- hGetLines' hdl
    return (hdl, stream)


readEventStreamFromSocket :: FromJSON (Event alpha) => Socket -> IO (Handle, Stream alpha)
readEventStreamFromSocket sock = do
    (hdl, byteStream) <- readListFromSocket' sock
    let eventStream = mapMaybe decodeStrict byteStream
    return (hdl, eventStream)


sendStream :: ToJSON (Event alpha) => Stream alpha -> HostName -> ServiceName -> IO ()
sendStream []     _    _    = return ()
sendStream stream host port = withSocketsDo $ do
    sock <- connectSocket host port
    handle <- socketToHandle sock ReadWriteMode
    -- putStrLn "Open output connection"
    hPutLines'    handle stream


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


hPutLines' :: ToJSON (Event alpha) => Handle -> Stream alpha -> IO ()
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
    getSocket addr = socket (addrFamily addr) (addrSocketType addr) (addrProtocol addr)
    isHost h
        | null h    = Nothing
        | otherwise = Just h
