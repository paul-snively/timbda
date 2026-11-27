# Timbda-0

**A verified compiler for the core semantics of the Verse language — built for
real, in MLIR and C++, with the proofs done in Rocq.**

## What this project builds

This project builds a verified Verse Timbda-0 MLIR dialect, **based on** the
Verse Calculus — the ICFP'23 paper by Augustsson, Breitner, Claessen, Jhala,
Peyton Jones, Shivers, Steele and Sweeney — and the OPLSS 2026 Summer School
(Oregon Programming Language Summer School) materials: Simon Peyton Jones's
Verse lectures and their "Supporting Figures" paper, which lays out Timbda-0's
rewrite rules, **using**:

- **Rocq** as the sole prover: the semantics lives as a machine-checked Gallina
  kernel, not as prose on paper;
- **ctrees** (choice trees) as the semantic carrier — a Verse program denotes a
  *set of candidates*, and the kernel models that set as branching choice trees
  read up to weak bisimilarity — with **coq-ext-lib** and **stdpp** as the
  supporting Rocq libraries;
- **CertiRocq** to compile the Gallina kernel down to C, so the proven
  semantics is not a reference implementation but the actual code that gets
  linked and run;
- **boost::context** (stack switching) as the semantic runtime layer for
  nondeterminism, not an optimization: programs whose candidate sets genuinely
  offer two or more candidates compile to explicit choice nodes (PLAN
  decision 15), and arbitrating those nodes requires re-enterable control —
  for such programs the stack switch is part of what it *means* to run them.
  It still enters only through a refinement proof, never as a bare runtime
  contract, and determinate fragments compile, by theorem, with zero context
  calls;
- **Lennart Augustsson's [verse-semantics](https://github.com/augustss/verse-semantics)**
  Haskell prototype as the oracle for the golden and differential tests;
- **Alive2** to police correctness at the C boundary, where clang takes over
  after the verified part of the chain ends.

## What "Timbda-0" means

Timbda is the name the Verse papers use for Verse's evaluation algorithm: the
machinery of choice (`or`), failure, binding, effects (`get`/`put`) and
pattern-matching. Timbda-0 is the small formal core of it that the papers
define (a.k.a. Core Verse): rewrite rules over expressions and patterns,
unification, primops, partial types (an ill-typed program simply denotes
nothing), and the candidate-set denotation. Verse's full source language is
out of scope for now.

The dialect (`dialect/Timbda.td`) makes those ideas first-class MLIR operations
(`timbda.bind`, `timbda.or`, `timbda.fail`, `timbda.match`, ...) — and, central
to the method, one TableGen record per paper rule generates *both halves* of
the pipeline: the MLIR C++ ops and rewrite patterns on one side, the Rocq data
constructors, rewrite relation, soundness-lemma skeleton and litmus tests on
the other. The compiler and the proof are built from the same rule table, so
"did we cover every rule in the paper?" is a mechanical audit, not a promise.

## What "verified" means here

- **Proven span:** paper rules → each rewrite carries a machine-checked
  soundness proof → determinacy analysis and the evaluator live in Gallina →
  CertiRocq compiles the kernel to Clight → C. CertiRocq's Gallina→Clight
  proof is the last machine-checked link.
- **Trusted-but-observed span:** from clang onward. **Alive2** translation
  validation checks clang's IR transforms against the emitted C, backed by
  binary-level differential testing and hardened compile flags at the
  CertiRocq-C boundary (TBAA/strict-aliasing is treated as a known hazard, not
  a surprise). CompCert is available as an optional final link.
- **Differential triangle:** every test expectation is derived by hand from the
  paper *before* looking at what any implementation produces, and independent
  corners — the extracted Gallina evaluator, the MLIR canonicalizer, and
  Augustsson's Haskell oracle — must all agree on the shared corpus.
- **The non-naive claim.** Verse invites eager, out-of-order evaluation of
  constant expressions; that is only worth doing if it provably preserves
  meaning. The project's theorem targets include out-of-order reordering
  soundness, adequacy of the specialized code against straight C, and a
  "no-context-call" theorem: determinate fragments compile to straight-line C
  with *zero* stack-switching calls. The converse is semantic too, not
  cosmetic: programs with genuine multi-candidate sets compile their choices
  to visible choice nodes, and the stack switches that arbitrate them are
  part of the semantics of running those programs (PLAN decision 15).
  Wherever there is a choice between proving
  something and trusting a runtime contract, we prove — even when that is
  harder up front.

## The end goal

Verse is Epic Games' language, and Timbda is the evaluation algorithm described
in Epic's papers and documentation. Today the project works on Timbda-0 — the
small formal core as described in the academic papers, including the OPLSS 2026
materials. The ultimate goal is to base everything on **Epic Games' own
materials** — the real Verse language and its documented evaluation algorithm —
and to carry the formalization all the way down to the **running artifact**:
the binary that MLIR and clang actually produce provably refines the proven
semantics. And all of it in a thoroughly practical context — a real MLIR
dialect, real TableGen, Bazel with hermetic-llvm toolchains, a thin C++ driver,
and a WASM leg (via the DCont/WAMI dialect and WebAssembly stack switching) —
because verified semantics that never produces a working compiler is just
semantics.

The project proceeds in milestones: the semantics kernel first, then the
dialect and its generator, then the specialization proofs (straight-line C,
no context switches), then the full certified runtime, then the stack-switch
layer — semantic for indeterminate programs, empty by theorem for determinate
ones — which also carries the performance/streaming leg, then WASM. The authoritative plan, the
architecture, and the full theorem inventory (T1–T12) are in
[docs/PLAN.md](docs/PLAN.md).

## Where to read more

- [docs/PLAN.md](docs/PLAN.md) — master plan: architecture, build
  infrastructure, theorem targets, milestones, prior-art audit and the precise
  statement of what this project does and does not claim (§ 11).
- [docs/VERSE-RULES.md](docs/VERSE-RULES.md) — transcription of the papers'
  rewrite rules that the kernel and the dialect are built from.
- [docs/RULES-AUDIT.md](docs/RULES-AUDIT.md) — per-rule proof status and the
  axiom audit (the kernel builds under a gate of zero `Admitted`).
- [docs/DESIGN-NOTES.md](docs/DESIGN-NOTES.md) — supporting decision records.

## Getting started

Host toolchain requirement: **nix, and only nix** — Bazel, Rocq, GHC and Python
all come from the pinned flake. `tools/pins/pins.toml` is the pin table of
record shared by the two build graphs (Bazel + hermetic-llvm for the C++ side;
Nix for the formal side).

```sh
python3 tools/pins/pins.py check               # pin table agrees with MODULE.bazel and flake.lock
bazelisk test //dialect:timbda_dialect_test    # dialect builds against hermetic-llvm MLIR
cd coq && dune build                           # the Gallina kernel (inside nix develop .#rocq or .#all)
nix flake check -L                             # everything: kernel gate, differential corpus, version consistency
```

## A note on provenance

*Timbda is the name the Verse papers use for Verse's evaluation algorithm.
Verse is developed by Epic Games; this is an independent academic project,
unaffiliated with Epic Games or the Verse team. The project builds openly on
published prior art — the Verse Calculus paper, Weirich's Coq mechanizations of
Verse, openverse, CompCertFX and others — and docs/PLAN.md § 11 states exactly
what is and is not claimed here.*
