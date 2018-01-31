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

streamGraphid :: Stream String -> Stream String
streamGraphid = Prelude.id

kaliParse :: Stream (String, String) -> Stream (String, UTCTime)
kaliParse = streamMap (\x -> (fst x, posixSecondsToUTCTime . fromRational $ fst (head (kaliParse' $ snd x)) / 1000000))

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

printStreamDelay :: Stream (String, UTCTime) -> IO ()
printStreamDelay (e@(E id t (pod,v)):r) = do
    now <- getCurrentTime
    let newe = mapTimeDelay e now
    print newe
    appendFile "sw-log.txt" (show newe ++ "\n")
    printStreamDelay r
printStreamDelay (e:r) = do
    print e
    printStreamDelay r
printStreamDelay [] = return ()

printStream :: Stream Int -> IO ()
printStream (e:r) = do
    print e
    printStream r

mapTimeDelay :: Event (String, UTCTime) -> UTCTime -> Event (String, UTCTime, Float)
mapTimeDelay (E id t (pod,v)) now = E id t newv
    where
        delay = diffUTCTime now v
        newv = (pod, v, roundN 10 (toRational delay))

roundN :: Int -> Rational -> Float
roundN n f = fromInteger (round $ f * (10^n)) / (10.0^^n)
