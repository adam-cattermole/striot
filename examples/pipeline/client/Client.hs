import Control.Concurrent
import Control.Concurrent.STM
import System.IO
import Striot.FunctionalProcessing
import Striot.FunctionalIoTtypes
import Striot.Nodes
import Network

portNum  = 9001::PortNumber
hostName = "haskellclient2"::HostName
-- hostName = "haskellserver" :: HostName

main :: IO ()
main = do
         -- let start = 1
             -- rate  = 20000
             -- swrate = 100
         -- indexVar <- newTVarIO start
         -- messageVar <- newTVarIO start
         threadDelay (1 * 1000 * 1000)
         -- _ <- forkIO $ generator2 indexVar messageVar rate rates
         -- nodeSource (src1 indexVar messageVar) streamGraph2 hostName portNum -- processes source before sending it to another node
         nodeSource src2 streamGraph1 hostName portNum

src2:: IO String
src2 = clockStreamNamed "TCPKaliMsgTS-0005620b16f909f3." 1000

clockStreamNamed:: String -> Int -> IO String -- returns the (next) payload to be added into an event and sent to a server
clockStreamNamed message period = do -- period is in ms
    threadDelay (period*1000)
    return message

streamGraph1 :: Stream String -> Stream String
streamGraph1 = Prelude.id

streamGraph2 :: Stream (Int, Int) -> Stream (Int, Int)
streamGraph2 = Prelude.id

src1 :: TChan Int -> IO Int
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

waitDelay :: TChan Int -> IO Int
waitDelay indexChan = do
    i <- atomically (peekTChan indexChan)
    case i of
        (-1) -> exitSuccess
        _ -> do
            threadDelay (hz i)
            return i

generator :: TVar Int -> Int -> Int -> IO b
generator indexVar rate index = do
    let newi = min (index+1) (subtract 1 $ length rates)
    threadDelay (rate*1000000)
    -- read off last after we write to update the current queue head
    atomically $ writeTVar indexVar newi
    generator indexVar rate newi

generator2 :: (Num a) => TChan a -> Int -> [a] -> IO ()
generator2 indexChan rate [] = do
    print "Gen at max"
    atomically $ writeTChan indexChan (-1)
    atomically $ tryReadTChan indexChan
    exitSuccess
generator2 indexChan rate (x:xs) = do
    gen' indexChan rate x
    generator2 indexChan rate xs

gen' :: TChan a -> Int -> a -> IO ()
gen' indexChan rate x = do
    atomically $ writeTChan indexChan x
    atomically $ tryReadTChan indexChan
    threadDelay (rate*1000)
