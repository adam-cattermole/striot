import Control.Concurrent
import Control.Concurrent.STM
import System.IO
import Striot.FunctionalProcessing
import Striot.FunctionalIoTtypes
import Striot.Nodes
import Network

portNum  = 9002::PortNumber
hostName = "haskellclient2"::HostName

main :: IO ()
main = do
         threadDelay (1 * 1000 * 1000)
         indexChan <- newTChanIO
         let start = 1
             rate  = 10000
             swrate = 100
         atomically $ writeTChan indexChan start
         _ <- forkIO $ generator2 indexChan rate rates
         nodeSource (src1 indexChan) streamGraph2 hostName portNum -- processes source before sending it to another node

streamGraph2 :: Stream Int -> Stream Int
streamGraph2 = Prelude.id

src1 :: TChan Int -> IO Int
src1 indexChan = waitDelay indexChan

rates :: [Int]
rates = [1,5,10,20,50,100,200,500,1000,10000]

swrates :: [Int]
swrates =
    let f   = 1       -- freq
        fs  = 800     -- sample rate
        hzmiddle = 250
    in  cycle [ceiling((sin (2*pi*f*(x/fs))+1)*hzmiddle) |  x <- [0..fs]]

message :: Int
message = 1

hz :: Int -> Int
hz x
    | x == 0 = f 1
    | otherwise = f x
    where f = round . (1000000 /) . fromIntegral

waitDelay :: TChan Int -> IO Int
waitDelay indexChan = do
    i <- atomically (peekTChan indexChan)
    threadDelay (hz i)
    return i



generator :: TChan Int -> Int -> Int -> IO b
generator indexChan rate index = do
    let newi = min (index+1) (subtract 1 $ length rates)
    threadDelay (rate*1000000)
    -- read off last after we write to update the current queue head
    atomically $ writeTChan indexChan newi
    atomically $ readTChan indexChan
    generator indexChan rate newi

generator2 :: TChan a -> Int -> [a] -> IO ()
generator2 indexChan rate [] = print "Gen at max"
generator2 indexChan rate (x:xs) = do
    gen' indexChan rate x
    generator2 indexChan rate xs

gen' :: TChan a -> Int -> [a] -> IO ()
gen' indexChan rate x = do
    atomically $ writeTChan indexChan x
    atomically $ tryReadTChan indexChan
    threadDelay (rate*1000)
