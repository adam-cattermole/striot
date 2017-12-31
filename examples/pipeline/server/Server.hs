import System.IO
import Data.List

import Striot.FunctionalProcessing
import Striot.FunctionalIoTtypes
import Striot.Nodes
import Network

import Data.Time (getCurrentTime, diffUTCTime, NominalDiffTime)
import Data.Time.Clock (UTCTime)
import Data.Time.Clock.POSIX (posixSecondsToUTCTime)
import Data.List.Split
import Numeric

listenPort = 9001 :: PortNumber

main :: IO ()
main = do
    writeFile "sw-log.txt" ""
    nodeSink kaliParse printStreamDelay listenPort
    -- nodeSink streamGraphid printStream listenPort

streamGraphid :: Stream String -> Stream String
streamGraphid = Prelude.id

kaliParse :: Stream String -> Stream UTCTime
kaliParse = streamMap (\x -> posixSecondsToUTCTime . fromRational $ fst (head (kaliParse' x)) / 1000000)

kaliParse' x = readHex $ filter (/='.') (splitOn "-" x !! 1)

-- streamGraph1 :: Stream Int -> Stream [Int]
-- streamGraph1= streamWindowAggregate (chopTime 1) fn

-- fn :: [Int] -> [Int]
-- fn e@(x:xs) =
--     let l = length e
--         currenthz = averageVal l (head e)
--         client2hz = averageVal l (last e) -- averaging over window in case it changes mid window
--     in [currenthz, client2hz, l]
-- fn [] = [0]

averageVal :: Int -> [Int] -> Int
averageVal l xs = sum xs `div` l

printStreamDelay :: Stream UTCTime -> IO ()
printStreamDelay (e@(E id t v):r) = do
    now <- getCurrentTime
    let newe = mapTimeDelay delay e where delay = diffUTCTime now v
    print newe
    appendFile "sw-log.txt" (show newe ++ "\n")
    printStreamDelay r
printStreamDelay (e:r) = do
    print e
    printStreamDelay r
printStreamDelay [] = return ()

printStream :: Stream String -> IO ()
printStream (e:r) = do
    print e
    printStream r

mapTimeDelay :: NominalDiffTime -> Event UTCTime -> Event (UTCTime, Float)
mapTimeDelay delay (E id t v) = E id t newv
    where newv = (v, roundN 10 (toRational delay))

roundN :: Int -> Rational -> Float
roundN n f = fromInteger (round $ f * (10^n)) / (10.0^^n)
