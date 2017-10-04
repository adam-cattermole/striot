{-# LANGUAGE OverloadedStrings #-}

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
import Control.Concurrent
import Control.Concurrent.STM

import Data.Aeson

import WhiskRest.WhiskJsonConversion

data ActionType = BoolOutput Bool | FloatOutput [Float]


main :: IO ()
main = do
    -- Grab command line args and error if there are none
    args <- getArgs
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
                run = performFun (arg fi) sub
                err = wskErrorString xs fun sub
            case fun of
                "mqtt" -> do
                    putStrLn "Perform mqtt function"
                    case sub of
                        "ACCELEROMETER" -> run accel
                        "MAGNETOMETER" -> run magn
                        "TEMPERATURE" -> run temp
                        -- "BUTTON" -> run btn
                        _ -> error $ err sub
                "util" -> do
                    putStrLn "Perform util function"
                    case sub of
                        "busy-wait" -> run busyWait
                        _ -> error $ err sub
                _ -> error $ err fun
        Nothing ->
            error "wsk-error: Failed to convert input to JSON"



---- WSK UTILITY FUNCTIONS ----

-- BUSY-WAIT

-- We can't use our helper runOperation function here
-- as this function is impure due to requiring IO from
-- additional threads and an IO TChan
busyWait :: [Float] -> IO String
busyWait param = do
    chan <- newTChanIO
    let delay = round $ head param

    _ <- forkIO $ do
        -- microseconds for threadDelay
        threadDelay (1000000 * delay)
        atomically $ writeTChan chan True

    out <- retryReadTChan chan
    return $ addJson (BoolOutput out)


retryReadTChan :: (Show a) => TChan a -> IO a
retryReadTChan chan = do
    r <- atomically $ tryReadTChan chan
    case r of
        Nothing -> retryReadTChan chan
        Just x -> return x



---- WSK MQTT FUNCTIONS ----

-- ACCEL
accel :: [Float] -> IO String
accel = runOperation (FloatOutput . fun)

-- MAGN
magn :: [Float] -> IO String
magn = runOperation (FloatOutput . fun)

-- TEMP
temp :: [Float] -> IO String
temp = runOperation (FloatOutput . fun)

-- BTN
-- Button data wouldn't be a float tbh - list of strings
-- btn :: [Float] -> IO String
-- btn = runOperation (FloatOutput . fun)


-- The function to run on the list of floats
-- can define whatever we want here, and easily change
-- what we are running on
fun :: [Float] -> [Float]
fun = map (+100)


getArgs' :: IO [String]
getArgs' = return ["{\\\"arg\\\": [300,123,12324], \\\"function\\\": \\\"mqtt.ACCELEROMETER\\\"}\""]


---- HELPER FUNCTIONS ----

-- Takes a function and prints the name passed in
-- Runs function and gets output before printing
-- Output should contain the JSON string
performFun :: [Float] -> String -> ([Float] -> IO String) -> IO ()
performFun param name fn = do
    putStrLn ("Perform "++ name ++ " func")
    output <- fn param
    putStrLn output


-- This takes a function which accepts the parameters and outputs an ActionType
-- The ActionType is converted to JSON by the necessary function and returned
-- as an IO string
runOperation :: ([Float] -> ActionType) -> [Float] -> IO String
runOperation f param  =
    let funOutput = f param
    in  return $ addJson funOutput

fetchInput :: String -> Maybe FunctionInput
fetchInput arg =
    let fixByteString = T.encodeUtf8 $ fixInputString arg
    in decode fixByteString :: Maybe FunctionInput

wskErrorString :: [String] -> String -> String -> String -> String
wskErrorString xs fun sub issue = "wsk-error: Invalid function provided. \n\
                \  \"" ++ issue ++ "\" unknown in:\n\
                \    (xs:" ++ show xs ++
                    ",fun:" ++ fun ++
                    ",sub:" ++ sub ++ ")"

fixInputString :: String -> Text
fixInputString s = replace "}\"" "}" . replace "\"{" "{" . replace "\\" "" $ pack s

addJson :: ActionType -> String
addJson (BoolOutput b) = fixOutputString ActionOutputBool {boolData = b}
addJson (FloatOutput xs) = fixOutputString ActionOutputFloatList {floatData = xs}

firstLast :: [a] -> [a]
firstLast xs@(_:_) = tail (init xs)
firstLast _ = []

removeElem :: (Eq a) => [a] -> [a] -> [a]
removeElem repl = filter (not . (`elem` repl))

fixOutputString :: (ToJSON a) => a -> String
fixOutputString = firstLast . removeElem "\\" . show . encode

---- UNUSED FUNCTIONS ----


convertToList :: (Num a, Read a) => String -> [a]
convertToList s =
    let d = words s !! 1
        i = splitOn "," d
    in map (read . removeElem "()") i

--

validFunctions :: Map.Map String [String]
validFunctions = Map.fromList [("mqtt",["accel","magn","temp","btn"]),("util",["busy-wait"])]

-- Another attempt at flow control
runFunction :: [String] -> String -> String -> String
runFunction xs fun sub =
    let x = Map.lookup fun validFunctions
    in  case x of
        Just v ->
            if sub `elem` v then
                "sub"
            else
                error $ wskErrorString xs fun sub sub
        Nothing ->
            error $ wskErrorString xs fun sub fun
