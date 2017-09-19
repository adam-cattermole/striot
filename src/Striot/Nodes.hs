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
import Control.Monad
import Control.Concurrent.STM
import System.Exit (exitFailure)
import Data.String.Conversions (cs)
import Data.List.Split
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

nodeLinkWhisk :: PortNumber -> HostName -> PortNumber -> IO ()
nodeLinkWhisk portNumInput1 hostNameOutput portNumOutput = withSocketsDo $ do
    sockIn <- listenOn $ PortNumber portNumInput1
    putStrLn "Starting (WHISK) link ..."
    hFlush stdout
    nodeLinkWhisk' sockIn hostNameOutput portNumOutput

nodeLinkWhisk' :: Socket -> HostName -> PortNumber -> IO ()
nodeLinkWhisk' sock host port = do
    activationChan <- newTChanIO
    outputChan <- newTChanIO
    stream <- readListFromSocket sock   -- read stream of Strings from socket
    _ <- forkIO $ forever $ handleActivations activationChan outputChan
    let eventStream = map read stream
    -- whiskRunner eventStream activationChan outputChan host port  -- process stream
    result <- whiskRunner eventStream activationChan outputChan
    sendStream result host port
    -- Will anything run after that or are we stuck in recursion?



whiskRunner :: Stream Text -> TChan Text -> TChan ActionOutputType -> IO (Stream ActionOutputType)
whiskRunner (e@(E i t v):r) activationChan outputChan = do
    -- Activate and add to TChan
    actId <- invokeAction v
    atomically $ writeTChan activationChan actId

    -- Check if we have output
    pay <- atomically $ tryReadTChan outputChan
    go pay
    where
        go pay =
            if isJust pay then do
                let (Just payload) = pay
                now <- getCurrentTime
                let msg = E 0 now payload
                wr <- System.IO.Unsafe.unsafeInterleaveIO (whiskRunner r activationChan outputChan)
                return (msg:wr)
            else
                whiskRunner r activationChan outputChan



handleActivations :: TChan Text -> TChan ActionOutputType -> IO ()
handleActivations activationChan outputChan = do
    actId <- atomically $ readTChan activationChan
    actOutput <- getActivationRetry 60 actId

    atomically $ writeTChan outputChan actOutput
    -- stream <- readResultFromWhisk (getActivationRetry 60 actId)

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



-- readListFromSource :: IO alpha -> IO (Stream alpha)
-- readListFromSource pay = do {l <- go pay 0; return l}
--   where
--     go pay i  = do
--                    now <- getCurrentTime
--                    payload <- pay
--                    let msg = E i now payload
--                    r <- System.IO.Unsafe.unsafeInterleaveIO (go pay (i+1)) -- at some point this will overflow
--                    return (msg:r)


----- END: WHISK LINK -----

---------------------------------------------------



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
    in return $ outputString t p

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
        return $ Just $ outputString t p
    else
        return Nothing

extractMsg :: MQTT.Message 'MQTT.PUBLISH -> (MQTT.Topic, ByteString, [Text])
extractMsg msg =
    let t = MQTT.topic $ MQTT.body msg
        p = MQTT.payload $ MQTT.body msg
        l = MQTT.getLevels t
    in (t,p,l)


---- HELPER FUNCTIONS ----

outputString :: MQTT.Topic -> ByteString -> String
outputString t p =
    let funcName = extractFuncName t
        param = extractFloatList p
    in  fixOutputString FunctionInput {function = cs funcName,
                                       arg      = param}

fixOutputString :: (ToJSON a) => a -> String
fixOutputString = firstLast . removeElem "\\" . show . encode

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

firstLast :: [a] -> [a]
firstLast xs@(_:_) = tail (init xs)
firstLast _ = []

removeElem :: (Eq a) => [a] -> [a] -> [a]
removeElem repl = filter (not . (`elem` repl))

----- END: MQTT SOURCE -----
