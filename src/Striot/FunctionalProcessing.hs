{-# OPTIONS_GHC -F -pgmF htfpp #-}
{-# LANGUAGE FlexibleContexts #-}

module Striot.FunctionalProcessing ( streamFilter
                                   , streamMap
                                   , streamWindow
                                   , streamWindowM
                                   , streamWindowAggregate
                                   , streamMerge
                                   , streamJoin
                                   , streamJoinE
                                   , streamJoinW
                                   , streamFilterAcc
                                   , streamFilterAccM
                                   , streamScan
                                   , streamScanM
                                   , streamExpand
                                   , WindowMaker
                                   , WindowAggregator
                                   , sliding
                                   , slidingM
                                   , slidingTime
                                   , slidingTimeM
                                   , chop
                                   , chopM
                                   , chopTime
                                   , chopTimeM
                                   , complete
                                   , EventFilter
                                   , EventMap
                                   , JoinFilter
                                   , JoinMap

                                   , htf_thisModulesTests) where

import           Control.Lens
import           Control.Monad.State
import           Control.Monad.Trans.Control
import           Data.Time                   (NominalDiffTime, UTCTime,
                                              addUTCTime, diffUTCTime)
import           Data.Maybe                  (isNothing)
import           Striot.FunctionalIoTtypes
import           Striot.Nodes.Types
import           System.IO.Unsafe            (unsafeInterleaveIO)
import           Test.Framework

-- Define the Basic IoT Stream Functions

-- Filter a Stream ...
type EventFilter alpha = alpha -> Bool                                 -- the type of the user-supplied function

streamFilter :: EventFilter alpha -> Stream alpha -> Stream alpha      -- if the value in the event meets the criteria then it can pass through
-- streamfilter ff (e@(Event _ (Just m) _ _):xs) = [e]
streamFilter ff s =
    let (f,r) = span (\(Event i m t v) -> isNothing m) s
        stream = f++[head r]
    in  filter (\(Event i m t v) -> maybe True ff v)      -- allow timestamped events to pass through for time-based windowing
                        stream

type EventMap alpha beta = alpha -> beta
-- Map a Stream ...
streamMap :: EventMap alpha beta -> Stream alpha -> Stream beta
-- streamMap fm (e@(Event i (Just m) t _):xs) = [Event i (Just m) t Nothing]
streamMap fm s =
    let (f,r) = span (\(Event i m t v) -> isNothing m) s
        stream = f++[head r]
    in  map (\(Event i m t v) -> case v of
                                            Just val -> Event i m t (Just (fm val))
                                            Nothing  -> Event i m t Nothing       ) -- allow timestamped events to pass through for time-based windowing
                    stream

-- create and aggregate windows
type WindowMaker alpha = Stream alpha -> [Stream alpha]
type WindowMakerM m alpha = Stream alpha -> m [Stream alpha]
type WindowAggregator alpha beta = [alpha] -> beta

streamWindow :: WindowMaker alpha -> Stream alpha -> Stream [alpha]
streamWindow fwm s = mapWindowId (fwm s)
           where getVals :: Stream alpha -> [alpha]
                 getVals s' = map (\(Event _ _ _ (Just val))->val) $ filter dataEvent s'
                 mapWindowId :: [Stream alpha] -> Stream [alpha]
                 mapWindowId [] = []
                 mapWindowId (x:xs) =
                     case x of
                         Event i m t _ : _ -> Event i m         t       (Just (getVals x)) : mapWindowId xs
                         []                -> Event 0 Nothing   Nothing (Just [])          : mapWindowId xs
                        --  Event i (Just m) t _ : _ -> []
                        --  Event i Nothing  t _ : _ -> Event i Nothing   t       (Just (getVals x)) : mapWindowId xs

streamWindowM :: (MonadState s m,
                 HasStriotState s (Stream alpha),
                 MonadIO m,
                 MonadBaseControl IO m)
              => WindowMakerM m alpha -> Stream alpha -> m (Stream [alpha])
streamWindowM fwm s = mapWindowId <$> fwm s
            where getVals :: Stream alpha -> [alpha]
                  getVals s' = map (\(Event _ _ _ (Just val))->val) $ filter dataEvent s'
                  -- set timestamp to id of last event in the window
                  mapWindowId :: [Stream alpha] -> Stream [alpha]
                  mapWindowId [] = []
                  mapWindowId (x:xs) =
                      case x of
                        []                           -> Event 0 Nothing   Nothing (Just [])          : mapWindowId xs
                        e@(Event i (Just m) t Nothing) : _ -> Event i (Just m) t Nothing : mapWindowId xs
                        _                            -> let l = last x
                                                        in  Event (eventId l) (manage l) (time l) (Just (getVals x)) : mapWindowId xs

-- chopM :: (MonadState s m,
--           HasStriotState s [alpha],
--           MonadIO m,
--           MonadBaseControl IO m)
--       => Int -> WindowMakerM m alpha
-- chopM wLength s = chop' wLength s
--      where  chop' wLength [] = []
--             chop' wLength s  = do
--                 let w@(xs,xs') = span (not . manageEvent) $ take wLength s
--                 case xs' of
--                     [] -> unsafeInterleaveLiftedIO $ (w :) <$> chop' wLength (drop wLength s)
--                     _  ->
                            --  in  w:(chop' wLength r)

chopM :: (MonadState s m,
          HasStriotState s (Stream alpha),
          MonadIO m,
          MonadBaseControl IO m)
      => Int -> WindowMakerM m alpha
chopM wLength s = do
    state <- get
    case state ^. accValue of
        Nothing -> chopM' wLength [] s
        Just v  -> let pw = map (\x -> x { eventId = 0 }) v
                   in  chopM' wLength pw s

chopM' :: (MonadState s m,
          HasStriotState s (Stream alpha),
          MonadIO m,
          MonadBaseControl IO m)
      => Int -> Stream alpha -> WindowMakerM m alpha
chopM' wLength pw s = do
    (w, xs, check) <- takeM wLength pw s
    if check then
        return [w]
    else unsafeInterleaveLiftedIO
           $ (w :)
          <$> chopM' wLength [] xs


slidingM :: (MonadState s m,
            HasStriotState s (Stream alpha),
            MonadIO m,
            MonadBaseControl IO m)
         => Int -> WindowMakerM m alpha
slidingM wLength s = do
    state <- get
    case state ^. accValue of
        Nothing -> slidingM' wLength [] s
        Just v  -> let pw = map (\x -> x { eventId = 0 }) v
                   in  slidingM' wLength pw s


slidingM' :: (MonadState s m,
            HasStriotState s (Stream alpha),
            MonadIO m,
            MonadBaseControl IO m)
         => Int -> Stream alpha -> WindowMakerM m alpha
slidingM' wLength [] s@(_:xs) = do
    (w, _, check) <- takeM wLength [] s
    if check then
        return [w]
    else unsafeInterleaveLiftedIO
           $ (w :)
          <$> slidingM' wLength [] xs
slidingM' wLength pw s = do
    (w, _, check) <- takeM wLength pw s
    if check then
        return [w]
    else unsafeInterleaveLiftedIO
           $ (w :)
          <$> slidingM' wLength (init pw) s
-- init = reverse . tail . reverse

chopTimeM :: (MonadState s m,
              HasStriotState s (Stream alpha),
              MonadIO m,
              MonadBaseControl IO m)
           => Int -> WindowMakerM m alpha
chopTimeM tLength s = do
    state <- get
    case state ^. accValue of
        Nothing -> chopTimeM' tLength [] s
        Just v  -> let pw = map (\x -> x { eventId = 0 }) v
                   in  chopTimeM' tLength pw s


chopTimeM' :: (MonadState s m,
              HasStriotState s (Stream alpha),
              MonadIO m,
              MonadBaseControl IO m)
           => Int -> Stream alpha -> WindowMakerM m alpha
chopTimeM' tLength pw s = do
    (w, xs, check) <- takeTimeM tLength pw s
    if check then
        return [w]
    else unsafeInterleaveLiftedIO
           $ (w :)
          <$> chopTimeM' tLength [] xs


slidingTimeM :: (MonadState s m,
                HasStriotState s (Stream alpha),
                MonadIO m,
                MonadBaseControl IO m)
             => Int -> WindowMakerM m alpha
slidingTimeM tLength s = do
    state <- get
    case state ^. accValue of
        Nothing -> slidingTimeM' tLength [] s
        Just v  -> let pw = map (\x -> x { eventId = 0 }) v
                   in  slidingTimeM' tLength pw s


slidingTimeM' :: (MonadState s m,
                 HasStriotState s (Stream alpha),
                 MonadIO m,
                 MonadBaseControl IO m)
              => Int -> Stream alpha -> WindowMakerM m alpha
slidingTimeM' tLength [] s@(_:xs) = do
    (w, _, check) <- takeTimeM tLength [] s
    if check then
        return [w]
    else unsafeInterleaveLiftedIO
           $ (w :)
          <$> slidingTimeM' tLength [] xs
slidingTimeM' tLength pw s = do
    (w, _, check) <- takeTimeM tLength pw s
    if check then
        return [w]
    else unsafeInterleaveLiftedIO
           $ (w :)
          <$> slidingTimeM' tLength (init pw) s
-- init = reverse . tail . reverse


takeM :: (MonadState s m,
          HasStriotState s (Stream alpha),
          MonadIO m,
          MonadBaseControl IO m)
       => Int -> Stream alpha -> Stream alpha -> m (Stream alpha, Stream alpha, Bool)
takeM n w = takeM' (n - length w) w

takeM' :: (MonadState s m,
          HasStriotState s (Stream alpha),
          MonadIO m,
          MonadBaseControl IO m)
       => Int -> Stream alpha -> Stream alpha -> m (Stream alpha, Stream alpha, Bool)
takeM' n w s | n <= 0 = return (reverse w, s, False)
takeM' _ w []         = return (reverse w, [], False)
takeM' _ w (Event i (Just m) t v : r)
    =  accKey   .= head m
    >> accValue .= Just w
    >> return ([Event i (Just m) Nothing Nothing], [], True)
takeM' n w (e@(Event i Nothing t (Just v)) : r)
    = takeM' (n-1) (e:w) r
takeM' n w (Event i Nothing t Nothing : r)
    = takeM' n w r


takeTimeM :: (MonadState s m,
             HasStriotState s (Stream alpha),
             MonadIO m,
             MonadBaseControl IO m)
          => Int -> Stream alpha -> Stream alpha -> m (Stream alpha, Stream alpha, Bool)
takeTimeM tLength [] s@(Event _ _ (Just tStart) _ : _)
    = let tEnd = addUTCTime (milliToTimeDiff tLength) tStart
      in  takeTimeM' tEnd [] s
takeTimeM tLength w s
    = let Just tStart = time . last $ w
          tEnd = addUTCTime (milliToTimeDiff tLength) tStart
      in  takeTimeM' tEnd w s

takeTimeM' :: (MonadState s m,
              HasStriotState s (Stream alpha),
              MonadIO m,
              MonadBaseControl IO m)
           => UTCTime -> Stream alpha -> Stream alpha -> m (Stream alpha, Stream alpha, Bool)
takeTimeM' _ w [] = return (reverse w, [], False)
takeTimeM' _ w (Event i (Just m) t v : r)
    =  accKey   .= head m
    >> accValue .= Just w
    >> return ([Event i (Just m) Nothing Nothing], [], True)
takeTimeM' ets w s@(e@(Event i Nothing (Just ts) v) : r)
    | ts < ets  = takeTimeM' ets (e:w) r
    | otherwise = return (reverse w, s, False)


-- a useful function building on streamWindow and streamMap
streamWindowAggregate :: WindowMaker alpha -> WindowAggregator alpha beta -> Stream alpha -> Stream beta
streamWindowAggregate fwm fwa s = streamMap fwa $ streamWindow fwm s

-- some examples of window functions
sliding :: Int -> WindowMaker alpha
sliding wLength s = sliding' wLength $ filter dataEvent s
           where sliding':: Int -> WindowMaker alpha
                 sliding' wLength []      = []
                 sliding' wLength s@(h:t) = take wLength s : sliding' wLength t

slidingTime:: Int -> WindowMaker alpha -- the first argument is the window length in milliseconds
slidingTime tLength s = slidingTime' (milliToTimeDiff tLength) $ filter timedEvent s
                        where slidingTime':: NominalDiffTime -> Stream alpha -> [Stream alpha]
                              slidingTime' tLen []                        = []
                              slidingTime' tLen s@(Event _ _ (Just t) _:xs) = takeTime (addUTCTime tLen t) s : slidingTime' tLen xs

takeTime:: UTCTime -> Stream alpha -> Stream alpha
takeTime endTime []                                        = []
takeTime endTime (e@(Event _ _ (Just t) _):xs) | t < endTime = e : takeTime endTime xs
                                               | otherwise   = []

milliToTimeDiff :: Int -> NominalDiffTime
milliToTimeDiff x = toEnum (x * 10 ^ 9)

chop :: Int -> WindowMaker alpha
chop wLength s = chop' wLength $ filter dataEvent s
     where chop' wLength [] = []
           chop' wLength s  = w:chop' wLength r where (w,r) = splitAt wLength s

chopTime :: Int -> WindowMaker alpha -- N.B. discards events without a timestamp
chopTime _       []                         = []
chopTime tLength s@((Event _ _ (Just t) _):_) = chopTime' (milliToTimeDiff tLength) t $ filter timedEvent s
    where chopTime' :: NominalDiffTime -> UTCTime -> WindowMaker alpha -- the first argument is in milliseconds
          chopTime' _    _      []    = []
          chopTime' tLen tStart s     = let endTime           = addUTCTime tLen tStart
                                            (fstBuffer, rest) = timeTake endTime s
                                        in  fstBuffer : chopTime' tLen endTime rest

timeTake :: UTCTime -> Stream alpha -> (Stream alpha, Stream alpha)
timeTake endTime = span (\(Event _ _ (Just t) _) -> t < endTime)

complete :: WindowMaker alpha
complete s = [s]

-- Merge a set of streams that are of the same type. Preserve time ordering
streamMerge:: [Stream alpha]-> Stream alpha
streamMerge []     = []
streamMerge [x] = x
streamMerge (x:xs) = merge' x (streamMerge xs)
    where merge':: Stream alpha -> Stream alpha -> Stream alpha
          merge' xs                               []                                           = xs
          merge' []                               ys                                           = ys
          merge' s1@(e1@(Event _ _ (Just t1) _):xs) s2@(e2@(Event _ _ (Just t2) _):ys) | t1 < t2   = e1: merge' s2 xs
                                                                                   | otherwise = e2: merge' ys s1
          merge' (e1:xs)                          s2                                           = e1: merge' s2 xs  -- arbitrary ordering if 1 or 2 of the events aren't timed
                                                                                                                   -- swap order of streams so as to interleave

-- Join 2 streams by combining elements
streamJoin :: Stream alpha -> Stream beta -> Stream (alpha,beta)
streamJoin []                               []                               = []
streamJoin _                                []                               = []
streamJoin []                               _                                = []
streamJoin    ((Event i1  m1  t1 (Just v1)):r1)    ((Event _ _ _ (Just v2)):r2) = Event i1 m1 t1 (Just(v1,v2)):streamJoin r1 r2
streamJoin    ((Event _   _   _  Nothing  ):r1) s2@((Event _ _ _ (Just v2)):_ ) = streamJoin r1 s2
streamJoin s1@((Event _   _   _  (Just v1)):_ )    ((Event _ _ _ Nothing  ):r2) = streamJoin s1 r2
streamJoin    ((Event _   _   _  Nothing  ):r1)    ((Event _ _ _ Nothing  ):r2) = streamJoin r1 r2

-- Join 2 streams by combining windows - some useful functions that build on streamJoin
type JoinFilter alpha beta        = alpha -> beta -> Bool
type JoinMap    alpha beta gamma  = alpha -> beta -> gamma

streamJoinE :: WindowMaker alpha ->
               WindowMaker beta ->
               JoinFilter alpha beta ->
               JoinMap alpha beta gamma ->
               Stream alpha ->
               Stream beta  ->
               Stream gamma
streamJoinE fwm1 fwm2 fwj fwm s1 s2 = streamExpand $ streamMap (cartesianJoin fwj fwm) $ streamJoin (streamWindow fwm1 s1) (streamWindow fwm2 s2)
    where cartesianJoin :: JoinFilter alpha beta -> JoinMap alpha beta gamma -> ([alpha],[beta]) -> [gamma]
          cartesianJoin jf jm (w1,w2) = map (uncurry jm) $ filter (uncurry jf) $ cartesianProduct w1 w2

          cartesianProduct:: [alpha] -> [beta] -> [(alpha,beta)]
          cartesianProduct s1 s2 = [(a,b)|a<-s1,b<-s2]

streamJoinW :: WindowMaker alpha ->
               WindowMaker beta  ->
              ([alpha] -> [beta] -> gamma)      -> Stream alpha -> Stream beta  -> Stream gamma
streamJoinW fwm1 fwm2 fwj s1 s2 = streamMap (uncurry fwj) $ streamJoin (streamWindow fwm1 s1) (streamWindow fwm2 s2)

-- Stream Filter with accumulating parameter
streamFilterAcc:: (beta -> alpha -> beta) -> beta -> (alpha -> beta -> Bool) -> Stream alpha -> Stream alpha
streamFilterAcc accfn acc ff []                         = []
streamFilterAcc accfn acc ff (e@(Event _ _ _ (Just v)):r) | ff v acc  = e:streamFilterAcc accfn (accfn acc v) ff r
                                                        | otherwise =    streamFilterAcc accfn (accfn acc v) ff r
streamFilterAcc accfn acc ff (e@(Event _ _ _ Nothing ):r)             = e:streamFilterAcc accfn acc           ff r -- allow events without data to pass through

-- Stream map with accumulating parameter
streamScan:: (beta -> alpha -> beta) -> beta -> Stream alpha -> Stream beta
streamScan _  _   []                       = []
streamScan mf acc (Event i m t (Just v):r) = Event i m t (Just newacc):streamScan mf newacc r where newacc = mf acc v
streamScan mf acc (Event i m t Nothing :r) = Event i m t Nothing      :streamScan mf acc    r -- allow events without data to pass through

instance Arbitrary a => Arbitrary (Event a) where
    arbitrary = Event 0 Nothing Nothing . Just <$> arbitrary

prop_streamScan_samelength :: Stream Int -> Bool
prop_streamScan_samelength s = length s == length (streamScan (\_ x-> x) 0 s)

-- Map a Stream to a set of events
streamExpand :: Stream [alpha] -> Stream alpha
streamExpand = concatMap eventExpand
      where eventExpand :: Event [alpha] -> [Event alpha]
            eventExpand (Event i m t (Just v)) = map (Event i m t . Just) v
            eventExpand (Event i m t Nothing ) = [Event i m t Nothing]


--- Monadic versions of our stateful streaming operators ---

streamScanM :: (MonadState s m,
                HasStriotState s beta,
                MonadIO m,
                MonadBaseControl IO m)
            => (beta -> alpha -> beta)
            -> beta
            -> Stream alpha
            -> m (Stream beta)
streamScanM mf acc s = do
    state <- get
    case state ^. accValue of
        Nothing -> streamScanM' mf acc s
        Just v  -> streamScanM' mf v   s

streamScanM' :: (MonadState s m,
                 HasStriotState s beta,
                 MonadIO m,
                 MonadBaseControl IO m)
             => (beta -> alpha -> beta)
             -> beta
             -> Stream alpha
             -> m (Stream beta)
streamScanM' _  _ [] = return []
streamScanM' mf acc (Event i (Just m) t v : r)
    =  accKey   .= head m
    >> accValue .= Just acc
    >> return [Event i (Just m) Nothing Nothing]
streamScanM' mf acc (Event i m t (Just v) : r)
    = unsafeInterleaveLiftedIO
    $ (Event i m t (Just newacc) :)
   <$> streamScanM' mf newacc r
        where newacc = mf acc v
streamScanM' mf acc (Event i m t Nothing : r)
    = unsafeInterleaveLiftedIO
    $ (Event i m t Nothing :)
   <$> streamScanM' mf acc r


streamFilterAccM :: (MonadState s m,
                     HasStriotState s beta,
                     MonadIO m,
                     MonadBaseControl IO m)
                 => (beta -> alpha -> beta)
                 -> beta
                 -> (alpha -> beta -> Bool)
                 -> Stream alpha
                 -> m (Stream alpha)
streamFilterAccM accfn acc ff s = do
    state <- get
    case state ^. accValue of
        Nothing -> streamFilterAccM' accfn acc ff s
        Just v  -> streamFilterAccM' accfn v   ff s


streamFilterAccM' :: (MonadState s m,
                      HasStriotState s beta,
                      MonadIO m,
                      MonadBaseControl IO m)
                  => (beta -> alpha -> beta)
                  -> beta
                  -> (alpha -> beta -> Bool)
                  -> Stream alpha
                  -> m (Stream alpha)
streamFilterAccM' _ _ _ [] = return []
streamFilterAccM' _ acc _ (Event i (Just m) _ _ : r)
    =  accKey   .= head m
    >> accValue .= Just acc
    >> return [Event i (Just m) Nothing Nothing]
streamFilterAccM' accfn acc ff (e@(Event _ _ _ (Just v)):r)
    | ff v acc  = unsafeInterleaveLiftedIO
                $ (e:)
               <$> streamFilterAccM' accfn (accfn acc v) ff r
    | otherwise = unsafeInterleaveLiftedIO
                $ streamFilterAccM' accfn (accfn acc v) ff r
streamFilterAccM' accfn acc ff (e@(Event _ _ _ Nothing):r)
      = (e:) <$> streamFilterAccM' accfn acc ff r


-- This functions allows us to lift our operation into the IO monad
-- to keep the semantics of lazily evaluated IO
unsafeInterleaveLiftedIO :: MonadBaseControl IO m => m a -> m a
unsafeInterleaveLiftedIO = liftBaseOp_ unsafeInterleaveIO


--streamSource :: Stream alpha -> Stream alpha
--streamSource ss = ss

-- streamSink:: (Stream alpha -> beta) -> Stream alpha -> beta
-- streamSink ssink s = ssink s

--- Tests ------
--t1 :: Int -> Int -> Stream alpha -> (Bool,Stream alpha,Stream alpha)
--t1 tLen sLen s = splitAtValuedEvents tLen (take sLen s)

s1 :: Stream Int
s1 = [Event 0 Nothing (Just (addUTCTime i (read "2013-01-01 00:00:00"))) (Just 999)|i<-[0..]]

s2 :: Stream Int
s2 = [Event 0 Nothing (Just (addUTCTime i (read "2013-01-01 00:00:00"))) Nothing |i<-[0..]]

s3 :: Stream Int
s3 = streamMerge [s1,s2]

s4 :: Stream Int
s4 = [Event 0 Nothing Nothing (Just i)|i<-[0..]]

s5 :: Stream Int
s5 = streamMerge [s2,s4]

s6 :: Stream Int
s6 = [Event 0 Nothing Nothing (Just i)|i<-[100..]]

ex1 i = streamWindow (sliding i) s3

ex2 i = streamWindow (chop i) s3

ex3 i = streamWindow (sliding i) s4

ex4 i = streamWindow (chop i) s4

ex5 = streamFilter (> 1000) s1

ex6 = streamFilter (< 1000) s1

sample :: Int -> Stream alpha -> Stream alpha
sample n = streamFilterAcc (\acc h -> if acc==0 then n else acc-1) n (\h acc -> acc==0)

ex7 = streamJoin s1 s4
ex8 = streamJoinW (chop 2) (chop 2) (\a b->sum a+sum b) s4 s6
ex9 = streamJoinE (chop 2) (chop 2) (<) (+) s4 s6
