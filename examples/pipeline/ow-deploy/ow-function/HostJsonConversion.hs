{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}

module HostJsonConversion
( FunctionInput (..)
, ActionOutput (..)
, ActionArg (..)
) where

import Data.Aeson.Types
import Data.Text

import GHC.Generics (Generic)


------ OUR DATA TYPE ------
data FunctionInput =
    FunctionInput { function    :: Text
                  , arg         :: [Float]
                  } deriving (Show, Generic)

instance FromJSON FunctionInput


------ ACTIONS ------
newtype ActionOutput =
    ActionOutput { output :: [Float] } deriving (Generic, Show)

instance ToJSON ActionOutput where
    toEncoding = genericToEncoding defaultOptions

newtype ActionArg =
    ActionArg { input :: String } deriving (Generic, Show)

instance FromJSON ActionArg
