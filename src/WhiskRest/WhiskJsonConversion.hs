{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE DeriveGeneric #-}

module WhiskRest.WhiskJsonConversion
( Activation (..)
, ActivationResponse (..)
, ActivationResult (..)
, ActivationInvocation (..)
, ActionInput (..)
--
, FunctionInput (..)
, ActionOutputType (..)
, EventJson (..)
--
, toEventJson
, fromEventJson
, encodeEvent
, decodeEvent
) where

import Data.Aeson
import Data.Aeson.Types
import Data.Text
import qualified Data.HashMap.Strict as HM

import Striot.FunctionalIoTtypes
import Data.Maybe(isJust)
import Data.ByteString.Lazy (ByteString)

import GHC.Generics (Generic)

------ OUR DATA TYPE ------
data FunctionInput =
    FunctionInput { function    :: Text
                  , arg         :: [Float]
                  } deriving (Show, Generic)

instance ToJSON FunctionInput where
  toEncoding = genericToEncoding defaultOptions

instance FromJSON FunctionInput

------ ACTIVATION ------
data Activation =
    Activation { namespace    :: Text
               , name         :: Text
               , version      :: Text
               , subject      :: Text
               , activationId :: Text
               , start        :: Int
               , end          :: Int
               , duration     :: Int
               , response     :: ActivationResponse
               , logs         :: Array
               , annotations  :: Array
               , publish      :: Bool
               } deriving (Show, Generic)

instance FromJSON Activation



------ ACTIVATION RESPONSE ------
data ActivationResponse =
    ActivationResponse { status       :: Text
                       , success      :: Bool
                       , result       :: EventJson
                       } deriving (Show, Generic)

instance FromJSON ActivationResponse



------ ACTIVATION RESULT ------

newtype ActivationResult =
    ActivationResult { output :: [Float] } deriving (Show, Generic)

instance FromJSON ActivationResult

------ ACTIVATION INVOCATION ------
newtype ActivationInvocation =
    ActivationInvocation { invokeId :: Text } deriving (Show, Generic)

instance FromJSON ActivationInvocation where
    parseJSON = withObject "ActivationInvocation" $ \o -> do
        invokeId <- o .: "activationId"
        return ActivationInvocation{..}


------ ACTION INPUT ------
newtype ActionInput =
    ActionInput { input :: Text} deriving (Generic, Show)

instance ToJSON ActionInput where
    toEncoding = genericToEncoding defaultOptions

------ ACTION OUTPUT TYPE ------

-- a 'tag' key is added to the JSON to represent which constructor is used
data ActionOutputType = ActionOutputBool { boolData :: Bool} |
                  ActionOutputFloatList { floatData :: [Float]}
                  deriving (Generic, Show, Read)

instance ToJSON ActionOutputType where
    toEncoding = genericToEncoding defaultOptions

instance FromJSON ActionOutputType


------ NEW EVENT JSON TYPE (WIP) ------

data EventJson =
    EventJson { uid         :: Int
              , timestamp   :: Text
              , body        :: Text
              } deriving (Show, Generic)

instance ToJSON EventJson where
  toEncoding = genericToEncoding defaultOptions

instance FromJSON EventJson


toEventJson :: (Show alpha) => Event alpha -> EventJson
toEventJson (E i t v) = EventJson { uid = i
                                , timestamp = pack . show $ t
                                , body = pack . show $ v}

fromEventJson :: (Read alpha) => EventJson -> Event alpha
fromEventJson eJson =
    let i = uid eJson
        t = read . unpack $ timestamp eJson
        v = read . unpack $ body eJson
    in  E i t v

encodeEvent :: (Show alpha) => Event alpha -> ByteString
encodeEvent = encode . toEventJson


decodeEvent :: (Read alpha) => ByteString -> Maybe (Event alpha)
decodeEvent bs =
    let x = decode bs :: Maybe EventJson
    -- in if isJust x then
    in fromEventJson <$> x
    --     let (Just dc) = x
    --         i = uid dc
    --         t = read . unpack $ timestamp dc
    --         v = read . unpack $ body dc
    --     in Just (E i t v)
    -- else
    --     Nothing
