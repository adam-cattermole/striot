module Striot.Nodes.Kafka.Types
( KafkaRecord
, blankRecord
) where

import           Data.Text as T (empty)
import           Kafka.Consumer                           as KC
import qualified Data.ByteString                 as B (ByteString)

type KafkaRecord = (Int, ConsumerRecord (Maybe B.ByteString) (Maybe B.ByteString))

blankRecord :: Int -> KafkaRecord
blankRecord i = (i, ConsumerRecord
                    (TopicName T.empty)
                    (PartitionId (-1))
                    (Offset (-1))
                    NoTimestamp
                    Nothing
                    Nothing)

