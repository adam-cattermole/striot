{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE FunctionalDependencies     #-}
{-# LANGUAGE GeneralisedNewtypeDeriving #-}
{-# LANGUAGE RecordWildCards            #-}
{-# LANGUAGE TemplateHaskell            #-}
{-# LANGUAGE UndecidableInstances       #-}

module Striot.Nodes.Types where

import           Control.Lens                             ((^.))
import           Control.Lens.Combinators                 (makeClassy)
import           Control.Lens.TH
import           Control.Monad.Base
import           Control.Monad.Reader
import           Control.Monad.State
import           Control.Monad.Trans.Control
import           Data.Int                                 (Int64)
import           Data.IORef
import           Network.Socket                           (HostName,
                                                           ServiceName)
import           System.Envy
import           System.Metrics.Prometheus.Metric.Counter (Counter)
import           System.Metrics.Prometheus.Metric.Gauge   (Gauge)


data Metrics = Metrics
    { _ingressConn   :: Gauge
    , _ingressBytes  :: Counter
    , _ingressEvents :: Counter
    , _egressConn    :: Gauge
    , _egressBytes   :: Counter
    , _egressEvents  :: Counter
    }

data NetConfig = NetConfig
    { _host :: HostName
    , _port :: ServiceName
    } deriving (Show)
makeLenses ''NetConfig

data TCPConfig = TCPConfig
    { _tcpConn :: NetConfig
    } deriving (Show)
makeLenses ''TCPConfig

data KafkaConfig = KafkaConfig
    { _kafkaConn     :: NetConfig
    , _kafkaTopic    :: String
    , _kafkaConGroup :: String
    } deriving (Show)
makeLenses ''KafkaConfig

data MQTTConfig = MQTTConfig
    { _mqttConn  :: NetConfig
    , _mqttTopic :: String
    } deriving (Show)
makeLenses ''MQTTConfig

data ConnectionConfig = ConnTCPConfig TCPConfig
                      | ConnKafkaConfig KafkaConfig
                      | ConnMQTTConfig MQTTConfig
                      deriving (Show)

data StriotConfig = StriotConfig
    { _nodeName          :: String
    , _ingressConnConfig :: ConnectionConfig
    , _egressConnConfig  :: ConnectionConfig
    , _chanSize          :: Int
    , _stateStore        :: NetConfig
    , _stateInit         :: Bool
    , _stateKey          :: String
    } deriving (Show)
makeClassy ''StriotConfig

instance ToEnv StriotConfig where
    toEnv StriotConfig {..} =
        makeEnv $
            [ "STRIOT_NODE_NAME" .= _nodeName
            , "STRIOT_CHAN_SIZE" .= _chanSize
            ] ++ writeConf INGRESS _ingressConnConfig
              ++ writeConf EGRESS  _egressConnConfig
              ++ [ "STRIOT_STATE_HOST" .= (_host _stateStore)
                 , "STRIOT_STATE_PORT" .= (_port _stateStore)
                 , "STRIOT_STATE_INIT" .= _stateInit
              ]

writeConf :: ConnectType -> ConnectionConfig -> [EnvVar]
writeConf t (ConnTCPConfig   conf) =
    let base = "STRIOT_" ++ show t ++ "_"
    in  [ (base ++ "TYPE") .= "TCP"
        , (base ++ "HOST") .= (conf ^. tcpConn . host)
        , (base ++ "PORT") .= (conf ^. tcpConn . port)]
writeConf t (ConnKafkaConfig conf) =
    let base = "STRIOT_" ++ show t ++ "_"
    in  [ (base ++ "TYPE")            .= "KAFKA"
        , (base ++ "HOST")            .= (conf ^. kafkaConn . host)
        , (base ++ "PORT")            .= (conf ^. kafkaConn . port)
        , (base ++ "KAFKA_TOPIC")     .= (conf ^. kafkaTopic)
        , (base ++ "KAFKA_CON_GROUP") .= (conf ^. kafkaConGroup)]
writeConf t (ConnMQTTConfig  conf) =
    let base = "STRIOT_" ++ show t ++ "_"
    in  [ (base ++ "TYPE")       .= "MQTT"
        , (base ++ "HOST")       .= (conf ^. mqttConn . host)
        , (base ++ "PORT")       .= (conf ^. mqttConn . port)
        , (base ++ "MQTT_TOPIC") .= (conf ^. mqttTopic)]

instance FromEnv StriotConfig where
    fromEnv _ =
        let state = readStateConf
        in  StriotConfig
            <$> envMaybe "STRIOT_NODE_NAME" .!= "striot"
            <*> readConf INGRESS
            <*> readConf EGRESS
            <*> envMaybe "STRIOT_CHAN_SIZE" .!= 10
            <*> nc "STRIOT_STATE_" (Just ("striot-redis", "6379"))
            <*> (fst <$> state)
            <*> (snd <$> state)

readConf :: ConnectType -> Parser ConnectionConfig
readConf t = do
    let base = "STRIOT_" ++ show t ++ "_"
    p <- env (base ++ "TYPE")
    case p of
        "TCP"   -> ConnTCPConfig
                    <$> (TCPConfig
                            <$> nc base Nothing)
        "KAFKA" -> ConnKafkaConfig
                    <$> (KafkaConfig
                        <$> nc base Nothing
                        <*> env (base ++ "KAFKA_TOPIC")
                        <*> env (base ++ "KAFKA_CON_GROUP"))
        "MQTT"  -> ConnMQTTConfig
                    <$> (MQTTConfig
                        <$> nc base Nothing
                        <*> env (base ++ "MQTT_TOPIC"))

readStateConf :: Parser (Bool, String)
readStateConf = do
    let p = envMaybe ("STRIOT_STATE_INIT") .!= False
    init <- p
    case init of
        False -> (,) <$> p <*> envMaybe "STRIOT_STATE_KEY" .!= ""
        True  -> (,) <$> p <*> env "STRIOT_STATE_KEY"

nc :: String -> Maybe (HostName, ServiceName) -> Parser NetConfig
nc base Nothing = NetConfig
    <$> env (base ++ "HOST")
    <*> env (base ++ "PORT")
nc base (Just (host,port)) = NetConfig
    <$> envMaybe (base ++ "HOST") .!= host
    <*> envMaybe (base ++ "PORT") .!= port

newtype StriotApp a =
    StriotApp {
        unStriotApp :: ReaderT StriotConfig IO a
    } deriving (
        Functor,
        Applicative,
        Monad,
        MonadReader StriotConfig,
        MonadIO
    )

data ConnectType = INGRESS
                 | EGRESS
                 deriving (Show)

data ConnectProtocol = TCP
                     | KAFKA
                     | MQTT

newtype App s a =
    App {
        unApp :: ReaderT StriotConfig (StateT (StriotState s) IO) a
    } deriving (
        Functor,
        Applicative,
        Monad,
        MonadReader StriotConfig,
        MonadState (StriotState s),
        MonadIO,
        MonadBase IO,
        MonadBaseControl IO
    )

data StriotState s = StriotState
    { _accKey   :: String
    , _accValue :: Maybe s}
    deriving (Show)
makeClassy ''StriotState
