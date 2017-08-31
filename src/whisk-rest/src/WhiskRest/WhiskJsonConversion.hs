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
) where

import Data.Aeson.Types
import Data.Text
import qualified Data.HashMap.Strict as HM

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
                       , result       :: ActionOutputType
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
                  deriving (Generic, Show)

instance ToJSON ActionOutputType where
    toEncoding = genericToEncoding defaultOptions

instance FromJSON ActionOutputType
