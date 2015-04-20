module Test.Spec.Node (
  Process(..),
  runNode
  ) where

import Debug.Trace
import Control.Monad
import Control.Monad.Eff
import Test.Spec
import Test.Spec.Console
import Test.Spec.Summary
import Test.Spec.Reporter (report)

foreign import data Process :: !

foreign import exit
  """
  function exit(code) {
    return function() {
      process.exit(code);
    };
  }
  """ :: forall eff. Number -> Eff (process :: Process | eff) Unit

runNode :: forall r. Spec (trace :: Trace, process :: Process | r) Unit
        -> Eff (trace :: Trace, process :: Process | r) Unit
runNode r = do
  results <- collect r
  -- TODO: Separate console printing as a pluggable "Reporter"
  report $ results
  when (not $ successful results) $
    exit 1

