module Test.Spec.Runner
       ( run
       , run'
       , runSpec
       , runSpec'
       , defaultConfig
       , timeout
       , Config
       , TestEvents
       , Reporter
       ) where

import Prelude

import Control.Alternative ((<|>))
import Effect (Effect)
import Effect.Aff (Aff, attempt, delay, makeAff, runAff, throwError, try)
import Effect.Class (liftEffect)
import Effect.Console (logShow)
import Effect.Exception (Error, error)
import Effect.Exception as Error
import Control.Monad.Trans.Class (lift)
import Control.Parallel (sequential, parallel)
import Data.Array (singleton)
import Data.Either (Either(..), either)
import Data.Foldable (foldl)
import Data.Int (toNumber)
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Time.Duration (Milliseconds(..))
import Data.Traversable (for)
import Pipes ((>->), yield)
import Pipes (for) as P
import Pipes.Core (Pipe, Producer, (//>))
import Pipes.Core (runEffectRec) as P
import Test.Spec (Spec, Group(..), Result(..), collect)
import Test.Spec as Spec
import Test.Spec.Console (withAttrs)
import Test.Spec.Runner.Event (Event)
import Test.Spec.Runner.Event as Event
import Test.Spec.Speed (speedOf)
import Test.Spec.Summary (successful)

foreign import exit :: Int -> Effect Unit

foreign import dateNow :: Effect Int

type Config = {
  slow :: Int
, timeout :: Maybe Int
, exit :: Boolean
}

defaultConfig :: Config
defaultConfig = {
  slow: 75
, timeout: Just 2000
, exit: true
}

trim :: ∀ r. Array (Group r) -> Array (Group r)
trim xs = fromMaybe xs (singleton <$> findJust findOnly xs)
  where
  findOnly :: Group r -> Maybe (Group r)
  findOnly g@(It true _ _) = pure g
  findOnly g@(Describe o _ gs) = findJust findOnly gs <|> if o then pure g else Nothing
  findOnly _ = Nothing

  findJust :: forall a. (a -> Maybe a) -> Array a -> Maybe a
  findJust f = foldl go Nothing
    where
    go Nothing x = f x
    go acc _ = acc

makeTimeout
  :: Int
  -> Aff Unit
makeTimeout time = do
  delay (Milliseconds $ toNumber time)
  makeAff \cb -> mempty <$ do
    cb <<< Left $ error $ "test timed out after " <> show time <> "ms"

timeout
  :: Int
  -> Aff Unit
  -> Aff Unit
timeout time t = do
  sequential (parallel (try (makeTimeout time)) <|> parallel (try t))
    >>= either throwError pure

-- Run the given spec as `Producer` in the underlying `Aff` monad.
-- This producer has two responsibilities:
--      1) emit events for key moments in the runner's lifecycle
--      2) collect the tst output into an array of results
-- This allows downstream consumers to report about the tests even before the
-- prodocer has completed and still benefit from the array of results the way
-- the runner sees it.
_run
  :: Config
  -> Spec Unit
  -> Producer Event Aff (Array (Group Result))
_run config spec = do
  yield (Event.Start (Spec.countTests spec))
  r <- for (trim $ collect spec) runGroup
  yield (Event.End r)
  pure r

  where
  runGroup (It only name test) = do
    yield Event.Test
    start    <- lift $ liftEffect dateNow
    e        <- lift $ attempt case config.timeout of
                                      Just t -> timeout t test
                                      _      -> test
    duration <- lift $ (_ - start) <$> liftEffect dateNow
    yield $ either
      (\err ->
        let msg = Error.message err
            stack = Error.stack err
         in Event.Fail name msg stack)
      (const $ Event.Pass name (speedOf config.slow duration) duration)
      e
    yield Event.TestEnd
    pure $ It only name $ either Failure (const Success) e

  runGroup (Pending name) = do
    yield $ Event.Pending name
    pure $ Pending name

  runGroup (Describe only name xs) = do
    yield $ Event.Suite name
    Describe only name <$> (for xs runGroup)
    <* yield Event.SuiteEnd

-- Run a spec, returning the results, without any reporting
runSpec'
  :: Config
  -> Spec Unit
  -> Aff (Array (Group Result))
runSpec' config spec = P.runEffectRec $ _run config spec //> const (pure unit)

runSpec
  :: Spec Unit
  -> Aff (Array (Group Result))
runSpec spec = P.runEffectRec $ _run defaultConfig spec //> const (pure unit)

type TestEvents = Producer Event Aff (Array (Group Result))

type Reporter = Pipe Event Event Aff (Array (Group Result))

-- Run the spec, report results and (if configured as such) exit the program upon completion
run'
  :: Config
  -> Array Reporter
  -> Spec Unit
  -> Effect Unit
run' config reporters spec = void do
  let events = foldl (>->) (_run config spec) reporters
  runAff (either onError onSuccess) (P.runEffectRec (P.for events onEvent))

  where
    onEvent _ = pure unit

    onError :: Error -> Effect Unit
    onError err = do withAttrs [31] $ logShow err
                     when config.exit do
                       exit 1

    onSuccess :: Array (Group Result) -> Effect Unit
    onSuccess results = when config.exit do
                          let code = if successful results then 1 else 0
                          exit code

run
  :: Array Reporter
  -> Spec Unit
  -> Effect Unit
run = run' defaultConfig
