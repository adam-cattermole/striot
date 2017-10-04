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
import Data.ByteString (ByteString)
import Data.String.Conversions (cs)
import Data.List.Split
import Data.Aeson

import Control.Monad(when)

import WhiskRest.WhiskJsonConversion

portNum  = 9002::PortNumber
hostName = "haskellclient2"::HostName
mqttHost = "mqtt-broker.eastus.cloudapp.azure.com"::HostName

accelT, btnT, tempT, magnT :: MQTT.Topic
accelT = "ACCELEROMETER"
btnT = "BUTTON"
tempT = "TEMPERATURE"
magnT = "MAGNETOMETER/+"
-- + one level deep wildcard
-- * all levels below wildcard

topics :: [MQTT.Topic]
topics = [accelT,btnT,tempT,magnT]

main :: IO ()
main = nodeMqttByTopicSource mqttHost topics accelT streamGraph2 hostName portNum

streamGraph2 :: (Floating alpha) => Stream [alpha] -> Stream [alpha]
streamGraph2 = streamMap Prelude.id
