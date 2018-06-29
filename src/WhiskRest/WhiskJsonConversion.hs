{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE DeriveGeneric #-}

module WhiskRest.WhiskJsonConversion
( ActivationInvocation (..)
, Activation (..)
, ActivationResponse (..)
) where

import Data.Aeson
import Data.Text
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

data Activation alpha =
    Activation { namespace    :: Text
               , name         :: Text
               , version      :: Text
               , subject      :: Text
               , activationId :: Text
               , start        :: Int
               , end          :: Int
               , duration     :: Int
               , response     :: ActivationResponse alpha
               , logs         :: Array
               , annotations  :: Array
               , publish      :: Bool
               } deriving (Show, Generic)

instance (FromJSON alpha) => FromJSON (Activation alpha)

------ ACTIVATION RESPONSE

data ActivationResponse alpha =
    ActivationResponse { status       :: Text
                       , success      :: Bool
                       , result       :: Event alpha
                       } deriving (Show, Generic)

instance (FromJSON alpha) => FromJSON (ActivationResponse alpha)
