import System.IO
import Data.List
import Striot.FunctionalProcessing
import Striot.FunctionalIoTtypes
import Striot.Nodes
import Network.Socket

listenPort = "9001" :: ServiceName

main :: IO ()
main = nodeSink streamGraphid printStream listenPort

streamGraph1 :: Stream String -> Stream [String]
streamGraph1 s = streamWindow (chop 2) $ streamMap (\st-> "Incoming Message at Server: " ++ st) s

streamGraphid :: Stream String -> Stream String
streamGraphid = streamMap Prelude.id

printStream:: Show alpha => Stream alpha -> IO ()
printStream = mapM_ print
