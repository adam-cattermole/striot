{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE FlexibleContexts #-}

module WhiskRest.WhiskConnect
( invokeAction
, getActivation
, getActivationRetry
, apiEndpointUrl
) where

import Data.Text
import Data.Aeson
import Control.Lens

import Network.Wreq
import Network.Wreq.Types (Postable, Putable)
import Network.Connection (TLSSettings (..))
import Network.HTTP.Client.TLS (mkManagerSettings)
import Network.HTTP.Client(HttpException)

import Control.Concurrent
import Control.Exception

import Data.String.Conversions (cs)
import qualified Data.ByteString.Lazy as BL (ByteString)

import Striot.FunctionalIoTtypes

import WhiskRest.WhiskJsonConversion
import qualified WhiskRest.WhiskConfig as WC


-- Need to create the url that we are communicating with for each action
-- Generic function which attaches parts of the request with optional parameters
apiEndpointUrl' :: Text -> Text -> Text -> Text -> Text
apiEndpointUrl' hostname ns section item =
    Data.Text.concat ["https://", hostname, "/api/v1/namespaces/",
        ns, "/", section, "/", item]


-- Here we partially apply the functions with default values
apiEndpointUrl :: Text -> Text -> Text
apiEndpointUrl = apiEndpointUrl' WC.hostname WC.namespace

-- Functions for whisk actions

-- Create new activation
invokeAction' :: ToJSON (Event alpha) => Text -> Event alpha -> IO Text
invokeAction' item obj = do
    let url = apiEndpointUrl "actions" item
    r <- postItem url obj
    return $ invokeId (r ^. responseBody)


invokeAction :: ToJSON (Event alpha) => Event alpha -> IO Text
invokeAction = invokeAction' WC.action


-- Get the output from activation
getActivation' :: FromJSON alpha => Text -> IO (Event alpha)
getActivation' item = do
    let url = apiEndpointUrl "activations" item
    getActivationType url


getActivationType :: FromJSON alpha => Text -> IO (Event alpha)
getActivationType url = do
    r <- getItem url
    return $ result . response $ r ^. responseBody


-- Recursively call get activation' and catch exception until out of retries
-- threadDelay is set to 1 second (at least) between retries. Once out of retries
-- exception is thrown
getActivationRetry :: FromJSON alpha => Int -> Text -> IO (Event alpha)
getActivationRetry n item =
    catch  (getActivation' item)
                (\e  -> do
                    let err = show (e :: HttpException)
                    -- hPutStrLn stderr ("wsk-warning: Failed to retrieve output (retries:" ++  show n ++ ", actId:" ++ show item ++ ")")
                    case n of
                        0 -> throw e
                        _ -> do threadDelay 1000000
                                getActivationRetry (n-1) item)


-- The default implementation runs through our function with 0 retries
getActivation :: FromJSON alpha => Text -> IO (Event alpha)
getActivation = getActivationRetry 0


----- UTILITY FUNCTIONS -----

-- Overall GET function
get' :: String -> IO (Response BL.ByteString)
get' = getWith createOpts


-- Overall POST function
post' :: (Postable a) => String -> a -> IO (Response BL.ByteString)
post' = postWith createOpts


-- Overall PUT function
put' :: (Putable a) => String -> a -> IO (Response BL.ByteString)
put' = putWith createOpts


-- Need to override the basic get function in the Network.Wreq package with our parameters
-- This simply appends auth and does not check the certificate
createOpts :: Network.Wreq.Options
createOpts = defaults & manager .~ Left (mkManagerSettings (TLSSettingsSimple True False False) Nothing)
                      & auth ?~ basicAuth WC.user WC.pass
                      & header "Content-Type" .~ ["application/json"]


-- gets at url for a JSON object
getItem :: (FromJSON a) => Text -> IO (Response a)
getItem url = asJSON =<< get' (cs url)


-- posts a JSON object and expects JSON response
postItem :: (FromJSON a, ToJSON b) => Text -> b -> IO (Response a)
postItem url obj = asJSON =<< post' (cs url) (encode obj)


-- puts a JSON object and expects a JSON response
putItem :: (FromJSON a, ToJSON b) => Text -> b -> IO (Response a)
putItem url obj = asJSON =<< put' (cs url) (encode obj)
