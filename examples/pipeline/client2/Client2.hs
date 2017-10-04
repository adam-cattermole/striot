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
main = nodeLinkWhisk fn listenPort connectHost connectPort

-- We have to define a function where we give the types, otherwise Haskell
-- will be unsure if it can serialise or deserialise using Show and Read
-- Just use id function so we do not transform the data

fn :: Floating alpha => Stream [alpha] -> Stream [alpha]
fn = Prelude.id


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
