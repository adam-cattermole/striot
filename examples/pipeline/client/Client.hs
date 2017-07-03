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

portNum  = 9002::PortNumber
hostName = "haskellclient2"::HostName

accelT, btnT, tempT, magnT :: MQTT.Topic
accelT = "ACCELEROMETER"
btnT = "BUTTON"
tempT = "TEMPERATURE"
magnT = "MAGNEMOTER"

main :: IO ()
main = do
    cmds <- MQTT.mkCommands
    pubChan <- newTChanIO
    let conf = (MQTT.defaultConfig cmds pubChan)
                  {
                  MQTT.cHost = "10.68.144.122"
                  , MQTT.cUsername = Just "mqtt-hs"
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
    nodeSource (getMqttMsg pubChan) streamGraph2 hostName portNum -- processes source before sending it to another node

streamGraph2 :: Stream String -> Stream String
streamGraph2 = streamMap Prelude.id

getMqttMsg :: TChan (MQTT.Message 'MQTT.PUBLISH) -> IO String
getMqttMsg pubChan = atomically (readTChan pubChan) >>= handleMsg

handleMsg :: MQTT.Message 'MQTT.PUBLISH -> IO String
handleMsg msg = do
    let t = MQTT.topic $ MQTT.body msg
        p = MQTT.payload $ MQTT.body msg
        l = MQTT.getLevels t
    return $ read (show t) ++ " " ++ read (show p)
