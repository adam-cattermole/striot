{-# Language DataKinds, OverloadedStrings #-}
module Striot.Nodes ( nodeSink
                    , nodeSink2
                    , nodeLink
                    , nodeLink2
                    , nodeSource
                    , nodeMqttSource
                    , nodeMqttByTopicSource
                    ) where

import Network
import System.IO
import Control.Concurrent
import Data.List
import Striot.FunctionalIoTtypes
import System.IO.Unsafe
import Data.Time (getCurrentTime)

--- FOR MQTT SOURCE
import qualified Network.MQTT as MQTT
import Data.Text (Text)
import Data.ByteString (ByteString)
import Control.Monad(when)
import Control.Concurrent.STM
import System.Exit (exitFailure)

nodeSink:: Read alpha => Show beta => (Stream alpha -> Stream beta) -> (Stream beta -> IO ()) -> PortNumber -> IO ()
nodeSink streamGraph iofn portNumInput1 = withSocketsDo $ do
                                              sock <- listenOn $ PortNumber portNumInput1
                                              putStrLn "Starting server ..."
                                              hFlush stdout
                                              nodeSink' sock streamGraph iofn

nodeSink' :: Read alpha => Show beta => Socket -> (Stream alpha -> Stream beta) -> (Stream beta -> IO ()) -> IO ()
nodeSink' sock streamOps iofn = do
                                   stream <- readListFromSocket sock          -- read stream of Strings from socket
                                   let eventStream = map read stream
                                   let result = streamOps eventStream         -- process stream
                                   iofn result

-- A Link with 2 inputs
nodeSink2:: Read alpha => Read beta => Show gamma => (Stream alpha -> Stream beta -> Stream gamma) -> (Stream gamma -> IO ()) -> PortNumber -> PortNumber -> IO ()
nodeSink2 streamGraph iofn portNumInput1 portNumInput2= withSocketsDo $ do
                                          sock1 <- listenOn $ PortNumber portNumInput1
                                          sock2 <- listenOn $ PortNumber portNumInput2
                                          putStrLn "Starting server ..."
                                          hFlush stdout
                                          nodeSink2' sock1 sock2 streamGraph iofn

nodeSink2' :: Read alpha => Read beta => Show gamma => Socket -> Socket -> (Stream alpha -> Stream beta -> Stream gamma) -> (Stream gamma -> IO ()) -> IO ()
nodeSink2' sock1 sock2 streamOps iofn = do
                                          stream1 <- readListFromSocket sock1          -- read stream of Strings from socket
                                          stream2 <- readListFromSocket sock2          -- read stream of Strings from socket
                                          let eventStream1 = map read stream1
                                          let eventStream2 = map read stream2
                                          let result = streamOps eventStream1 eventStream2     -- process stream
                                          iofn result

readListFromSocket :: Socket -> IO [String]
readListFromSocket sock = do {l <- go sock; return l}
  where
    go sock   = do (handle, host, port) <- accept sock
                   eventMsg             <- hGetLine handle
                   r                    <- System.IO.Unsafe.unsafeInterleaveIO (go sock)
                   return (eventMsg:r)

nodeLink :: Read alpha => Show beta => (Stream alpha -> Stream beta) -> PortNumber -> HostName -> PortNumber -> IO ()
nodeLink streamGraph portNumInput1 hostNameOutput portNumOutput = withSocketsDo $ do
                                         sockIn <- listenOn $ PortNumber portNumInput1
                                         putStrLn "Starting link ..."
                                         hFlush stdout
                                         nodeLink' sockIn streamGraph hostNameOutput portNumOutput

nodeLink' :: Read alpha => Show beta => Socket -> (Stream alpha -> Stream beta) -> HostName -> PortNumber -> IO ()
nodeLink' sock streamOps host port = do
                             stream <- readListFromSocket sock   -- read stream of Strings from socket
                             let eventStream = map read stream
                             let result = streamOps eventStream  -- process stream
                             sendStream result host port         -- to send stream to another node

-- A Link with 2 inputs
nodeLink2:: Read alpha => Read beta => Show gamma => (Stream alpha -> Stream beta -> Stream gamma) -> PortNumber -> PortNumber -> HostName -> PortNumber -> IO ()
nodeLink2 streamGraph portNumInput1 portNumInput2 hostName portNumOutput = withSocketsDo $ do
                                          sock1 <- listenOn $ PortNumber portNumInput1
                                          sock2 <- listenOn $ PortNumber portNumInput2
                                          putStrLn "Starting server ..."
                                          hFlush stdout
                                          nodeLink2' sock1 sock2 streamGraph hostName portNumOutput

nodeLink2' :: Read alpha => Read beta => Show gamma => Socket -> Socket -> (Stream alpha -> Stream beta -> Stream gamma) -> HostName -> PortNumber -> IO ()
nodeLink2' sock1 sock2 streamOps host port = do
                                     stream1 <- readListFromSocket sock1          -- read stream of Strings from socket
                                     stream2 <- readListFromSocket sock2          -- read stream of Strings from socket
                                     let eventStream1 = map read stream1
                                     let eventStream2 = map read stream2
                                     let result = streamOps eventStream1 eventStream2 -- process stream
                                     sendStream result host port                      -- to send stream to another node


sendStream:: Show alpha => Stream alpha -> HostName -> PortNumber -> IO ()
sendStream (h:t) host port = withSocketsDo $ do
                      handle <- connectTo host (PortNumber port)
                      hPutStr handle (show h)
                      hClose handle
                      sendStream t host port

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

nodeSource :: Show beta => IO alpha -> (Stream alpha -> Stream beta) -> HostName -> PortNumber -> IO ()
nodeSource pay streamGraph host port = do
                               putStrLn "Starting source ..."
                               stream <- readListFromSource pay
                               let result = streamGraph stream
                               sendStream result host port -- or printStream if it's a completely self contained streamGraph

readListFromSource :: IO alpha -> IO (Stream alpha)
readListFromSource pay = do {l <- go pay 0; return l}
  where
    go pay i  = do
                   now <- getCurrentTime
                   payload <- pay
                   let msg = E i now payload
                   r <- System.IO.Unsafe.unsafeInterleaveIO (go pay (i+1)) -- at some point this will overflow
                   return (msg:r)


----- START: MQTT SOURCE -----

nodeMqttSource :: Show beta => HostName -> [MQTT.Topic] -> (Stream String -> Stream beta) -> HostName -> PortNumber -> IO ()
nodeMqttSource mqttHost topics fn host port = do
    pubChan <- setupMqtt topics mqttHost
    nodeSource (getMqttMsg pubChan) fn host port

nodeMqttByTopicSource :: Show beta => HostName -> [MQTT.Topic] -> MQTT.Topic -> (Stream String -> Stream beta) -> HostName -> PortNumber -> IO ()
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

getMqttMsg :: TChan (MQTT.Message 'MQTT.PUBLISH) -> IO String
getMqttMsg pubChan = atomically (readTChan pubChan) >>= handleMsg

handleMsg :: MQTT.Message 'MQTT.PUBLISH -> IO String
handleMsg msg =
    let (t,p,l) = extractMsg msg
    in return $ read (show t) ++ " " ++ read (show p)

getMqttMsgByTopic :: TChan (MQTT.Message 'MQTT.PUBLISH) -> MQTT.Topic -> IO String
getMqttMsgByTopic pubChan topic = do
    message <- atomically (readTChan pubChan) >>= handleMsgByTopic topic
    case message of
        Just m -> return m
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
