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

import           Control.Lens           (makeLenses, (%~), (.~), (^.))
import           Data.Bits              ((.&.))
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

toNib8 :: Char -> Word8
toNib8  = inline toNibble

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
    rst = toNib8 (ts!4) /= 0
    ept = toNib8 (ts!5)
    tok = toEnum $ toNibble (ts!6)
    usb = toEnum $ toNibble (ts!7)
    crc = toNib8 (ts!0) >= 8
    trn = toEnum $ toNibble (ts!0) .&. 7
    sof = toNib8 (ts!1) >= 8
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
entry i q@(Entry _ _ _ _ e _ _ _ _ _) = printf "%04d => %s" i str'
  where
    rst' = reset (q & usbReset .~ True) q
    usb' = xusb  (q & usbState .~ UsbDump) q
    trn' = usbrx (q & transact .~ TrnErrBlkI & usbToken .~ Reserved) q
    ctl' = xctl  (q & ctlState .~ CtrlDone) q
    crc' = xcrc  (q & crcError .~ not e) q
    sof' = xsof  (q & usbSof   .~ False) q
    fun' = endpt (q & usbEndpt %~ succ) q
    phy' = xphy  (q & phyState %~ succ) q
    str' = B.toLazyText $ mconcat [rst', usb', trn', fun', ctl', crc', sof', phy']

step :: Int -> Entry -> [Entry] -> IO ()
step _ _    []  = pure ()
step i _   [y]  = putStrLn (entry i y)
step i x (y:ys) = putStrLn s >> step (i+1) y ys
  where
    fs = [reset, xusb, usbrx, endpt, xctl, xcrc, xsof, xphy]
    ts = B.toLazyText . mconcat $ (\f -> f x y) <$> fs
    s  | y^.phyState == PhyPowerOn = entry i y
       | otherwise                 = printf "%04d => %s" i ts
    -- s  = if y^.phyState == PhyPowerOn then entry i y else printf "%04d => %s" i ts


-- ** Builders
------------------------------------------------------------------------------
reset :: Entry -> Entry -> B.Builder
reset x y
  | y^.usbReset = B.fromText "[RST] "
  | x^.usbReset = B.fromText " ---  "
  | otherwise   = B.fromText "      "

xphy :: Entry -> Entry -> B.Builder
xphy x y = B.fromLazyText pre' <> B.fromLazyText phy'
  where
    pre' = if x^.phyState /= y^.phyState then "PHY: " else "     "
    phy' = T.take 8 $ T.drop 3 (show (y^.phyState)) <> "       "

xusb :: Entry -> Entry -> B.Builder
xusb x y = B.fromLazyText yus <> B.singleton ' '
  where
    yuc = T.toUpper . T.drop 3 . show $ y^.usbState
    yus = if x^.usbState == y^.usbState then "    " else yuc

xctl :: Entry -> Entry -> B.Builder
xctl x y = B.fromText pre' <> B.fromLazyText ctl'
  where
    ctl' = T.take 11 $ T.drop 4 (show (y^.ctlState)) <> "          "
    pre' = if x^.ctlState /= y^.ctlState then "CTL: " else "     "

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
