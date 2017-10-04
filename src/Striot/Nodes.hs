{-# Language DataKinds, OverloadedStrings #-}
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
import           Control.Monad             (when)
import           Data.List
import           Data.Time                 (getCurrentTime)
import           Network                   (PortID (PortNumber), connectTo,
                                            listenOn)
import           Network.Socket
import           Striot.FunctionalIoTtypes
import           System.IO
import           System.IO.Unsafe

import Control.Concurrent
import Control.Monad
import Control.Concurrent.STM

import Data.Time (getCurrentTime)
import Data.Text (Text)
import Data.ByteString (ByteString, unpack)
import Data.Char (chr)
import Data.Maybe (isJust)
import Data.Aeson

---------------------------------------------------

----- START: ATTEMPT AT NEW SINK -----
-- import Control.Concurrent.STM

-- nodeSinkChan :: Read alpha => Show beta => (Stream alpha -> Stream beta) -> (Stream beta -> IO ()) -> PortNumber -> TChan beta -> IO ()
-- nodeSinkChan streamGraph iofn portNumInput1 chan = withSocketsDo $ do
--     sock <- listenOn $ PortNumber portNumInput1
--     putStrLn "Starting server ..."
--     hFlush stdout
--     nodeSinkChan' sock streamGraph iofn chan
--
-- nodeSinkChan' :: Read alpha => Show beta => Socket -> (Stream alpha -> Stream beta) -> (Stream beta -> IO ()) -> TChan beta -> IO ()
-- nodeSinkChan' sock streamOps iofn chan = do
--     stream <- readListFromSocket sock
--     let eventStream = map read stream
--     let result = streamOps eventStream
--     iofn result
--     writeStreamToChan chan eventStream
--
-- writeStreamToChan :: TChan alpha -> Stream alpha -> IO ()
-- writeStreamToChan chan (V id   v:r) = do
--     atomically $ writeTChan chan v
--     writeStreamToChan chan r
----- END: ATTEMPT AT NEW SINK -----

----- START: WHISK LINK -----
import Data.Maybe
import WhiskRest.WhiskConnect
import WhiskRest.WhiskJsonConversion


----- START: WHISK LINK -----

nodeLinkWhisk :: Read alpha => (Show beta, Read beta) => (Stream alpha -> Stream beta) -> PortNumber -> HostName -> PortNumber -> IO ()
nodeLinkWhisk fn portNumInput1 hostNameOutput portNumOutput = withSocketsDo $ do
    sockIn <- listenOn $ PortNumber portNumInput1
    putStrLn "Starting (WHISK) link ..."
    hFlush stdout
    nodeLinkWhisk' sockIn fn hostNameOutput portNumOutput

nodeLinkWhisk' :: Read alpha => (Show beta, Read beta) => Socket -> (Stream alpha -> Stream beta) -> HostName -> PortNumber -> IO ()
nodeLinkWhisk' sock fn host port = do
    activationChan <- newTChanIO
    outputChan <- newTChanIO
    stream <- readListFromSocket sock   -- read stream of Strings from socket
    _ <- forkIO $ forever $ handleActivations activationChan outputChan
    let eventStream = map read stream
    let output = fn eventStream
    -- Result is generated and continually recurses while sendStream recursively
    -- sends the output onwards
    result <- whiskRunner output activationChan outputChan
    sendStream result host port


whiskRunner :: (Show alpha, Read alpha) => Stream alpha -> TChan Text -> TChan (Event alpha) -> IO (Stream alpha)
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


handleActivations :: (Read alpha) => TChan Text -> TChan (Event alpha) -> IO ()
handleActivations activationChan outputChan = do
    actId <- atomically $ readTChan activationChan
    eJson <- getActivationRetry 60 actId
    atomically $ writeTChan outputChan (fromEventJson eJson)

    -- print [show $ floatData actOutput]
    -- print (map read [show $ floatData actOutput] :: Stream Text)
    -- let result = stream
    -- sendStream result host port         -- to send stream to another node

readResultFromWhisk :: HostName -> PortNumber -> Maybe ActionOutputType  -> IO ()
readResultFromWhisk host port (Just actType) = do
    now <- getCurrentTime
    let msg = E 0 now actType
    sendStream [msg] host port
sendResultFromWhisk host port _ = return ()



nodeSink' :: (Read alpha, Show beta) => Socket -> (Stream alpha -> Stream beta) -> (Stream beta -> IO ()) -> IO ()
nodeSink' sock streamOps iofn = do
    (handle, stream) <- readEventStreamFromSocket sock -- read stream of Events from socket
    let result = streamOps stream         -- process stream
    iofn result
    hClose handle
    -- print "Closed input handle"
    nodeSink' sock streamOps iofn


-- A Link with 2 inputs
nodeSink2 :: (Read alpha, Read beta, Show gamma) => (Stream alpha -> Stream beta -> Stream gamma) -> (Stream gamma -> IO ()) -> PortNumber -> PortNumber -> IO ()
nodeSink2 streamGraph iofn portNumInput1 portNumInput2= withSocketsDo $ do
    sock1 <- listenOn $ PortNumber portNumInput1
    sock2 <- listenOn $ PortNumber portNumInput2
    putStrLn "Starting server ..."
    hFlush stdout
    nodeSink2' sock1 sock2 streamGraph iofn


nodeSink2' :: (Read alpha, Read beta, Show gamma) => Socket -> Socket -> (Stream alpha -> Stream beta -> Stream gamma) -> (Stream gamma -> IO ()) -> IO ()
nodeSink2' sock1 sock2 streamOps iofn = do
    (handle1, stream1) <- readEventStreamFromSocket sock1 -- read stream of Events from socket
    (handle2, stream2) <- readEventStreamFromSocket sock2 -- read stream of Events from socket
    let result = streamOps stream1 stream2     -- process stream
    iofn result
    hClose handle1
    hClose handle2
    -- print "Close input handles"
    nodeSink2' sock1 sock2 streamOps iofn


--- LINK FUNCTIONS ---

nodeLink :: (Read alpha, Show beta) => (Stream alpha -> Stream beta) -> PortNumber -> HostName -> PortNumber -> IO ()
nodeLink streamGraph portNumInput1 hostNameOutput portNumOutput = withSocketsDo $ do
    sockIn <- listenOn $ PortNumber portNumInput1
    putStrLn "Starting link ..."
    hFlush stdout
    nodeLink' sockIn streamGraph hostNameOutput portNumOutput


nodeLink' :: (Read alpha, Show beta) => Socket -> (Stream alpha -> Stream beta) -> HostName -> PortNumber -> IO ()
nodeLink' sock streamOps host port = do
    (handle, stream) <- readEventStreamFromSocket sock -- read stream of Events from socket
    let result = streamOps stream  -- process stream
    sendStream result host port         -- to send stream to another node
    hClose handle
    -- print "Closed input handle"
    nodeLink' sock streamOps host port


-- A Link with 2 inputs
nodeLink2 :: (Read alpha, Read beta, Show gamma) => (Stream alpha -> Stream beta -> Stream gamma) -> PortNumber -> PortNumber -> HostName -> PortNumber -> IO ()
nodeLink2 streamGraph portNumInput1 portNumInput2 hostName portNumOutput = withSocketsDo $ do
    sock1 <- listenOn $ PortNumber portNumInput1
    sock2 <- listenOn $ PortNumber portNumInput2
    putStrLn "Starting server ..."
    hFlush stdout
    nodeLink2' sock1 sock2 streamGraph hostName portNumOutput


nodeLink2' :: (Read alpha, Read beta, Show gamma) => Socket -> Socket -> (Stream alpha -> Stream beta -> Stream gamma) -> HostName -> PortNumber -> IO ()
nodeLink2' sock1 sock2 streamOps host port = do
    (handle1, stream1) <- readEventStreamFromSocket sock1 -- read stream of Events from socket
    (handle2, stream2) <- readEventStreamFromSocket sock2 -- read stream of Events from socket
    let result = streamOps stream1 stream2 -- process stream
    sendStream result host port                      -- to send stream to another node
    hClose handle1
    hClose handle2
    -- print "Closed input handles"
    nodeLink2' sock1 sock2 streamOps host port


{-
sendSource:: Show alpha => IO alpha -> IO ()
sendSource pay       = withSocketsDo $ do
                            handle <- connectTo hostNameOutput (PortNumber portNumOutput)
                            now    <- getCurrentTime
                            payload <- pay
                            let msg = show (E now payload)
                            hPutStr handle msg
                            hClose handle
                            sendSource pay
-}

--- SOURCE FUNCTIONS ---

nodeSource :: Show beta => IO alpha -> (Stream alpha -> Stream beta) -> HostName -> PortNumber -> IO ()
nodeSource pay streamGraph host port = do
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
    in return $ read (show t) ++ " " ++ read (show p)

getMqttMsgByTopic :: Read alpha => TChan (MQTT.Message 'MQTT.PUBLISH) -> MQTT.Topic -> IO alpha
getMqttMsgByTopic pubChan topic = do
    message <- atomically (readTChan pubChan) >>= handleMsgByTopic topic
    case message of
        Just m -> return $ read m
        Nothing -> getMqttMsgByTopic pubChan topic

handleMsgByTopic :: MQTT.Topic -> MQTT.Message 'MQTT.PUBLISH -> IO (Maybe String)
handleMsgByTopic topic msg =
    let (t,p,l) = extractMsg msg
    in if topic == t then
        return $ Just $ read (show t) ++ " " ++ read (show p)
    else
        return Nothing

extractMsg :: MQTT.Message 'MQTT.PUBLISH -> (MQTT.Topic, ByteString, [Text])
extractMsg msg =
    let t = MQTT.topic $ MQTT.body msg
        p = MQTT.payload $ MQTT.body msg
        l = MQTT.getLevels t
    in (t,p,l)

----- END: MQTT SOURCE -----

---- HELPER FUNCTIONS ----

convertBsToString :: ByteString -> String
convertBsToString = map (chr. fromEnum) . unpack

-- outputString :: MQTT.Topic -> ByteString -> String
-- outputString t p =
--     let funcName = extractFuncName t
--         param = extractFloatList p
--     in  fixOutputString FunctionInput {function = cs funcName,
--                                        arg      = param}
-- fixOutputString :: (ToJSON a) => a -> String
-- fixOutputString = convertBsToString . encode

extractFuncName :: MQTT.Topic -> String
extractFuncName = (++) "mqtt." . read . show

extractFloatList :: ByteString -> [Float]
extractFloatList bs =
    let x = convertToList (read (show bs))
    in  map read x

convertToList :: String -> [String]
convertToList s =
    let l = splitOn "," s
    in  map (removeElem "[]") l

readListFromSource :: IO alpha -> IO (Stream alpha)
readListFromSource = go 0
  where
      go i pay = System.IO.Unsafe.unsafeInterleaveIO $ do
          x  <- msg i
          xs <- go (i + 1) pay
          return (x : xs)
        where
          msg x = do
              now     <- getCurrentTime
              payload <- pay
              return (E x now payload)


readListFromSocket :: Socket -> IO [String]
readListFromSocket sock = do
    (_, stream) <- readListFromSocket' sock
    return stream


readListFromSocket' :: Socket -> IO (Handle, [String])
readListFromSocket' sockIn = do
    (sock, _) <- accept sockIn
    hdl       <- socketToHandle sock ReadWriteMode
    hSetBuffering hdl NoBuffering
    -- print "Open input connection"
    stream <- hGetLines' hdl
    return (hdl, stream)


readEventStreamFromSocket :: Read alpha => Socket -> IO (Handle, Stream alpha)
readEventStreamFromSocket sock = do
    (hdl, stringStream) <- readListFromSocket' sock
    let eventStream = map read stringStream
    return (hdl, eventStream)


sendStream :: Show alpha => Stream alpha -> HostName -> PortNumber -> IO ()
sendStream []     host port = return ()
sendStream stream host port = withSocketsDo $ do
    handle <- connectTo host (PortNumber port)
    hSetBuffering handle NoBuffering
    -- print "Open output connection"
    hPutLines'    handle stream


hGetLines' :: Handle -> IO [String]
hGetLines' handle = System.IO.Unsafe.unsafeInterleaveIO $ do
    readable <- hIsReadable handle
    eof      <- hIsEOF handle
    if not eof && readable
        then do
            x  <- hGetLine handle
            xs <- hGetLines' handle
            -- print x
            return (x : xs)
        else return []


hPutLines' :: Show alpha => Handle -> Stream alpha -> IO ()
hPutLines' handle [] = do
    hClose handle
    -- print "Closed output handle"
    return ()
hPutLines' handle (x:xs) = do
    writeable <- hIsWritable handle
    open      <- hIsOpen handle
    when (open && writeable) $ do
            -- print h
        hPrint     handle x
        hPutLines' handle xs
