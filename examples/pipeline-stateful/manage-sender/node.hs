-- node1
import Striot.FunctionalIoTtypes
import Striot.FunctionalProcessing
import Striot.Nodes
import Striot.Nodes.Types
import System.Envy
import Control.Monad.Reader
import Control.Concurrent
import Control.Lens
import Data.Store


src1 = do
    threadDelay (1000*1000)
    return "Hello from Client!"

streamGraphFn :: Stream String -> Stream String
streamGraphFn = id

sendManage :: (Store alpha, Store beta,
               MonadReader r m,
               HasStriotConfig r,
               MonadIO m)
            => IO alpha
            -> (Stream alpha -> Stream beta)
            -> m ()
sendManage iofn streamOp = do
    c <- ask
    metrics <- liftIO $ startPrometheus (c ^. nodeName)
    let stream = [Event (Just 0) Nothing Nothing]
        result = streamOp stream
    liftIO $ threadDelay (1000*1000*120)
    sendStream metrics result

main :: IO ()
main = do
    conf <- decodeEnv :: IO (Either String StriotConfig)
    case conf of
        Left _  -> print "Could not read from env"
        Right c -> runReaderT (unStriotApp $ sendManage src1 streamGraphFn) c