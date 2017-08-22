{-# LANGUAGE DeriveGeneric, OverloadedStrings #-}
-- {-# LANGUAGE RecordWildCards #-}

import System.Environment
import Data.List.Split
import Data.ByteString.Lazy (ByteString)
import Data.Text.Lazy (Text, replace, pack)
import qualified Data.Text.Lazy.Encoding as T
import Control.Monad

import Data.Aeson
import Data.Aeson.Types
import GHC.Generics
import GHC.Exts

newtype ActionOutput =
    ActionOutput { output :: [Float] } deriving (Generic, Show)

newtype ActionArg =
    ActionArg { input :: String } deriving (Generic, Show)

instance ToJSON ActionOutput where
    -- No need to provide a toJSON implementation.

    -- For efficiency, we write a simple toEncoding implementation, as
    -- the default version uses toJSON.
    toEncoding = genericToEncoding defaultOptions

instance FromJSON ActionArg
-- TODO: find out if need a specific definition of FromJSON or can use
--       default generic version
-- instance FromJSON ActionArg where
--     parseJSON = withObject "ActionArg" $ \o -> do
--         input <- o .: "input"
--         return ActionArg{..}
--     -- No need to provide a parseJSON implementation.

main :: IO ()
main = do
    -- Grab command line args
    args <- getArgs
    print $ head args
    -- No arguments
    when (null args) $ error "No arguments passed in!"

    -- Sort out string convert to JSON
    let input = fetchInput args
    case input of
        Just i -> do
            putStrLn ("input:" ++ i)
            putStrLn $ fun i
        Nothing -> putStrLn "Invalid Input: Failed to parse JSON"


fun :: String -> String
fun [] = []
fun s =
    let accData = convertToList s
        funOutput = ourOperation accData
    in  addJson funOutput

-- The function to run on the list of floats

ourOperation :: [Float] -> [Float]
ourOperation = map (+100)

getArgs' :: String
getArgs' = "[\"{\\\"input\\\": \\\"ACCELEROMETER (-14.377,-9.398,-31.597)\\\"}\"]"

-- Utility functions

fetchInput :: [String] -> Maybe String
fetchInput arg =
    let fixString = replace "}\"" "}" $ replace "\"{" "{" $ replace "\\" "" $ pack $ head arg
        decodeArg = decode (T.encodeUtf8 fixString) :: Maybe ActionArg
    in  case decodeArg of
            Just aa -> Just (input aa)
            Nothing -> Nothing

convertToList :: (Num a, Read a) => String -> [a]
convertToList s =
    let d = words s !! 1
        i = splitOn "," d
    in map (read . removeElem "()") i

convertToTuple  :: [Float] -> (Float,Float,Float)
convertToTuple [x,y,z] = (x,y,z)

addJson :: [Float] -> String
addJson output' = firstLast . removeElem "\\" $
    show $ encode ActionOutput {output = output'}

firstLast :: [a] -> [a]
firstLast xs@(_:_) = tail (init xs)
firstLast _ = []

removeElem :: String -> String -> String
removeElem repl = filter (not . (`elem` repl))
