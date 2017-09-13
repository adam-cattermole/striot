{-# Language DataKinds, OverloadedStrings #-}
--import Network
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

main :: IO ()
main = nodeMqttByTopicSource mqttHost topics accelT streamGraph2 hostName portNum

streamGraph2 :: Stream String -> Stream String
streamGraph2 = streamMap Prelude.id
