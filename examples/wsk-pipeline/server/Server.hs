import Striot.FunctionalProcessing
import Striot.FunctionalIoTtypes
import Striot.Nodes
import Network.Socket (ServiceName)
import Data.Time (getCurrentTime, diffUTCTime, NominalDiffTime)


listenPort = "9001" :: ServiceName


main :: IO ()
main = do
    writeFile "sw-log.txt" ""
    nodeSink streamGraphid printStream listenPort


streamGraphid :: Stream String -> Stream String
streamGraphid = Prelude.id


averageVal :: Int -> [Int] -> Int
averageVal l xs = sum xs `div` l


printStreamDelay :: Stream (Int,Int) -> IO ()
printStreamDelay (e@(E id t v):r) = do
    now <- getCurrentTime
    let newe = mapTimeDelay delay e where delay = diffUTCTime now t
    appendFile "sw-log.txt" (show newe ++ "\n")
    print newe
    printStreamDelay r
printStreamDelay (e:r) = do
    print e
    printStreamDelay r
printStreamDelay [] = return ()


printStream :: Stream String -> IO ()
printStream stream = mapM_ print stream


mapTimeDelay :: NominalDiffTime -> Event (Int, Int) -> Event (Int, Int, Float)
mapTimeDelay delay (E id t v) = E id t newv
    where newv = (fst v, snd v, roundN 15 (toRational delay))


roundN :: Int -> Rational -> Float
roundN n f = fromInteger (round $ f * (10^n)) / (10.0^^n)
