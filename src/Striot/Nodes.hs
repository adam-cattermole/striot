module Striot.Nodes ( nodeSink
                    , nodeSink2
                    , nodeLink
                    , nodeLink2
                    , nodeSource
                    ) where

import           Control.Concurrent
import           Control.Concurrent.Chan.Unagi as U
import           Control.Concurrent.STM
import           Control.Monad                 (forever, when)
import           Data.List
import           Data.Time                     (getCurrentTime)
import           Network                       (PortID (PortNumber), accept,
                                                connectTo, listenOn)
import           Network.Socket                hiding (accept)
import           Striot.FunctionalIoTtypes
import           System.IO
import           System.IO.Unsafe


--- SINK FUNCTIONS ---

nodeSink :: (Read alpha, Show beta) => (Stream alpha -> Stream beta) -> (Stream beta -> IO ()) -> PortNumber -> IO ()
nodeSink streamGraph iofn portNumInput1 = withSocketsDo $ do
    sock <- listenOn $ PortNumber portNumInput1
    putStrLn "Starting server ..."
    hFlush stdout
    nodeSink' sock streamGraph iofn


nodeSink' :: (Read alpha, Show beta) => Socket -> (Stream alpha -> Stream beta) -> (Stream beta -> IO ()) -> IO ()
nodeSink' sock streamOps iofn = do
    stream <- processSocket sock
    let result = streamOps stream
    iofn result


-- A Sink with 2 inputs
nodeSink2 :: (Read alpha, Read beta, Show gamma) => (Stream alpha -> Stream beta -> Stream gamma) -> (Stream gamma -> IO ()) -> PortNumber -> PortNumber -> IO ()
nodeSink2 streamGraph iofn portNumInput1 portNumInput2= withSocketsDo $ do
    sock1 <- listenOn $ PortNumber portNumInput1
    sock2 <- listenOn $ PortNumber portNumInput2
    putStrLn "Starting server ..."
    hFlush stdout
    nodeSink2' sock1 sock2 streamGraph iofn


nodeSink2' :: (Read alpha, Read beta, Show gamma) => Socket -> Socket -> (Stream alpha -> Stream beta -> Stream gamma) -> (Stream gamma -> IO ()) -> IO ()
nodeSink2' sock1 sock2 streamOps iofn = do
    stream1 <- processSocket sock1
    stream2 <- processSocket sock2
    let result = streamOps stream1 stream2
    iofn result


--- LINK FUNCTIONS ---

nodeLink :: (Read alpha, Show beta) => (Stream alpha -> Stream beta) -> PortNumber -> HostName -> PortNumber -> IO ()
nodeLink streamGraph portNumInput1 hostNameOutput portNumOutput = withSocketsDo $ do
    sockIn <- listenOn $ PortNumber portNumInput1
    putStrLn "Starting link ..."
    hFlush stdout
    nodeLink' sockIn streamGraph hostNameOutput portNumOutput


nodeLink' :: (Read alpha, Show beta) => Socket -> (Stream alpha -> Stream beta) -> HostName -> PortNumber -> IO ()
nodeLink' sock streamOps host port = do
    stream <- processSocket sock
    let result = streamOps stream
    sendStream result host port


-- A Link with 2 inputs
nodeLink2 :: (Read alpha, Read beta, Show gamma) => (Stream alpha -> Stream beta -> Stream gamma) -> PortNumber -> PortNumber -> HostName -> PortNumber -> IO ()
nodeLink2 streamGraph portNumInput1 portNumInput2 hostName portNumOutput = withSocketsDo $ do
    sock1 <- listenOn $ PortNumber portNumInput1
    sock2 <- listenOn $ PortNumber portNumInput2
    putStrLn "Starting link ..."
    hFlush stdout
    nodeLink2' sock1 sock2 streamGraph hostName portNumOutput


nodeLink2' :: (Read alpha, Read beta, Show gamma) => Socket -> Socket -> (Stream alpha -> Stream beta -> Stream gamma) -> HostName -> PortNumber -> IO ()
nodeLink2' sock1 sock2 streamOps host port = do
    stream1 <- processSocket sock1
    stream2 <- processSocket sock2
    let result = streamOps stream1 stream2
    sendStream result host port


--- SOURCE FUNCTIONS ---

nodeSource :: Show beta => IO alpha -> (Stream alpha -> Stream beta) -> HostName -> PortNumber -> IO ()
nodeSource pay streamGraph host port = do
    stream <- readListFromSource pay
    let result = streamGraph stream
    sendStream result host port -- or printStream if it's a completely self contained streamGraph


---- UTILITY FUNCTIONS ----

readListFromSource :: IO alpha -> IO (Stream alpha)
readListFromSource = go 0
  where
    go i pay = System.IO.Unsafe.unsafeInterleaveIO $ do
        x  <- msg i
        xs <- go (i + 1) pay    -- This will overflow eventually
        return (x : xs)
      where
        msg x = do
            now     <- getCurrentTime
            payload <- pay
            return (E x now payload)


{- processSocket is a wrapper function that handles concurrently
accepting and handling connections on the socket and reading all of the strings
into an event Stream -}
processSocket :: Read alpha => Socket -> IO (Stream alpha)
processSocket sock = do
    eventChan <- acceptConnections sock
    readEventsTChan eventChan

processSocket' :: Read alpha => Socket -> IO (Stream alpha)
processSocket' sock = acceptConnections sock >>= readEventsTChan

{- acceptConnections takes a socket as an argument and spins up a new thread to
process the data received. The returned TChan object contains the data from
the socket -}
acceptConnections :: Read alpha => Socket -> IO (U.OutChan (Event alpha))
acceptConnections sock = do
    (inChan, outChan) <- U.newChan
    _         <- forkIO $ connectionHandler sock inChan
    return outChan


{- connectionHandler sits accepting any new connections. Once
accepted, it is converted to a handle and a new thread is forked to handle all
reading. The function then loops to accept a new connection. forkFinally is used
to ensure the thread closes the handle before it exits -}
connectionHandler :: Read alpha => Socket -> U.InChan (Event alpha) -> IO ()
connectionHandler sockIn eventChan = forever $ do
    -- putStrLn "Awaiting new connection"
    (hdl, _, _) <- accept sockIn
    -- hdl       <- socketToHandle sock ReadWriteMode
    -- putStrLn "Forking to process new connection"
    forkFinally   (processHandle hdl eventChan) (\_ -> hClose hdl)


{- processHandle takes a Handle and TChan. All of the events are read through
hGetLines' with the IO deferred lazily. The string list is mapped to a Stream
and passed to writeEventsTChan -}
processHandle :: Read alpha => Handle -> U.InChan (Event alpha) -> IO ()
processHandle handle eventChan = do
    stringStream <- hGetLines' handle
    let eventStream = map read stringStream
    U.writeList2Chan eventChan eventStream


{- writeEventsTChan takes a TChan and Stream of the same type, and recursively
writes the events atomically to the TChan, until an empty list -}
writeEventsTChan :: Read alpha => Stream alpha -> U.InChan (Event alpha) -> IO ()
writeEventsTChan (h:t) eventChan = do
    U.writeChan eventChan h
    writeEventsTChan t eventChan
writeEventsTChan [] _ = return ()


{- readEventsTChan creates a stream of events from reading the next element from
a TChan, but the IO is deferred lazily. Only when the next value of the Stream
is evaluated does the IO computation take place -}
readEventsTChan :: Read alpha => U.OutChan (Event alpha) -> IO (Stream alpha)
readEventsTChan eventChan = System.IO.Unsafe.unsafeInterleaveIO $ do
    x <- U.readChan eventChan
    xs <- readEventsTChan eventChan
    return (x : xs)


readListFromSocket :: Socket -> IO [String]
readListFromSocket sock = do
    (_, stream) <- readListFromSocket' sock
    return stream


readListFromSocket' :: Socket -> IO (Handle, [String])
readListFromSocket' sockIn = do
    (hdl, _, _) <- accept sockIn
    -- hdl       <- socketToHandle sock ReadWriteMode
    -- print "Open input connection"
    stream <- hGetLines' hdl
    return (hdl, stream)


readEventStreamFromSocket :: Read alpha => Socket -> IO (Handle, Stream alpha)
readEventStreamFromSocket sock = do
    (hdl, stringStream) <- readListFromSocket' sock
    let eventStream = map read stringStream
    return (hdl, eventStream)


sendStream :: Show alpha => Stream alpha -> HostName -> PortNumber -> IO ()
sendStream []     _ _ = return ()
sendStream stream host port = withSocketsDo $ do
    handle <- connectTo host (PortNumber port)
    -- print "Open output connection"
    hPutLines'    handle stream


{- hGetLines' creates a list of Strings from a Handle, where the IO computation
is deferred lazily until the values are requested -}
hGetLines' :: Handle -> IO [String]
hGetLines' handle = System.IO.Unsafe.unsafeInterleaveIO $ do
    eof      <- hIsEOF handle
    if not eof
        then do
            x  <- hGetLine handle
            xs <- hGetLines' handle
            -- print x
            return (x : xs)
        else return []


hPutLines' :: Show alpha => Handle -> Stream alpha -> IO ()
hPutLines' handle [] = do
    hClose handle
    -- print "Closed output handle"
    return ()
hPutLines' handle (x:xs) = do
    -- print h
    hPrint     handle x
    hPutLines' handle xs
