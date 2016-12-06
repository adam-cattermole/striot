--import Network
import Control.Concurrent
import System.IO
import FunctionalProcessing
import FunctionalIoTtypes
import Nodes

main :: IO ()
main = do
         threadDelay (1 * 1000 * 1000)
         nodeSource src1 streamGraph2 -- processes source before sending it to another node
         
streamGraph2 :: Stream String -> Stream String
streamGraph2 s = streamMap (\st-> st++st) s

src1:: IO String
src1 = clockStreamNamed "Hello from Simon!" 1000

clockStreamNamed:: String -> Int -> IO String -- returns the (next) payload to be added into an event and sent to a server
clockStreamNamed message period = do -- period is in ms                                   
                                    threadDelay (period*1000)
                                    return message   
