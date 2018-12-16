{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}

module Axel.Haskell.File where

import Prelude hiding (putStr, putStrLn)

import Axel.AST (Statement(SModuleDeclaration), ToHaskell(toHaskell))
import Axel.Eff.Console (putStrLn)
import qualified Axel.Eff.Console as Effs (Console)
import qualified Axel.Eff.FileSystem as Effs (FileSystem)
import qualified Axel.Eff.FileSystem as FS (readFile, removeFile, writeFile)
import Axel.Eff.Process (StreamSpecification(InheritStreams))
import qualified Axel.Eff.Process as Effs (Process)
import Axel.Eff.Resource (readResource)
import qualified Axel.Eff.Resource as Effs (Resource)
import qualified Axel.Eff.Resource as Res (astDefinition)
import Axel.Error (Error)
import Axel.Haskell.Prettify (prettifyHaskell)
import Axel.Haskell.Stack (interpretFile)
import Axel.Macros (ModuleInfo, exhaustivelyExpandMacros)
import Axel.Normalize (normalizeStatement)
import Axel.Parse
  ( Expression(Symbol)
  , parseSource
  , programToTopLevelExpressions
  )
import Axel.Utils.Recursion (Recursive(bottomUpFmap))

import Control.Lens.Operators ((<&>), (%~))
import Control.Lens.Tuple (_2)
import Control.Monad (forM, unless, void)
import Control.Monad.Freer (Eff, Members)
import Control.Monad.Freer.Error (runError)
import qualified Control.Monad.Freer.Error as Effs (Error)
import Control.Monad.Freer.State (gets, modify)
import qualified Control.Monad.Freer.State as Effs (State)

import qualified Data.Map as Map (adjust, fromList, lookup)
import Data.Maybe (catMaybes, fromMaybe, listToMaybe)
import Data.Semigroup ((<>))
import qualified Data.Text as T (isSuffixOf, pack)

import System.FilePath (stripExtension, takeFileName)

convertList :: Expression -> Expression
convertList =
  bottomUpFmap $ \case
    Symbol "List" -> Symbol "[]"
    x -> x

convertUnit :: Expression -> Expression
convertUnit =
  bottomUpFmap $ \case
    Symbol "Unit" -> Symbol "()"
    Symbol "unit" -> Symbol "()"
    x -> x

readModuleInfo ::
     (Members '[ Effs.Error Error, Effs.FileSystem] effs)
  => [FilePath]
  -> Eff effs ModuleInfo
readModuleInfo axelFiles = do
  modules <-
    forM axelFiles $ \filePath -> do
      source <- FS.readFile filePath
      exprs <- programToTopLevelExpressions <$> parseSource source
      case listToMaybe exprs of
        Just expr ->
          runError @Error (normalizeStatement expr) <&> \case
            Right (SModuleDeclaration moduleId) ->
              Just (filePath, (moduleId, False))
            _ -> Nothing
        Nothing -> pure Nothing
  pure $ Map.fromList $ catMaybes modules

transpileSource ::
     (Members '[ Effs.Console, Effs.Error Error, Effs.FileSystem, Effs.Process, Effs.Resource, Effs.State ModuleInfo] effs)
  => String
  -> Eff effs String
transpileSource source =
  prettifyHaskell . toHaskell <$>
  (parseSource source >>=
   exhaustivelyExpandMacros transpileFile' . convertList . convertUnit >>=
   normalizeStatement)

axelPathToHaskellPath :: FilePath -> FilePath
axelPathToHaskellPath axelPath =
  let basePath =
        if ".axel" `T.isSuffixOf` T.pack axelPath
          then fromMaybe axelPath $ stripExtension ".axel" axelPath
          else axelPath
   in basePath <> ".hs"

transpileFile ::
     (Members '[ Effs.Console, Effs.Error Error, Effs.FileSystem, Effs.Process, Effs.Resource, Effs.State ModuleInfo] effs)
  => FilePath
  -> FilePath
  -> Eff effs ()
transpileFile path newPath = do
  fileContents <- FS.readFile path
  newContents <- transpileSource fileContents
  putStrLn $ "Writing " <> newPath <> "..."
  FS.writeFile newPath newContents
  modify @ModuleInfo $ Map.adjust (_2 %~ not) newPath

-- | Transpile a file in place.
transpileFile' ::
     (Members '[ Effs.Console, Effs.Error Error, Effs.FileSystem, Effs.Process, Effs.Resource, Effs.State ModuleInfo] effs)
  => FilePath
  -> Eff effs FilePath
transpileFile' path = do
  moduleInfo <- gets @ModuleInfo $ Map.lookup path
  let alreadyCompiled =
        case moduleInfo of
          Just (_, isCompiled) -> isCompiled
          Nothing -> False
  let newPath = axelPathToHaskellPath path
  unless alreadyCompiled $ transpileFile path newPath
  pure newPath

evalFile ::
     (Members '[ Effs.Console, Effs.Error Error, Effs.FileSystem, Effs.Process, Effs.Resource] effs)
  => FilePath
  -> Eff effs ()
evalFile path = do
  putStrLn ("Building " <> takeFileName path <> "...")
  let astDefinitionPath = "AutogeneratedAxelAST.hs"
  readResource Res.astDefinition >>= FS.writeFile astDefinitionPath
  let newPath = axelPathToHaskellPath path
  putStrLn ("Running " <> takeFileName path <> "...")
  void $ interpretFile @'InheritStreams newPath
  FS.removeFile astDefinitionPath
