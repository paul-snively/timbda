# Compile.v — the strategy, in depth

*(Design document, saved verbatim from the strategy review of 2026-11-26. Built on decisions
12-15 and probe p529 (`docs/probes/p529/`); companion narrative: `docs/DESIGN-NOTES.md`
§§ 13.16-13.18; theorem obligations: `docs/PLAN.md` § 3 and the M2 bullet.)*

## 0. The thesis in one paragraph

`Compile.v` states the compiler as a **hylomorphism over the kernel's own trees**: the coalgebra is the kernel's `observe` (ctrees exposes exactly one constructor of `ctreeF` per step); the algebra is a Clight accumulator with its own supply of temporaries, slots, and loop policy; the hylo is ctrees' `Interp.Fold.fold` specialized to that algebra. The compiler never builds the carrier — the corecursive object that made the § 13.16 blowup inevitable — it consumes the kernel's cofixes **one observation at a time** and appends **one Clight construct per observation**. Its correctness is not a normal-form equality but a **simulation** between the observation trace and the emitted statement trace, glued to the already-gate-attested `T6_exec_ws` execution witnesses through the existing `T6_T4_match_*` bridges. The whole file is ~60 lines of definitions plus a small estate of per-arm `reflexivity` equations — probed end-to-end in p529: 17 goals, 0.42 s, zero new axioms.

## 1. What is already under it (nothing is invented)

Every load-bearing part exists and is gate-attested:

- **The fold.** `fold (h : E ~> M) (g : B ~> M) : ctree E B ~> M := fun R => iter (fun t => match observe t with …)` (`Interp/Fold.v:29-45`), with the target supplying `iter` through `MonadIter/MonadStep/MonadStuck` (`Core/Utils.v:10-20`). Probe p529 instantiated all five classes over an inline accumulator and ran it on real `denE` output — including `Seq`'s `>>=` cofix spine — 17 Leibniz-`=` goals, all `reflexivity`, four times "Closed under the global context."
- **The Clight side.** `Realize.v` already carries the empty Clight context (`ge0`, `le0`), the Int64↔Z bridge (`vint_z`, `Int64.signed/z64` with the signed-window discipline), the per-primop lowering maps (`prim_match_*`, the floor-`Z.div` fold at `PDiv`), the guard maps (`prim_guard_match_P*`), and the exec-and-pin witness `T6_exec_ws` (CompCert `ClightBigstep` over the WS memory correspondence), plus the composition bridges `T6_T4_match_*`.
- **The semantics facts.** T4 uniqueness/`T4_value_unique`, T5 over the accepted fragment, T8 adequacy (`candidate_set (eval_run e) = candidate_set (sem e)`), T3 as the primop-agreement hinge, the ≅-level arm-equation machine of § 13.16, and decision 15's carrier law (scoped commutativity; materialized observation nodes).

`Compile.v` is what happens when the realization (one primop corner at a time) learns to walk a whole program **without re-realizing it** — the fold *is* the walk.

## 2. The mathematical skeleton

**Why a hylomorphism, precisely.** `denote p` is `cata ∘ ana` over `ctreeF`: unfold the program into a tree, then interpret the whole tree. ctrees' `bind`/`subst` are CoFixpoints (`CTreeDefinitions.v:229-241`), so that tree is a *productive object*, not a value: § 13.16 proved no reduction strategy can normalize it (fuel 4 → 1 s, fuel 5 → 18 s, fuel 6 → stall, 61 GiB `rocqworker`), and no `=` is even available on it. A hylomorphism `hylo cog alg` replaces the composition with a **single fused pass**: at each step one `cog` observation feeds one `alg` arm, and the intermediate carrier is never materialized anywhere — in Coq or in memory. Fusion is not an optimization layered on top; it *is* the definition (`fold` is the fused form, with `inl` residuals as its partiality valve).

**The two halves.**

- **Coalgebra (`cog`)**: `state -> F state` with `F` the kernel's own one-step shape — the six `ctreeF` arms (`RetF/StuckF/GuardF/StepF/BrF/VisF`) specialized to `void1`/`B2` — and `cog = observe` on the residual tree carried in the state. Note what this says: *the kernel's denotation is already coalgebraic*; `denE` builds nothing to compile because `observe` peels it lazily. Determinacy (`det_struct`, `prim_total_res`, the guard hypotheses) is the hypothesis that makes `cog` single-valued at `BrF` — which is exactly the condition for `hylo cog alg` to be a function rather than a relation.
- **Algebra (`alg`)**: `F A -> A` over `A` = a Clight fragment accumulator: `list Clight.stmt` plus fresh-name supply (`PTree` temps over `le0`), the slot/WS map (the landed T6 correspondence), and the loop policy. `alg` has three verdicts per arm, mirroring the probe's `MRes`: **append and continue** (`MDone`), **emit a control node and stop unrolling** (`MLoopR` — the resumption boundary as *data*), **trap** (`MTrap` — only for genuinely stuck compilations, which determinate programs never reach).

**Where the cofixes live and why they are safe.** Cofixes appear in exactly two places, both harmless. (1) Inside the *input* trees (`denE`'s `>>=` spines): `fold` demands one `observe` per step, and `subst` under `observe` on a `RetF` head is an iota step — probe `b_seq` compiled a `Seq` of two returns at zero emitted cost, at Leibniz `=`. (2) Inside `iter`'s type — resolved by the target's fuel-decreasing `Fixpoint`. What is structurally impossible is the § 13.16 shape: strict evaluation demanding a cofix *tower*, because `iter` can only ever ask for the next observation, never the whole spine. The negative-delta discipline of 13.16 becomes redundant-by-construction: there is no fuel tower left to reopen.

**The regime split, now law (`=` vs `≅`).** Everything the fold *produces* is a concrete finite object (a fragment, a value): Leibniz `=`, discharged by `reflexivity` per arm. Everything the fold *consumes* is a denotation, and source-side rewrites there live at `≅`/`≈` (the 13-axiom cone's home) — permitted as input rewriting, never as code-level rewriting (decision 15: `Br2_Commut_W`/`Br2_Idem_W` are denotation-level facts only). `≅`-only monad laws remain where they belong: they flag "no algebra chosen here," i.e., source side.

**The fusion law.** The hylo's payoff, stated as a lemma: `compile` of a composed tree is the **concatenation of the compiled fragments**, at `=`, whenever the arms fuse. Probe `b_seq_choice` is the two-arm specimen (a decision followed by a sequencing, one accumulating pass, `[i_branch_left]` then the value). In the real file this is the family that licenses not materializing intermediates — it *is* the correctness of fusion, per arm.

## 3. The file itself (shape, not decoration)

```coq
(* instances, verbatim in shape from probe p529 *)
Record cstate := mkCS { fuel : nat; frag : list Clight.stmt; temps : …; slots : … }.
Inductive CRes X := CDone of frag X | CLoop of frag | CTrap of frag.
Definition M X := cstate -> CRes X.   (* Functor/Monad/MonadIter/MonadStep/MonadStuck *)

Definition h : void1 ~> M := fun _ e => match e return M _ with end.   (* kernel is pure *)

Definition g : B2 ~> M := fun X b s =>
  match b in B2 Y return CRes Y with
  | branch2 => match sched_site s with        (* decision 15, two modes: *)
               | Determinate pf => _          (* bool FORCED by the candidate-existence pf *)
               | Indeterminate  => emit_choice_node s   (* CLoop-side: materialize *)
               end
  end.

Definition compile (p : Expr) (fuel : nat) : M SResult :=
  fold h g (denE nil p fuel) (mkCS fuel nil …).
```

Six definitions, five instances, one `fold`. The theorem estate around it: per-arm fusion lemmas (one per `observe` arm — ret/step/guard/branch/primop-app/tuple/iter, the same "arm-equation machine" style that made `RealizeCorners.v` compile in 2 s), the budget lemma (below), the scheduler-eligibility lemmas (below), the simulation theorem `Compile_Sim`, and the composition theorem gluing `Compile_Sim` to `T6_exec_ws` and the `T6_T4_match_*` bridges. `Compile.v` is a **leaf** (decision 12e: no hub inflation) with its own test unit.

## 4. What the emitted Clight is

The output is **ordinary sequential Clight** — `Sassign`, `Ssequence`, `Sifthenelse`, `Sblock/Sexit`, `Sloop/Sbreak`, `Scall` — over the landed `ge0/le0` and the WS memory correspondence. Three regimes:

- **Determinate straight-line code.** Each fused observation appends one construct: a primop becomes an Int64 expression through the landed lowering (T3's hinge; the floor-`Z.div` fold for `PDiv`, signed-window discipline via `vint_z`); a guard arm becomes `Sifthenelse` testing an Int64 comparison (the landed `prim_guard_match_P*` maps); kernel `Block` slots become locals/`Sblock`s; temporaries are allocated from the `PTree` supply, so **no name generation is a proof burden** and no allocation appears in the C.
- **Kernel loops are *rebound*, not unrolled.** For `IFor` (`for(l..h){e}`), `alg`'s loop policy recognizes the iteration arm and emits **one `Sloop` with a guard and an increment** — O(1) C nodes regardless of `l..h`. This is the one place `iter`'s `inl` residual is used constructively rather than defensively: the resumption boundary is where a C loop begins, so the emitted fragment's size does not depend on trip count. The cost of this is one honest proof obligation (the loop-fusion simulation, § 7 below) and nothing else.
- **Indeterminate choice becomes a named materialized node — never a silent pick.** Decision 15's law, operationalized: at a `BrF` whose determinacy certificate exists, `g`'s bool is *forced* (the candidate-existence proof says which arm has candidates — "left priority" alone is wrong on `Choice Fail (Ret 1)`, and the probe shows the pair) and the arm fuses into straight-line C. Where the candidate set genuinely has ≥ 2 members (exactly the corpus's 7 candidate-bag cases among the golden-test programs), the fold emits **one choice node**: candidate blocks followed by a `Scall` to a named arbiter whose *specification* is fixed in M2 (`one`/`if` leftmost, the VC-printed order) and whose *implementation* lands in M4/M5 (boost.context re-enterable control; the WAMI/DCont leg). In M2 the arbiter is a declared external with a stated spec — no axiom is introduced; the leaf's cone stays the 13 pins; T12/M4/M5 inherit the obligation because § 13.18 made the runtime layer a semantic necessity, not an annex.

For the golden-test fragment specifically: determinate programs compile with **zero choice nodes** (pure straight-line + rebound loops + guarded ifs), and each of the 7 bag cases contains exactly one choice structure. That is the "nature of the resulting Clight": *the straight-line code of a determinate functional language, plus a visible, named, specified trace of the nondeterminism the paper itself says is there.*

## 5. Footprint — measured, then structural

**Proof-time (Coq), measured.** The probe family costs what the leaf will cost per lemma: p529's 17 goals — 0.42 s/file, ~454 MiB peak, and that peak is the CTree *import*, not the proofs (they are `reflexivity` over concrete terms). The landed Coq units bracket the file's home: `Realize.v` 499 MiB, cone sweep 515 MiB, full-lane `dune build` 655 MiB peak — `Compile.v` joins a lane family where every unit is under 1 GiB (decision 12e's budget, enforced per-unit, not a global cap).

**Proof-time, structural (the point).** The budget law — one `observe` per arm, `RetF` included — makes the working set of any proof about `compile` proportional to **the observations its goal mentions**, never to the program: fragment length ≤ fuel by construction (a two-line induction on `iterF`, which I'd make a first-class lemma precisely so it can be *cited* when a lane starts costing too much). Compare the dead spelling, quantified: the carrier-tower evaluation cost grew superlinearly in fuel (1 s at 4, 18 s at 5, stall past 6, 61 GiB before earlyoom); the hylo spelling is constant-per-arm worst-case-linear *by the shape of `iter`*, and fuel is a lemma parameter pinned tiny (≤ `6%nat` scale) in every test goal while the theorems are stated for all fuel. The guard rail from decision 14 — "no whole-program normalization in any proof" — is checkable mechanically: no goal statement contains `compile` applied to a program it does not intend to step through.

**Build-time (nix), measured.** The gate chain is warm now: 18-25 s docs-only, kernel `buildPhase` 4 min 30 s cold and 0 s when the GC root holds (decision 13). `Compile.v` adds one Coq unit to the kernel derivation and one test lane (`compile-leaf`: the fusion-estate compile, the cone sweep re-attesting "13 pinned axioms" — expected to print the same 13, since the probe showed the fold path is axiom-free and the Clight-exec half is already pinned through `Realize.v`), inside the same < 1 GiB unit budget. No new axioms ⇒ no cone amendment ⇒ no change to `flake.nix`'s `expected_cone`.

**Emitted-program-time.** Fragment size: linear in the program's constructor count, plus O(1) per `IFor` (rebound), plus one node per indeterminate observer (exactly the observers the paper's own `all/if/one` combs create — no invented nondeterminism, so the number of choice nodes is bounded by the source). No heap allocation beyond the landed WS correspondence; no unbounded Coq-side evaluation anywhere in the pipeline because `compile` never evaluates the kernel — it only ever asks it for its next constructor.

## 6. Correctness architecture (why the claim is *earned*)

The chain, each link already attested where it exists:

1. **`Compile_Sim`** (new): the observation trace of `denE p` (which exists arm-by-arm by the 13.16 machine) corresponds, statement-for-statement, to the CompCert big-step execution of `compile p`'s fragment over the WS correspondence — determinate arms via the fusion lemmas, `IFor` via the loop-fusion argument, choice nodes via the arbiter spec.
2. **`T6_exec_ws`** (landed): the Clight execution half of each realized corner — `Compile_Sim` composes into it per arm, not re-proves it.
3. **`T6_T4_match_*`** (landed): the glue from exec witnesses back to the denotation at `≅`.
4. **T8 adequacy** (landed): candidate bags of evaluation ≅ candidate bags of semantics — which, after decision 15, is exactly the statement that the compile's materialized nodes preserve *meaning*: the compiler may fuse singletons (determinacy) but collapses nothing, because collapsing anything else would contradict the already-proved T8.
5. **T3** (the hinge, with its recorded open integer obligation): primop-level Gallina↔int63/Clight agreement — the straight-line code is straight-line-*C* code, per primop, and `Compile.v` inherits it arm by arm rather than restating it.

So "the compiler is correct" decomposes entirely into: per-arm equations (`reflexivity`-regime, cheap, 17 specimens already green), one per-observer correctness fact for materialized nodes (relative to a *specified* arbiter), and one loop argument — and everything else is composition of gate-attested pieces. No step of this chain re-proves T4/T5/T6; it *uses* them.

## 7. The four hard corners, named so no one is surprised

1. **Scheduler eligibility lemmas.** `g`'s forced bool needs, per `BrF` site, a candidate-existence certificate. The hub has this for primop guards (`prim_total_res`, `prim_args_ok`); `Choice` sites need the analogous pair ("arm has candidates iff…") tied to `cand_bag`. These are small, per-arm-shaped lemmas — but they are the *interface* between determinacy analysis and code generation, so they get stated first and used everywhere.
2. **Loop fusion.** The `IFor` rebound (C `Sloop` simulates the kernel's iteration combinator) is the only genuinely new simulation *idea* in the leaf: a loop invariant over the slot/WS correspondence, discharged through CompCert's `ClightBigstep`. It is also the only place where `iter`'s "target supplies the loop" is load-bearing — which is why probe part A implemented `iter` in exactly the shape that makes this argument the natural one.
3. **The correspondence relation itself.** `Compile_Sim` needs a definition: observation trace ↔ statement trace. Once defined (it is basically the fusion lemmas' common generalization), every per-arm lemma is an instance; getting *one* relation right is the whole design risk, and it is a small relation.
4. **The arbiter is a spec, not an implementation, in M2.** Choice-node correctness is relative to the stated leftmost policy; its runtime realization (boost.context / DCont-WAMI stack switching) is M4/M5's job — now with a *reason to exist* (decision 15) and a proof obligation written in advance.

## 8. Why the very big step is a very small file

The depth of this increment is in **what was refused**, not in what is proved: the carrier (never built), the collapse (never done), the whole-program normalization (never requested), the axioms (none added), the unbounded evaluator (never invoked). What remains — instances, two half-morphisms, one `fold`, per-arm `reflexivity` equations, one budget lemma, one simulation, one composition — is on the order of a few hundred lines total, each one a specimen of a pattern p529 already ran green end-to-end on the kernel's real signature. The hylo is what makes that possible: it converts the hardest problem in the compiler (the corecursive semantics) into the cheapest operation in the compiler (one observation, one append) — and after 13.16, 14, and 15, that conversion is not a hope on the design page, it is three landed rulings and a probe log.

On your go-ahead, the landing sequence is: `Compile.v` leaf + `CompileTest` unit + the `compile-leaf` lane, built corner by corner exactly the way T6 landed — smallest corner first (`Ret`/`Fail`/`Seq` — already proven as `b_ret/b_fail/b_seq`), then primops with guards, then `IFor` with the loop-fusion argument, then the 7 choice-node cases, each increment gate-attested, cone re-attested to the same 13 axioms every time. The golden test then pins the fragments, including their named choice nodes — and M2 closes with the compiler as a hylomorphism whose every nondeterminism is either proved away or printed in the C, which is precisely the sentence the paper's candidate-set model needs a compiler to satisfy.
