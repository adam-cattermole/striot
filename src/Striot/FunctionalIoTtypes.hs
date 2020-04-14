{-# LANGUAGE DeriveGeneric #-}
module Striot.FunctionalIoTtypes where
import           Data.Store
import           Data.Time    (UTCTime)
import           GHC.Generics (Generic)

data Event alpha = Event { eventId :: Int
                         , manage  :: Maybe Int
                         , time    :: Maybe Timestamp
                         , value   :: Maybe alpha
                         }
     deriving (Eq, Ord, Show, Read, Generic)

type Timestamp       = UTCTime
type Stream alpha    = [Event alpha]

instance (Store alpha) => Store (Event alpha)

dataEvent :: Event alpha -> Bool
dataEvent (Event i m t (Just v)) = True
dataEvent (Event i m t Nothing ) = False

timedEvent :: Event alpha -> Bool
timedEvent (Event i m (Just t) v) = True
timedEvent (Event i m Nothing  v) = False

manageEvent :: Event alpha -> Bool
manageEvent (Event i (Just m) t v) = True
manageEvent (Event i Nothing  t v) = False
