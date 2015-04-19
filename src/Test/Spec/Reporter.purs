module Test.Spec.Reporter where

import Debug.Trace
import Data.String
import Data.Array (map, concatMap)
import Data.Foldable
import Control.Monad.Eff
import Control.Monad.Eff.Exception
import Control.Monad.Extras
import qualified Test.Spec as S
import Test.Spec.Console
import Test.Spec.Summary

foreign import debug
  """
  function debug(value) {
    console.log('Debug', value);
    return value;
  }
  """ :: forall v. v -> v

foreign import showAssertionError
  """
  function showAssertionError(err) {
    return err.message;
  }
  """ :: Error -> String

data Entry = Describe [S.Name]
           | It S.Name S.Result
           | Pending S.Name

instance eqEntry :: Eq Entry where
  (==) (Describe n1) (Describe n2) = n1 == n2
  (==) (It n1 S.Success) (It n2 S.Success) = n1 == n2
  (==) (It n1 (S.Failure e1)) (It n2 (S.Failure e2)) =
    n1 == n2 && (showAssertionError e1) == (showAssertionError e2)
  (==) (It n1 _) (It n2 _) = false
  (==) (Pending n1) (Pending n2) = n1 == n2
  (/=) e1 e2 = not (e1 == e2)

instance showEntry :: Show Entry where
  show (Describe names) = "Describe \"" ++ (joinWith " » " names) ++ "\""
  show (It name S.Success) = "It \"" ++ name ++ "\" Success"
  show (It name (S.Failure err)) = "It \"" ++ name ++ "\" (Failure \"" ++ showAssertionError err ++ "\")"
  show (Pending name) = "Pending \"" ++ name ++ "\""

printEntry :: forall r. Entry
           -> Eff (trace :: Trace | r) Unit
printEntry (It name S.Success) = do
  withAttrs [32] $ writeln $  "√ " ++ name
printEntry (Pending name) = do
  withAttrs [33] $ writeln $  "~ " ++ name
printEntry (It name (S.Failure err)) = do
  withAttrs [31] $ writeln $ "✗ " ++ name ++ ":"
  trace ""
  withAttrs [31] $ writeln $ "  " ++ showAssertionError err
  trace ""
printEntry (Describe []) = return unit
printEntry (Describe [last]) =
  withAttrs [1, 35] $ writeln last
printEntry (Describe (name : names)) = do
  withAttrs [1] do
    write name
    write " » "
  printEntry $ Describe names

countDescribes :: [Entry] -> Number
countDescribes groups = foldl f 0 groups
  where f c (Describe _) = c + 1
        f c _ = c

collapse :: S.Group -> [Entry]
collapse (S.It name result) = [It name result]
collapse (S.Pending name) = [Pending name]
collapse (S.Describe name groups) =
  let sub = concatMap collapse groups
      prependName (Describe names) = Describe (name : names)
      prependName e = e
      c = countDescribes sub
      -- n = debug $ show sub ++ " " ++ show c
  in if c == 0 then (Describe [name]) : sub
               else map prependName sub

report :: forall r. [S.Group] -> Eff (trace :: Trace | r) Unit
report groups = do
  writeln ""
  mapM_ printEntry $ concatMap collapse groups
  printSummary groups
