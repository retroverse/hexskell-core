module Bot where

import Hex

import Data.List
import Data.Maybe
import System.Process
import System.IO
import System.Exit
import Text.Regex
import Text.Read
import Data.Bifunctor (second, bimap)

data BotError = BotError String
type Bot = BoardState -> Checker -- board state -> new piece
type Bots = (Bot, Bot) --red, blue
type BotArgument = BoardState -- has (friendly, enemy) instead of (red, blue)

-- helpers
meetsAll :: a -> [(a -> Bool)] -> Bool
meetsAll x predicates = all ($ x) predicates
mapBoth :: (a -> a) -> (b -> b) -> Either a b -> Either a b
mapBoth = bimap
mapRight :: (b -> c) -> Either a b -> Either a c
mapRight = second
--

botError :: String -> BotError
botError message = BotError message

phBot :: Bot
phBot (red, blue) =
  head $ filter empty $ allCheckers
  where
    empty = (not . positionHasChecker (red, blue))

toExternalCheckersString :: Checkers -> String
toExternalCheckersString checkers = concat $ intersperse "|" $ map (\(x, y) -> show x ++ "," ++ show y) checkers

fromExternalCheckerString :: String -> Maybe Checker
fromExternalCheckerString str = readMaybe ("(" ++ str ++ ")") :: Maybe Checker

scriptFromTemplate :: String -> String -> String
scriptFromTemplate template code =
  (subRegex
    (mkRegex "\\/\\*\\s*BOT-START\\s*\\*\\/([\\s\\S]*)\\/\\*\\s*BOT-END\\s*\\*\\/")
    template
    code
  )

isValidNewChecker :: BoardState -> Checker -> Bool
isValidNewChecker boardState@(red, blue) checker = checker `meetsAll` predicates
  where
    predicates = [validCoordinate, isAllegiance boardState Neutral]

botCodeIsValid :: String -> Bool
botCodeIsValid botJS = botJS `meetsAll` predicates
  where
    predicates = [not . isInfixOf "require"]    

executeBot :: String -> BotArgument -> IO (Either BotError Checker)
executeBot script argument@(friendly, enemy) = do

  -- run external process
  (exitCode, out, err) <- readProcessWithExitCode command arguments script

  -- parse output to a checker
  let maybeChecker = fromExternalCheckerString out

  -- was there an error / return approp value?
  return $ case exitCode of
    ExitFailure _ -> Left (BotError err) -- probably add more detail later and stuff
    ExitSuccess -> case maybeChecker of
      Nothing -> Left $ BotError "Bot failed to return a checker"
      Just checker -> if isValidNewChecker argument checker
        then Right checker
        else Left $ BotError $ "Bot returned invalid checker " ++ show checker

  where
    command = "node"
    friendlyS = toExternalCheckersString friendly
    enemyS = toExternalCheckersString enemy
    arguments = ["", friendlyS, enemyS]

-- requires 'node' in PATH & 'bot-template.js' in cd
-- still need a detailed error when code is invalid (i.e why is it invalid?)
runExternalBot :: String -> Allegiance -> BoardState -> IO (Either BotError Checker) --String -> BotArgument -> IO (Maybe Coordinate)
runExternalBot botJS allegiance bs@(red, blue) = (do
  -- read template
  template <- readFile templatePath

  -- sub in program js code
  let fullScript = scriptFromTemplate template botJS

  -- swap red and blue and transpose based on allegiance and transpose correclty
  let arg = if allegiance == Red then (red, blue) else transposeBoardState (blue, red)

  -- is bot valid?
  if botCodeIsValid fullScript
    then executeBot fullScript arg
    else return $ Left $ BotError "Bot code is invalid"
  
  ) >>= (return . mapRight (if allegiance == Red then id else transposeCoordinate)) -- transpose back if blue

  where
    templatePath = "./bot-template.js"