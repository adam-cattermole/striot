import Striot.FunctionalProcessing
import Striot.FunctionalIoTtypes
import Striot.Nodes
import Network.Socket (HostName, ServiceName)


listenPort =  "9001" :: ServiceName
connectPort = "9001" :: ServiceName
connectHost = "server" :: HostName


main :: IO ()
main = nodeLink streamGraphid listenPort connectHost connectPort


streamGraphid :: Stream String -> Stream String
streamGraphid = Prelude.id


streamGraph1 :: Stream Int -> Stream [Int]
streamGraph1 = streamWindowAggregate (slidingTime 1) fn

-- We have to define a function where we give the types, otherwise Haskell
-- will be unsure if it can serialise or deserialise using Show and Read
-- Just use id function so we do not transform the data

fn :: [Int] -> [Int]
fn ys@(x:xs) = [x, length ys]

-- Data arrives from previous node
-- Data shipped to whisk
-- Data retrieved from whisk
-- Data forwarded to next node
