{-# LANGUAGE DeriveGeneric #-}
module TaxiUtil ( tripParse
                , tripToJourney
                , inRangeQ1
                , Trip (..)
                , Journey (..)
                , Cell (..)
                , Dollars
                , topk
                , journeyChanges
                , inRangeQ2
                , emptyTaxisPerCell
                , cellProfit
                , profitability
                , changes ) where

import Striot.FunctionalIoTtypes
import Striot.FunctionalProcessing
import Striot.Nodes
import Control.Concurrent
import Data.Time (UTCTime)
import System.IO
import Data.List
import Data.List.Split
import qualified Data.Map as Map
import GHC.Generics (Generic)
import Data.Aeson

-- Define the types and data structures needed by the application
type MD5Sum  = String
type Dollars = Float

type Degrees = Float
data Location = Location         -- taxi's latitude and longitude
                { lat  :: Degrees
                , long :: Degrees
                } deriving (Eq, Ord, Show, Generic)

instance FromJSON Location
instance ToJSON Location where
   toEncoding = genericToEncoding defaultOptions

data PaymentType = Card | Cash
     deriving (Eq, Ord, Show, Generic)

instance FromJSON PaymentType
instance ToJSON PaymentType where
   toEncoding = genericToEncoding defaultOptions

type Medallion  = MD5Sum

data Trip = Trip
   { medallion        :: Medallion
   , hackLicense      :: MD5Sum
   , pickupDatetime   :: UTCTime
   , dropoffDatetime  :: UTCTime
   , tripTimeInSecs   :: Int
   , tripDistance     :: Float
   , pickup           :: Location
   , dropoff          :: Location
   , paymentType      :: PaymentType
   , fareAmount       :: Dollars
   , surcharge        :: Dollars
   , mtaTax           :: Dollars
   , tipAmount        :: Dollars
   , tollsAmount      :: Dollars
   , totalAmount      :: Dollars
   } deriving (Eq, Ord, Show, Generic)

instance FromJSON Trip
instance ToJSON Trip where
 toEncoding = genericToEncoding defaultOptions

data Cell = Cell  -- the Cell in which the Taxi is located
   { clat  :: Int
   , clong :: Int}
   deriving (Eq, Ord, Generic)

instance FromJSON Cell
instance FromJSONKey Cell
instance ToJSONKey Cell
instance ToJSON Cell where
   toEncoding = genericToEncoding defaultOptions

instance Show Cell where
    show c = show (clat c) ++ "." ++ show (clong c)

data Journey  = Journey -- a taxi journey from one cell to another
   { start       :: Cell
   , end         :: Cell
   , pickupTime  :: UTCTime
   , dropoffTime :: UTCTime}
   deriving (Eq, Ord, Generic)

instance FromJSON Journey
instance ToJSON Journey where
  toEncoding = genericToEncoding defaultOptions

instance Show Journey where
    show j = show (start j) ++ "->" ++ show (end j)


---- QUERY 1 ----

tripParse :: Event String -> Event Trip
tripParse e@(Event eid _ (Just v)) =
    let t = stringsToTrip $ Data.List.Split.splitOn "," v
    in  e { eventId = eid
          , time    = Just $ dropoffDatetime t
          , value   = Just t }


-- turns a line from the input file (already split into a list of fields) into a Trip datastructure
stringsToTrip :: [String] -> Trip
stringsToTrip [med, hack, pickupDateTime, dropoffDateTime, trip_time, trip_dist, pickup_long, pickup_lat,
               dropoff_long, dropoff_lat, pay_type, fare, sur, mta, tip, tolls, total] =
   Trip med hack (read pickupDateTime) (read dropoffDateTime) (read trip_time) (read trip_dist)
                 (Location (read pickup_lat)  (read pickup_long))
                 (Location (read dropoff_lat) (read dropoff_long))
                 (if pay_type == "CRD" then Card else Cash)
                 (read fare) (read sur) (read mta) (read tip) (read tolls) (read total)
stringsToTrip s = error ("error in input: " ++ intercalate "," s)


-- checks if a cell is in the range specified in the problem definition
inRangeQ1 :: Cell -> Bool
inRangeQ1 = inRange 300 300

inRange :: Int -> Int -> Cell -> Bool
inRange maxLat maxLong cell = clat cell <= maxLat && clong cell <= maxLong && clat cell >= 1 && clong cell >= 1

toCellQ1 :: Location -> Cell
toCellQ1 = toCell cell11Origin (Location 0.004491556 0.005986)

-- Query 1: Frequent Routes
cellLatLength :: Float
cellLatLength   = 0.004491556 -- the cell sizes for query 1
cellLongLength :: Float
cellLongLength  = 0.005986
-- The coordinate 41.474937, -74.913585 marks the center of the first cell
cell1p1CentreLat :: Float
cell1p1CentreLat  =  41.474937
cell1p1CentreLong :: Float
cell1p1CentreLong = -74.913585

-- calculate the origin of the grid system
cell11Origin :: Location
cell11Origin = Location (cell1p1CentreLat + (cellLatLength / 2)) (cell1p1CentreLong - (cellLongLength / 2))

-- tranforms a location into a cell given the origin of the grid and the cell side length
toCell :: Location -> Location -> Location -> Cell
toCell cellOrigin cellSideLength l = Cell (floor ((lat cellOrigin - lat  l) / lat  cellSideLength) + 1)
                                          (floor ((long l - long cell11Origin) / long cellSideLength) + 1)

tripToJourney :: Trip -> Journey
tripToJourney t = Journey{start=toCellQ1 (pickup t), end=toCellQ1 (dropoff t), pickupTime=pickupDatetime t, dropoffTime=dropoffDatetime t}

-- produces an ordered list of the i most frequent elements from list l ---------------------------------
topk :: (Num freq, Ord freq, Ord alpha) => Int -> [alpha] -> [(alpha, freq)]
topk i l = take i
         $ sortBy (\(_, v1) (_, v2) -> compare v2 v1)
         $ Map.toList
         $ foldr (\k -> Map.insertWith (+) k 1) Map.empty l

journeyChanges :: Stream ((UTCTime, UTCTime),[(Journey, Int)]) -> Stream ((UTCTime, UTCTime),[(Journey, Int)])
journeyChanges (Event _ _ (Just val):r) = streamFilterAcc (\acc h -> if snd h == snd acc then acc else h) val (\h acc -> snd h /= snd acc) r


---- QUERY 2 ----

inRangeQ2 :: Cell -> Bool
inRangeQ2 = inRange 600 600

pickupHistory :: [(Trip, Journey)] -> Map.Map Cell [Trip]
pickupHistory = foldr (\t -> Map.insertWith (++) (start $ snd t) [fst t]) Map.empty

newestPickup :: [(Trip, Journey)] -> Map.Map (Cell, Medallion) UTCTime
newestPickup = foldr (\t -> Map.insertWith (\newt existing -> if newt > existing then newt else existing)
                         (start $ snd t, medallion $ fst t) (pickupDatetime $ fst t)) Map.empty

oldestDropoff :: [(Trip, Journey)] -> Map.Map (Cell, Medallion) UTCTime
oldestDropoff = foldr (\t -> Map.insertWith (\newt existing -> if newt < existing then newt else existing)
                          (end $ snd t, medallion $ fst t) (dropoffDatetime $ fst t)) Map.empty

--"The profit that originates from an area is computed by calculating the median fare + tip for trips that started in the area and ended within the last 15 minutes."
profit :: [Trip] -> Dollars
profit ts = median $ map (\t -> fareAmount t + tipAmount t) ts

median :: Ord alpha => [alpha] -> alpha
median l =  let sl = sort l in
                sl !! floor (fromIntegral (length sl) / (2.0 :: Double))

cellProfit :: [(Trip, Journey)] -> Map.Map Cell Dollars
cellProfit tjs = Map.map profit $ pickupHistory tjs

--"The number of empty taxis in an area is the sum of taxis that had a drop-off location in that area less than 30 minutes ago and had no following pickup yet."

taxisDroppedOffandNotPickedUp :: Map.Map (Cell, Medallion) UTCTime -> [(Trip, Journey)] -> [Cell]
taxisDroppedOffandNotPickedUp np ts = map (\(_, j) -> start j)
                                    $ filter (\(t, j) -> (Map.notMember (start j, medallion t) np ||
                                                         (np Map.! (start j, medallion t) < dropoffDatetime t))) ts

emptyTaxisPerCell ::  [(Trip, Journey)] -> Map.Map Cell Int
emptyTaxisPerCell ts = foldl (\m c -> Map.insertWith (+) c 1 m) Map.empty (taxisDroppedOffandNotPickedUp (newestPickup ts) ts)

allCells :: Int -> Int -> [Cell]
allCells latMax longMax = [Cell lat' long' | lat' <- [1..latMax], long' <- [1..longMax]]

initCellMap :: Int -> Int -> a -> Map.Map Cell a
initCellMap latMax longMax val = Map.fromList (zip (allCells latMax longMax) (repeat val))

profitability :: Map.Map Cell Int -> Map.Map Cell Dollars -> Map.Map Cell Dollars
profitability emptyTaxis cellProf = foldl (\m c -> Map.insert c (Map.findWithDefault 0 c cellProf / fromIntegral (Map.findWithDefault 0 c emptyTaxis)) m) Map.empty (Map.keys emptyTaxis)

--- removes consecutive repeated values from a stream, leaving only the changes
changes :: Eq alpha => Stream alpha -> Stream alpha
changes (e@(Event _ _ (Just val)):r) = e : streamFilterAcc (\_ h -> h) val (/=) r
