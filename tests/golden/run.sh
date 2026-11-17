#!/bin/sh
# M-1 trivial golden test: compile golden.hs with the pinned ghc, run it,
# compare against golden.expected.
set -e
cd "$(dirname "$0")"
ghc -O0 -o golden golden.hs
./golden > actual.out
diff -u golden.expected actual.out
echo "timbda-golden-test ok"
