# Probe p529 - the compile-as-hylomorphism probe: ctrees' `fold` specialized to an accumulator, measured axiom-free (measured 2026-11-26)

Question this probe answers: M2's `Compile.v` leaf ("compile CertiRocq to C") can be a
**hylomorphism** - a coalgebra read through a chosen algebra - via the pinned library's own
`CTree/Interp/Fold.v:29-45`

```coq
fold (h : E ~> M) (g : B ~> M) : ctree E B ~> M
  := fun R => iter (fun t => match observe t with ... end)
```

instead of the § 13.16 carrier-tower reading, *and* at what cost in axioms, memory, and proof
regime.  Decision record: docs/PLAN.md decision 14; narrative: docs/DESIGN-NOTES.md sec. 13.17.

Parts (each compiles green in one pass; both run inside the rocq dev shell against the built
`coq/` tree, `coqc -Q . Timbda` under a 6 GiB user scope):

| part | content |
| --- | --- |
| `p529_a.v` | the shape on stand-ins (`E0`/`B2`/`Res0`): target monad `M X := st -> MRes X` with `st := {fuel; ofrag}` and `MRes = MDone frag x \| MLoopR frag \| MTrap frag`; `iter` implemented by the TARGET as a fuel-decreasing `Fixpoint` whose exhausted-budget case emits an `i_loop` instruction; the two half-morphisms (`h0` empty, `g0` a dependent pattern match on the branch token); `compile := fold h0 g0`; nine Leibniz-`=` goals, all `reflexivity` |
| `p529_b.v` | the same fold on the kernel's real signature `ctree void1 B2 SResult` fed by `denE` directly: arms `Ret`/`Fail`/kernel-fuel-`SStuck`/`Choice` (=`br2`) with a left AND a right scheduler differing only in the returned bool/`Seq` (whose denotation is a `>>=` cofix spine) /`Seq∘Choice`; kernel-fuel artifact measured by `Compute` at two fuels; four `Print Assumptions` outputs, all **`Closed under the global context`** |

Measured cost: parts A and B each compile in 0.42-0.43 s wall at ~454 MiB peak RSS - and that
figure is the CTree import cost, not the proof cost: every proof is `reflexivity` over a
concrete term.  17 goals total, zero failures after the goals were corrected to the measured
semantics (below).

**Measured laws (the content the Compile.v leaf will be built on).**

1. *Budget law.* `iter`'s budget is consumed **one observation per arm, `RetF` included**:
   `compile` of a three-`StepF` chain at fuel 3 never observes the final `RetF` and stops with
   `MLoopR [i_step; i_step; i_step; i_loop]`; fuel 4 yields `MDone [i_step; i_step; i_step] rok`
   (`p529_a.v`, `c_chain`).  The emitted fragment is bounded by the fuel *by construction*: the
   "proof working set proportional to one instruction, never to one program" rule becomes a
   property of the fold's shape, not a discipline imposed on tactics.
2. *Two stucks, permanently distinct.* Kernel fuel exhaustion is a **result** (`denE rho e 0 =
   sret SStuck`, propagating through `>>=`: `Seq (Choice (Ret 1) Fail) (Ret 2)` at kernel fuel 2
   compiles to `MDone [i_branch_left] SStuck` - a `MDone`, no `i_loop`, verified by `Compute`
   before being pinned as `b_seq_choice_kernel_fuel`).  Compile fuel exhaustion is an **emitted
   instruction** (`i_loop`) plus `MLoopR`.  The probe keeps both goals adjacent as the guard
   against re-committing the decision-12f category error.
3. *The branch algebra IS the candidate decision.* `br2 t u = br branch2 (fun b => if b then t
   else u)` (CTreeDefinitions.v:123-124): the `B2` payload bool (`Variant B2 : Type -> Type :=
   | branch2 : B2 bool`, Index.v:19) *is* the candidate selector.  `b_choice` and
   `b_choice_right` compile the SAME `Choice` tree with schedulers returning `true` vs `false` -
   two compiles differing only in that bool.  The determinacy analysis (`det_struct` /
   `prim_total_res` / the guard hypotheses) is exactly what licenses returning *which* bool.
   The library's own warning stands next to this: `FoldCTree.v`'s `CounterExample` shows a
   branch-resolving fold need not preserve weak bisimilarity (`t1 ~ t2` yet
   `~ (interp h t1 ~ interp h t2)`) - the RULES-AUDIT sec. 4 horn restated: the emitted C is
   defined on determinate programs, which is the same hypothesis that makes the coalgebra side
   single-valued.
4. *`=` genuinely reaches the target side; `≅` stays on the source side.* Kernel trees whose
   `Seq`/`Unify` arms contain `>>=` spines compile arm-by-arm at Leibniz `=` because `fold`
   performs a single `observe` per step and `subst` under an `observe` on a `RetF` head *is* the
   iota step (`b_seq`: Seq of two returns costs zero emitted instructions).  `bindM` exists only
   in the `Monad` dictionary; the compile path runs on `iter`/`fmap`/`mstuck`/`mstep`
   (CTree/Core/Utils.v:10-20 classes).  This is the regime split that answers the § 13.16
   "`≅`-only monad laws" observation: anywhere a `=` is needed, a fold with a chosen algebra
   must be planted; `≅`-only laws flag "no fold chosen here".
5. *A cone question, answered numerically.* `Print Assumptions` on `b_choice`, `b_seq`,
   `b_seq_choice`, `b_seq_choice_kernel_fuel`: **`Closed under the global context`** four times.
   A fuel-bounded fold into a chosen algebra needs none of the 13 pinned axioms; the cone
   belongs to the bisimilarity/certiRocq side only.

**Verdicts.**

- `CTree/Interp/FoldStateT.v` is a wrapper, not the accumulator: `fold_state := fold h g` over
  ExtLib's `stateT` transformer, `#[global] Typeclasses Opaque fold_state interp_state
  refine_state`, file opening with `Unset Universe Checking`.  The inline state of part A is
  what matters because it is where `iter` gets its fuel-and-loop-node meaning; the transformer's
  `iter` comes from an inner monad and encodes no resumption policy.  Do not build on it.
- A polymorphic branch algebra `g : B2 ~> M` (`forall X, B2 X -> M X`) *must* pattern-match:
  `match b in B2 Y return MRes Y with branch2 => ... end` forces the index equation `X = bool`
  before any value can be produced.  "A function returning true" is not a well-typed scheduler;
  the candidate semantics enters through that index equation.

**Toolchain traps (Rocq 9.1.1), all measured here, all reusable.**

- Patterns on a parameterized inductive must supply the parameter: `| MDone l x` fails with
  "constructor MDone (in type MRes) is expected to be applied to 3 arguments while it is
  actually applied to 2"; a `return` annotation does not fix it; `| @MDone _ l x` does.
- Implicit binders (`{X : Type}`) on terms offered to ExtLib `Functor`/`Monad` class fields are
  refused (`fmap := fmapM` with implicit args: expected `forall A B : Type, ...`); spell
  class-supplied binders with parentheses.
- `MonadIter`'s field order is `{R I}` (ITree/Basics/Basics.v:92-93), not `{I R}`; `mstep : M
  unit` with a transparent `M` unfolds to `st -> MRes unit` - ONE lambda.
- An empty match in term position needs BOTH `return T` and `with`: `match e end` and `match e
  with end` are parse errors.
- `Import ListNotations` works only as a plain `Import` after `Lists.List` is loaded; `From ...
  Require Import ListNotations` answers "Cannot find module ListNotations".  (The § 13.15
  "Realize.v imports no ListNotations" line has a scope: the notation scope question and the
  module-path question are separate facts.)
- Eta-short morphism spellings (`fun _ _ => ...`) hide the payload binder under Coq's
  eta-expansion, and `~>` is ambiguous for `B2` under `ctree_scope`; spell `h0`/`g0` with named
  binders.

Reproduce (from the repo root; the `Timbda` logical prefix is the built `coq/_build/default`
tree - `dune build` first if it is stale):

```sh
cd coq && dune build && cd _build/default
cp <this dir>/p529_a.v <this dir>/p529_b.v .
systemd-run --user --scope -p MemoryMax=6G -p MemorySwapMax=0 \
  bash -c 'timeout 300 coqc -Q . Timbda p529_a.v'   # nine reflexivity goals
systemd-run --user --scope -p MemoryMax=6G -p MemorySwapMax=0 \
  bash -c 'timeout 300 coqc -Q . Timbda p529_b.v'   # kernel arms + Print Assumptions
```

Both print only deprecation warnings; part B additionally prints four `Closed under the global
context` lines.
