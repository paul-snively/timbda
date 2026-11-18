# Timbda-0 Verified Compiler — Master Plan

Status: plan settled; ready to execute on agent switch. Last updated: 2026-11-16.
Authoritative recapitulation. Supporting decision records are also stored in Strata memory
(tags: timbda, gallina-kernel, ctrees, certirocq, boost-context, nix, bazel, hermetic-llvm,
compcert, clight, tbaa) — recall via /recall or find_solutions with tag "timbda".

## 0. First committed action: M-1 build-infra skeleton

- Commit to starting with a TINY skeleton: flake.nix + MODULE.bazel + generated pin table +
  version-consistency CI check (~300 lines total), before any C++ or Rocq code exists.
  Add bones and flesh incrementally on top of it.
- Definition of done for M-1: both graphs "hello world" green — bazel builds a trivial dialect
  target under hermetic-llvm; rocq compiles a trivial kernel stub; Haskell side builds a trivial
  golden test; consistency check passes.
- Pre-M-1 probe (half-day): clone the DCont fork (github.com/CMUAbstract/mlir-wasm-dialect),
  identify which MLIR API vintage its conversion passes assume, check against the hermetic-llvm
  0.8.x llvm-project overlay. This sets the llvm-project commit pin (watch-out #1).

## 1. Scope and principles (stipulated)

- Timbda-0 only = Core Verse semantics. Source Verse and Essential Verse out of scope.
- Goal: a working Timbda implementation in C++, aggressive about proving it is (a) really a
  Timbda-0 implementation and (b) a non-naive one (out-of-order constant-expression reduction
  provably yields straight C with no unneeded boost::context calls).
- Principle: whenever there is a "prove" vs "runtime contract" choice, PROVE, even if harder
  upfront. Consequences: determinacy analysis lives in the Gallina kernel; strategy execution is
  a Gallina evaluator (search as data/work-queues, not stack switches); boost::context demoted
  to a later, provably-mapped optimization (M4).
- Formalization calibration "up to what the papers themselves formalize":
  - Tier 1 — papers define it => our definitions (unified expr/pat/type syntax, rewrite relation,
    denotation, M laws, partial types, ill-typed => empty).
  - Tier 2 — papers state/sketch it => mechanized theorems (rule soundness, M algebra, delta-primop
    agreement, strategy adequacy incl. match-first).
  - Tier 3 — papers leave open (full confluence, general strategy invariance) => faithfully stated
    conjectures, attempted opportunistically per fragment (beta/delta subsystem, determinate
    fragments), never milestone-blocking. Nuance (see sec. 11): VC (ICFP'23) *did* prove confluence
    for well-behaved terms — by hand, Appendix C — and *explicitly leaves evaluation strategies
    unformalized* (its sec. 3.7). Mechanized confluence and mechanized strategy adequacy remain open.
- No Isabelle/HOL, no Lean: Rocq is the sole prover. Practical framing; minimal open-research emphasis.

## 2. Architecture

    timbda dialect (ODS: Timbda-0 ops+types)              dcont (WAMI fork)
            |  rewrites = generated DRR patterns            |
            +----------------+                              |
            v                v                              v
    specialization / determinacy pass          two backend legs from dcont:
    (Gallina kernel)                             native: llvm.func externs with
            |  Gallina lowering to Clight           emitted attrs (convergent etc.)
            v                                       + C via CertiRocq + boost.context shim
    CertiRocq -> Clight -> clang (CompCert optional)   wasm: WAMI lowering -> SsaWasm -> Wasm
            |                                              |
            +----------> C objects <---- thin C++ driver; VeriFFI boundary;
                                        Alive2 validates clang-side IR

- Gallina kernel owns: determinacy analysis, lowering, and the strategy evaluator (explicit
  work-queue scheduler over the ctrees model — search realized as data, not stack switches).
- boost::context is a later, provably-mapped optimization (M4) for performance/streaming/reactive
  control. It enters only via a T12-style theorem, never as a bare runtime contract. WASM
  equivalent = WebAssembly stack-switching (WASI 0.3 async ABI / WAMI pipeline).
- DCont = control-flow dialect from WAMI (Kang/Desai/Jia/Lucia, arXiv:2506.16048,
  github.com/CMUAbstract/mlir-wasm-dialect): shift/reset-style ops lowering to SsaWasm/Wasm via
  the Wasm stack-switching proposal. Not upstream yet; pinned managed fork (see sec. 6).
  Upstreaming in progress (llvm/llvm-project PR #149233, WasmSSA); fork retires when a
  DCont-equivalent lands in-tree.

### TableGen single source of truth (dialect/Timbda.td)

- Ops: timbda.bind, .or, .fail, .return, .get, .put, .select, .match (region-based),
  .typeof (partial; verifier rejection = denotation empty).
- TimbdaRule records: one per paper rewrite rule (lhs dag, rhs dag, side conditions,
  class in {eval, match, delta, unify}, semName).
- ContextExtern records: symbol name, C++ decl, wasm shape, LLVM function-attribute dict,
  VeriFFI spec name; fixed annotation string "timbda.context_switch".
- Each record generates FIVE artifacts:
  1. MLIR dialect C++ + DRR rewriter (stock mlir-tblgen backends);
  2. Rocq: AST ctor, Rew relation ctor, per-rule soundness-lemma skeleton (new TableGen backend
     -gen-rocq-ast / -gen-rocq-rules / -gen-rocq-checker / -gen-externs);
  3. pdll lit-test skeleton;
  4. Gallina checker/evaluator hook;
  5. extern declarations on BOTH sides: llvm.func with attributes AND C++ shim header decl with
     __attribute__((annotate("timbda.context_switch"))) __attribute__((nocf_check)).
     Annotations are emitted from MLIR/TableGen, never handwritten.
- Optional generated bridge: Haskell rules for the augustss verse-semantics REPL (differential oracle).
- Annotation mechanism (confirmed): clang __attribute__((annotate)) -> @llvm.global.annotations
  -> Annotation2Metadata -> !annotation metadata; MLIR has llvm.intr.annotation + attribute-based
  metadata. LLVM "convergent" function attribute is LangRef's documented encoding for
  setjmp/longjmp-like re-enterable control — the correct marker for boost.context bindings.
  Attribute dict for context externs: convergent, nobuiltin, nocf_check, deliberately NO willreturn.

### Repo layout

    timbda/
    |- dialect/          Timbda.td; DCont/ (pinned fork subtree + patches/); conversion passes;
    |                    tblgen-rocq/ backend
    |- coq/              the Gallina kernel
    |  |- Syntax.v       inductive Expr/Pat/Ty (generated + hand-glued)
    |  |- Semantics.v    [[ _ ]] : Expr -> CTree unit Val  (ctrees; events Get/Put/Primop)
    |  |- Denotation.v   stdpp gsets candidate model; M-law equalities up to weak bisim
    |  |- Rewriting.v    Inductive Rew (one ctor per TimbdaRule record)
    |  |- Checks.v       determinacy checker + CompCert-style certified validator
    |  |- Eval.v         scheduler over CTree (explicit work queue, fair select)
    |  |- Lower.v        determinate fragments -> Clight; general -> CPS calls back into Eval
    |  |- Ffi.v          VeriFFI extern specs
    |  |- Compile.v      CertiRocq wiring; optional CompCert composition
    |- driver/           thin MLIR pass adapters (C++); M4 boost.context shim (generated)
    |- tests/            lit/ (pdll), coq-golden/, differential/ (shared generated corpus)
    |- wasm/             timbda -> DCont -> SsaWasm -> Wasm emission (WAMI pipeline)

## 3. Theorem targets

1. T1 Rule soundness (generated, one per TimbdaRule): Rew_r e e' -> Wbisim (sem e) (sem e')
   in the ctrees model. Licenses every DRR rewrite in MLIR.
2. T2 M-algebra: or commutative/idempotent/associative, fail as zero, monad laws
   (CTrees equational theory), mirroring the paper's candidate-set claims.
3. T3 delta-primop agreement: for each primop, Gallina primop_eval agrees with int63/Clight
   evaluation of the constant the delta-rule produces. The hinge of "straight C code" fidelity.
4. T4 Determinacy soundness: det_check e = true -> exists v s', sem e = ret (v, s')
   (single candidate, total, no control effects). Checker lives in Gallina (decision), so no
   MLIR-side pass is trusted; CompCert-style certified validator on the MLIR side.
5. T5 Out-of-order lemma: for independent fragments, Wbisim (sem (seq e1 e2)) (sem (seq e2 e1))
   and fold/reassociate laws under det_check hypotheses; divergence handled by weak bisimulation.
   Machine-checked version of "constant expressions, even out-of-order".
6. T6 Straight-line specialization: lower_det e = c -> Wbisim (sem e) (ClightSem c) against
   CompCert's Clight semantics (library dep — see sec. 4).
7. T7 No-context-call theorem: det_check e = true -> no_switch (lower e) — structural induction
   on the Gallina lowering function. The anti-naivety guarantee verbatim.
8. T8 Evaluator adequacy: eval_candidates e = candidate_set (sem e); the Gallina scheduler is
   strategy-complete (fair for select), incl. match-first as special case.
9. T9 End-to-end refinement: composition T6/T8 x CertiRocq (x optional CompCert): extracted C
   refines the Timbda-0 denotation; kernel ships as certified C linked into the thin C++ driver.
10. T10 Type discipline: MLIR verifier rejection <-> Rocq typing judgment;
    ill_typed e -> sem e = empty. Partial-type story mechanical on both sides.
11. T11 (Tier-3, opportunistic): beta/delta-subsystem confluence, determinate-fragment diamond.
    Faithfully stated conjectures; strengthens T5/T7 if proved; nothing gates on them.
12. T12 (M4, later): boost.context extern family implements its VeriFFI specification; generated
    dcont -> extern lowering is a refinement of shift/reset semantics in the model. The C++ fast
    path enters only as a theorem, never a contract.

## 4. Verification ledger (TCB)

- Proven span: Timbda-0 semantics -> Gallina kernel (rewrites, determinacy, lowering, evaluator)
  -> Clight. CertiRocq's Gallina->Clight proof is the last machine-checked link.
- Trusted-but-observed span: Clight -> clang -> machine. Deliberate choice: Clight is valid C
  compiled routinely by gcc/clang (CertiRocq docs recommend gcc; CompCert listed as the optional
  alternative). Clight expressions are pure (calls only as statements, fixed order) and Clight is
  UB-free by construction, so clang's UB-driven transforms have nothing to grab onto.
  "Observed" = Alive2/alivecc-class IR-level translation validation over clang's pipeline +
  binary-level differential testing + hardening flags below.
- CompCert = nice-to-have (decision): stays as a BUILD-TIME LIBRARY dependency regardless
  (Clight definitions + PrintClight are CompCert code; nixpkgs builds it with -clightgen).
  Invoking ccomp as a compiler is an optional, license-gated CI lane (INRIA non-commercial license).
- Boundary hazard: TBAA/strict aliasing at Clight->clang (generated C + CertiRocq runtime: val
  tagging, gc_stack, boxed/unboxed floats, pointer punning — CompCert's memory model has no TBAA,
  clang's does). Mitigation: "Clight-boundary hardening" copts group (-fno-strict-aliasing first;
  review -fno-strict-prototypes etc. against emitted shapes) applied BY RULE in Bazel to the TU
  group: generated code + CertiRocq runtime + VeriFFI glue. Order-sensitivity lives only at the
  extern/VeriFFI boundary — governed by T12-style contracts.
- Differential triangle (always on): Gallina-extracted evaluator <-> MLIR canonicalizer <->
  augustss Haskell REPL tester, on shared generated corpus.

## 5. Milestones

- M-1 (first action): build-infra skeleton, per sec. 0 + sec. 6.
- M0: semantics spike. Syntax.v, Semantics.v, Rewriting.v; T1 for ~12 core rules, T2; extracted
  evaluator + T8 draft; differential harness vs augustss REPL. Transcribe rules from the SPJ
  "Supporting Figures" paper (done: Figs. 6-18, lines 319-671, transcribed in docs/VERSE-RULES.md;
  the rewrite-rule pages 9-12 — unification, primops/delta, beta, iteration/choice — fed the
  M0 gate: 15 discharged T1 ctors + the br2 algebra, per-rule status in docs/RULES-AUDIT.md):
  cs.uoregon.edu/research/summerschool/summer26/_lectures/SPJ_Verse-figures.pdf.
  Timbda-0's ZF-flavored denotation ported predicatively in Rocq (stdpp gsets as candidate sets;
  universe stratification).
- M1: dialect + generator. Timbda.td, DRR rewriters, tblgen-rocq backend, pdll tests, paper-rule
  coverage audit (every paper rule => a record + an MLIR pattern + a Rocq ctor — the audit IS the
  completeness claim).
- M2: the non-naive leg. Checks.v (T4), T5, Lower.v for determinate fragments (T6, T7),
  CertiRocq->C; golden test: out-of-order constant-expression programs compile to straight-line C
  with zero switch sites, proved.
- M3: closed certified runtime. Full Gallina evaluator (T8, T9 e2e). Complete usable Timbda-0
  implementation with zero boost.context dependency.
- M4: performance/streaming path. dcont lowering + generated ContextExtern annotations + shim;
  T12. Skippable until demanded by profiling or reactive/streaming features.
- M5: WASM leg. timbda -> DCont -> SsaWasm -> Wasm (WAMI pipeline); optionally CertiRocq's
  WebAssembly target for the evaluator itself.

## 6. Build infrastructure (stipulated + confirmed)

Shape: one Nix flake, two graphs, one generated interface. Nix = provisioner + formalization build
+ checks; Bazel = C++ orchestrator. They meet only at generated artifacts (timbda.td -> dialect
C++/DRR on the Bazel side; -gen-rocq output on the Nix side) plus a version-consistency check.
Distinct trusted roots by design; do not make one graph build the other's artifacts.

### C++ side (Bazel + hermetic-llvm)

- Bazel from nixpkgs (8.5+ recommended; >=7.7 required by hermetic-llvm).
- hermetic-llvm via BCR: bazel_dep(name="llvm", version="0.8.27") (hermeticbuild/hermetic-llvm;
  zero-sysroot hermetic cross toolchains: linux gnu/musl x86_64/aarch64/riscv64/s390x/armv7,
  macOS, windows gnu/msvc, bpf, wasm32/wasm64-unknown-unknown; sanitizers; remote exec).
  Also provides "Bazeled LLVM targets" (compiler-rt, libc++, libc++abi, libunwind, sanitizers).
  Fallback: bazel-contrib/toolchains_llvm (has wasm32 platforms).
- LLVM/MLIR under Bazel via in-tree overlay llvm/utils/bazel (peripheral tier LP-0002 — actively
  patched through late 2026 incl. MLIR BUILD fixes; use HEAD pins, not release tags).
- Pin the llvm-project source commit to the DCont fork's expected MLIR API:
  git_override(module_name="llvm_project", commit="<pinned>").
- DCont git machinery (managed fork, 3 layers):
  1. dcont/ subtree from our own fork of CMUAbstract/mlir-wasm-dialect (we must fork: timbda->DCont
     conversion passes + a native lowering leg they don't have);
  2. patches/ kept tiny: bazel-ification patch (their include/WAMI, lib/WAMI, include/wasmstack
     layout is clean dialect+pass dirs; wrapping in BUILD.bazel against the llvm overlay is
     day-scale) + timbda hooks;
  3. nightly CI drift check reapplying the patch series onto their upstream main, non-blocking.
  Retirement: when Wasm/DCont dialects upstream (WasmSSA PR #149233), fork dissolves into a pinned
  llvm-project commit; only our conversion passes remain out-of-tree.
- boost.context: vendor the minimal context closure (context + dep set) as a pinned http_archive,
  not full Boost; select()-excluded on wasm targets (WASI libc supplies the C runtime there).
  Note: boost::context::continuation is move-only, no cheap cloning — shared/forked search trees
  need trampolining/CPS sharing/work queues (this is ALSO why the Gallina evaluator is primary).
- Target matrix: hermetic-llvm targets INTERSECT boost.context fcontext support
  (x86_64/aarch64/riscv64 on unix-likes). Certified-e2e checks on x86_64-linux-gnu +
  aarch64-linux-gnu first; musl is static-only in hermetic-llvm — probe boost.context there before
  promising it; wasm32 = bazel cross + pinned wasmtime (record WAMI stack-switching engine flags /
  Wizard-engine config in check scripts). Optional ccomp lane pinned to CompCert targets
  (x86_64/aarch64/riscv64-linux), license-gated.

### Formalization side (Nix-native Rocq; opam secondary)

- nixpkgs rocqPackages + mkRocqDerivation (coqPackages merging into it). DevShell via
  rocq.withPackages (ps: [ctrees stdpp equations certirocq compcert ... kernel]) with
  rocq-lsp / vsrocq-language-server INSIDE the same withPackages call (separate installs won't see
  the packages).
- Packaged in nixpkgs: compcert (3.17 for the Rocq 8.15-9.1 window; external Flocq/MenhirLib;
  -clightgen; wrapped ccomp; per-arch target selection), stdpp (1.12.0 for 8.19-9.1), equations,
  flocq, MenhirLib. Verify interaction-trees/extlib packaging status on first flake write.
- NOT packaged -> local pkgs/rocq/ derivations via mkRocqDerivation on pinned flake inputs:
  ctrees (vellvm/ctrees; Rocq 9.0 compat; deps InteractionTrees, Equations, Coinduction,
  RelationAlgebra, Extlib; namespace CTree), CertiRocq (ship its C runtime — gc_stack.o, FFI glue
  — as a package output so the driver links exactly the certified runtime blob), VeriFFI
  (CertiRocq/VeriFFI).
- Pin matrix (lock day one; single generated table consumed by MODULE.bazel, flake inputs, and a
  printed pins.toml): rocq 9.0/9.1 x compcert 3.17+ x stdpp 1.12 x ctrees pinned rev x
  interaction-trees/equations/coinduction/RelationAlgebra/extlib revs x verse-semantics (Haskell)
  rev x llvm-project commit x hermetic-llvm BCR version x dcont fork rev x bazel version x ghc version.
- OPAM: an opam switch available in the Rocq devShell for editor/ocaml-ecosystem convenience,
  generated FROM the same pin table, never the reverse. Nix is the source of truth.

### Haskell side

- augustss/verse-semantics pinned via fetchFromGitHub; build with nixpkgs Haskell infra
  (cabal2nix or haskell-flake cabalProject). Expose the tester and repl binaries as flake packages.
- The golden triangle is a FLAKE CHECK, not a shell habit: tests/differential/<corpus> (generated
  from the .td records) runs against (a) the Gallina-extracted evaluator, (b) the bazel-built
  timbda-canonicalize binary, (c) the Haskell tester; assert candidate-set equality. It is the only
  place all three ecosystems touch at runtime — keep it small and paranoid.

### Flake outputs (sketch)

    inputs:    nixpkgs, haskell deps, dcont-fork, ctrees, certirocq, veriffi, verse-semantics
               (compcert/stdpp from nixpkgs)
    packages:  timbda-kernel(coq) | certirocq+runtime | verse-semantics |
               bazel-built driver binaries (bazel builds, nix checks consume as prebuilt)
    devShells: cpp(bazel + repo tooling) | rocq(withPackages + lsp) | hs(ghc+cabal)
               | all(+wasmtime, llvm-lit, clang-format)
    checks:    coq-kernel-tests . bazel-{native,wasm32-cross}-tests . tblgen-rocq-golden .
               dialect-lit-tests . differential-triangle . certirocq-e2e (Gallina->Clight->clang->run) .
               version-consistency (pin table <-> MODULE.bazel <-> flake.lock) .
               [license-gated] ccomp-lane rerun

- version-consistency check is mandatory: any PR touching a compiler-adjacent pin must touch the
  pin table; CI asserts table == MODULE.bazel == flake.lock.

## 7. Watch-outs (ranked)

1. MLIR API drift vs DCont fork: fork <-> our dialect <-> llvm-project commit must share ONE MLIR
   API vintage; hermetic-llvm moves fast (0.8.x weekly-ish). Pin aggressively; update in deliberate
   batches. (Resolves first: pre-M-1 probe.)
2. LLVM peripheral-tier Bazel upkeep (LP-0002): breakage lands on us first; budget maintenance.
3. TBAA at the Clight->clang boundary (see sec. 4 hardening copts).
4. wasmtime stack-switching version/flag pinning (record engine config per WAMI harness).
5. musl: static-only toolchain in hermetic-llvm; boost.context probe required before commitment.
6. CompCert: at the tail; optional license-gated lane only.

## 8. Decision log (also in Strata, tag "timbda")

1. Scope: Timbda-0 only; DCont control-flow (WAMI, git-only pinned fork); ultimate lowering to
   LLVM; WASI/WASM stack-switching as WASM-side equivalent of boost.context; Rocq + ctrees +
   extlib + stdpp semantics; CertiRocq-verified Gallina->C backing the C++; boost::context
   implements (later) native control flow; annotations emitted from MLIR/TableGen source, never
   handwritten; no Isabelle/Lean; practical framing, prove non-naive out-of-order reduction to
   straight C without unnecessary context switches.
2. "Prove over runtime contract" principle => determinacy analysis in the Gallina kernel; strategy
   execution = Gallina evaluator; boost.context demoted to provably-mapped M4 optimization;
   Tier-3 conjectures non-blocking; formalization calibrated to the papers (Tier 1/2/3).
3. Build infra: one flake, two graphs; Bazel + hermetic-llvm (BCR "llvm" 0.8.x) + LLVM in-tree
   bazel overlay; DCont pinned fork + tiny patch series + drift CI; nixpkgs rocqPackages primary,
   local mkRocqDerivation for unpinned libs, opam secondary (generated from pin table); pinned
   Haskell verse-semantics; mandatory version-consistency check; target matrix
   hermetic-llvm INTERSECT boost.context.
4. CompCert demoted to nice-to-have: guarantee ledger = proven up to Clight, clang trusted-but-
   observed; TBAA hazard + hardening copts; CompCert remains a build-time library dep; ccomp lane
   optional and license-gated.
5. (This file) Commit to M-1 skeleton-first: flake.nix + MODULE.bazel + pin table + consistency CI,
   ~300 lines, both graphs green, before any C++/Rocq code.

## 9. Known reference anchors

- Verse papers: simon.peytonjones.org/oplss-26/ ; OPLSS authoritative lecture PDFs at
  cs.uoregon.edu/research/summerschool/summer26/_lectures/ : SPJ_lecture{1..4}_Notes.pdf (fully
  read), SPJ_Verse-figures.pdf (24 pp.; pages 9-12 — the rewrite rules — still unread: first
  transcription target), SCW_Verse.pdf (47 pp.; derived material, de-emphasized).
- Prototype/oracle: github.com/augustss/verse-semantics (Haskell repl + tester; :set match-first,
  :set trace).
- DCont/WAMI: arXiv:2506.16048 ; github.com/CMUAbstract/mlir-wasm-dialect ; upstreaming PR
  llvm/llvm-project#149233 (WasmSSA) ; github.com/WebAssembly/stack-switching ;
  component-model Concurrency.md (WASI 0.3 async ABI).
- ctrees: github.com/vellvm/ctrees (Choice Trees; Rocq 9.0; MIT; weak bisimulation theory).
- CertiRocq: certicoq.org ; github.com/CertiRocq/certirocq (Gallina->Clight AND WebAssembly;
  docs recommend gcc for emitted C; CompCert optional) ; github.com/CertiRocq/VeriFFI.
- LLVM annotations: LangRef "convergent" (setjmp/longjmp encoding); clang annotate ->
  @llvm.global.annotations -> Annotation2Metadata -> !annotation; MLIR llvm.intr.annotation.
- hermetic-llvm: github.com/hermeticbuild/hermetic-llvm ; BCR module "llvm" v0.8.27.
- LLVM Bazel: llvm/llvm-project utils/bazel (LP-0002 peripheral tier).
- Alive2: github.com/AliveToolkit/alive2 (alive-tv, alivecc/alive++, alive-exec; no
  interprocedural transforms).
- Reference-only context: First-Class Verification Dialects for MLIR (PLDI'25,
  www2.cs.utah.edu/~regehr/papers/pldi25.pdf).

## 10. Retrieval in future sessions

- This file (docs/PLAN.md in the timbda repo, at ~/timbda) is the authoritative recapitulation;
  read it first in any new session on this project. Repo home: ~/timbda (git branch main, with a
  jj overlay; jj tracks the git default bookmark). The OpenCode session plan directory
  (.opencode/plan/, gitignored) holds only a pointer stub to this file.
- Strata memory holds the same decisions as individual records; search with tag "timbda" via
  /recall or find_solutions, and check /strata-status / get_project_context at session start.
- After each significant decision or fix, store a new Strata record per the project AGENTS.md so
  the ledger stays current between sessions.

## 11. Prior-art audit and claim boundaries (added 2026-11-16; full audit = first week of M0)

Discovered prior art (cite and differentiate; verify marked items during the M0 audit):

- Verse Calculus (VC), ICFP'23 (Augustsson, Breitner, Claessen, Jhala, Peyton Jones, Shivers,
  Steele, Sweeney): rewrite semantics for deterministic functional logic; confluence PROVEN for
  well-behaved terms (hand proof, extended-version Appendix C); evaluation strategies explicitly
  NOT formalized (sec. 3.7); "choices laid out in space, not in time" — search-as-data is VC's own
  design thesis, not our invention. VC != Timbda-0: Timbda-0 is the OPLSS'26 ZF-denotation line,
  whose full paper SPJ repeatedly calls "the subject of another paper" (still unpublished).
- github.com/sweirich/lambda-calculus (Weirich; MIT; ~77 commits; README verified 2026-11-16): Coq
  mechanizations of lambda calculus + "extensions for the verse programming language":
  verse/syntax.v (well-scoped de Bruijn via autosubst), verse/icfp.v (equational theory explicitly
  "based on ICFP reduction rules" = VC-era), stepverse/ (denotations as sets of values / sets of
  LABELED RESULTS), graphverse/ (graph-model semantics + consistency/continuity/substitution
  theories), structures/ (Sets, Monad, FSet, NFSet libraries). "First mechanization of Verse
  semantics" is NOT ours. Her mechanized artifacts target VC-era (ICFP reduction-rule) semantics —
  read them before weighing our claim 2: the stepverse/ labeled-result and graphverse/ graph-model
  lines are adjacent to candidate sets. Her well-scoped de Bruijn / autosubst idiom is the right
  idiom; `coq/Syntax.v` borrows it.
- github.com/rudi-cilibrasi/openverse (created 2026-11-04, active): unofficial Verse runtime;
  Verse semantics defined and proved in Lean 4; C runtime checked against it (integer arithmetic,
  program loading, rollback proved via QuickProof [VST + CompCert]; object store/value heap by
  differential testing + fuzzing). Repo also lists Rocq sources — watch what they mechanize in
  Rocq. "First verified Verse implementation/runtime" is NOT ours.
- CompCertFX (Bayazit, Ebresafe, Xie — U Toronto; preprint 2025/26): first VERIFIED COMPILER for
  effect handlers — CompCert extended with one-shot handlers, proved in Rocq down to stack
  switching in AArch64 assembly; new IRs MachSwitched1/2; repaired CompCert invariants (stack
  disjointness, value analysis under non-local control). "Verified compilation to stack switching"
  is NOT ours; they verify the correctness OF switching; our distinct claim is its licensed use
  (T12) and provable ABSENCE for determinate fragments of a natively nondeterministic source (T7).
- Iris-WasmFX (PLDI 2026): mechanisation of the WasmFX/Wasm stack-switching proposal in Iris
  (WasmFXCert) + modular reasoning — adjacent to our WASM leg; possible anchor for pinning DCont
  op semantics (M5).
- Compiling with continuations, correctly (ICFP'21, CertiCoq L6 CPS proof): verified CPS via
  step-indexed logical relations — precedent for verified continuations in the Gallina chain.
- Bahr, Calculating Certified Compilers for Non-Deterministic Languages: Coq framework for
  soundness+completeness of nondeterministic-language compilers — precedent for T8/T9 shape.
- Antoy & Jost, The Fair Scheme (LOPS'13): deterministic compilation strategy for functional-logic
  rewriting with hand proofs of correctness AND optimality — closest FLP precedent for T5/T8;
  unmechanized, no machine-control layer. Cite.
- Omnisemantics (MIT PLV): set-of-outcomes Coq semantics; forward compiler-correctness proofs for
  nondeterminism — vocabulary precedent for Denotation.v.
- github.com/paul-snively/verse (2022-23, project owner's own prior work): Coq experiments on VC;
  conjecture that VC uses the "LOW" reduction strategy (Biernacka et al., ICFP'22 Zoo of strategies)
  and ambition to prove confluence. Personal intellectual lineage; this project is the machinery
  that can finally answer it.

Claim boundaries — legitimately ours (paper-defensible phrasing):
1. Verified SPECIALIZATION of a search language: a certified Gallina kernel for Verse-lineage
   semantics whose specialization theorems (out-of-order soundness T5, straight-line Clight
   adequacy T6, no-context-call T7) machine-check "non-naive", with machine control effects
   permitted only where a theorem licenses them (T12). No verified pipeline for a natively
   nondeterministic (functional-logic) language carries such reordering/specialization/
   effect-freeness theorems; CompCertFX verifies stack switching as the handler mechanism, not
   its provable absence from determinate fragments; Fair Scheme proves strategy correctness by
   hand only, unmechanized.
2. First mechanization of TIMBDA-0 proper (the OPLSS'26 candidate-set denotation, paper still
   unwritten) incl. the ctrees weak-bisimulation bridge to candidate-set equality; plus
   mechanizing what the papers explicitly leave unformalized: evaluation-strategy adequacy (VC
   sec. 3.7) and mechanized diamonds/confluence for restricted classes (VC's confluence proof is
   hand-written). Time-sensitive: the Verse team's own denotational paper is forthcoming.
3. Method: one TimbdaRule/ContextExtern record table generating BOTH halves of the pipeline —
   DRR passes, Rocq Rew constructors + soundness skeletons, pdll tests, and FFI/annotation
   emission (convergent etc.) — with an auditable paper-rule coverage claim; and a proven Gallina
   kernel lowered to two control models (native C via CertiRocq+clang; Wasm via DCont/stack
   switching). Related (verify): Pottier's verified-rewriting-engine case study; CompCert validated
   checkers; Rhino (generated verified rewriting engines).

NOT claimable: inventing search-as-data (VC's thesis); Gallina->C compilation (CertiCoq/CertiRocq);
verified compilation to stack switching (CompCertFX, Iris-WasmFX); a verified Verse runtime
(openverse); verified rewriting engines in general; differential-testing method generally.

Standing watch-items: openverse's proof scope and any Rocq activity in it; the Verse team's
forthcoming denotational-semantics paper — if the Verse team mechanizes Timbda-0 alongside it,
claim 2 narrows to evaluation-strategy adequacy plus the compilation half: a complementary
division of labor rather than a collision; CompCertFX publication status; Rhino citation check.
Claims become real only when the M0-M3 artifacts exist; until then this is a well-positioned
proposal.
