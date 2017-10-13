import System.IO
import Data.List

import Striot.FunctionalProcessing
import Striot.FunctionalIoTtypes
import Striot.Nodes
import Network

import Data.Time (getCurrentTime, diffUTCTime, NominalDiffTime)

listenPort = 9001 :: PortNumber

main :: IO ()
main = nodeSink streamGraphid printStream listenPort

streamGraphid :: Stream (Int, Int) -> Stream (Int, Int)
streamGraphid = Prelude.id

streamGraph1 :: Stream (Int, Int) -> Stream (Int, Int, Int)
streamGraph1= streamWindowAggregate (chopTime 1) fn

fn :: [(Int, Int)] -> (Int, Int, Int)
fn e@((x,y):xs) =
    let l = fromIntegral (length e)
    in  (x, truncate l, round (fromIntegral (sum (map snd e))/l))
fn [] = (0, 0, 0)

printStream :: Show alpha => Stream alpha -> IO ()
printStream (h:t) = do
    print h
    printStream t
