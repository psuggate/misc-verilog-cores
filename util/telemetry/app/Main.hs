{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import           Lib
import           Relude
import           Text.Printf


-- * Main Entry-Point
------------------------------------------------------------------------------
main :: IO ()
main  = do
  getArgs >>= \case
    fp:_ -> dump =<< parseTelemetry fp
    _    -> error "USAGE:\ntelemetry <FILE>"
