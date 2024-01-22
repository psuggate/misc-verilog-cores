{-# LANGUAGE DeriveGeneric     #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell   #-}

module Lib
  ( UsbState (..)
  , BulkState (..)
  , CtrlState (..)
  , PhyState (..)
  , UsbToken (..)
  , Entry (..)
  , usbEndpt
  , usbToken
  , usbState
  , crcError
  , transact
  , usbSof
  , blkState
  , ctlState
  , phyState

  , dump
  , toNibble
  , parseTelemetry
  )
where

import           Control.Lens        (makeLenses, (^.))
import           Data.Bits           ((.&.))
import qualified Data.Text.Lazy      as T
import           Data.Vector.Unboxed (Vector, (!))
import qualified Data.Vector.Unboxed as Vec
import           Relude
import           Text.Printf


data UsbState
  = UsbIdle
  | UsbCtrl
  | UsbBulk
  | UsbDump
  deriving (Eq, Ord, Bounded, Enum, Generic, Read, Show)

data BulkState
  = BulkIdle
  | BulkDataInTx
  | BulkDataInZDP
  | BulkDataInAck
  | BulkDataOutRx
  | BulkDataOutErr
  | BulkDataOutAck
  | BulkDataOutNak
  | BulkDone
  deriving (Eq, Ord, Bounded, Enum, Generic, Read, Show)

data CtrlState
  = CtrlSetupRx
  | CtrlSetupAck
  | CtrlDataOutRx
  | CtrlDataOutAck
  | CtrlDataOutTok
  | CtrlDataInTx
  | CtrlDataInAck
  | CtrlDataInTok
  | CtrlStatusRx
  | CtrlStatusTx
  | CtrlStatusAck
  | CtrlDone
  deriving (Eq, Ord, Bounded, Enum, Generic, Read, Show)

data PhyState
  = PhyPowerOn
  | PhyFSStart
  | PhyFSLSSE0
  | PhyWaitSE0
  | PhyChirpK0
  | PhyChirpK1
  | PhyChirpK2
  | PhyChirpKJ
  | PhyHSStart
  | PhyIdle
  | PhySuspend
  | PhyReset
  deriving (Eq, Ord, Bounded, Enum, Generic, Read, Show)

data UsbToken
  = Reserved
  | UsbOUT
  | UsbACK
  | UsbDATA0
  | UsbPING
  | UsbSOF
  | UsbNYET
  | UsbDATA2
  | UsbSPLIT
  | UsbIN
  | UsbNAK
  | UsbDATA1
  | UsbERR
  | UsbSETUP
  | UsbSTALL
  | UsbMDATA
  deriving (Eq, Ord, Bounded, Enum, Generic, Read, Show)

data Entry = Entry { _usbEndpt :: !Word8
                   , _usbToken :: !UsbToken
                   , _usbState :: !UsbState
                   , _crcError :: !Bool
                   , _transact :: !Word8
                   , _usbSof   :: !Bool
                   , _blkState :: !BulkState
                   , _ctlState :: !CtrlState
                   , _phyState :: !PhyState
                   } deriving (Eq, Generic, Show)

makeLenses ''Entry


toTokens :: Text -> Vector Char
toTokens  = Vec.fromList . filter (\x -> x /= '-') . toString

toNibble :: Integral i => Char -> i
toNibble c
  | c >= '0' && c <= '9' = fromIntegral $ ord c - ord '0'
  | c >= 'A' && c <= 'F' = fromIntegral $ ord c - ord 'A'
  | c >= 'a' && c <= 'f' = fromIntegral $ ord c - ord 'A'
  | otherwise = error . fromString $ printf "Can not nibblise: %c\n" c


-- * Parser
------------------------------------------------------------------------------
decodeTelemetry :: Vector Char -> Entry
decodeTelemetry ts = Entry ept tok usb crc trn sof blk ctl phy
  where
    ept = toNibble (ts!5)
    tok = toEnum $ toNibble (ts!6)
    usb = toEnum $ toNibble (ts!7)
    crc = toNibble (ts!0) >= 8
    trn = toNibble (ts!0) .&. 7
    sof = toNibble (ts!1) >= 8
    blk = toEnum $ toNibble (ts!1) .&. 7
    ctl = toEnum $ toNibble (ts!2)
    phy = toEnum $ toNibble (ts!3)

parseTelemetry :: FilePath -> IO [Entry]
parseTelemetry fp = do
  concat . map (map (decodeTelemetry . toTokens) . words) . lines . fromString <$> readFile fp


-- * Display
------------------------------------------------------------------------------
dump :: [Entry] -> IO ()
dump []     = pure ()
dump (x:xs) = step 0 x xs

entry :: Int -> Entry -> String
entry i (Entry f t u e x s b c p) = printf "%03d => PHY: %s" i (T.drop 3 $ show p)

step :: Int -> Entry -> [Entry] -> IO ()
step i x    []  = putStrLn (entry i x)
step i x (y:ys)
  | x^.phyState /= y^.phyState = putStrLn (entry i x) >> step (i+1) y ys
  | otherwise = step (i+1) y ys
