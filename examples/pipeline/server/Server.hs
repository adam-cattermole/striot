import System.IO
import Data.List
import Striot.FunctionalProcessing
import Striot.FunctionalIoTtypes
import Striot.Nodes
import Network

import Data.Time (getCurrentTime, diffUTCTime, NominalDiffTime)

listenPort = 9001 :: PortNumber

main :: IO ()
main = do
    writeFile "serial-log.txt" ""
    nodeSink streamGraph1 printStreamDelay listenPort

streamGraphid :: Stream [Int] -> Stream [Int]
streamGraphid = Prelude.id

streamGraph1 :: Stream [Int] -> Stream [Int]
streamGraph1= streamWindowAggregate (chopTime 1) fn

fn :: [[Int]] -> [Int]
fn e@(x:xs) =
    let l = length e
        currenthz = averageVal l (map head e)
        client2hz = averageVal l (map last e) -- averaging over window in case it changes mid window
    in [currenthz, client2hz, l]
fn [] = [0]

averageVal :: Int -> [Int] -> Int
averageVal l xs = sum xs `div` l

printStreamDelay :: Stream [Int] -> IO ()
printStreamDelay (e@(E id t v):r) = do
    now <- getCurrentTime
    let newe = mapTimeDelay delay e where delay = diffUTCTime now t
    appendFile "serial-log.txt" (show newe ++ "\n")
    print newe
    printStreamDelay r
printStreamDelay (e:r) = do
    print e
    printStreamDelay r
printStreamDelay [] = return ()

mapTimeDelay :: NominalDiffTime -> Event [Int] -> Event ([Int], Float)
mapTimeDelay delay (E id t v) = E id t newv
    where newv = (v, roundN 3 (toRational delay))

roundN :: Int -> Rational -> Float
roundN n f = fromInteger (round $ f * (10^n)) / (10.0^^n)
