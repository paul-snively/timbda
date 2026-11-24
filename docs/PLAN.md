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
            +----------> C objects <---- thin C++ driver; extern-region boundary;
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
  VeriFFI spec name (generated into the `Ffi.v` carrier; monitors CI-lane only — § 4 boundary
  policy); fixed annotation string "timbda.context_switch".
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
    |  |- Semantics.v    denote : Expr -> nat -> ctree void1 B2 SResult  (ctrees; the events
    |  |                 Get/Put/Primop signature arrives with the M2/M3 block-slot layer)
    |  |- Denotation.v   candidate model = ctrees br2 branching; RewSound_* + the br2 algebra,
    |  |                 stated up to weak bisim (carrier decision: sec. 5 + DESIGN-NOTES § 7)
    |  |- Rewriting.v    Inductive Rew (one ctor per TimbdaRule record)
    |  |- Checks.v       determinacy checker + CompCert-style certified validator
    |  |- Eval.v         head-redex table + fuel-bounded norm (Gallina corner of the differential
    |  |                 triangle); the fair work-queue scheduler is the M2/M3 step
    |  |- Lower.v        determinate fragments -> Clight; general -> CPS calls back into Eval
    |  |- Ffi.v          extern specs: T12 proof carrier + CI monitor lane
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
   One obligation is already open and unclosed, and it is recorded rather than assumed: integer
   division.  The kernel floors (`Z.div`, `(-7)/2 = -4`) and agrees there with the pinned Haskell
   oracle (`Red.hs:1346-1347`: `j /= 0` then `i \`div\` j`; `Core/Expr.hs:623`/`645-647` make
   "divisor nonzero" a *precondition* even though `primOpCanFail Div = False`), but the C++ side's
   rounding was never verified - no C++ runtime source (`Value.h`) exists in this repo, its bazel
   externals, or on this host - so the C++ lowering is a T3 obligation to be discharged against real
   upstream source, not a measured fact (`docs/VERSE-RULES.md` § 3 DEV-5, tools/corpus/README.md § 6).
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
8. T8 Evaluator adequacy: candidate_set (eval_run e) = candidate_set (sem e), where the candidate
   model is ctrees `br2` branching and `=` is weak bisimilarity — i.e. Wbisim (denote (Eval.norm
   fuel e) f') (denote e f) under the uniform-fuel accounting of coq/Denotation.v.  The Gallina
   scheduler is strategy-complete (fair for select), incl. match-first as special case.
9. T9 End-to-end refinement: composition T6/T8 x CertiRocq (x optional CompCert): extracted C
   refines the Timbda-0 denotation; kernel ships as certified C linked into the thin C++ driver.
10. T10 Type discipline: MLIR verifier rejection <-> Rocq typing judgment;
    ill_typed e -> sem e = empty. Partial-type story mechanical on both sides.
11. T11 (Tier-3, opportunistic): beta/delta-subsystem confluence, determinate-fragment diamond.
    Faithfully stated conjectures; strengthens T5/T7 if proved; nothing gates on them.
12. T12 (M4, later): boost.context extern family implements its VeriFFI specification; generated
    dcont -> extern lowering is a refinement of shift/reset semantics in the model. The C++ fast
    path enters only as a theorem, never a contract. The proof is static; shipping carries no
    monitors (§ 4 boundary policy) — monitors police the CI build of the extern region.

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
  group: generated code + CertiRocq runtime + VeriFFI glue (CI-build TUs only — the shipped group
  carries no VeriFFI runtime, § 4 boundary policy). Order-sensitivity lives only at the extern
  region — governed by T12-class contracts (§ 4 boundary policy: the extern region carries no
  shipped monitors).
- Extern-monitor boundary policy (decision, 2026-11-21). VeriFFI's runtime monitors are not
  shipped. The distinction that decides it: VeriFFI's *specs* are load-bearing — they give externs
  denotations in the same universe as the kernel model, and they are the thing a T12-class proof
  proves *implementation* of; VeriFFI's *monitors* are enforcement, and enforcement is needed only
  where no proof reaches — hand-written C++. In this design the extern region is closed by
  construction: shims are generated (TableGen emits both sides' declarations and annotations), the
  only non-generated code in the region is pinned library code (`boost.context`, a pinned rev), and
  `Ffi.v` carries the specs. Coverage for the residual: the static layer (spec + T12-class proof +
  attribute machinery: `convergent`, `nobuiltin`, `nocf_check`, annotation chain), pinning, and CI
  empiricism — a monitor-enabled VeriFFI build of the extern region runs in the CI lane over the
  shared generated corpus. Shipping monitors fail the project's own runtime-cost bar on three
  counts: they police the only region where the proofs already reach (M4's context-switch family —
  the fast path); they are the state-tracking class of monitor, not cheap argument checks; and they
  tax the very optimization whose "provably-mapped, never a bare contract" rule they sit under. The
  reversibility asymmetry decides the rest: re-enabling shipping monitors is one generated flag
  away if a named threat model ever appears (externs outside the pinned+generated+proven set);
  shipping them "just in case" is permanent cost with no named threat. The weighed-and-declined
  counter-case (third-party C misbehaving in the field): at a pinned rev that case is inside the
  T12 obligation's scope — a `boost.context` bug is a library-correctness failure upstream of this
  ledger's scope, and no named threat at this boundary justifies the cost. Shipping extern
  overhead: zero. CertiRocq's own runtime (gc_stack.o, link glue, malloc/free calls) remains the
  certified-baseline cost and is not part of this removal — the certified baseline is deliberately
  the naive-but-proved leg; the non-naive leg (T5/T7/T9) is where overhead must survive this bar.
- Differential triangle (always on): Gallina-extracted evaluator <-> MLIR canonicalizer <->
  augustss Haskell REPL tester, on shared generated corpus. A monitor-enabled VeriFFI build runs
  over the same corpus in CI: the extern boundary is checked by spec + proof + monitor +
  differential — the monitor living in CI, not in the shipped binary.

## 5. Milestones

- M-1 (first action): build-infra skeleton, per sec. 0 + sec. 6.
- M0: semantics spike. Syntax.v, Semantics.v, Rewriting.v; T1 for ~12 core rules, T2; extracted
  evaluator + T8 draft; differential harness vs augustss REPL. Transcribe rules from the SPJ
  "Supporting Figures" paper (done: Figs. 6-18, lines 319-671, transcribed in docs/VERSE-RULES.md;
  the rewrite-rule pages 9-12 — unification, primops/delta, beta, iteration/choice — fed the
  M0 gate: 15 discharged T1 ctors + the br2 algebra, per-rule status in docs/RULES-AUDIT.md):
  cs.uoregon.edu/research/summerschool/summer26/_lectures/SPJ_Verse-figures.pdf.
  Timbda-0's ZF-flavored denotation ported predicatively in Rocq: the candidate-set model is the
  ctrees `br2` branching read up to weak bisimilarity — the free commutative-idempotent-monad
  reading of the paper's "or", all inside `Type` with no Set/Type jump.  The "stdpp gsets"
  formulation was probed and dropped on 2026-11-18: `gset` needs `Countable`/`EqDecision` for the
  kernel's own mutual Val/Expr (instance search fails out of the box) and drags Stdlib `Bool`,
  which clashes with the ctrees notation table.  Evidence: docs/DESIGN-NOTES.md § 7.
  The differential half of M0 is a build gate, not a plan (measured 2026-11-19): one spec file
  `tests/corpus/m0.texpr` — 64 cases, every expectation derived by hand from docs/VERSE-RULES.md
  *before* looking at what the evaluator produces, 7 of them also asserting a candidate bag — is read
  independently by two corners.  `tools/corpus/corpus.py` emits 135 Coq `reflexivity` assertions about
  Gallina `Eval.norm` / `head_redex` / `cand_bag` (one `head` and one `norm` per case plus one per
  candidate-bag claim, 421 lines of generated `.v`, all discharged by `rocq`); `tools/corpus/driver.ml`
  parses the same file a second time with its own reader and runs the OCaml that `Extraction` produced
  from those same Gallina functions (`tools/extract/extract.v` → 1465 lines, `Print Assumptions` =
  closed under the global context for all four extracted names).  `checks.corpus-differential`
  cross-checks them: both corners must accept every case, both must report the same case *and*
  candidate-bag counts, and anti-vacuity guards (non-empty corpus, non-trivial generated corner,
  non-truncated extraction, and each corner asserting its own recorded exit codes) keep a green build
  from meaning "nothing ran".  It paid for itself on the first run: `dotdot[1,3]` materialised as
  `⟨1,2⟩` because `Syntax.v`'s `seq_z` guarded on `Z.ltb`, while paper line 459 and the pinned oracle
  (`Red.hs:1384`, `i <- [l..h]`) are inclusive — the guard is now `Z.leb`, pinned by three
  `KernelTest.v` examples.  M0's closing step selected the Fig. 8 rows (`R_Subst`, `R_PromoteL`,
  `R_PromoteR` via `Eval.v`'s `body_walk`; `Gc1` deliberately not selected), which is what makes the
  decision-3 divergence reachable instead of latent (docs/RULES-AUDIT.md § 3 C1, docs/DESIGN-NOTES.md
  § 9).  All harness scaffolding stays in `tools/` + `tests/`, so the kernel gate (zero `Admitted`,
  exactly one axiom) is untouched by it.  Details: tools/corpus/README.md, docs/DESIGN-NOTES.md § 8.
  Build memory is a build-infrastructure fact, not an aside: `coq/dune-workspace` pins `(jobs 2)` and
  `tools/build/coq-build.sh` runs the build inside a verified cgroup envelope with an artifact check
  (docs/DESIGN-NOTES.md § 4.2).
- M1: dialect + generator. Timbda.td, DRR rewriters, tblgen-rocq backend, pdll tests, paper-rule
  coverage audit (every paper rule => a record + an MLIR pattern + a Rocq ctor — the audit IS the
  completeness claim).
- M2: the non-naive leg. Checks.v (T4), T5, Lower.v for determinate fragments (T6, T7),
  CertiRocq->C; golden test: out-of-order constant-expression programs compile to straight-line C
  with zero switch sites, proved.  *Status 2026-11-22:* M2's gate corpus `tests/corpus/m2-det.texpr`
  (29 claims, hand-derived 2026-11-21 per decision 6, wired to `checks.corpus-m2-differential`) has
  been executed through both corners: green at 29 cases / 7 candidate bags, with the m0 pair
  re-attested unchanged (64 / 7).  27 of the 29 claims held exactly as derived; the two that failed
  were Group D block-collapse claims, wrong on the claim side, and are amended from the rule text
  rather than from engine output (docs/DESIGN-NOTES.md § 11, tests/corpus/README.md § 8).  What the
  run fixed for the machinery ahead: T4's sem-side and eval-side legs are separately pinned (the
  evaluator's shape for a slot-independent closed block is a *partial* one), and T5's witnesses are
  the amended mirrored partial-shape pair.  *Status 2026-11-23:* both T4 legs are discharged -
  `T4_sem` in `coq/Checks.v` (`det_check e = true -> exists v, denote e (e_fuel e + k) ≈ sret (SOk v)`,
  the kernel's own `equ` witness transported to `≈`) and `T4_eval` in `coq/ChecksEval.v` (`det_check e
  = true -> cand_bag (norm fuel e) = norm fuel e :: nil`, assembled from `head_redex_det` /
  `norm_det` / `cand_bag_single`; the two modules are one theory, split for a measured build-cost
  reason - docs/DESIGN-NOTES.md § 12.1) - and `coq/tests/ChecksTest.v` mirrors all 29 corpus verdicts at the Gallina level
  (17 accept / 12 reject, the corpus's own tally, written from decision 8 and untouched by what the
  checker returned) together with the nine `norm` pins and all seven candidate bags, the five accepted
  ones proved *through* `T4_eval`.  `Print Assumptions T4_eval` is `Closed under the global context`;
  `T4_sem` inherits the single `eq_rect_eq` the ctrees machinery contributes (docs/DESIGN-NOTES.md § 12).
  The recorded M1-side build TODO (docs/DESIGN-NOTES.md § 4.3) is closed in the same step:
  `Denotation.v`'s `t1_norm`/`t1_fold` retactored to a root-peeling `rewrite` loop over a kernel-`sret`
  bridge lemma, cold compile 708 s / 11.2 GiB down to 181 s / 1.9 GiB, statements and axiom audit
  untouched (docs/DESIGN-NOTES.md § 12.2).
  *Status 2026-11-24:* M2's stability corollary `T4_value_unique` (`coq/Checks.v`, after `T4_sem`)
  pins what the fuel index does and does not buy: at a fixed fuel an accepted term has at most one
  value - with `T4_sem`'s existence, exactly one - while the cross-fuel statement needs the recorded
  `denE_total_pairwise` strengthening, not a setoid chain.  docs/DESIGN-NOTES.md § 13 records the
  fuel-vs-coinduction taxonomy and T5's route as the kernel's first explicit coinductive proof
  (coq-coinduction `coinduction` tactic / ctrees' up-to-bind `bind_chain_gen`, witnessed by the
  § 11.3 mirrored partial-shape pair).
  What M2 still owes: T5, `Lower.v` for determinate fragments (T6, T7), and the golden test.
- M3: closed certified runtime. Full Gallina evaluator (T8, T9 e2e). Complete usable Timbda-0
  implementation with zero boost.context dependency.
- M4: performance/streaming path. dcont lowering + generated ContextExtern annotations + shim;
  T12 (static; shipping monitor-free per § 4 boundary policy). Skippable until demanded by
  profiling or reactive/streaming features.
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

- nixpkgs-provided formal deps (namespace `rocqPackages`, with legacy `coqPackages` for what has not
  merged yet) at the pinned nixpkgs `b349185b…`: `rocq-core` 9.1.1, `stdlib` 9.0.0,
  `relation-algebra` 1.8.0, `equations` 1.3.1+9.1 (legacy namespace only), `stdpp` 1.13.0,
  `compcert` 3.17 (license-gated, built only when the C leg starts).  `rocqPackages` provides no
  ctrees / interaction-trees / coq-ext-lib / paco at all, and coinduction's `master` branch needs
  rocq ≥ 9.2 — so the kernel's own dependency cone cannot come from nixpkgs alone.
- Built in the flake from the locked inputs, in `flake.nix`'s `coqStack`/`mkRocqLib` (each exported
  as `.#timbda-<lib>`, and each with a setup hook that mirrors rocq's ROCQPATH into dune's COQPATH):
  coq-ext-lib 0.13.0-dev, coq-paco 4.4-dev, rocq-coinduction 1.21 (tag `v1.21`; master needs rocq
  ≥ 9.2), coq-itree 5.2.1-dev, rocq-ctree 2.0-dev.  Two upstream quirks patched: extlib's
  dune-project declares `using coq 0.8` (retargeted to 0.7), paco's Makefile invokes the retired
  `coq_makefile` (`rocq makefile -f`).  CertiRocq remains unpinned-until-needed (M2/M3: ship its
  C runtime — gc_stack.o, link glue — as package outputs).  VeriFFI's runtime pieces (monitors and
  their link glue) enter the CI lane only — § 4 boundary policy; no shipped VeriFFI overhead, and
  M2/M3 shipping runtime contains no VeriFFI component (M3's certified runtime is CertiRocq +
  Gallina only, consistent with its zero-switch design; the amendment fixes an earlier mis-bundling
  of "VeriFFI glue" into the M2/M3 shipped-runtime list). Pins stay: the CI lane uses them.
- Coq-mode dune 3.21.1 also comes from nixpkgs.  `coq/dune-project` pins `using coq 0.7`, and CI
  keeps every Coq-mode stanza in the repo on that version (coq lang ≥ 0.8 compiles with `coqc -boot`,
  which drops the Stdlib package from the loadpath — DESIGN-NOTES § 5).
- `stdpp` 1.13.0 is pinned but deliberately **not** in `rocqDeps`: nothing in `coq/` imports it, and
  the pinned ctrees rev references `stdpp` zero times (`theories/` included).  It stays pinned
  because the M2/M3 candidate-bag layer may want a finite-set carrier, and because the carrier probe
  (DESIGN-NOTES § 7) measured exactly what importing stdpp would cost — `Countable` over the kernel's
  mutual Val/Expr, and a `Bool` × ctrees notation collision.  A pin no build consumes has to carry
  that reason in pins.toml, which it now does.
- DevShell (`nix develop .#rocq`, and `.#all` for the cross-stack shell): `rocqDeps` + coq-mode dune
  + the `rocq c`/`rocq dep`/`rocq doc` shims + ocaml/findlib (for the coinduction findlib plugin) +
  vsrocq-language-server, with `COQPATH` mirrored from `ROCQPATH`.
- Pin matrix (single table of record `tools/pins/pins.toml`; `tools/pins/pins.py check` asserts
  pins.toml == MODULE.bazel == .bazelversion == flake inputs == flake.lock, and
  `checks.version-consistency` asserts pins.toml == the nixpkgs attribute versions): rocq 9.1.1 x
  compcert 3.17 x stdpp 1.13.0 x equations 1.3.1+9.1 x stdlib 9.0.0 x relation-algebra 1.8.0 x
  ctrees/interaction-trees/coinduction/extlib/paco pinned revs x verse-semantics rev x llvm-project
  commit x hermetic-llvm BCR version x dcont fork rev x bazel 9.3.2 x ghc 9.12.3 x dune 3.21.1 x
  ocaml-for-rocq 4.14.4.
- OPAM: an opam switch available in the Rocq devShell for editor/ocaml-ecosystem convenience,
  generated FROM the same pin table, never the reverse. Nix is the source of truth.
  Host contract (clarified 2026-11-18, closed same day): the host provides **nix alone** — Rocq,
  Python 3, GHC, Bazel all come from the flake. The DEV-3 gap (docs/DESIGN-NOTES.md sec. 4) is shut:
  flake.nix builds extlib/paco/coinduction/interaction-trees/ctrees from the locked inputs, so
  `cd coq && dune build` runs inside `nix develop .#rocq` and no host opam switch is load-bearing.
  Any convenience switch an editor wants must be generated *inside* the devShell from pins.toml.

### Haskell side

- augustss/verse-semantics pinned via fetchFromGitHub; build with nixpkgs Haskell infra
  (cabal2nix or haskell-flake cabalProject). Expose the tester and repl binaries as flake packages.
- The golden triangle is a FLAKE CHECK, not a shell habit: tests/differential/<corpus> (generated
  from the .td records) runs against (a) the Gallina-extracted evaluator, (b) the bazel-built
  timbda-canonicalize binary, (c) the Haskell tester; assert candidate-set equality — a bag
  comparison on the harness side, whose Coq-side reading is Wbisim over br2 (sec. 3.8). It is the
  only place all three ecosystems touch at runtime — keep it small and paranoid.
- Two of those three legs already exist as `packages.timbda-corpus-coq-corner` +
  `packages.timbda-corpus-ocaml-corner`, gated by `checks.corpus-differential` (sec. 5 M0). The
  corpus lives at `tests/corpus/m0.texpr` and is deliberately *hand*-derived so that a corner
  disagreement is evidence about the kernel rather than about the harness. The augustss `tester`
  leg joins as the third corner at M3 rather than now: its cabal dependency set
  (megaparsec, mtl, optparse-applicative, scientific, containers, …) is a build-infra project of
  its own, and until it is in place the pinned oracle is consulted by hand, case by case — as it
  was for the `dotdot` range (Red.hs:1384 + its `tests.versetest` cases) and for `Div` rounding
  (Red.hs:1347).

### Flake outputs (sketch)

    inputs:    nixpkgs, haskell deps, dcont-fork, ctrees, certirocq, veriffi, verse-semantics
               (compcert/stdpp from nixpkgs)
    packages:  timbda-kernel(coq) | timbda-corpus-{coq,ocaml}-corner | certirocq+runtime |
               verse-semantics |
               bazel-built driver binaries (bazel builds, nix checks consume as prebuilt)
    devShells: cpp(bazel + repo tooling) | rocq(withPackages + lsp) | hs(ghc+cabal)
               | all(+wasmtime, llvm-lit, clang-format)
    checks:    coq-kernel-tests . corpus-differential . bazel-{native,wasm32-cross}-tests .
               tblgen-rocq-golden . dialect-lit-tests . differential-triangle .
               certirocq-e2e (Gallina->Clight->clang->run) .
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
7. **Open question, measured but not ruled (2026-11-22): block-scope/freshness - the kernel is
   stricter than VC.**  `m2-det.texpr` Group G's four probes came back `head -> no row` in both
   corners: the kernel's `promote_ok` (coq/Rewriting.v ll. 224-226 - counts mentions of *any* slot
   of the block) rejects re-promotion of a slot VC's line-416 `R_PromoteL/R` freshness would allow
   (VERSE-RULES § 3.2, VC l. 416: a *fresh* declared slot may still be free in the substituted
   value).  Kernel-stricter means every kernel-derivable block is VC-derivable, never the reverse,
   which is the safe direction for T4/T6 but means the kernel can reject a flex fill VC endorses.
   **Status: queued, not decided** - the ruling (keep the stricter guard and state T4's sem-side
   with a VC-fresh-but-kernel-stuck witness, vs. relaxing `promote_ok` toward the line-416 reading)
   waits on the Sweeney/SPJ publication line, the same receipt decision 8 is owed.  Evidence:
   docs/DESIGN-NOTES.md § 11.2-11.3.  Related correction recorded with it, re-measured against the
   code on 2026-11-22: "freshness" is a property of the kernel's selected rows, not of any fuel -
   row *selection* is fuel-free (`head_redex` coq/Eval.v l. 234 and `cand_bag` l. 331 take no fuel
   argument), while the evaluator proper is fuel-bounded (`Fixpoint norm (fuel : nat) (e : Expr)`,
   coq/Eval.v l. 284) and the corpus harness's default fuel 24 (tools/corpus/corpus.py) is
   extraction-scaffold machinery driving that bounded walk (docs/DESIGN-NOTES.md § 8.3).  The
   first draft of this item said the evaluator "takes no fuel argument at all" and cited a
   non-existent DESIGN-NOTES § 12; both are wrong and are corrected here.

## 8. Decision log (also in Strata, tag "timbda")

1. Scope: Timbda-0 only; DCont control-flow (WAMI, git-only pinned fork); ultimate lowering to
   LLVM; WASI/WASM stack-switching as WASM-side equivalent of boost.context; Rocq + ctrees +
   extlib + stdpp semantics; CertiRocq-verified Gallina->C backing the C++; boost::context
   implements (later) native control flow; annotations emitted from MLIR/TableGen source, never
   handwritten; no Isabelle/Lean; practical framing, prove non-naive out-of-order reduction to
   straight C without unnecessary context switches.
   1a. (amended 2026-11-18) "stdpp semantics" narrowed: the candidate-set semantics is read through
   ctrees `br2` up to weak bisimilarity, not through stdpp `gset`; stdpp stays pinned and available
   but is not in the kernel's dependency cone (sec. 6, DESIGN-NOTES § 7).
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
6. (2026-11-18, closed 2026-11-19) Differential corpus shape: ONE hand-derived spec file
   (`tests/corpus/*.texpr`), read by two independent readers — generated Coq `reflexivity` assertions
   (native Gallina evaluator) and an OCaml driver over the `Extraction`'d evaluator — gated by
   `checks.corpus-differential`, which also requires the two corners to see the same case count *and*
   candidate-bag count and blocks vacuous passes (empty corpus, empty generated corner, truncated
   extraction, a corner ignoring its own recorded `rc`).  Harness scaffolding lives outside `coq/` so
   adding cases never touches the kernel's axiom/`Admitted` gate; the augustss `tester` becomes the
   third corner at M3.  Evidence: 64/64 green on both corners (7 candidate-bag groups), the `seq_z`
   inclusive-range kernel fix it produced, and the Fig. 8 row selection (`R_Subst`/`R_PromoteL`/
   `R_PromoteR`) that close-out added.  Docs: docs/DESIGN-NOTES.md § 8-9, tools/corpus/README.md § 6.
7. (2026-11-19) Build memory is infrastructure, not an aside, and it has two halves.  The **dev-shell**
   build is containable: `(jobs 2)` (`coq/dune-workspace`) plus a *verified* systemd cgroup envelope with
   a host watchdog (`tools/build/coq-build.sh`, which refuses to run uncapped, reads back its own
   `memory.max`, asserts its expected `.vo` set, and aborts the build when host `MemAvailable` or swap
   headroom collapses).  The **nix gate chain is not cappable from an unprivileged session**: the daemon
   runs builds as root in a cgroup with `MemoryMax=infinity` (Determinate Nix 3.24.2 / nix 2.35.3,
   `/nix/store` not
   user-writable) and `max-jobs = 20`, so a user-scope cap around `nix build` is a placebo; the guard
   there is a preflight refusal plus `--max-jobs 1` (`tools/build/nix-gate.sh`).  Measured reason this is
   not theoretical: an uncapped gate chain coincided with 30 `earlyoom` SIGTERMs in 10 minutes, 28 of
   them the model server at 41-47 GiB each.  Also measured: warm and cold builds are different numbers
   (647 MiB warm; `coq/Denotation.v` alone over 3.5 GiB cold, stalling rather than failing under a 3 GiB
   and a 3.6 GiB cap) - and the 53.9 GiB peak that started this was one unprovable `Example`
   (fuel-24 `vm_compute` over the ctrees denotation), not the kernel.  Follow-up, M1-side: bound the
   cost of `Ltac t1_norm` (`coq/Denotation.v:100`), whose `repeat (setoid_rewrite …; kernel_cbn)` loop
   is the candidate explanation for the cold cost.  (2026-11-19 addendum, verified live: the
   root-side envelope is **applied** - 16 GiB `/swapfile` + fstab, and `nix-daemon.service` carries
   `MemoryHigh=4G`/`MemoryMax=5G` confirmed at the cgroup; `max-jobs = 1` also applied
   **client-side** for the interactive account (`~/.config/nix/nix.conf`; a plain no-flag `nix build`
   measured 3 concurrent workers -> 1), while the daemon's own `max-jobs` still awaits root-side
   `/etc/nix/nix.custom.conf`; `earlyoom --avoid/--prefer` and the sysctl tuning remain unapplied.
   Statuses: `tools/build/README.md` § "Status after 2026-11-19".)  Docs: docs/DESIGN-NOTES.md § 4.2-4.3, tools/build/README.md.
8. (2026-11-21; M2 gate rulings, **accepted pending** - revision is owed to new Verse-team
   information (Sweeney/SPJ/publication line), and any revision must be recorded saying which
   limb moved and on what receipt.  (a) **M2's determinate fragment is closed blocks only**: every
   slot `Some`; open-block completion semantics stays the admitted Tier-2 M3/T1 obligation
   (`RewBetaL`/`RewBetaT`/`RewSubst`/`RewPromoteL` general forms, RULES-AUDIT C1), so T4/T5/T6/T7
   never face a `None` slot and the M0-reachable C1 divergence stays out of M2's scope.  (b) **T6
   is stated as conditional refinement**: the C behaviour refines the kernel where the kernel does
   not get stuck; `det_check` rejects obvious stuck shapes (literal `Div _ 0` - consistent with
   DEV-5 half 2's measured PStuck reading); the floor-vs-C-truncation correction ladder the
   dialect already carries (`divZ`, DEV-20) must be carried through `Lower.v` so T6's division
   claims match the kernel's `Z.div`; T3's C++-rounding half (DEV-5) is not in M2's scope - M2
   ends at Clight.  (c) **DEV-20's owed bound is verifier-side**: external literals wider than the
   128-bit mirror are rejected, plus a span bound on eager `DotDot` materialisation; fuel is not
   the mechanism.  (d) **Gc1 stays unselected through M2**: straight-line lowering has no dead-slot
   removal to do, and the `dropSlot`/`shrinkE` reindexing lemma has nothing to check against until
   slot shrinking actually runs.)  Corollary cleanups the same day: RULES-AUDIT's "no (M2)" on the
   Gc1 row resolves to M3/T1 (8d), and the "M2's T8 adequacy" phrasing at RULES-AUDIT ll. 57/159
   corrects to M3 (PLAN § 5 puts T8 at M3), giving the C3 fuel-rebudget lemma a consistent home.
   The M2 golden-test corpus follows decision 6's ritual: claims written by hand before either
   engine runs.

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
- The Ariola chain inside VC — the prior-art lineage of the very sharing/recursive-substitution
  machinery this audit measures. Entries transcribed 2026-11-21 from the VC extended-version PDF
  itself (doi:10.1145/3607845; simon.peytonjones.org copy); every DOI below is exactly as VC's own
  reference list prints it. Launchbury, A Natural Semantics for Lazy Evaluation, POPL'93
  (doi:10.1145/158511.158618): the heap-threading semantics VC's rewrite semantics replaces — VC's
  intro says the only semantics "faithful to its sharing semantics ... was an operational semantics
  that sequentially threads a global heap through execution", "But then Ariola et al., in a seminal
  paper, showed how to reify the heap into the term itself ... Inspired by their idea, we present a
  new rewrite system for functional logic programs that reifies logical variables, unification, and
  choice into the term itself." Ariola, Maraist, Odersky, Felleisen, Wadler, A Call-by-Need Lambda
  Calculus, POPL'95 (doi:10.1145/199448.199507): VC annotates its central sharing rule subst as
  "precisely the same as the let-v rule of Ariola et al. [1995]". Occurs discipline: VC's occurs
  check is rule u-occurs — "u-occurs reduces x = ⟨1, x, 3⟩; e to fail using the context V =
  ⟨1, □, 3⟩" — with "the side condition v ≠ V [ x ] in subst avoids an overlap with u-occurs".
  Recursion: VC §4.1.2 reproduces the letrec pathology verbatim — "It is well known that adding
  letrec to the lambda calculus makes it non-confluent, in a very tiresome, but hard-to-avoid, way
  [Ariola and Blom 2002]" (their "Notorious Even/odd Problem"): VC's own term ∃x y. x = ⟨1, y⟩;
  y = (λz. x); x, reduced substituting-for-x-first vs substituting-for-y-first, yields two cyclic
  terms that "cannot be joined", "equivalent only under some kind of graph isomorphism". Ariola &
  Klop, Cyclic Lambda Graph Rewriting, LICS'94 (doi:10.1109/LICS.1994.316066); Ariola & Klop, Lambda
  Calculus with Explicit Recursion, Inf. Comput. 139(2), 154–233, 1997 (doi:10.1006/inco.1997.2651)
  — VC §4.3: "Ariola and Klop studied a form of the lambda calculus with an added letrec construct
  and determined (like us) that their calculus was not confluent; then they added a specific
  constraint on recursive substitution and proved that the modified calculus is confluent." Ariola &
  Blom, Skew Confluence and the Lambda Calculus with Letrec, Ann. Pure Appl. Log. 117(1), 95–168,
  2002 (doi:10.1016/S0168-0072(01)00104-X). Ledger caution, from the paper's own text: VC's proven
  confluence (Thm 4.1, full proof App. C) holds only for "well-behaved" terms — those that never
  reduce to "obviously problematic" lambda-unification / cyclic-substitution terms — and inside that
  carve-out recursion is by fixpoint combinator: "one can still write recursive (and non-terminating)
  programs using one's favorite fixpoint combinator, such as Y or Z." VC's stated open problem is the
  Ariola-Blom tool itself: "We believe, and currently are trying to prove, that VC without the pesky
  no-recursion side condition of Theorem 4.1 is skew confluent" — with the paper's own caveat that
  "the proof of skew confluence is not yet complete" (App. D). Cite. Kernel-side counterpart
  (measured 2026-11-21): the kernel stands inside a carve-out of its own — "Non-recursive slots only
  (recursive heaps = Gc-Rec/Def-Rec Tier-2 rows)" (coq/Syntax.v header); the promote/GC occurs
  guards carry "Exact for the non-recursive M0 fragment" (coq/Rewriting.v ll. 78-83, 226, 232-236);
  and VERSE-RULES' Gc row records "M0 kernel restricts to non-recursive `def`", the Gc-Rec SCC
  variant admitted as a Tier-2 row (M3/T1). The kernel is the
  well-behaved side of the fork. VC's even/odd term above is recorded as a candidate out-of-corpus
  test for the M2/M3 flex obligations: if a flex fill ever produces a cyclic slot, kernel behaviour
  is measured before this ledger says anything about it — no recursion claim is inheritable from
  VC's own unfinished skew-confluence proof.
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
  conjecture that VC uses the "low" reduction strategy and ambition to prove confluence. Personal
  intellectual lineage; this project is the machinery that can finally answer it. Venue correction
  2026-11-21 (this line previously read "Biernacka et al., ICFP'22 Zoo of strategies"): the zoo
  paper is Biernacka, Charatonik & Drab, The Zoo of Lambda-Calculus Reduction Strategies, And Coq,
  LIPIcs vol. 233 (13th ITP), art. 7, pp. 7:1–7:19, 2022 (doi:10.4230/LIPIcs.ITP.2022.7; verified
  from the Dagstuhl PDF); "low" ("leftmost innermost weak") is a strategy that paper *introduces*
  ("By swapping the phases of lcbw and rcbw, we have formulated the low (leftmost innermost weak)
  strategy"), its Coq formalization sits at bitbucket.org/pl-uwr/strategies, and it names
  call-by-need as the admitted omission from its zoo ("it is harder to characterize, and it still is
  in the wild") — the region where VC-like strategies live. Cite.

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
