{-# LANGUAGE OverloadedStrings #-}

module WhiskRest.WhiskConnect
( invokeAction
, getActivation
, getActivationRetry
, apiEndpointUrl
) where

import Data.Text
import Data.Aeson
import Data.Aeson.Lens (key, nth)
import Control.Lens

import Network.Wreq
import Network.Wreq.Types (Postable, Putable)
import Network.Connection (TLSSettings (..))
import Network.HTTP.Client.TLS (mkManagerSettings)
import Network.HTTP.Client(HttpException)

import Control.Monad
import Control.Concurrent
import Control.Concurrent.STM
import Control.Exception

import Data.String.Conversions (cs)
import Data.ByteString (ByteString)
import qualified Data.Text.Lazy.Encoding as T
import qualified Data.ByteString.Lazy as DBL (ByteString)

import System.IO
-- Our file defining the types for JSON conversion
import WhiskRest.WhiskJsonConversion
import Striot.FunctionalIoTtypes
-- Configuration parameters
import qualified WhiskRest.WhiskConfig as WC


-- Need to create the url that we are communicating with for each action
-- Generic function which attaches parts of the request with optional parameters
apiEndpointUrl' :: Text -> Text -> Text -> Text -> Text
apiEndpointUrl' hostname ns section item =
    Data.Text.concat ["http://", hostname, "/api/v1/namespaces/",
        ns, "/", section, "/", item]

-- Here we partially apply the functions with default values
apiEndpointUrl :: Text -> Text -> Text
apiEndpointUrl = apiEndpointUrl' WC.hostname WC.namespace

-- Create functions for each of the wsk actions

-- create new activation
invokeAction' :: (Show alpha) => Text -> Event alpha -> IO Text
invokeAction' item event = do
    let url = apiEndpointUrl "actions" item
        eJson = toEventJson event
        -- decoded = decode . T.encodeUtf8 . cs . fixInputString $ value :: Maybe FunctionInput
    -- case decoded of
        -- Just fi -> do
    r <- postItem url eJson
    return $ invokeId (r ^. responseBody)
        -- Nothing -> error "wsk-error: Failed to decode FunctionInput (value:" ++ cs value ++")"
        -- actInput = ActionInput {input = value}
    -- r <- postItem url actInput
    -- return $ invokeId (r ^. responseBody)

invokeAction :: (Show alpha) => Event alpha -> IO Text
invokeAction = invokeAction' WC.action


-- Get the output from activation
getActivation' :: Text -> IO EventJson
getActivation' item = do
    let url = apiEndpointUrl "activations" item
    getActivationType url


getActivationType :: Text -> IO EventJson
getActivationType url = do
    r <- getItem url
    return $ result . response $ r ^. responseBody


-- Recursively call get activation' and catch exception until out of retries
-- threadDelay is set to 1 second (at least) between retries. Once out of retries
-- exception is thrown
getActivationRetry :: Int -> Text -> IO EventJson
getActivationRetry n item =
    catch  (getActivation' item)
                (\e -> do
                    let err = show (e :: HttpException)
                    hPutStrLn stderr ("wsk-warning: Failed to retrieve output (retries:" ++  show n ++ ", actId:" ++ show item ++ ")")
                    case n of
                        0 -> throw e
                        _ -> do threadDelay 1000000
                                getActivationRetry (n-1) item)


-- The default implementation runs through our function with 0 retries
getActivation :: Text -> IO EventJson
getActivation = getActivationRetry 0


----- UTILITY FUNCTIONS -----

-- Overall GET function
get' :: String -> IO (Response DBL.ByteString)
get' = getWith createOpts

-- Overall POST function
post' :: (Postable a) => String -> a -> IO (Response DBL.ByteString)
post' = postWith createOpts

-- Overall PUT function
put' :: (Putable a) => String -> a -> IO (Response DBL.ByteString)
put' = putWith createOpts

-- Need to override the basic get function in the Network.Wreq package with our parameters
-- This simply appends auth and does not check the certificate
createOpts :: Network.Wreq.Options
createOpts = defaults & manager .~ Left (mkManagerSettings (TLSSettingsSimple True False False) Nothing)
                                & auth ?~ basicAuth WC.user WC.pass

-- Generalised getter
-- TODO: Add in JSON conversion and extraction
getItem :: (FromJSON a) => Text -> IO (Response a)
getItem url = asJSON =<< get' (cs url)

-- TODO: Add in JSON conversion
postItem :: (FromJSON a, ToJSON b) => Text -> b -> IO (Response a)
postItem url obj = asJSON =<< post' (cs url) (toJSON obj)

putItem :: (FromJSON a, ToJSON b) => Text -> b -> IO (Response a)
putItem url obj = asJSON =<< put' (cs url) (toJSON obj)


fixInputString :: Text -> Text
fixInputString = replace "}\"" "}" . replace "\"{" "{" . replace "\\" ""
