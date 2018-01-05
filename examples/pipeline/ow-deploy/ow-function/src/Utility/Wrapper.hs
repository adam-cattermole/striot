{-# LANGUAGE OverloadedStrings #-}

module Utility.Wrapper
(
runner
) where

import System.Environment

import qualified Data.Text.Lazy.Encoding as T
import Data.Text.Lazy (Text, replace, pack)
import qualified Data.ByteString.Lazy.Char8 as Char8 (ByteString, unpack, putStrLn)
import Data.String.Conversions (cs)
import Data.Aeson
import Data.Char

import Control.Monad

import Striot.FunctionalIoTtypes
import WhiskRest.WhiskJsonConversion

runner :: (Show alpha, Read alpha) => (alpha -> alpha) -> IO ()
runner fun = do
    -- decode input to Event
    -- run function on Event alpha
    -- encode to json
    -- print output

    -- Grab command line args and error if there are none
    args <- getArgs'
    print $ head args
    when (null args) $ error "No arguments passed in!"
    let input = fetchInput $ head args
    case input of
        Just (E i t v) -> do
            let output = E i t (fun v)
            Char8.putStrLn $ encodeEvent output
        Nothing ->
            error "wsk-error: Failed to convert input to JSON"
    --
    -- print "test"
    -- print "output"



getArgs' :: IO [String]
getArgs' = return ["{\\\"body\\\": \\\"\\\\\\\"TCPKaliMsgTS-0005620a83d91718.\\\\\\\"\\\", \\\"uid\\\": 1, \\\"timestamp\\\": \\\"2017-11-21 16:30:00 UTC\\\"}\""]



fetchInput :: (Read alpha) => String -> Maybe (Event alpha)
fetchInput arg =
    let bs = T.encodeUtf8 . fixInputString $ arg
    in decodeEvent bs

fixInputString :: String -> Text
fixInputString s = replace "}\"" "}" . replace "\"{" "{" . replace "\\\\" "\\" . replace "\\\"" "\"" $ pack s
