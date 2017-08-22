{-# LANGUAGE OverloadedStrings #-}
import Data.Text
import Data.Aeson
-- Easy traversal of JSON data
import Data.Aeson.Lens (key, nth)
import Control.Lens
-- import Network.HTTP.Conduit
import Network.Wreq
import Network.Wreq.Types (Postable, Putable)
import Network.Connection (TLSSettings (..))
import Network.HTTP.Client.TLS (mkManagerSettings)
import Data.String.Conversions (cs)
import Control.Monad
-- import Control.Monad.IO.Class
import Data.ByteString (ByteString)
import qualified Data.ByteString.Lazy as DBL (ByteString)
-- import Data.Attoparsec.Number
-- import Control.Applicative
-- import Control.Monad.Trans
import WhiskJsonConversion

main :: IO ()
main = do
    putStrLn "Testing RESTful interaction"
    let section = "activations"
        actId = "171506fe8d1b49c4a5dbcb02550bc236"
        action = "test-whisk"
        url = apiEndpointUrl section actId
        testInput = ActionInput {input = "ACCELEROMETER (123,456,789)"}
    -- r <- asValue =<< get' (cs url)
    -- r <- getActivation actId
    putStrLn $ cs (encode testInput)
    r <- invokeAction action "ACCELEROMETER (123,456,789)"
    print $ r ^? responseBody
    -- print $ r ^? responseBody . key "activationId"

    -- r <- getActivation "c93ec2da45a4447ebb394016afe20cc3"

    -- r <- getActivation' "c93ec2da45a4447ebb394016afe20cc3"
    -- print r
    -- print $ r ^? responseBody . key "response" . key "result"
    -- print url




-- Need to create the url that we are communicating with for each action
-- Generic function which attaches parts of the request with optional parameters

apiEndpointUrl' :: Text -> Text -> Text -> Text -> Text
apiEndpointUrl' hostname ns section item =
    Data.Text.concat ["http://", hostname, "/api/v1/namespaces/",
        ns, "/", section, "/", item]

-- Here we partially apply the functions with default values
apiEndpointUrl :: Text -> Text -> Text
apiEndpointUrl = apiEndpointUrl' hostname ns

-- Create functions for each of the wsk actions

-- createAction
invokeAction :: Text -> Text -> IO (Response Value)
invokeAction item value =
    let url = apiEndpointUrl "actions" item
        actInput = ActionInput {input = value}
    in  postItem url actInput

-- TODO: Maybe change to this or no?
invokeAction' :: Text -> Text -> IO Text
invokeAction' item value = do
    let url = apiEndpointUrl "actions" item
        actInput = ActionInput {input = value}
    r <- postItem url actInput
    return $ activationId (r ^. responseBody)


getActivation :: Text -> IO (Response Value)
getActivation item =
    let url = apiEndpointUrl "activations" item
    in  getItem url

-- TODO: Maybe change to this or no?
-- getActivation' :: Text -> IO (Maybe Value)
-- getActivation' item = do
--     let url = apiEndpointUrl "activations" item
--     r <- getItem url
--     return $ r ^? responseBody . key "response" . key "result"

-- getActivation' :: Text -> Text
getActivation' item = do
    let url = apiEndpointUrl "activations" item
    r <- getItem url
    return $ output (r ^. responseBody)

-- Handle our particular data type

-- Convert to and from JSON, using aeson as done prior




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
                                & auth ?~ basicAuth user pass

-- Generalised getter
-- TODO: Add in JSON conversion and extraction
getItem :: (FromJSON a) => Text -> IO (Response a)
getItem url = asJSON =<< get' (cs url)

-- TODO: Add in JSON conversion
postItem :: (FromJSON a, ToJSON b) => Text -> b -> IO (Response a)
postItem url obj = asJSON =<< post' (cs url) (toJSON obj)

putItem :: (FromJSON a, ToJSON b) => Text -> b -> IO (Response a)
putItem url obj = asJSON =<< put' (cs url) (toJSON obj)



----- CONFIGURATION OPTIONS -----
-- definition of some default settings
hostname :: Text
hostname = "haskell-whisk.eastus.cloudapp.azure.com:10001"

ns :: Text
ns = "_"

-- definition of some basic user credentials
user :: ByteString
user = "23bc46b1-71f6-4ed5-8c54-816aa4f8c502"

pass :: ByteString
pass = "123zO3xZCLrMN6v2BKK1dXYFpXlPkccOFqm12CdAsMgRU4VrNZ9lyGVCGuMDGIwP"


-- May be of use
-- https://charlieharvey.org.uk/page/haskell_servant_rest_apis_as_types
