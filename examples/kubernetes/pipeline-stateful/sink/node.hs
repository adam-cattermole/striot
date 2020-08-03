-- node3
import Striot.FunctionalIoTtypes
import Striot.FunctionalProcessing
import Striot.Nodes
import Control.Concurrent
import System.IO


sink1 :: Show a => Stream a -> IO ()
sink1 s = hSetBuffering stdout NoBuffering >> mapM_ print s


streamGraphFn :: Stream Int -> Stream String
streamGraphFn n1 = let
    n2 = (\s -> streamMap (\st->"Incoming Message at Server: " ++ show st) s) n1
    -- n3 = (\s -> streamWindow (chop 2) s) n2
    in n2


main :: IO ()
main = nodeSink (defaultSink "9001") streamGraphFn sink1