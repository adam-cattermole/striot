{-# LANGUAGE OverloadedStrings #-}
-- {-# LANGUAGE RecordWildCards #-}

import System.IO
import System.Environment

import Data.List.Split
import qualified Data.Map as Map
import Data.ByteString.Lazy (ByteString)
import Data.Text.Lazy (Text, replace, pack)
import Data.String.Conversions (cs)
import qualified Data.Text.Lazy.Encoding as T

import Control.Monad
import Control.Exception

import Data.Aeson

-- import Data.Aeson.Types
-- import GHC.Generics
-- import GHC.Exts
import HostJsonConversion


main :: IO ()
main = do
    -- Grab command line args and error if there are none
    args <- getArgs'
    print $ head args
    when (null args) $ error "No arguments passed in!"

    -- Convert our string to our JSON FunctionInput
    -- 'function':  determines the function to run
    -- 'arg':       provides us some arguments for the desired function
    let funcInput = fetchInput $ head args
    case funcInput of
        Just fi -> do
            print funcInput
            let xs@(fun:[sub]) = splitOn "." $ cs (function fi)
            case fun of
                "mqtt" -> do
                    putStrLn "Perform mqtt function"
                    case sub of
                        "accel" -> putStrLn "Perform accel func"
                        "magn" -> putStrLn "Perform magn func"
                        "btn" -> putStrLn "Perform btn func"
                        _ -> error $ wskErrorString sub xs fun sub
                "util" -> do
                    putStrLn "Perform util function"
                    case sub of
                        "busy-wait" -> putStrLn "Perform busy-wait func"
                        _ -> error $ wskErrorString sub xs fun sub
                _ -> error $ wskErrorString fun xs fun sub
            -- Run required actions here
        Nothing ->
            error "wsk-error: Failed to convert input to JSON"
    -- case input of
        -- Just i -> do
            -- putStrLn ("input:" ++ i)
            -- putStrLn $ runOperation i
        -- Nothing -> putStrLn "Invalid Input: Failed to parse JSON"


-- Another attempt at flow control
runFunction :: [String] -> String -> String -> String
runFunction xs fun sub =
    let x = Map.lookup fun validFunctions
    in  case x of
        Just v ->
            if sub `elem` v then
                "sub"
            else
                error $ wskErrorString sub xs fun sub
        Nothing ->
            error $ wskErrorString fun xs fun sub



validFunctions :: Map.Map String [String]
validFunctions = Map.fromList [("mqtt",["accel","magn","temp","btn"]),("util",["busy-wait"])]


runOperation :: String -> String
runOperation [] = []
runOperation s =
    let accData = convertToList s
        funOutput = fun accData
    in  addJson funOutput

-- The function to run on the list of floats

fun :: [Float] -> [Float]
fun = map (+100)

getArgs' :: IO [String]
getArgs' = return ["{\\\"arg\\\": [123, 300, 100], \\\"function\\\": \\\"util.busy-wait\\\"}\""]

---- UTILITY FUNCTIONS ----

fetchInput :: String -> Maybe FunctionInput
fetchInput arg =
    let fixByteString = T.encodeUtf8 $ fixInputString arg
    in decode fixByteString :: Maybe FunctionInput
    -- in  case decodeArg of
            -- Just aa -> Just (input aa)
            -- Nothing -> Nothing


convertToList :: (Num a, Read a) => String -> [a]
convertToList s =
    let d = words s !! 1
        i = splitOn "," d
    in map (read . removeElem "()") i

wskErrorString :: String -> [String] -> String -> String -> String
wskErrorString issue xs fun sub = "wsk-error: Invalid function provided. \n\
                \  \"" ++ issue ++ "\" unknown in:\n\
                \    (xs:" ++ show xs ++
                    ",fun:" ++ fun ++
                    ",sub:" ++ sub ++ ")"


fixInputString :: String -> Text
fixInputString s = replace "}\"" "}" . replace "\"{" "{" . replace "\\" "" $ pack s


addJson :: [Float] -> String
addJson output' = firstLast . removeElem "\\" $
    show $ encode ActionOutput {output = output'}

firstLast :: [a] -> [a]
firstLast xs@(_:_) = tail (init xs)
firstLast _ = []

removeElem :: String -> String -> String
removeElem repl = filter (not . (`elem` repl))
