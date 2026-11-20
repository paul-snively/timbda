#!/usr/bin/env bash
# M1 TD sweep: run the pinned vintage's mlir-tblgen (docs/PLAN.md sec. 6:
# hermetic-llvm 0.8.27 / LLVM 23.1.2) over the dialect, the record corpus and
# the pattern corpus.
#
#   asserted:   dialect TD op decls/defs parse; TimbdaRules.td parses; and
#               TimbdaPatterns.td -gen-rewriters emits exactly 23 rewriter
#               structs with stderr free (one per kernel ctor whose record has
#               pattern = "drr"; tools/rules-audit.py separately matches those
#               struct names against the kernel ctors).  tblgen warns "no
#               matchers or constraints for the matched operation" for a
#               degenerate match, so a warning is a FAIL, not noise.
#   informational: probes/p5/*.td - the shape record the encoding was built on
#               (each probe header states what it proved) - and the pre-M1
#               probes/p4 + probes/probe4.td suite, kept as historical evidence
#               of the dialect shape the current encoding moved away from.
#
# Usage: bash probes/sweep.sh      exit status = the gate's status
set -u
cd "$(cd "$(dirname "$0")" && pwd)/.."

TB=bazel-bin/external/llvm++llvm+llvm-project/mlir/mlir-tblgen
[ -x "$TB" ] || { echo "missing $TB - first run: bazel build @llvm-project//mlir:mlir-tblgen"; exit 2; }
MAIN=$(cd "$(readlink bazel-out 2>/dev/null || echo bazel-out)/.." 2>/dev/null && pwd)
INC="$MAIN/external/llvm++llvm+llvm-project"
[ -n "${INC:-}" ] && [ -d "$INC/mlir/include/mlir/IR" ] || { echo "cannot locate llvm_project checkout via bazel-out"; exit 2; }

rc_all=0

run() { # <name> <expect-rc> <td-file> [extra tblgen args]  - parse-only gate
  local name=$1 expect=$2 file=$3
  shift 3
  local out rc
  out=$("$TB" -I . -I dialect -I probes -I probes/p4 -I probes/p5 -I "$INC/mlir/include" \
        "$@" "$file" 2>&1 >/dev/null)
  local rc=$?
  printf '%s\n' "$out" > "probes/_sweeps/$name.err"
  if [ "$expect" = 0 ] && [ $rc -ne 0 ]; then
    echo "FAIL $name (rc $rc)"; echo "$out" | head -8; rc_all=1
  elif [ "$expect" != 0 ] && [ $rc -eq 0 ]; then
    echo "FAIL $name (expected rejection, got rc 0)"; rc_all=1
  else
    echo "ok   $name (rc $rc)"
  fi
}

gen_gate() { # <name> <td-file> <expected-struct-count>
  local name=$1 file=$2 want=$3
  "$TB" -I . -I dialect -I probes -I probes/p4 -I probes/p5 -I "$INC/mlir/include" \
        -gen-rewriters "$file" > "/tmp/sweep_$name.inc" 2> "/tmp/sweep_$name.err"
  local rc=$?
  local structs warn
  structs=$(grep -c '^struct ' "/tmp/sweep_$name.inc")
  local warn_n
  warn_n=$(grep -c 'warning' "/tmp/sweep_$name.err")
  if [ $rc -ne 0 ]; then
    echo "FAIL $name (rc $rc)"; head -8 "/tmp/sweep_$name.err"; rc_all=1
  elif [ "$warn_n" -ne 0 ]; then
    echo "FAIL $name ($warn_n tblgen warnings - degenerate match? see /tmp/sweep_$name.err)"; rc_all=1
  elif [ "$structs" -ne "$want" ]; then
    echo "FAIL $name ($structs rewriter structs, expected $want)"; rc_all=1
  else
    echo "ok   $name ($structs warning-free rewriter structs)"
  fi
}

info() { # <td-file>
  local file=$1
  local base out err
  base=$(basename "$file" .td)
  "$TB" -I . -I dialect -I probes -I probes/p4 -I probes/p5 -I "$INC/mlir/include" \
        -gen-rewriters "$file" > /tmp/sweep_info.inc 2> /tmp/sweep_info.err
  local rc=$? structs warn_n
  structs=$(grep -c '^struct ' /tmp/sweep_info.inc)
  warn_n=$(grep -c 'warning' /tmp/sweep_info.err)
  echo "  info $base (rc $rc, $structs structs${warn_n:+, $warn_n warnings})"
}

mkdir -p probes/_sweeps

echo "== gate: dialect TD (dialect/Timbda.td) =="
run dialect-opdecls 0 dialect/Timbda.td -gen-op-decls
run dialect-opdefs  0 dialect/Timbda.td -gen-op-defs

echo "== gate: TimbdaPatterns.td -> generated rewriter structs =="
gen_gate patterns dialect/TimbdaPatterns.td 23

echo "== informational: probes/p5 shape record =="
for f in probes/p5/*.td; do
  info "$f"
done

echo "== informational: pre-M1 probes/p4 suite =="
info probes/probe4.td

exit $rc_all
