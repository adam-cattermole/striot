{-# Language DataKinds, OverloadedStrings #-}
import Control.Concurrent
import Control.Concurrent.STM
import System.IO
import System.Exit (exitFailure)
import Striot.FunctionalProcessing
import Striot.FunctionalIoTtypes
import Striot.Nodes
import Network

import qualified Network.MQTT as MQTT
import Data.Text (Text)
import Data.String
import Data.ByteString (ByteString)
import Control.Monad(when)

import System.Environment

portNum  = 9002::PortNumber
--hostName = "haskellclient2"::HostName

accelT, btnT, tempT, magnT :: MQTT.Topic
accelT = "ACCELEROMETER"
btnT = "BUTTON"
tempT = "TEMPERATURE"
magnT = "MAGNETOMETER/+"
-- + one level deep wildcard
-- * all levels below wildcard

main :: IO ()
main = do
    podName <- getEnv "HOSTNAME"
    hostName <- getEnv "HASKELL_CLIENT2_SERVICE_HOST"
    cmds <- MQTT.mkCommands
    pubChan <- newTChanIO
    let conf = (MQTT.defaultConfig cmds pubChan)
                  {
                --   MQTT.cHost        = "10.68.144.122"
                  MQTT.cHost        = "mqtt-broker.eastus.cloudapp.azure.com"
                  , MQTT.cUsername  = Just $ fromString podName
                  , MQTT.cClientID  = fromString $ "mqtt-haskell_" ++ podName
                  }

    -- Attempt to subscribe to individual topics
    _ <- forkIO $ do
        qosGranted <- MQTT.subscribe conf [(accelT, MQTT.Handshake)
                                          ,(btnT, MQTT.Handshake)
                                          ,(tempT, MQTT.Handshake)
                                          ,(magnT, MQTT.Handshake)]
        case qosGranted of
          [MQTT.Handshake, MQTT.Handshake, MQTT.Handshake, MQTT.Handshake] -> putStrLn "Topic Handshake Success!" -- forever $ atomically (readTChan pubChan) >>= handleMsg
          _ -> do
            hPutStrLn stderr $ "Wanted QoS Handshake, got " ++ show qosGranted
            exitFailure

      -- this will throw IOExceptions
    _ <- forkIO $ do
        terminated <- MQTT.run conf
        print terminated

    -- atomically (readTChan pubChan)
    threadDelay (1 * 1000 * 1000)
    nodeSource (getMqttMsgByTopic pubChan btnT) streamGraph2 hostName portNum -- processes source before sending it to another node
    -- nodeSource (getMqttMsg pubChan) streamGraph2 hostName portNum -- processes source before sending it to another node

streamGraph2 :: Stream String -> Stream String
streamGraph2 = streamMap Prelude.id

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
