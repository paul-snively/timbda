#!/usr/bin/env bash
# Sync the vendored ctrees checkout (deps/ctrees) to the revision pinned in
# tools/pins/pins.toml [formal.ctrees].  Idempotent: re-running only fetches/advances.
#
# The vendored tree is the primary deliverable: coq/'s dune build compiles CTree from
# it.  The opam-switch pin below is the transitional fallback for DEV-3
# (docs/DESIGN-NOTES.md sec. 4) — run with TIMBDA_OPAM_PIN=0 to skip it.  From M-2 the
# flake devShell provides CTree via a local mkRocqDerivation on the same pinned input
# (the host provides nix, nothing else).
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

if [[ "${TIMBDA_OPAM_PIN:-1}" == 0 ]] || ! command -v opam >/dev/null; then
  echo "switch pin skipped (TIMBDA_OPAM_PIN=0 or no opam): CTree comes from the vendored" >&2
  echo "deps/ctrees + the nix devShell (DEV-3 exit path, docs/DESIGN-NOTES.md sec. 4)." >&2
  exit 0
fi

opam exec --switch "$SWITCH" -- opam pin add --no-action --yes \
  rocq-ctree "file://$DEST" >/dev/null
opam exec --switch "$SWITCH" -- opam install --yes rocq-ctree
