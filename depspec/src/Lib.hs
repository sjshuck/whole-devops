{-# LANGUAGE TemplateHaskellQuotes #-}

module Lib where

import Data.Yaml
import Language.Haskell.TH

mkAppPatterns :: String -> DecsQ
mkAppPatterns filename = do
    names <- runIO $ decodeFileThrow filename

    let mkCon name = normalC (mkName $ "AppPattern" ++ name) []
    dec <- dataD
        (return [])
        (mkName "AppPattern")
        []
        Nothing
        (map mkCon names)
        [derivClause Nothing [
            [t| Eq |],
            [t| Ord |],
            [t| Show |]]]
    return [dec]
