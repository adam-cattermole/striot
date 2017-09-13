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

streamGraph2 :: Stream String -> Stream String
streamGraph2 = streamMap Prelude.id

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
