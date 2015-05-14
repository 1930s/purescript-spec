# purescript-spec

purescript-spec is a simple testing framework for Purescript using NodeJS. It's
inspired by [hspec](http://hspec.github.io/).

<img src="https://raw.githubusercontent.com/owickstrom/purescript-spec/master/example.png" width="400" />

## Usage

```bash
bower install purescript-spec
```

Then in a `Main.purs` file you can start writing your tests.

```purescript
module Main where

import Control.Monad.Aff
import Test.Spec (describe, pending, it)
import Test.Spec.Node
import Test.Spec.Assertions
import Test.QuickCheck

additionSpec =
  describe "Addition" do
    it "does addition" do
      (1 + 1) `shouldEqual` 2
    it "fails as well" do
      (1 + 1) `shouldEqual` 3

main = runNode do
  describe "Math" do
    additionSpec
    describe "Multiplication" do
      pending "will do multiplication in the future"
  describe "Async" do
    it "asserts in the future" do
      res <- later' 100 $ return "Alligator"
      res `shouldEqual` "Alligator"
```

In this example `additionSpec` is embedded into the `Math` specification. This
is useful if you want to split specifications into multiple files and combine
them in `Main`.

The last test demonstrates how you can use [Aff](https://github.com/slamdata/purescript-aff)
to write async tests.

```purescript
main = suite do
  mathSpec
  stringsSpec
  arraySpec
  ...
```

Then run the test suite using `psc-make` and NodeJS. Not that `$TESTS`, `$SRC`
and `$LIB` contains all the Purescript source paths needed.

```bash
psc-make -o output/tests $TESTS $SRC $LIB
NODE_PATH=output/tests node -e "require('Main').main();"
```

## QuickCheck

You can use [QuickCheck](https://github.com/purescript/purescript-quickcheck)
together with the [`purescript-spec-quickcheck`](https://github.com/owickstrom/purescript-spec-quickcheck)
adapter to get nice output formatting for QuickCheck tests.

## API

See [API](API.md).

## Build

```bash
# Make the library
make
# Run tests
make run-tests
# Generate docs
make docs
```

## CTags

```bash
make ctags
```

### Generate Example

Generating the `example.png` requires:

* phantomjs
* aha
* imagemagick

```
make example.png
```

## Contribute

If you have any issues or possible improvements please file them as
[GitHub Issues](https://github.com/owickstrom/purescript-spec/issues). Pull
requests requests are encouraged.

## License

[MIT License](LICENSE.md).
