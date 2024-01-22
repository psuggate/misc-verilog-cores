{-# LANGUAGE DeriveGeneric     #-}
{-# LANGUAGE LambdaCase        #-}
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
import           Data.Char           (toUpper)
import qualified Data.List           as L
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
  deriving (Eq, Ord, Generic, Read, Show)

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
  = CtrlDone
  | CtrlSetupRx
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

data Transact
  = TrnErrNone
  | TrnErrBlkI
  | TrnErrBlkO
  | TrnTokRecv
  | TrnUsbRecv
  | TrnUsbSent
  | TrnUsbDump
  | TrnTimeout
  deriving (Eq, Ord, Bounded, Enum, Generic, Read, Show)

data Entry = Entry { _usbReset :: !Bool
                   , _usbEndpt :: !Word8
                   , _usbToken :: !UsbToken
                   , _usbState :: !UsbState
                   , _crcError :: !Bool
                   , _transact :: !Transact
                   , _usbSof   :: !Bool
                   , _blkState :: !BulkState
                   , _ctlState :: !CtrlState
                   , _phyState :: !PhyState
                   } deriving (Eq, Generic, Show)

makeLenses ''Entry


-- * Some Instances
------------------------------------------------------------------------------
instance Bounded UsbState where
  minBound = UsbIdle
  maxBound = UsbDump

instance Enum UsbState where
  toEnum = \case
    1 -> UsbIdle
    2 -> UsbCtrl
    4 -> UsbBulk
    8 -> UsbDump
    i -> error . fromString $ printf "Invalid 'UsbState': %d" i
  fromEnum = \case
    UsbIdle -> 1
    UsbCtrl -> 2
    UsbBulk -> 4
    UsbDump -> 8


-- * Helpers
------------------------------------------------------------------------------
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
decodeTelemetry ts = Entry rst ept tok usb crc trn sof blk ctl phy
  where
    rst = toNibble (ts!4) /= 0
    ept = toNibble (ts!5)
    tok = toEnum $ toNibble (ts!6)
    usb = toEnum $ toNibble (ts!7)
    crc = toNibble (ts!0) >= 8
    trn = toEnum $ toNibble (ts!0) .&. 7
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
dump (x:xs) = putStrLn (entry 0 x) >> step 1 x xs

entry :: Int -> Entry -> String
entry i (Entry r f t u e x s b c p) = printf "%04d => %sPHY: %s" i rst' phy'
  where
    rst' = if r then "[RST] " else replicate 6 ' '
    phy' = T.drop 3 $ show p

reset :: Entry -> Entry -> String
reset x y
  | y^.usbReset = "[RST] "
  | x^.usbReset = " ---  "
  | otherwise   = replicate 6 ' '

xphy :: Entry -> Entry -> String
xphy x y
  | x^.phyState /= y^.phyState = printf "PHY: %s" phy'
  | otherwise = printf "     %s" phy'
  where
    phy' = pad 8 . L.drop 3 . show $ y^.phyState

xusb :: Entry -> Entry -> String
xusb x y
  | x^.usbState == y^.usbState = replicate 5 ' '
  | otherwise = printf "%s " . map toUpper . L.drop 3 . show $ y^.usbState

xctl :: Entry -> Entry -> String
xctl x y
  | x^.ctlState /= y^.ctlState = printf "CTL: %s " ctl'
  | otherwise = printf "     %s " ctl'
  where
    ctl' = pad 10 . L.drop 4 . show $ y^.ctlState

xsof :: Entry -> Entry -> String
xsof x y
  | x^.usbSof /= y^.usbSof = "SoF "
  | otherwise = replicate 4 ' '

xcrc :: Entry -> Entry -> String
xcrc x y
  | y^.crcError = "CRC "
  | x^.crcError = "--- "
  | otherwise = replicate 4 ' '

endpt :: Entry -> Entry -> String
endpt x y
  | x^.usbEndpt /= y^.usbEndpt = printf "EP: 0x%1x " (y^.usbEndpt)
  | otherwise = replicate 7 ' '

usbrx :: Entry -> Entry -> String
usbrx x y
  | y^.transact == TrnErrNone  = replicate 14 ' '
  | x^.usbToken /= y^.usbToken
  , x^.transact /= y^.transact = tok ++ trn
  | x^.transact /= y^.transact = replicate 6 ' ' ++ trn
  | x^.usbToken /= y^.usbToken = tok ++ replicate 8 ' '
  | otherwise = replicate 14 ' '
  where
    trn = printf "%s " . T.drop 3 . show $ y^.transact
    tok = case y^.usbToken of
      Reserved -> "---   "
      UsbOUT   -> "OUT   "
      UsbACK   -> "ACK   "
      UsbDATA0 -> "DATA0 "
      UsbPING  -> "PING  "
      UsbSOF   -> "SOF   "
      UsbNYET  -> "NYET  "
      UsbDATA2 -> "DATA2 "
      UsbSPLIT -> "SPLIT "
      UsbIN    -> "IN    "
      UsbNAK   -> "NAK   "
      UsbDATA1 -> "DATA1 "
      UsbERR   -> "ERR   "
      UsbSETUP -> "SETUP "
      UsbSTALL -> "STALL "
      UsbMDATA -> "MDATA "

pad :: Int -> String -> String
pad n xs
  | m < n = xs ++ replicate (n - m) ' '
  | otherwise = xs
  where
    m = length xs

step :: Int -> Entry -> [Entry] -> IO ()
step i x    []  = putStrLn (entry i x)
step i x (y:ys) = putStrLn s >> step (i+1) y ys
  where
    fs = [reset, xphy, xusb, xctl, xcrc, xsof, usbrx, endpt]
    ts = concatMap (\f -> f x y) fs
    s  = printf "%04d => %s" i ts
