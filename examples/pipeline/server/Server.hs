{-# LANGUAGE FlexibleContexts #-}
import System.IO
import System.IO.Unsafe (unsafeInterleaveIO)
import Data.List

import Striot.FunctionalProcessing
import Striot.FunctionalIoTtypes
import Striot.Nodes
import Network.Socket (ServiceName)

import Data.Time (getCurrentTime, diffUTCTime, NominalDiffTime)
import Data.Time.Clock (UTCTime)
import Data.Time.Clock.POSIX (posixSecondsToUTCTime)
import Data.List.Split
import qualified Data.ByteString.Lazy.Char8 as BLC (hPutStrLn)
import Numeric
import Data.Aeson
import qualified Data.Text as T
import qualified Data.Text.Read as TR
import Data.Either.Combinators
import Control.Monad (when)
import Control.Concurrent
import Control.Concurrent.STM

listenPort = "9001" :: ServiceName
fileName = "sw-log.txt"

main :: IO ()
main = do
    chan <- newTChanIO
    writeFile fileName ""
    hdl <- openFile fileName WriteMode
    hSetBuffering hdl NoBuffering
    _ <- forkFinally (writeToFile hdl chan) (\_ -> hClose hdl)
    nodeSink streamGraphid (sinkToChan chan) listenPort
    -- nodeSink streamGraphid printStream listenPort

streamGraphid :: Stream T.Text -> Stream T.Text
streamGraphid = streamMap (\x -> Prelude.id x)

kaliParse :: Stream String -> Stream UTCTime
kaliParse = streamMap (\x -> posixSecondsToUTCTime . fromRational $ fst (head (kaliParse' x)) / 1000000)

kaliParse' x = readHex $ take 16 (drop 13 x)

kaliParse'' :: Stream T.Text -> Stream UTCTime
kaliParse'' = streamMap (\x -> posixSecondsToUTCTime . fromRational $ (kaliParse''' x) /1000000)

kaliParse''' :: T.Text -> Rational
kaliParse''' x =
    let e = kaliParse'''' x
        (i, t) = fromRight' e
    in  fromIntegral i

kaliParse'''' :: T.Text -> Either String (Integer, T.Text)
kaliParse'''' x = TR.hexadecimal $ T.take 16 (T.drop 13 x)

averageVal :: Int -> [Int] -> Int
averageVal l xs = sum xs `div` l


sinkToChan :: (ToJSON alpha) => TChan (Event (alpha, UTCTime)) -> Stream alpha -> IO ()
sinkToChan chan stream = do
    out <- mapDelay stream
    mapM_ (writeEvent chan) out
  where
      writeEvent chan x = atomically $ writeTChan chan x

writeToFile :: (ToJSON alpha) => Handle -> TChan (Event (alpha, UTCTime)) -> IO ()
writeToFile hdl chan = do
    stream <- readEventsTChan chan
    hPutLines'' hdl stream

readEventsTChan :: ToJSON alpha => TChan (Event (alpha, UTCTime)) -> IO (Stream (alpha, UTCTime))
readEventsTChan eventChan = System.IO.Unsafe.unsafeInterleaveIO $ do
    x <- atomically $ readTChan eventChan
    xs <- readEventsTChan eventChan
    return (x : xs)


printStreamDelay :: (ToJSON alpha, Show alpha) => Stream alpha -> IO ()
printStreamDelay stream = do
    hdl <- openFile fileName WriteMode
    hSetBuffering hdl NoBuffering
    output <- mapDelay stream
    hPutLines'' hdl output


mapDelay :: Stream alpha -> IO (Stream (alpha, UTCTime))
mapDelay (e@(E id t v):r) = unsafeInterleaveIO $ do
    x <- msg e v
    xs <- mapDelay r
    return (x:xs)
  where
    msg x v = do
        now <- getCurrentTime
        return x { value = (v, now) }


hPutLines'' :: ToJSON (Event alpha) => Handle -> Stream alpha -> IO ()
hPutLines'' handle (x:xs) = do
    writable <- hIsWritable handle
    when writable $ do
        BLC.hPutStrLn handle (encode x)
        hFlush handle
        hPutLines'' handle xs

-- printStreamDelay :: Stream UTCTime -> IO ()
-- printStreamDelay (e@(E id t v):r) = do
--     now <- getCurrentTime
--     let newe = mapTimeDelay delay e where delay = diffUTCTime now v
--     appendFile "sw-log.txt" (show newe ++ "\n")
--     printStreamDelay r
-- printStreamDelay (e:r) = do
--     print e
--     printStreamDelay r
-- printStreamDelay [] = return ()

printStream :: Stream String -> IO ()
printStream (e:r) = do
    print e
    printStream r

mapTimeDelay :: NominalDiffTime -> Event UTCTime -> Event (UTCTime, Float)
mapTimeDelay delay (E id t v) = E id t newv
    where newv = (v, roundN 10 (toRational delay))

roundN :: Int -> Rational -> Float
roundN n f = fromInteger (round $ f * (10^n)) / (10.0^^n)
