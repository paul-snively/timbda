#!/usr/bin/env bash
# Sync the vendored ctrees checkout (deps/ctrees) to the revision pinned in
# tools/pins/pins.toml [formal.ctrees].  Idempotent: re-running only fetches/advances.
#
# What the vendored copy is for now: a *source* tree at the pinned revision, so the
# upstream line citations in docs/DESIGN-NOTES.md sec. 3 can be opened locally.  CTree
# for the build no longer comes from here: flake.nix's coqStack builds rocq-ctree from
# the same pinned input, and `cd coq && dune build` runs inside `nix develop .#rocq`.
# (DEV-3, the transitional opam-switch fallback, was closed 2026-11-18.)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$REPO_ROOT/deps/ctrees"

read_pin() { # dotted section key, key
  python3 - "$REPO_ROOT/tools/pins/pins.toml" "$1" "$2" <<'PY'
import sys, tomllib
with open(sys.argv[1], "rb") as f:
    table = tomllib.load(f)
node = table
for part in sys.argv[2].split("."):
    node = node[part]
print(node[sys.argv[3]])
PY
}

REPO="$(read_pin formal.ctrees repo)"
REV="$(read_pin formal.ctrees rev)"
BRANCH="$(read_pin formal.ctrees branch)"

# pins.toml stores flake-style `github:owner/repo`; git wants an https URL.
GIT_URL="$REPO"
case "$GIT_URL" in
  github:*) GIT_URL="https://github.com/${GIT_URL#github:}.git" ;;
  gitlab:*) GIT_URL="https://gitlab.com/${GIT_URL#gitlab:}.git" ;;
esac

echo "ctrees: $GIT_URL @ $REV (branch $BRANCH) -> $DEST"

# Plain vendored copy (no nested git repo): the parent repo tracks nothing under
# deps/, so the checkout is reconstructed here from the pinned rev.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
git clone --quiet "$GIT_URL" "$TMP/ctrees"
git -C "$TMP/ctrees" checkout -q --detach "$REV"
mkdir -p "$DEST"
rsync -a --delete --exclude '.git' --exclude '_build' "$TMP/ctrees/" "$DEST/"
echo "vendored $(git -C "$TMP/ctrees" rev-parse HEAD) into $DEST"
