#!/usr/bin/env bash
# Sync the vendored ctrees checkout (deps/ctrees) to the revision pinned in
# tools/pins/pins.toml [formal.ctrees], and point the opam switch's rocq-ctree
# pin at it.  Idempotent: re-running only fetches/advances.
#
# Why vendored-and-gitignored: the flake (M-2) builds ctrees from the same pinned
# input via a local mkRocqDerivation; the opam dev shell needs the identical
# source tree so that `dune build` in coq/ and `nix build` see the same library.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$REPO_ROOT/deps/ctrees"
SWITCH="${TIMBDA_OPAM_SWITCH:-RP.2026.02.0~9.1~2026.01}"

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

if ! command -v opam >/dev/null; then
  echo "opam not on PATH: skipping switch pin (dune build will still work with an"
  echo "installed CTree, e.g. the one provided by the nix devShell)." >&2
  exit 0
fi

opam exec --switch "$SWITCH" -- opam pin add --no-action --yes \
  rocq-ctree "file://$DEST" >/dev/null
opam exec --switch "$SWITCH" -- opam install --yes rocq-ctree
