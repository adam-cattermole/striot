{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE DeriveGeneric #-}

module WhiskRest.WhiskJsonConversion
( Activation (..)
, ActivationResponse (..)
, ActivationResult (..)
, ActivationInvocation (..)
, ActionInput (..)
) where

import Data.Aeson.Types
import Data.Text

import GHC.Generics (Generic)


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
                       , result       :: ActivationResult
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


------ ACTIONS ------
newtype ActionInput =
    ActionInput { input :: Text} deriving (Generic, Show)

instance ToJSON ActionInput where
    toEncoding = genericToEncoding defaultOptions
