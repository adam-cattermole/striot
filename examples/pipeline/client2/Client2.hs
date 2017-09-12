--import Network
--import Control.Concurrent
import System.IO
import Striot.FunctionalProcessing
import Striot.FunctionalIoTtypes
import Striot.Nodes
import Network

-- import WhiskRest.WhiskConnect
-- import Control.Concurrent
-- import Control.Concurrent.STM

-- import Data.String.Conversions (cs)
-- import Data.Text
-- import Data.List

listenPort =  9002 :: PortNumber
connectPort = 9001 :: PortNumber
connectHost = "haskellserver" :: HostName

main :: IO ()
main = nodeLinkWhisk listenPort connectHost connectPort
    -- nodeSink streamGraph1 printStream listenPort

-- streamGraph1 :: Stream String -> Stream [String]
-- streamGraph1 s = streamWindow (chop 1) $ streamMap (\st-> "Incoming Message at Server: " ++ st) s
--
-- printStream:: Show alpha => Stream alpha -> IO ()
-- printStream (h:t) = do
--     print h
--     printStream t


-- invokeAddToChan :: TChan String -> Stream String -> IO ()
-- invokeAddToChan chan (V id   v:r) = do
--     invId <- invokeAction (cs v)
--     atomically $ writeTChan chan (cs invId)
--     print v
--     invokeAddToChan chan r





-- Data arrives through link
-- Data shipped to whisk
-- Data retrieved from whisk
-- Data forwarded to next node
