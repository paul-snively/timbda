#!/bin/sh
# push-task.sh - the push half of the landing ritual (docs/TOOLING.md T-005).
#
# PRECONDITION, outside this script: `jj describe` done and the pinned gate
# chain green against this exact tree:
#   TIMBDA_NIX_GATE_MIN=5G TIMBDA_NIX_GATE_GUARD=8 NIX_CONFIG="cores = 2" tools/build/nix-gate.sh
# (the gate is long; the ritual keeps it a separate step so this script stays a
# fast, atomic, verifiable tail with no long-running stage to interrupt).
#
# WHAT IT DOES, in order:
#   1. asserts the milestone table of record (README == tools/pins/milestones.toml)
#   2. moves the main bookmark to @ and opens a fresh working copy
#   3. pushes (keyring SSH_AUTH_SOCK unless the caller set one)
#   4. verifies origin/main is the exact commit the bookmark moved to
#   5. syncs the GitHub About section from the latest dated CLOSED milestone
#
# The Strata memory note stays the agent-side final step of the ritual; a
# shell script has no archive to remember into.
set -eu
cd "$(dirname "$0")/../.."

echo "== 1. milestone table of record"
python3 tools/pins/milestones.py check

echo "== 2. main bookmark -> @"
jj bookmark set main -r @
COMMIT=$(jj log -r main --no-graph --limit 1 -T 'commit_id')
jj new

echo "== 3. jj git push"
if [ -z "${SSH_AUTH_SOCK:-}" ]; then SSH_AUTH_SOCK=/run/user/1000/keyring/ssh; export SSH_AUTH_SOCK; fi
jj git push

echo "== 4. verify origin/main"
REMOTE=$(git ls-remote origin main | awk '{print $1}')
test "$REMOTE" = "$COMMIT" || { echo "FAIL: origin/main $REMOTE != bookmarked $COMMIT"; exit 1; }
echo "origin/main == $REMOTE"

echo "== 5. About section"
python3 tools/pins/milestones.py sync-about

echo "push-task OK: main=$REMOTE"
