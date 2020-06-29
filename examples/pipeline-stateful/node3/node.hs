-- node3
import Striot.FunctionalIoTtypes
import Striot.FunctionalProcessing
import Striot.Nodes
import Control.Concurrent
import System.IO


sink1 :: Show a => Stream a -> IO ()
sink1 s = do
    hdl <- openFile  "output.txt" WriteMode
    hSetBuffering hdl NoBuffering
    mapM_ (hPutStrLn hdl . show) s


sink2 :: Show a => Stream a -> IO ()
sink2 = mapM_ print

streamGraphFn :: Stream Int -> Stream String
streamGraphFn n1 = let
    n2 = (\s -> streamMap (\st->"Incoming Message at Server: " ++ show st) s) n1
    -- n3 = (\s -> streamWindow (chop 2) s) n2
    in n2


main :: IO ()
main = nodeSink (defaultSink "9001") streamGraphFn sink2


