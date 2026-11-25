#!/bin/sh
# tblgen-rocq driver (docs/DESIGN-NOTES.md sec. 13.10): runs the TableGen
# backend compiled by flake.nix's timbda-tblgen-rocq package.
#
# Classic tablegen (the API nixpkgs' llvmPackages_23 can link against) resolves
# `include "..."` from the CWD, so this driver materializes the layout a run
# needs in a scratch dir: the input file's sibling .td files, plus symlinks to
# the mlir and llvm .td include roots.  Output paths are made absolute before
# the cd, so relative -o works from any caller directory.
set -e

mode="${1:-}"; tdfile="${2:-}"
if [ -z "$mode" ] || [ -z "$tdfile" ]; then
  echo "usage: tblgen-rocq <-gen-rocq-rules|-gen-rocq-ast|-gen-rocq-checker|-gen-pdll-tests|-gen-rocq-externs> <input.td> [-o <output>]" >&2
  exit 1
fi
shift 2
out=""
if [ "${1:-}" = "-o" ]; then
  out="${2:?-o needs an argument}"
  case "$out" in
    /*) ;;
    *) out="$PWD/$out" ;;
  esac
fi

tdir=$(cd "$(dirname "$tdfile")" && pwd -P)
tbase=$(basename "$tdfile")

wd=$(mktemp -d)
trap 'rm -rf "$wd"' EXIT
ln -s @MLIR_INC@/mlir "$wd/mlir"
ln -s @LLVM_INC@/llvm  "$wd/llvm"
for f in "$tdir"/*.td; do
  ln -s "$f" "$wd/$(basename "$f")"
done
cd "$wd"

prefix=$(cd "$(dirname "$0")/.." && pwd)
exec "$prefix/libexec/tblgen-rocq-bin" "$mode" "$tbase" ${out:+-o "$out"}
