#!/bin/sh
# bazel-lane.sh - the bazel half of the "bazel builds, nix checks consume as
# prebuilt" contract (docs/PLAN.md § 6; decision 9 § 5.0 item 4: the M1
# bazel-attestation lane).
#
# WHAT IT DOES.  Runs the bazel graph over the dialect - TableGen generation,
# the dialect + canonicalization libraries, and the dialect test - against the
# hermetic-llvm pin in MODULE.bazel, and records the exact result in
# tools/build/bazel-lane-status.txt (the artifact the flake check
# `checks.bazel-native-tests` consumes).  bazelisk itself comes from the
# flake: the intended invocation is
#     nix develop .#cpp -c tools/build/bazel-lane.sh
#
# WHY THE STATUS IS CONTENT-HASHED.  The nix-side check re-runs
# `sha256sum -c` over the source-hash block this script embeds, against its
# own copy of the tree, and refuses on any mismatch.  Prebuilt evidence is
# therefore bound to the exact dialect/pin content it claims to have built:
# a stale status against a changed dialect is a red gate, not an unchecked
# claim.  No timestamp is written - the content hashes are the freshness
# signal, and git already knows when the lane ran.
#
# On bazel failure nothing is rewritten: the last green status remains paired
# with the last tree it actually matches.
set -e
cd "$(dirname "$0")/../.."
OUT="tools/build/bazel-lane-status.txt"
LOG="$(mktemp)"

# The M1 lane target set (decision 9 item 4): generated rewriters, the
# canonicalization TU, the dialect ops library, and its test.
if ! bazel --batch test \
      //dialect:timbda_dialect_test \
      //dialect:TimbdaCanonicalization \
      //dialect:TimbdaCanonicalizationIncGen \
      //dialect:TimbdaDialect > "$LOG" 2>&1; then
  echo "bazel-lane: bazel FAILED - status NOT updated.  Log tail:" >&2
  tail -25 "$LOG" >&2
  exit 1
fi

COMPLETED=$(grep -m1 '^INFO: Build completed' "$LOG" || true)
[ -n "$COMPLETED" ] || { echo "bazel-lane: no 'Build completed' line - refusing" >&2; exit 1; }
TESTLINES=$(grep -E '^//dialect:[A-Za-z_]+ +.*(PASSED|FAILED|TIMEOUT)' "$LOG" || true)
case "$TESTLINES" in
  *FAILED*|*TIMEOUT*) echo "bazel-lane: test summary contains FAILED/TIMEOUT - refusing" >&2; exit 1;;
esac
[ -n "$TESTLINES" ] || { echo "bazel-lane: no dialect test summary line - refusing (vacuous run)" >&2; exit 1; }

{
  echo '# timbda bazel-lane status - consumed by flake check checks.bazel-native-tests'
  echo '# Regenerate: nix develop .#cpp -c tools/build/bazel-lane.sh'
  echo 'lane=timbda-bazel-native-tests'
  echo "bazel_version=$(bazel --version 2>&1 | grep -m1 '^bazel ')"
  echo "bazelversion_file=$(cat .bazelversion)"
  echo "llvm_bazel_dep=$(grep -m1 'bazel_dep(name = "llvm"' MODULE.bazel)"
  echo 'build_targets=//dialect:timbda_dialect_test //dialect:TimbdaCanonicalization //dialect:TimbdaCanonicalizationIncGen //dialect:TimbdaDialect'
  echo "build_completed=$COMPLETED"
  echo "test_summary=$(printf '%s' "$TESTLINES" | tr '\n' ';')"
  echo 'bazel_rc=0'
  echo '=== source hashes ==='
  sha256sum dialect/*.td dialect/*.cpp dialect/*.h dialect/BUILD.bazel \
    MODULE.bazel MODULE.bazel.lock .bazelversion tools/pins/pins.toml
} > "$OUT"

echo "bazel-lane: wrote $OUT ($(wc -l < "$OUT") lines); $COMPLETED"
