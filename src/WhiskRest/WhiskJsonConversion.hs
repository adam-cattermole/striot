{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE DeriveGeneric #-}

module WhiskRest.WhiskJsonConversion
( ActivationInvocation (..)
, Activation (..)
, ActivationResponse (..)
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
import Data.ByteString.Lazy (ByteString)

import Striot.FunctionalIoTtypes

import GHC.Generics (Generic)

----------------- TO WHISK -----------------
------ ACTIVATION INVOCATION
newtype ActivationInvocation =
    ActivationInvocation { invokeId :: Text } deriving (Show, Generic)

instance FromJSON ActivationInvocation where
    parseJSON = withObject "ActivationInvocation" $ \o -> do
        invokeId <- o .: "activationId"
        return ActivationInvocation{..}

----------------- FROM WHISK -----------------
------ ACTIVATION
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

------ ACTIVATION RESPONSE
data ActivationResponse =
    ActivationResponse { status       :: Text
                       , success      :: Bool
                       , result       :: EventJson
                       } deriving (Show, Generic)

instance FromJSON ActivationResponse

------ NEW EVENT JSON TYPE

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
    in fromEventJson <$> x
