{-# LANGUAGE OverloadedStrings #-}
-- {-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE DeriveGeneric #-}

module WhiskJsonConversion
( Activation (..)
, ActivationResponse (..)
, ActivationResult (..)
, ActivationInvocation (..)
, ActionInput (..)
) where

import Data.Aeson.Types
import Data.Text

import GHC.Generics (Generic)


------ ACTIVATIONS ------
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



data ActivationResponse =
    ActivationResponse { status       :: Text
                       , success      :: Bool
                       , result       :: ActivationResult
                       } deriving (Show, Generic)

instance FromJSON ActivationResponse

newtype ActivationResult =
    ActivationResult { output :: [Float] } deriving (Show, Generic)

instance FromJSON ActivationResult

newtype ActivationInvocation =
    ActivationInvocation { activationId :: Text } deriving (Show, Generic)

instance FromJSON ActivationInvocation

------ ACTIONS ------
newtype ActionInput =
    ActionInput { input :: Text} deriving (Generic, Show)

instance ToJSON ActionInput where
    toEncoding = genericToEncoding defaultOptions

-- "response": {
--   "result": {
--     "result": [200.0, 300.0, 400.0]
--   },
