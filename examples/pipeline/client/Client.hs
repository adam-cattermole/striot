import Control.Concurrent
import Control.Concurrent.STM
import System.IO
import Striot.FunctionalProcessing
import Striot.FunctionalIoTtypes
import Striot.Nodes
import Network

import System.Exit

portNum  = 9002::PortNumber
hostName = "haskellclient2"::HostName

main :: IO ()
main = do
         let start = 1
             rate  = 20000
             swrate = 100
         indexVar <- newTVarIO start
         messageVar <- newTVarIO start
         threadDelay (1 * 1000 * 1000)
         _ <- forkIO $ generator2 indexVar messageVar rate rates
         nodeSource (src1 indexVar messageVar) streamGraph2 hostName portNum -- processes source before sending it to another node

streamGraph2 :: Stream (Int, Int) -> Stream (Int, Int)
streamGraph2 = Prelude.id

src1 :: TVar Int -> TVar Int -> IO (Int, Int)
src1 = waitDelay

rates :: [Int]
rates = [1,5,10,20,50,100,200,500,1000,10000]

swrates :: [Int]
swrates =
    let f   = 1       -- freq
        fs  = 800     -- sample rate
        hzmiddle = 250
    in  [ceiling((sin (2*pi*f*(x/fs))+1)*hzmiddle) |  x <- [0..fs]]

message :: Int
message = 1

hz :: Int -> Int
hz x
    | x == 0 = f 1
    | otherwise = f x
    where f = round . (1000000 /) . fromIntegral

waitDelay :: TVar Int -> TVar Int -> IO (Int, Int)
waitDelay indexVar messageVar = do
    i <- atomically $ readTVar indexVar
    case i of
        (-1) -> exitSuccess
        _ -> do
            threadDelay (hz i)
            m <- atomically $ readTVar messageVar
            atomically $ writeTVar messageVar (m+1)
            return (m, i)

generator :: TVar Int -> Int -> Int -> IO b
generator indexVar rate index = do
    let newi = min (index+1) (subtract 1 $ length rates)
    threadDelay (rate*1000000)
    -- read off last after we write to update the current queue head
    atomically $ writeTVar indexVar newi
    generator indexVar rate newi

generator2 :: (Num a) => TVar a -> TVar a -> Int -> [a] -> IO ()
generator2 indexVar messageVar rate [] = do
    print "Gen at max"
    atomically $ writeTVar indexVar (-1)
    atomically $ writeTVar messageVar (-1)
    exitSuccess
generator2 indexVar messageVar rate (x:xs) = do
    gen' indexVar messageVar rate x
    generator2 indexVar messageVar rate xs

gen' :: (Num a) => TVar a -> TVar a -> Int -> a -> IO ()
gen' indexVar messageVar rate x = do
    atomically $ writeTVar indexVar x
    atomically $ writeTVar messageVar 1
    threadDelay (rate*1000)
