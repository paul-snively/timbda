# Timbda-0

A verified compiler project: MLIR-based C++ canonicalization lane (Bazel +
hermetic-llvm) and a Gallina/Rocq kernel lane (Nix), cross-checked against a
Haskell golden/differential harness. Authoritative design and milestone plan:
[docs/PLAN.md](docs/PLAN.md).

## M-1 skeleton (PLAN step 0)

Two build graphs with distinct trusted roots, meeting only through the pin
table and a version-consistency check:

- `tools/pins/pins.toml` — pin table of record (single source of truth).
- `MODULE.bazel` + `.bazelversion` + `.bazelrc` — C++ lane: Bazel 9.3.2,
  hermetic-llvm 0.8.27 (default LLVM/MLIR vintage 23.1.2).
- `flake.nix` + `flake.lock` — formal/tooling lane: nixpkgs 26.05, Rocq 9.1.1,
  CompCert 3.17, GHC 9.12, plus locked source-only inputs for DCont, ctrees,
  InteractionTrees, coq-ext-lib, coinduction, CertiRocq, VeriFFI,
  verse-semantics.

### Checks

```sh
python3 tools/pins/pins.py check   # pins.toml == MODULE.bazel == .bazelversion == flake.lock == BCR
bazelisk test //dialect:timbda_dialect_test   # trivial Timbda dialect vs. hermetic-llvm MLIR
nix flake check -L                 # eval + version-consistency assert + Rocq kernel stub + GHC golden test
```

Watch-out #1 (docs/PLAN.md sec. 6): the llvm-project commit, the DCont fork,
and our dialect `.td` must share one MLIR API vintage. The probe result is
recorded in `tools/pins/pins.toml` under `[llvm_project]`; the `from_git`
switch is deliberately deferred to M-2.

## Dev shells

Host toolchain requirement: **nix, and only nix** (see `docs/DESIGN-NOTES.md` § 4).
`nix develop .#all` (cpp / rocq / hs variants) supplies Bazel/bazelisk, Python, GHC and Rocq
from the pin table — including the Coq libraries nixpkgs does not ship (extlib, paco,
coinduction, interaction-trees, ctrees), which the flake builds from pinned inputs. So
`cd coq && dune build` builds the full M0 kernel with no host toolchain beyond nix;
`nix build .#packages.x86_64-linux.timbda-kernel` builds it (with its `Admitted`/axiom gate)
outside a shell too. The transitional opam switch (DEV-3) is closed as of 2026-11-18.
