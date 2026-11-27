# Timbda-0 Verified Compiler — Master Plan

Status: plan settled; per-milestone DoDs + statuses recorded at § 5.0 (M-1/M0 closed, M1 open,
M2 paused behind M1 - decision 9). Last updated: 2026-11-25.
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
  provably yields straight C with no unneeded boost::context calls - the *unneededness* is a
  theorem of determinacy, and the calls that ARE needed are semantic: decision 15 materializes
  choice nodes for multi-candidate programs).
- Principle: whenever there is a "prove" vs "runtime contract" choice, PROVE, even if harder
  upfront. Consequences: determinacy analysis lives in the Gallina kernel; strategy execution is
  a Gallina evaluator (search as data/work-queues, not stack switches); boost::context as the
  provably-mapped *semantic* layer for decision 15's materialized choice nodes (M4 implements
  it; decision 2a amends the original "optimization" wording).
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
- boost::context is the provably-mapped **semantic** runtime layer for materialized choice nodes
  (decision 15): programs whose candidate sets genuinely offer two or more candidates - the
  corpus's 7 candidate-bag cases among them - need re-enterable control to arbitrate them, so a
  native runtime without stack switching is not a complete implementation of their semantics. It
  enters only via a T12-style theorem, never as a bare runtime contract; determinate programs
  compile with zero context calls, by theorem. Performance/streaming/reactive use sits on the
  same layer, secondary. WASM equivalent = WebAssembly stack-switching (WASI 0.3 async ABI /
  WAMI pipeline).
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
2. T2 M-algebra: or commutative/idempotent/associative - scoped by decision 15 to contexts
   where no `all`/`for`/`if`/`one` observes the choice - fail as zero, monad laws
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
   Measured 2026-11-24 (docs/DESIGN-NOTES.md § 13.4/§ 13.6): the naive reading is false in this
   kernel — the `Seq` arm discards the prefix value — so the delivered truth is
   `T5_swap_discarded` (swap at a discarded prefix position) + `T5_swap_assoc` (fold/reassociate)
   + `T5_swap_equal_values` (top swap under a shared value witness), with `T5_top_swap_needs_value`
   refuting the naive claim.
6. T6 Straight-line specialization: lower_det e = c -> Wbisim (sem e) (ClightSem c) against
   CompCert's Clight semantics (library dep — see sec. 4).  CertiRocq-cone rule
   (docs/DESIGN-NOTES.md § 13.5, measured 2026-11-24): the Gallina fed to CertiRocq is
   structurally recursive or fuel-indexed `Fixpoint` only - `lower_det` is written as a
   fuel-bounded function, which is exactly the shape CertiRocq lowers to plain `while` loops;
   no `CoFixpoint`, no ctrees cofix constructions (`bind`/`subst`, Denotation.v:77) enter the
   compiled cone.  Measured 2026-11-25: the landed T7 `lower` (docs/DESIGN-NOTES.md § 13.8) is
   the other legal shape — structurally recursive, fuel-free — and the two shapes meet on the
   straight-line fragment `app_node_ok` pins.  For checked terms the emitted fuel guard is provably never-false
   (`T4_sem` runs at every `e_fuel e + k`), so the while loop is the unbounded idealization
   over precisely the accepted fragment.  *Formulation settled 2026-11-25 (decision 10, probes
   p519):* T6 is the statement-level realization - `Clight1.exec_stmt` derivability of
   `clight_of (lower e)` from the empty context, observed at tempvar `lower_res` and composed
   with `T4_sem`'s value witness, under a computable `range_ok` 64-bit guard; the whole-program
   reading defers to the golden-test design (docs/DESIGN-NOTES.md § 13.14).
   *Increment B landed 2026-11-25 (probe p524):* `Realize.v`'s `T6_exec_ws`/`T6_exec` prove the
   statement-level part outright - every tree with `ws_expr d e = det_struct e = range_ok e = true`
   executes from `ge0`/`Clight.empty_env`/`Mem.empty`, and the final `lower_res` pin is
   characterized by the monadic fold `lower_final` (decision 11).  *Increment C landed
   2026-11-26 (probe p528, decision 12):* the Int64-to-kernel-Z bridges (repr-level arith,
   signed-level cmp, the `int64_eq_signed` route) and the three-way correspondence composition
   (`T6_T4_match_add` / `T6_T4_match_PGt` / `T6_T4_match_PDiv`: the exact corner denotation at
   fuel 6 glued to `T6_exec_ws`'s exec-and-pin witness), with the div semantics fork closed by a
   floor constant fold in `Lower.prim_expr`'s PDiv arm - the kernel floors, CompCert truncates,
   and the fold makes the lowering emit the floor (docs/DESIGN-NOTES.md § 13.15).
7. T7 No-context-call theorem: det_check e = true -> no_switch (lower e) — structural induction
   on the Gallina lowering function. The anti-naivety guarantee verbatim.
   Landed 2026-11-25 (docs/DESIGN-NOTES.md § 13.8): `no_switch` is `no_switch_l` over
   `coq/Lower.v`'s fuel-free structural `lower`; `T7_no_switch` proved through the
   depth-general `ws_expr` form, `Print Assumptions T7_no_switch` printing `Closed under the
   global context` in the build (coq/tests/LowerTest.v), so Flocq's pair (§ 13.7) stays on
   the T6 side only.
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
    dcont -> extern lowering is a refinement of shift/reset semantics in the model. By decision 15
    the family is the arbiter of the materialized choice nodes: for indeterminate programs it is a
    semantic obligation, not optional performance. The C++ path — fast path for determinacy-fused
    fragments, semantic arbiter for choice nodes — enters only as a theorem, never a contract.
    The proof is static; shipping carries no
    monitors (§ 4 boundary policy) — monitors police the CI build of the extern region.

## 4. Verification ledger (TCB)

- Proven span: Timbda-0 semantics -> Gallina kernel (rewrites, determinacy, lowering, evaluator)
  -> Clight. CertiRocq's Gallina->Clight proof is the last machine-checked link.
- Compiled-cone rule (measured 2026-11-24, docs/DESIGN-NOTES.md § 13.5): everything the CertiRocq
  leg compiles is structurally-recursive or fuel-indexed Gallina (the extraction cone today -
  tools/extract/extract.v's four `Eval.v` names - already is); coinduction and ctrees' cofix
  machinery live in the spec/proof side only and are erased before extraction.  CoFixpoint closures
  are not lowered; unbounded iteration is expressed as fuel-indexed loops.
- Trusted-but-observed span: Clight -> clang -> machine. Deliberate choice: Clight is valid C
  compiled routinely by gcc/clang (CertiRocq docs recommend gcc; CompCert listed as the optional
  alternative). Clight expressions are pure (calls only as statements, fixed order) and Clight is
  UB-free by construction, so clang's UB-driven transforms have nothing to grab onto.
  "Observed" = Alive2/alivecc-class IR-level translation validation over clang's pipeline +
  binary-level differential testing + hardening flags below.
- CompCert = nice-to-have (decision): stays as a BUILD-TIME LIBRARY dependency regardless
  (Clight definitions + PrintClight are CompCert code; nixpkgs builds it with -clightgen).
  That dep is in the toolchain since 2026-11-25: `.packages.x86_64-linux.timbda-compcert` =
  `pkgs.coqPackages_9_1.compcert` 3.17, in the flake's `rocqDeps`.  Measured trap: the
  top-level `pkgs.compcert` attribute is the `coqPackages_9_0` build of the same 3.17 -
  prover-9.0-locked .vo files, unusable on this 9.1.1 stack (docs/DESIGN-NOTES.md § 13.7).
  The nixpkgs import gates `compcert` alone through a scoped `allowUnfreePredicate`; the
  consumption is Coq-library only (Clight syntax+semantics, Smallstep, export.Clightdefs -
  nothing in coq/ imports them yet).  Invoking ccomp as a compiler remains an optional,
  license-gated CI lane (INRIA non-commercial license).
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
  the region T12's proof reaches, semantic for choice nodes per decision 15); they are the
  state-tracking class of monitor, not cheap argument checks; and they
  tax the very extern family whose "provably-mapped, never a bare contract" rule they sit under. The
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

### 5.0 Completion discipline (decision 9, 2026-11-25)

A milestone is DONE-DONE only when every item of its recorded Definition of Done has landed on
`main`, gate-attested, with no residue parked inside a later milestone's work; the next
milestone's work begins only after that declaration. An audit confirming that hand-built pieces
agree is not completion - completion is the pieces themselves. When execution lands a later
milestone's item before an earlier milestone closed, the deviation is recorded here with cause
and debt, not absorbed. Only M-1 ever had a written DoD (sec. 0); that gap caused the drift
recorded under M1 below. Decision 9 closes the gap: every milestone carries its DoD in this
section, written before its first commit lands against it.

Per-milestone DoD and status (this section is the source of record; the gate lanes carry the
attestations):

- **M-1 - CLOSED.** DoD as stipulated in sec. 0 (both graphs hello-world green + pin-table
  consistency). Standing witnesses: `checks.version-consistency`, `checks.golden-test` (still
  the trivial ghc test by design - M2's real golden test is an M2 item, not an M-1 residue),
  the bazel dialect seed.

- **M0 - CLOSED.** DoD (from the M0 line plus decision 6): Syntax/Semantics/Rewriting kernel;
  T1 at the core-rule scope (met: 15 named ctors + PrimSchema at both used arities,
  docs/RULES-AUDIT.md); T2 br2 algebra; extracted evaluator; differential harness as a BUILD
  GATE - the augustss `tester` corner was explicitly re-baselined to M3 (recorded amendment,
  not residue). Standing witnesses: `checks.corpus-differential` (64 cases / 7 candidate bags)
  and the kernel audit (zero `Admitted`, sole axiom `eq_rect_eq`).

- **M1 - CLOSED 2026-11-25.**  Closure condition (decision 9): every written DoD
  item of this block is DONE-DONE gate-attested on `main`; at closure the default
  eight-lane chain ran fully green with zero watchdog kills.  Landed: `Timbda.td`
  ODS + 72 `TimbdaRuleRecord` rows; DRR
  rewriters (`TimbdaPatterns.td` -> tblgen `.inc` -> `populateWithGenerated`); and the three
  verification lanes of decision 9 (all green 2026-11-25, now in the gate chain's default set):
  - *rules-audit lane*: `checks.rules-audit` runs `tools/rules-audit.py` in the gate - the
    coverage audit (35 ctor rows: coq ctor = audit tag = record = DRR pattern; 72/35/37/3 row
    arithmetic; 23-pattern DRR bijection; zero `Admitted`) is gate evidence, not a local ritual.
  - *bazel attestation lane*: `tools/build/bazel-lane.sh` runs the dialect graph
    (tblgen gen + canonicalization TU + dialect ops lib + `timbda_dialect_test`) under
    bazelisk + the MODULE.bazel-pinned hermetic-llvm (measured: the LLVM/MLIR 23.1.2 closure is
    fully cached on this host - dialect test PASSED with 2141 action-cache hits), and
    `checks.bazel-native-tests` consumes only the recorded status - refusing unless it carries
    rc=0, a PASSED dialect-test summary, the pinned bazel version, and a `sha256sum -c`-verified
    source-hash block matching the exact dialect/pin inputs nix evaluates. Stale prebuilt
    evidence fails the gate; the negative path was exercised before the first green run.
    Since 2026-11-25 the lane's bazel run also materializes the generated
    `TimbdaCanonicalization.cpp.inc` into `tools/build/bazel-evidence/`,
    sha256-bound by the same block - bazel-out symlinks do not survive the nix
    tree copy (measured), and that committed text is what `checks.rules-audit`
    and `checks.dialect-lit-tests` consume as the dialect-side evidence.
  - *lit lane*: `checks.dialect-lit-tests` (item 2's landing, DESIGN-NOTES sec.
    13.13) runs lit 18.1.8 + FileCheck over `tests/lit` against that evidence:
    23 generated pdll skeletons + the populate-shape test = 24 passes, the
    canonicalize skeleton registered UNSUPPORTED until a timbda-aware opt
    binary exists (M2), and the skeletons themselves byte-diffed against
    regeneration.
  Remaining, per decision 9's rulings:
  1. `dialect/tblgen-rocq/` backend per sec. 2 - `-gen-rocq-ast`, `-gen-rocq-rules`,
     `-gen-rocq-checker` generating into `coq/` for the rule-record family; hand-glued `Rew` /
     AST artifacts retire as generated files land. `-gen-rocq-externs` ships with the
     ContextExtern family at M4 (recorded binding). The rules-audit lane extends to assert
     generated-file provenance once this lands. **Rules half landed 2026-11-25**
     (DESIGN-NOTES sec. 13.11): `-gen-rocq-rules` emits the generated `Rew` surface -
     ctor coq* fields + emission groups transcribed into `TimbdaRules.td` by
     `tools/rules-coqctor.py`, `coq/RewRules.v` regenerated inside the dune unit, the
     hand-glued ctor block retired from `Rewriting.v`, `checks.tblgen-rocq-golden`
     byte-diffs regeneration (it also closes item 2's golden half early), and rules-audit
     sec. 1b asserts record-field provenance (35/35) plus the group partition.
     **AST + registry halves landed 2026-11-25** (DESIGN-NOTES sec. 13.12):
     `-gen-rocq-ast` emits `coq/RuleAst.v` - the eval-side `RuleID` from the ctor rows'
     distinct `kernelTag` fields in `TimbdaRuleAstOrder` group order, `selected_rows`
     derived from the records' `selected`/`rank` fields - retiring the hand-glued
     block from `Eval.v`, which now `Require`s the generated file; `-gen-rocq-checker`
     emits `coq/CheckerManifest.v`, a soundness REGISTRY (per-row `RewSound_*` lemma
     inventory as Coq data - deliberately not statements, measured against the
     discharged lemmas: statement text is proof-side design). The golden lane
     regenerates all three files, rules-audit sec. 1c asserts their provenance, and
     the kernel witnesses + `EXPECTED_VO` gained `RuleAst`/`CheckerManifest`.
     Item 1 is now closed for the rule-record family; the only registered mode left
     refusing is `-gen-rocq-externs`, bound to M4 above.
     Toolchain resolved 2026-11-25
     (DESIGN-NOTES sec. 13.10, probes p512/p513): the generator is the Nix-side half of sec. 6,
     built against the new `[formal.mlir_gen]` pin (nixpkgs llvmPackages_23 = 23.1.0, classic
     llvm TableGen API - parsed the real Timbda.td, 72 defs / 26 selected); binary prebuilts are
     not consumable by sandboxed checks, so generated *text* is the only cross-graph interface;
     generated files enter `coq/` outside the dune unit until their proofs make them
     kernel-compatible.
  2. pdll lit-test skeletons + flake checks `dialect-lit-tests` and `tblgen-rocq-golden`.
     **Landed 2026-11-25** (DESIGN-NOTES sec. 13.13): `-gen-pdll-tests` emits one
     FileCheck skeleton per DRR ctor row into `tests/lit/pdll/` (asserting exactly
     what the record derives of the rewriter text: struct name, root op
     `"timbda."+ops[0]`, populate entry - measured before choosing: the
     `100 - rank` benefit invariant holds 21/23, so benefit is not asserted);
     `checks.dialect-lit-tests` regenerates them twice, byte-diffs against the
     committed files, and runs lit 18.1.8 + FileCheck (the `[formal.mlir_gen]`
     pin) over `tests/lit` - 24 passes, 1 registered-UNSUPPORTED canonicalize
     skeleton (M2-bound, honest skip). The bazel lane now materializes
     `tools/build/bazel-evidence/TimbdaCanonicalization.cpp.inc` as sha256-bound
     committed text - bazel-out symlinks are invisible to nix-side checks, which
     had been silently SKIPping the audit's populate check in every gate run.
  Recorded deviation: T4 (2026-11-23), T5 (2026-11-24), the CompCert toolchain (2026-11-25) and
  T7 (2026-11-25) all landed while M1 stayed open - cause: no written DoD beyond M-1's, and
  M2's kernel path has no hard dependency on M1 artifacts. The debt was paid by ordering, not
  argument: T6, the CertiRocq wiring, and the real golden test start only after M1 items 1-2
  landed and M1 was declared closed here.
  Bound elsewhere (recorded so nothing floats): ContextExtern dual-side declarations +
  annotation chain (sec. 2 artifact 5) -> M4; vendored DCont fork subtree (sec. 6) -> M4/M5
  when the conversion passes start.

- **M2 - OPEN; M1-closure pause LIFTED 2026-11-25** (M1 declared closed above;
  decision 9's ordering obligation is met). Landed: T4 both legs +
  `T4_value_unique`, T5 for the accepted fragment, T7, the m2-det gate corpus (29/7), CompCert
  toolchain. Outstanding, in forced order: T6 (design obligations settled 2026-11-25 by probes
  p519 - decision 10, docs/DESIGN-NOTES.md § 13.14; the proof landed 2026-11-26, decisions 12
  and 13), then CertiRocq->C wiring (`Compile.v` - shape ruled by decision 14: a fold-specialized
  hylomorphism, probe docs/probes/p529/; carrier ruled by decision 15: scoped commutativity,
  materialized choice nodes; full strategy: docs/COMPILE-STRATEGY.md), then the real golden test.

- **M3 / M4 / M5 - NOT STARTED.** Per decision 9 each gets its DoD written into this section
  before its first commit lands. Inherited bindings: M3 carries the augustss third corner
  (decision 6); M4 carries the ContextExtern family, `-gen-rocq-externs`, and the DCont fork
  subtree; M5 carries the WAMI pipeline and wasmtime pins.

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
  Build memory is a build-infrastructure fact, not an aside: `coq/dune-workspace` pins `(jobs 1)`
  (measured rationale, 2026-11-26: docs/DESIGN-NOTES.md § 4.2) and
  `tools/build/coq-build.sh` runs the build inside a verified cgroup envelope with an artifact check
  (docs/DESIGN-NOTES.md § 4.2).
- M1: dialect + generator. Timbda.td, DRR rewriters, tblgen-rocq backend, pdll tests, paper-rule
  coverage audit (every paper rule => a record + an MLIR pattern + a Rocq ctor — the audit IS the
  completeness claim).  *Open as of 2026-11-25: DoD, landed/remaining items, and the deviation
  record are at § 5.0; decision 9 orders its closure before further M2 work.*
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
  `denE_total_pairwise` strengthening, not a setoid chain.  The T5 draft ran the same day and
  measured (docs/DESIGN-NOTES.md § 13.4): the naive out-of-order claim is refuted in the kernel
  (`T5_top_swap_needs_value` - the `Seq` arm discards the prefix's value, Semantics.v:218; the
  corpus had already pinned differing final components 9/6 in the amended Group D pair); the true
  lemma is the swap at a DISCARDED prefix position (`T5_swap_discarded`, proved at `≈` for checked
  terms; corpus witness `oo_swap_prefix_sem` discharges `e_oo_left` vs `e_oo_swap` through the
  theorem), a top-position swap needs a shared value witness (`T5_swap_equal_values`), and the
  fold/reassociate half waits for `denE_total_pairwise` - whose first consumer it now is.  No
  coinduction was needed for any of it; § 13.3 keeps the coinduction route (`coinduction S CIH`,
  up-to-bind `bind_chain_gen`) as machinery for the deferred claims - Iter-era M3 - not for T5.
  *Same-day follow-up:* the recorded `denE_total_pairwise` strengthening landed — totality at two
  budgets in one induction (`coq/Checks.v`, after `denE_total`; five of the ten arms close because
  the peeled prim/tuple/literal trees are fuel-free, only Seq and Block recurse) — and with it T5's
  fold/reassociate half (`T5_swap_assoc`, corpus witness `oo_assoc_sem` discharging Group D's own
  assoc pair; docs/DESIGN-NOTES.md § 13.6).  T5 is now fully discharged for the accepted fragment.
  What M2 still owes: T6 and the golden test.  T7 landed 2026-11-25: `coq/Lower.v`'s
  fuel-free structural `lower`/`no_switch_l` and `T7_no_switch`, build-audited by
  `coq/tests/LowerTest.v` (docs/DESIGN-NOTES.md § 13.8).  Its toolchain prep landed
  2026-11-25: CompCert 3.17 in `rocqDeps` (docs/DESIGN-NOTES.md
  § 13.7), consumption probed against the installed tree, and the T6-side surfaces measured
  - `Smallstep.forward_simulation` axiom-free, Clight's own semantics cone carrying Flocq's
  two `ClassicalDedekindReals` axioms.  The audit decision has half-resolved: T7 touches only
  Clight *syntax*, which is axiom-closed, so the kernel Print-Assumptions audit (hard-pinned
  to `eq_rect_eq` alone) survived the increment untouched; T6's statement will meet the
  semantics cone and must decide those two axioms explicitly - allowlist, separate audit
  scope, or a float-avoiding formulation for int-only fragments - BEFORE the first proof
  line, not discovered mid-proof.  *Resolved 2026-11-25 (decision 10, probes p519): separate
  audit scope, pinned - see decision 10a and docs/DESIGN-NOTES.md § 13.14.  T6 increment A
  landed the same day: `coq/Realize.v` (ge0/le0, clight_of, the `range_ok` guard, per-node
  realization lemmas, the add[2,3] / gt[3,2] / Ret corners) with the cone sweep wired into the
  `timbda-kernel` buildPhase (`rocq check -silent -o Timbda.Realize`, thirteen-axiom context
  pinned verbatim).  *Increment B landed the same day (probe p524):* `T6_exec_ws` - the full
  statement-level induction over the checked fragment, with the monadic `lower_final`
  value-characterization and the `prim_guard_ok`/`prim_guard_ok_canon` transfer of the kernel's
  div guards to CompCert's (decision 11) - plus `T6_exec` at `le0`.  *Increment C landed
  2026-11-26 (probe p528, decision 12):* the div semantics fork measured and closed at
  lowering time (kernel `Z.div` floors, CompCert `Int64.divs` truncates, the dialect `divZ`
  ladder mirrored and pinned to the floor), the Int64-to-kernel-Z bridges, and the
  `T4_sem`-side composition (`T6_T4_match_add`/`T6_T4_match_PGt`/`T6_T4_match_PDiv`), whose
  corner-denotation half first landed mis-stated as Leibniz equalities and is re-pinned at ctrees'
  structural equality `≅` (decision 12f, DESIGN-NOTES § 13.16);
  what remains of M2 is the CertiRocq->C wiring and the golden test.*
  *Ordering 2026-11-25 (decision 9): what remains of M2 and the order it must land in are
  pinned at § 5.0 - M1 closure first.*
- M3: closed certified runtime. Full Gallina evaluator (T8, T9 e2e). Complete usable Timbda-0
  implementation with zero boost.context dependency - a Coq-side statement: candidate sets run as
  data (work-queues) there, indeterminate programs included; native execution of those programs
  is M4's semantic layer.
- M4: the semantic runtime layer for materialized choice nodes (decision 15), carrying the
  performance/streaming path with it. dcont lowering + generated ContextExtern annotations + shim;
  T12 (static; shipping monitor-free per § 4 boundary policy). Skippable only for determinate-only
  programs: the corpus's 7 candidate-bag cases require stack-switch execution for complete native
  semantics.
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
   2a. (amended 2026-11-26, by decision 15) The word "optimization" in item 2 did not survive the
   carrier ruling. Decision 15's materialized choice nodes make re-enterable control (boost.context
   natively, WebAssembly stack-switching on the WASM leg) SEMANTIC for programs whose candidate
   sets genuinely offer two or more candidates - seven such cases are already pinned in the corpus
   - so M4 is no longer an optional improvement of the runtime; it is the layer without which the
   full corpus has no complete native semantics. What survives the amendment intact: "provably
   mapped, never a bare runtime contract" (T12/VeriFFI), and the determinacy-side theorem that
   determinate programs compile to straight-line C with zero context calls
   (docs/COMPILE-STRATEGY.md §§ 4-5). Same-day doc sweep applied the ruling to the surfaces:
   README stack-switching bullets and milestone sentence, PLAN § 1 goal/principle, § 2 overview,
   § 4 boundary-policy paragraph, the T12 item, and the § 5.0 M3/M4 milestone lines.
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
9. (2026-11-25) **Milestone discipline: done-done before moving on.**  A milestone closes only
   when every item of its written Definition of Done (§ 5.0) has landed on `main` gate-attested,
   with no residue parked inside a later milestone's work; later-milestone work does not begin
   against an open milestone; a deviation that happened anyway is recorded with cause and debt,
   not absorbed by an audit that merely confirms the hand-built pieces agree.  Scope rulings for
   the open case (M1): (a) the generator contract stands as written in sec. 2 - build the
   tblgen-rocq backends; audit+reconstruct may not substitute for generation; (b) M1's boundary
   is the § 5 line plus sec. 2's five-artifact contract for TimbdaRule *rule* records, with the
   ContextExtern artifacts explicitly bound to M4 and the DCont fork subtree to M4/M5 (recorded
   bindings, nothing floats).  Forced order now: M1 close-out (tblgen-rocq backend; pdll lit
   tests + `dialect-lit-tests`/`tblgen-rocq-golden` checks; `checks.rules-audit` gate lane; the
   bazel attestation lane) precedes T6, the CertiRocq leg, and the real golden test.  Decision 9
   reorders what remains; it does not re-litigate what landed - the M0/M2 status entries above
   stand.  M3/M4/M5 must have their DoDs written in § 5.0 before their first commit lands.
10. (2026-11-25) **T6's pre-pinned design obligations settled, by measurement (probes p519,
    docs/DESIGN-NOTES.md § 13.14, sources at docs/probes/p519/).**  (a) **Audit scope**: a
    statement-level `exec_stmt` derivation for even `add[2,3]` - built from CompCert's own
    constructor rules - already prints six axioms (Flocq's `sig_not_dec`/`sig_forall_dec`,
    `functional_extensionality_dep`, `classic`, `inline_assembly_sem`, `external_functions_sem`),
    because they sit in the *premise types* of `Clight.eval_expr`/`Values.sem_binary_operation`,
    not in any proof shortcut; no formulation inside CompCert's rules keeps T6 in the kernel's
    `eq_rect_eq`-only lane.  Ruling: a second, separately-pinned audit scope - the kernel lane's
    allow-list stays `eq_rect_eq` only for kernel-owned theorems; the CompCert-facing cone
    (T6, then the CertiRocq/golden-test theorems) is audited against the pinned six-axiom list
    as its own block; anything outside `eq_rect_eq` (kernel) plus the six (cone) reds the gate.
    Implementation (increment A, same day): the cone scope runs `rocq check -silent -o Timbda.Realize`
    - rocqchk re-checks the module and its whole transitive cone, and what is pinned verbatim is
    that CONTEXT SUMMARY: thirteen fully-qualified axioms, i.e. the six above plus the transitive
    CompCert surface (`Events.inline_assembly_properties`, `Events.external_functions_properties`,
    `ProofIrrelevance.proof_irrelevance`, `compcert.lib.Axioms.proof_irr`,
    `Ensembles.Extensionality_Ensembles`, `x86_64.Archi.win64`), with the type-in-type /
    unsafe-(co)fixpoint / positivity sections required to stay `<none>`.  A new axiom anywhere
    in the cone reds the gate and must be adjudicated here before landing.
    (b) **Formulation**: T6 is the statement-level realization - `Clight1.exec_stmt`
    derivability of `clight_of (lower e)` from the empty context (`ge0`, `Clight.empty_env`,
    `PTree.empty val`, `Mem.empty`), observed at tempvar `lower_res`, composing with
    `T4_sem`'s value witness; the whole-program reading (int32-pinned
    `bigstep_program_terminates`) defers to the golden-test design.  (c) **Range hypothesis**:
    a computable `range_ok e` guard (every `VInt` constant and every admitted prim
    application's kernel result inside the signed 64-bit window) is a T6 hypothesis;
    `det_check` is not touched - changing the accepted fragment is not licensed by decision 8.
    (d) **Placeholder arms**: the kernel's relational primops return their first argument on
    guard success (`prim_total`, Syntax.v l.344-357), so value claims split three ways: the
    arithmetic map {add,sub,mul,div,neg} - final `lower_res = Vlong (Int64.repr z)` for the
    kernel result; the guard map {gt,lt,geq,leq,neq} - final `lower_res = Vint 1` exactly when
    the kernel guard succeeds on the same in-range literals; everything else admitted
    (identity prims hitting the `Econst 0` placeholder, table prims with var operands, TupE,
    `None`/`VVar` slots, `Unify`) gets exec-existence only; a lowered TupE claims "last ret
    wins" in the final temp env.  These rulings bind T6's first proof line; changing any of
    them requires amending this decision.
 11. (2026-11-25) **T6 increment B: the statement-level induction lands (`T6_exec_ws` in
     `coq/Realize.v`); its formulation rulings.**  Probe p524 (sources at docs/probes/p524/),
     compiled against the increment-A store tree before touching `Realize.v`.  (a) **Value
     characterization** is the monadic computable fold `lower_final e o : option val` - the
     value `clight_of (lower e)` leaves in `lower_res` when started from an incoming value
     `o`: `Seq e1 e2` composes (`lower_final e2 (lower_final e1 o)`), Block's slot prelude
     passes `o` through (slot tempvars never name `lower_res` - `lower_res_ne_slot`), TupE
     claims "last ret wins" via `last_val`, and placeholder arms mirror `vconst`'s
     `Int64.repr 0`.  An earlier non-monadic draft (a `lower_final`/`lower_get` pair) was
     retired as unsound for Seq when the first half writes and the second half has no value
     claim.  (b) **Div-guard transfer**: `prim_guard_ok p vs` states, syntactically for the
     prim shape, exactly the guards `eval_bin64_Odiv` needs (nonzero divisor; not the
     `min_signed / -1` overflow pair); `prim_guard_ok_canon` discharges it from kernel facts
     - `prim_total_res` pins the operand shape to `VInt x :: VInt y :: nil`, `range_ok` of
     the operand list pins in-range-ness, `prim_node_range_ok` pins the result range (hence
     a nonzero divisor - `prim_total_res_PDiv_ne`), and the table/bare `app_node_ok_shape`
     paths are vacuous because `prim_args_ok`/`prim_bare_ok` reject PDiv.  (c) **Toolchain
     rulings measured during authoring**: Rocq 9.1 multi-goal `match goal`/`solve` silently
     under-covers after a multi-`destruct` (a skipped goal surfaces only at `Qed`), so the
     per-prim dispatch in `prim_expr_eval` is explicit 18-arm bullets with arity brackets;
     `destruct ... eqn:E` rewrites hypotheses containing the destructed term and can consume
     E itself; `discriminate` is purely syntactic (hidden implicit args break it) -
     rewrite-first instead.  (d) **Depth and env threading**: `T6_exec_ws` carries the
     ws_expr depth and the incoming temp env universally (Block checks its body at
     `length sl + d`, `%nat`-pinned; Seq threads `le` through `exec_seq_close`); `T6_exec`
     is the `d = 0`, `le = le0` corollary.  Increment C - the Int64-to-kernel-Z bridges and
     the `T4_sem` composition - stays owed per decision 10b; these rulings bind it.
 12. (2026-11-26) **T6 increment C: the div semantics fork measured and closed by a floor
     fold at lowering (`coq/Lower.v` and the realization fan-in - the `Realize` hub plus
     `RealizeBridges` / `RealizeDiv` / `RealizeCorners` / `RealizeCompose`).**  Probe p528 (sources at
     docs/probes/p528/), proven against the installed store tree before the `coq/` edits.
     (a) **The fork**: the kernel's `Z.div` is a true FLOOR (`Z.div 7 (-2) = -4`);
     CompCert's `Int64.divs = Int64.repr (Z.quot (signed .) (signed .))` TRUNCATES
     (`7 divs (-2) = -3`; `Int64.mods = Z.rem`, dividend-signed); the dialect's `divZ`
     (`TimbdaCanonicalization.cpp` 176-183) is truncation plus a ladder correction.  The Coq
     mirror `divZ_ladder` with `divZ_ladder_div` (five quadrant rungs) pins the ladder to
     `Z.div` exactly.  The earlier DESIGN-NOTES § 13.14 claim "`Z.div` truncates like
     CompCert's int64 division" is retracted as measured false.  (b) **The closure**:
     `Lower.prim_expr`'s PDiv arm constant-folds
     `Econst_long (Int64.repr (Z.div (vint_z a) (vint_z b))) tint64` and `prim_clight`
     mirrors it - no `Cop.Odiv` node is ever emitted, so CompCert's truncating runtime
     division and its guard ladder play no part in T6; `odiv_ready`/`sem_Odiv_long`/
     `eval_bin64_Odiv` stay as measured bridges the dispatch never reaches.  Soundness:
     `app_node_ok` pins operands literal, `vint_z_VInt` says the signed reading recovers the
     kernel Z for `int64_range` operands, and an out-of-range div result fails
     `prim_node_range_ok` and is outside T6's claim (`z64` + `vint_z` therefore move to
     `Lower.v`, the only direction the imports allow).  (c) **The composition**: the exact
     corner denotation (`denote (prim_corner p [..]) 6%nat = sret (SOk ..)` - `e_fuel` of a
     two-operand corner is 6) glued to `T6_exec_ws`'s exec-and-pin witness by
     `T6_T4_match_add` / `T6_T4_match_PGt` / `T6_T4_match_PDiv`, discharging decision 10d's
     three-way correspondence on the prim corners: arith results as
     `Vlong (Int64.repr of the kernel result)`, guard success as `Vint (Int.repr 1)`.
     (d) **Toolchain rulings measured**: `cbn` (even bare, even delta-listed) refuses to
     unfold an applied constant like `vint_z` under `Z.div` - `unfold` fires; an
     `Int64.repr`-based value claim without `int64_range` hypotheses is false, not merely
     unprovable; `Z_lt_dec` is a 3-way sumbool in 9.1 (`Z_lt_ge_dec` for binary splits);
     `rewrite` with a hypothesis-bearing lemma puts the main goal FIRST in the bullet
     sequence (`apply` last); `lia` refuses div/quot identities head-on - route through
     `Z.div_unique` with `Z.quot`/`Z.rem` shielded by `set ... in *`.  (e) **Build-unit policy
     (the fan-in split, same day)**: landed as one ~750-line `Realize.v` section the increment
     killed the box twice silently - `strata-host` measured 41.5-50 GiB RSS, the hub coqc unit
     ~15 GiB, `(jobs 2)` allowing exactly two such peaks - dune RC=1 then coqc RC=143, each with
     no Coq error and no `Realize.vo` (the sec. 4.1 kill signature).  The increment-C text moved
     *verbatim* into leaves - `RealizeBridges.v`, `RealizeDiv.v`, `RealizeCorners.v`,
     `RealizeCompose.v` - with `Realize.v` staying the CompCert-side hub they read;
     `coq/dune-workspace` went to `(jobs 1)`; the flake cone sweep checks the roots
     `Timbda.Realize` + `Timbda.RealizeCompose` (Compose pulls every leaf transitively), the
     thirteen-axiom pin re-attesting against both at the landing gate.  Every future increment -
     D (CertiRocq->C) next - lands in its own leaf, never by inflating the hub.  (f) **Corner
     denotations restated at ctrees' structural equality `≅` (the increment-C second half, same
     day)**: the fuel-6 corner goals spelled as Leibniz equalities are FALSE statements, not hard
     ones - `>>=` is ctrees' CoFixpoint `subst`, unstuck only under `observe`, so no delta list
     fires a bind chain and any strict normalization re-materializes the cofix tower per fuel
     layer (measured: `kernel_cbn` 1 s at fuel 4, 18 s at fuel 5, stall at fuel 6; the uncapped
     61 GiB `rocqworker` earlyoom shot was this shape).  The landed spelling is
     `denote corner 6%nat ≅ sret (SOk v)` proved by the arm-equation machine - one
     `reflexivity`-level `denE`/`denE_tup`/`apply_c` arm equation per rewrite, binds fired by
     `bind_sret_l`, closure by a negative-delta `cbn -[...]` pass that blocks every fixpoint
     (DESIGN-NOTES § 13.16).  `cbn`'s refusal-to-unfold-then-revert semantics (a delta-listed
     unfold whose subtree is stuck reverts the whole cascade) routes guard-bearing structure claims
     through one-line `prim_total_res_*_true` equations; `prim_args_ok` is the structural-prim
     arity check, so `det_struct` of a failed-guard corner is genuinely false.  The same probes
     re-measured the build-unit memory policy: a clean full-lane `dune build` peaks at 655 MiB
     (`Realize.v` 499 MiB, `KernelTest.v` 655 MiB) and the cone sweep at 515 MiB - decision 12e's
     ~15 GiB hub-unit figure belonged to the grinding Leibniz-`=` WIP, so `(jobs 1)` stays as
     concurrency policy and not as a per-unit budget (DESIGN-NOTES sec. 4.2, 13.16).  With this,
     M2's remaining items are the CertiRocq->C wiring and the golden test.
13. (2026-11-26) **Gate-chain ordering is memory policy, and a gate script's host facts are re-read,
    not inherited.**  Two rulings, both from the increment-C gate runs (DESIGN-NOTES sec. 4.3.1).
    (a) **Dependency-first exception to cheap-first.**  `checks.corpus-differential` drags the whole
    Coq kernel through the corpus corners' `buildInputs`, so with the kernel lane last the cold store
    compiled it inside the corpus target's poll window: 85 s, `MemAvailable` 6918 -> 5021 MiB, watchdog
    floor 5120 MiB crossed, `rc=124 … (target not attested)`.  Same target with the kernel derivation in
    the store: `rc=0`, never below 5799 MiB.  Kernel lane alone: `rc=0` in 270 s, host unmoved (7362 ->
    7393 MiB).  `tools/build/nix-gate.sh` now runs `.#packages.x86_64-linux.timbda-kernel` before the
    check lanes that consume it; with `--max-jobs 1` this does not lower the peak, it makes a kill and
    its evidence belong to the lane that costs the memory.  Re-attested 8/8, `nix failures: 0`,
    `watchdog kills: 0`.  (b) **The two remaining gate costs were store churn, and they are closed.**
    Determinate Nix's collector had eaten the morning's green kernel output (`error: path
    /nix/store/…-timbda-kernel-0.1.0 is not valid` at 15:02, full 4 min 30 s `buildPhase` paid twice in
    one day, rebuilt to the identical path), so the gate now registers a GC root for the Coq-side lanes
    it just attested (`nix-store --realise --add-root … --indirect`, the one rooting form a
    `trusted-users` account may use - `--profile /nix/var/nix/profiles/…` is `Permission denied`),
    rooted set = kernel + `corpus-differential`, not `golden-test`'s 3.3 GiB ghc, and lane builds pass
    `--no-link` so no `result` symlink lands in the repo.  On the flake side the corpus corners stopped
    taking `src = ./.`: they read `tools/corpus/corpus.py`, `tools/corpus/driver.ml`,
    `tools/extract/extract.v` and `tests/corpus/*.texpr`, and take a narrowed `cornerSrc` now, so a
    docs-only commit no longer rehashes a generated corner (`corpus-differential.outPath` measured
    identical across a `docs/` edit, lane green at 64 cases / 7 candidate bags).  Toolchain fact learned
    doing it: nix 2.35.3 passes a `cleanSourceWith` filter the **store path being copied**, not a path
    relative to `src` - a relative-equality filter kept every directory and no file, failing as `cp:
    cannot stat '…/source/tools/extract/extract.v'`; match suffixes/infixes, `cleanSourceFilter` first.  (c) **Stale host facts are defects.**  The gate's own header asserted
    `nix-daemon.service MemoryMax=infinity` and `nix show-config max-jobs = 20`; today the machine
    answers `MemoryHigh=4294967296`, `MemoryMax=5368709120`, `MemorySwapMax=infinity` (cgroup
    `memory.max = 5368709120`) and `max-jobs = 1` on both sides, while `earlyoom -h` (v1.7, run as
    `-r 3600` with no `-m`/`-s`) states its defaults as 10 % mem AND 10 % swap with SIGKILL at half.
    The conclusion the header draws is unchanged - an unprivileged scope around `nix build` is a
    placebo, the cap is root's and its `MemorySwapMax=infinity` is what turns pressure into swap - but a
    guard documented on facts that no longer hold is not a guard, so: when `nix-gate.sh` is touched, its
    host facts get a dated re-read in the same commit.  Consequence for planning: gate headroom is now
    the ~54.5 GiB model-server residency problem, not the proof units, which cost under 1 GiB.
14. (2026-11-26) **M2's compile increment is a fold-specialized hylomorphism; probe p529 measured
    the shape, the budget law, and an axiom cost of zero.**  Rulings (DESIGN-NOTES sec. 13.17,
    sources at docs/probes/p529/).  (a) **The shape.**  `coq/Compile.v` (its own leaf, hub
    untouched) is `compile := fold h g` over ctrees' `Interp.Fold.fold` specialized to an inline
    accumulator monad `M X := st -> MRes X` (`st := {fuel; ofrag}`,
    `MRes = MDone frag x | MLoopR frag | MTrap frag`) whose `iter` the *target* supplies as a
    fuel-decreasing `Fixpoint` with an exhausted case that emits an `i_loop` instruction and
    returns `MLoopR`: the resumption boundary is data in the emitted fragment, and the carrier is
    never demanded.  Per-arm fusion lemmas live in the `reflexivity` regime (17 goals across the
    probe, all `reflexivity`, 0.42 s/file at ~454 MiB); correctness is a `cog`-simulation composed
    with the existing `T6_T4_match_*` bridges, not an equality of normal forms.  Guard rails that
    keep the framing load-bearing, not vocabulary: no `bind` on the compile path (it survives only
    in the `Monad` dictionary), no whole-program normalization in any proof, fusion lemma stated
    and used.  (b) **The budget law.**  The fold spends one observation per arm, `RetF` included;
    emitted-fragment length is bounded by fuel by construction - sec. 4.2's "proportional to one
    instruction, never to one program" promoted from tactic hygiene to a property of the shape.
    (c) **Two stucks, permanently distinct.**  Kernel fuel exhaustion is a result (`SStuck`,
    propagating through `>>=`: `Seq (Choice (Ret 1) Fail) (Ret 2)` at kernel fuel 2 compiles to
    `MDone [i_branch_left] SStuck`, `Compute`-verified); compile fuel exhaustion is an emitted
    instruction plus `MLoopR`.  Decision 12f's category error stays guarded by keeping both goals
    adjacent in the leaf.  (d) **The branch algebra is the candidate decision.**
    `br2 t u = br branch2 (if b then t else u)` with `branch2 : B2 bool`; one `Choice` tree, two
    schedulers, the compiles differ only in the returned bool, and a polymorphic `g : B2 ~> M` must
    pattern-match the branch token before any value exists (the match forces `X = bool`).  The
    determinacy analysis licenses *which* bool; `FoldCTree.v`'s counterexample (branch-resolving
    folds need not preserve weak bisimilarity) is RULES-AUDIT sec. 4's horn restated.  The
    ordered-vs-bag carrier question is **open and now operationally sharp** - it is "which bool
    for which program, and is emitted order insensitive" - and must be ruled when `Compile.v` is
    written, not smuggled through `br2`.  (e) **Cone unchanged, verified from below.**  `Print
    Assumptions` on the probe's kernel-arm goals: `Closed under the global context` x4 - the hylo
    path adds no axioms; the 13-axiom pin stays the bisimilarity side's bill, and `Compile.v` must
    not grow it (the gate's cone sweep re-attests).  Ruled a distraction: `CTree/Interp/FoldStateT.v`
    (`fold_state := fold h g` over ExtLib `stateT`, `Typeclasses Opaque`, `iter` inherited from an
    inner monad); the inline state is where the resumption policy lives.
15. (2026-11-26) **The candidate-carrier question (RULES-AUDIT issue #1) is ruled by material
    compatibility: commutativity scoped, observation materialized.**  Decision 14(d) left three
    readings live - (A) ordered collapse at compile time (priority `g`), (B) bag algebra in the
    target (unrestricted T2, fusion modulo permutation), (C) split by determinacy: determinate
    `br2` sites fuse under a forced bool, indeterminate sites lower to explicit choice nodes whose
    arbitration lives in the runtime layer (DCont/WAMI M5, boost.context M4).  Ruled (C), because
    it is the only reading compatible with the materials' own text; the other two fail on named
    lines: (i) Fig. 13's `IterChoice` (docs/VERSE-RULES.md § 3.4) is the paper's
    **candidate-splitting** rule - `iter(ic){B[C[b1 b2]]}{e} ⟶
    iter(ic){B[C[block{b1}]]}{iter(ic){B[C[block{b2}]]}{e}}` - choice compiles into nested
    observable structure, the paper never collapses it: (A)'s collapse-at-indeterminate-sites is
    ruled out.  (ii) The paper's own iteration combs (`IAll | IIf | IFor`, Syntax.v:48) ARE scoped
    observation modes, and `iter(if)`'s first-candidate reading (issue #1) is priority defined
    only where an observer exists - VC walks the ordered route in print (`one` leftmost).
    (iii) The candidate set IS the program's meaning (T2 "mirroring the paper's candidate-set
    claims"; T8 `candidate_set (eval_run e) = candidate_set (sem e)`): a compile that resolves a
    genuine multi-candidate program to one priority run contradicts T8 - this kills (A) outright
    at indeterminate sites, and licenses collapse only where determinacy makes the set a
    singleton, which is exactly (C)'s fusion side.  (iv) (B) contradicts the ordered Fig. 13
    transcription that produced the conflict (`iter(all){1|2}{⟨⟩}` → `⟨1,2⟩` vs `⟨2,1⟩`) and needs
    permutation-invariance of the compiled output that `FoldCTree.v`'s counterexample says is not
    provable in general.  (v) The plan's runtime layers exist for the materialized nodes:
    re-enterable control (boost.context as the setjmp/longjmp-like marker, PLAN sec. 1; WAMI/DCont
    stack switching, M5) is where a choice node's arbitration lands - the layers graduate from
    optimization to semantic obligation.  Consequences: PLAN § 3's T2 sentence narrowed in place;
    the discharged `Br2_Commut_W`/`Br2_Idem_W` rows read as denotation-level (wbisim) facts only,
    never code-level rewrites; decision 14(d)'s `g` is fully specified - determinacy-forced bool
    at determinate sites (probe p529 `b_choice`), choice-node emission plus the fold's `inl`
    residual (probe A's `i_loop`/`MLoopR` mechanism) at indeterminate sites; decision 2's
    boost.context sentence ("which steps fuse into straight-line C and which materialize")
    becomes the stated fusion lemma about `g`, and T12/M4-M5 inherit it as their reason to exist;
    M3's owed iter ruling is pre-decided consistently - `RewSound_IterChoice` and `RewSound_IterAll`
    both pursued under the scoped law with the ordered transcription kept; the golden test pins
    fragments containing choice nodes for the corpus's 7 candidate-bag cases; `cand_bag` stays a
    collection order (Eval.v:330) whose bag claims remain true under the scoped law, corpus
    unchanged.  Audit trail: docs/DESIGN-NOTES.md sec. 13.18; probe-side mechanism:
    docs/probes/p529/.

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
  differential testing + fuzzing). Rocq-side scope measured 2026-11-25 (issue #1 comparison):
  openverse mechanizes no Verse semantics in Rocq — its Rocq sources are the QuickProof laws about
  the C runtime (`proofs/quickproof/`); the Lean 4 semantics is the main proof body. "First
  verified Verse implementation/runtime" is NOT ours.
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
