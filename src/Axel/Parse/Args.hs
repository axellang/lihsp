module Axel.Parse.Args where
import qualified Prelude as GHCPrelude
import qualified Axel.Parse.AST as AST
import Axel.Prelude
import Control.Applicative((<**>))
import Data.Foldable(asum)
import Data.Semigroup((<>))
import qualified Data.Text as T
import Options.Applicative(Parser,ParserInfo,argument,command,fullDesc,helper,hsubparser,info,metavar,progDesc,str)
data FileCommand = ConvertFile FilePath|RunFile FilePath|FormatFile FilePath
data ProjectCommand = RunProject 
data Command = FileCommand FileCommand|ProjectCommand ProjectCommand|Version 
experimental  = ((<>) "(EXPERIMENTAL) ")
experimental :: ((->) String String)
fileCommandParser  = (hsubparser (mconcat [convertFileCommand,formatFileCommand,runFileCommand])) where {convertFileCommand  = (command "convert" (filePathParser ConvertFile (experimental "Convert a Haskell file to Axel")));runFileCommand  = (command "run" (filePathParser RunFile "Transpile and run an Axel file"));formatFileCommand  = (command "format" (filePathParser FormatFile "Format an Axel file"));filePathParser ctor desc = (info ((<$>) ((.) ctor ((.) FilePath T.pack)) (argument str (metavar "FILE"))) (progDesc desc))}
fileCommandParser :: (Parser FileCommand)
projectCommandParser  = (hsubparser (mconcat [runProjectCommand])) where {runProjectCommand  = (command "run" (info (pure RunProject) (progDesc "Build and run the project")))}
projectCommandParser :: (Parser ProjectCommand)
commandParserInfo  = (let {subparsers = (asum [fileCommand,projectCommand,versionCommand])} in (info ((<**>) subparsers helper) fullDesc)) where {fileCommand  = (hsubparser ((<>) (command "file" (info ((<$>) FileCommand fileCommandParser) (progDesc "Run file-specific commands"))) (metavar "file")));projectCommand  = (hsubparser ((<>) (command "project" (info ((<$>) ProjectCommand projectCommandParser) (progDesc "Run project-wide commands"))) (metavar "project")));versionCommand  = (hsubparser ((<>) (command "version" (info (pure Version) (progDesc "Display the version of the Axel compiler"))) (metavar "version")))}
commandParserInfo :: (ParserInfo Command)