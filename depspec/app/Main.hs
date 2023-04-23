{-# LANGUAGE TemplateHaskell #-}

module Main (
    main,
    AppPattern(..))
where

import Lib

mkAppPatterns "app-patterns.yaml"

main :: IO ()
main = print AppPatternCloudSQL
