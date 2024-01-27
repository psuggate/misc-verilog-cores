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
  , ctlCycle
  , usbLS

  , dump
  , toNibble
  , parseTelemetry
  )
where

import           Control.Lens           (makeLenses, (%~), (.~), (^.))
import           Data.Bits              (shiftR, (.&.))
import qualified Data.Text.Lazy         as T
import qualified Data.Text.Lazy.Builder as B
import           Data.Vector.Unboxed    (Vector, (!))
import qualified Data.Vector.Unboxed    as Vec
import           GHC.Exts               (inline)
import           Relude
import           Text.Printf


data UsbState
  = UsbIdle
  | UsbCtrl
  | UsbBulk
  | UsbDump
  deriving (Eq, Ord, Generic, Read, Show, Bounded, Enum)

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
  | PhyResume
  | PhyReset
  deriving (Eq, Ord, Bounded, Enum, Generic, Read, Show)

data UsbToken
  = Reserved -- 0b0000
  | UsbOUT -- 0b0001
  | UsbACK -- 0b0010
  | UsbDATA0 -- 0b0011
  | UsbPING -- 0b0100
  | UsbSOF -- 0b0101
  | UsbNYET
  | UsbDATA2
  | UsbSPLIT
  | UsbIN
  | UsbNAK
  | UsbDATA1
  | UsbERR
  | UsbSETUP -- 0b1101
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

data LineState = LS0 | LSJ | LSK | LS1
  deriving (Eq, Ord, Bounded, Enum, Generic, Read, Show)

data Entry = Entry { _usbReset :: !Bool -- Reset to (downstream) USB cores
                   , _usbEndpt :: !Word8
                   , _usbToken :: !UsbToken
                   , _usbState :: !UsbState
                   , _crcError :: !Bool
                   , _transact :: !Transact
                   , _usbSof   :: !Bool
                   , _blkState :: !BulkState
                   , _ctlState :: !CtrlState
                   , _phyState :: !PhyState
                   , _ctlCycle :: !Bool
                   , _ctlError :: !Bool
                   , _usbLS    :: !LineState
                   } deriving (Eq, Generic, Show)

makeLenses ''Entry


-- * Helpers
------------------------------------------------------------------------------
toTokens :: Text -> Vector Char
toTokens  = Vec.fromList . filter (\x -> x /= '-') . toString

toNib8 :: Char -> Word8
toNib8  = inline toNibble

toNibble :: Integral i => Char -> i
toNibble c
  | c >= '0' && c <= '9' = fromIntegral $ ord c - ord '0'
  | c >= 'A' && c <= 'F' = fromIntegral $ ord c - ord 'A' + 10
  | c >= 'a' && c <= 'f' = fromIntegral $ ord c - ord 'A' + 10
  | otherwise = error . fromString $ printf "Can not nibblise: %c\n" c


-- * Parser
------------------------------------------------------------------------------
decodeTelemetry :: Vector Char -> Entry
decodeTelemetry ts = Entry rst ept tok usb crc trn sof blk ctl phy cyc cer uls
  where
    rst = toNib8 (ts!4) .&. 1 /= 0
    ept = toNib8 (ts!5)
    tok = toEnum $ toNibble (ts!6)
    usb = toEnum $ toNibble (ts!7) .&. 3
    crc = toNib8 (ts!0) >= 8
    trn = toEnum $ toNibble (ts!0) .&. 7
    sof = toNib8 (ts!1) >= 8
    blk = toEnum $ toNibble (ts!1) .&. 7
    ctl = toEnum $ toNibble (ts!2)
    phy = toEnum $ toNibble (ts!3)
    cyc = toNib8 (ts!4) .&. 2 /= 0
    cer = toNib8 (ts!7) .&. 8 /= 0
    uls = toEnum . flip shiftR 2 $ toNibble (ts!4) .&. 6

parseTelemetry :: FilePath -> IO [Entry]
parseTelemetry fp = do
  concat . map (map (decodeTelemetry . toTokens) . words) . lines . fromString <$> readFile fp


-- * Display
------------------------------------------------------------------------------
dump :: [Entry] -> IO ()
dump []     = pure ()
dump (x:xs) = putStrLn (entry 0 x) >> step 1 x xs

entry :: Int -> Entry -> String
entry i q = printf "%04d => %s" i str'
  where
    rst' = reset (q & usbReset .~ True) q
    usb' = xusb  (q & usbState .~ UsbDump) q
    trn' = usbrx (q & transact .~ TrnErrBlkI & usbToken .~ Reserved) q
    ctl' = xctl  (q & ctlState .~ CtrlDone) q
    crc' = xcrc  (q & crcError %~ not) q
    sof' = xsof  (q & usbSof   .~ False) q
    fun' = endpt (q & usbEndpt %~ succ) q
    phy' = xphy  (q & phyState %~ yuck) q
    str' = B.toLazyText $ mconcat [usb', trn', fun', ctl', crc', sof', rst', phy']
    yuck = toEnum . flip mod 13 . succ  . fromEnum

step :: Int -> Entry -> [Entry] -> IO ()
step _ _    []  = pure ()
step i _   [y]  = putStrLn (entry i y)
step i x (y:ys) = putStrLn s >> step (i+1) y ys
  where
    fs = [xusb, usbrx, endpt, xctl, xcrc, xsof, reset, xphy]
    ts = B.toLazyText . mconcat $ (\f -> f x y) <$> fs
    s  | y^.phyState == PhyPowerOn = entry i y
       | otherwise                 = printf "%04d => %s" i ts


-- ** Builders
------------------------------------------------------------------------------
reset :: Entry -> Entry -> B.Builder
reset x y
  | y^.usbReset = B.fromText "[RST] "
  | x^.usbReset = B.fromText " ---  "
  | otherwise   = B.fromText "      "

xphy :: Entry -> Entry -> B.Builder
xphy x y = B.fromLazyText pre' <> uls' <> B.singleton ':' <> B.fromLazyText phy'
  where
    pre' = if x^.phyState /= y^.phyState then " PHY:" else "     "
    uls' = B.fromLazyText . T.drop 2 . show $ y^.usbLS
    phy' = T.take 8 $ T.drop 3 (show (y^.phyState)) <> "       "

xusb :: Entry -> Entry -> B.Builder
xusb x y = B.fromLazyText yus <> B.singleton ' '
  where
    yuc = T.toUpper . T.drop 3 . show $ y^.usbState
    yus = if x^.usbState == y^.usbState then "    " else yuc

xctl :: Entry -> Entry -> B.Builder
xctl x y = B.fromText pre' <> B.fromLazyText ctl' <> B.fromText cyc'
  where
    ctl' = T.take 11 $ T.drop 4 (show (y^.ctlState)) <> "          "
    pre' = if x^.ctlState /= y^.ctlState then " CTL:" else "     "
    cyc' = case (y^.ctlError, y^.ctlCycle) of
      (True , True ) -> "EC "
      (True , False) -> "E  "
      (False, True ) -> " C "
      _              -> "   "

xsof :: Entry -> Entry -> B.Builder
xsof x y
  | x^.usbSof /= y^.usbSof = B.fromText "SoF "
  | otherwise              = B.fromText "    "

xcrc :: Entry -> Entry -> B.Builder
xcrc x y
  | y^.crcError = B.fromText "CRC "
  | x^.crcError = B.fromText "--- "
  | otherwise   = B.fromText "    "

endpt :: Entry -> Entry -> B.Builder
endpt x y
  | y^.transact == TrnErrNone
  , x^.usbToken == y^.usbToken
  , x^.usbEndpt == yue = B.fromText "    "
  | otherwise = B.fromText "EP" <> yuc <> B.singleton ' '
  where
    yue = y^.usbEndpt
    yuc = B.singleton . chr . fromIntegral . (yue +) $ if yue > 9 then 55 else 48

usbrx :: Entry -> Entry -> B.Builder
usbrx x y = B.fromText tok <> B.fromLazyText trn <> B.singleton ' '
  where
    ytt = y^.transact
    trn
      | ytt == TrnErrNone  = "       "
      | x^.transact == ytt = "       "
      | otherwise          = T.drop 3 . show $ y^.transact
    yut = y^.usbToken
    -- tok = case yut of
    tok
      | x^.usbToken /= yut = case yut of
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
      | otherwise = "      "
