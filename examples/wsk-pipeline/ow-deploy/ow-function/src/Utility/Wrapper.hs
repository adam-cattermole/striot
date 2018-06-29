{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE FlexibleContexts #-}

module Utility.Wrapper
(
runner
) where

import System.Environment
import qualified Data.ByteString.Lazy.Char8 as BLC (putStrLn, pack)
import Data.Aeson
import Control.Monad (when)

import Striot.FunctionalIoTtypes

runner :: (ToJSON (Event beta), FromJSON (Event alpha), FromJSON alpha) => (alpha -> beta) -> IO ()
runner fun = do
    -- decode input to Event
    -- run function on Event alpha
    -- encode to json
    -- print output

    -- Grab command line args and error if there are none
    args <- getArgs
    when (null args) $ error "No arguments passed in!"
    print $ "First arg: " ++ head args
    let input = decode . BLC.pack $ head args
    case input of
        Just (E i t v) -> do
            let output = E i t (fun v)
            BLC.putStrLn $ encode output
        _ ->
            error "wsk-error: Failed to convert input to JSON"
