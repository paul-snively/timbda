(* Compile.v - docs/PLAN.md M2's CertiRocq->C wiring (decision 9's order: after T6),
   increment D1, per docs/COMPILE-STRATEGY.md sec. 3 and its sec. 8 landing sequence:
   "smallest corner first (Ret/Fail/Seq - already proven as b_ret/b_fail/b_seq)".
   Shape ruled by decision 14 (a fold-specialized hylomorphism; probe docs/probes/p529/),
   carrier ruled by decision 15 (scoped commutativity; materialized choice nodes).

   WHAT THIS FILE IS.  `compile` is ctrees' `fold` (CTree/Interp/Fold.v:28-45)
   specialized to a Clight accumulator the target supplies: the coalgebra is the
   kernel's own `observe` on `denE` output (ctrees exposes exactly one `ctreeF`
   constructor per step); the algebra is `cstate`'s fragment list over the landed
   `Lower.v` spelling (`lower_res`, `vconst`); the hylo is the one `fold`.  The
   compiler never builds the carrier - it consumes the kernel's cofixes one
   observation at a time.  What the fold PRODUCES is concrete finite data at
   Leibniz `=` (every specimen here is `reflexivity`); what it CONSUMES is
   denotation, and no goal in this file rewrites the source side at all - the
   regime split of decision 12f/15 is enforced by there being nothing to split
   (strategy sec. 2, "the regime split, now law").

   THE OBSERVATION FACT D1 MEASURES (what the algebra can see).  `void1` has no
   constructors, so on `ctree void1 B2 SResult` the observable heads are `RetF`
   and `BrF` only: a determinate straight-line program's whole `denE` spine is a
   chain of `sret`/bind layers, and a bind on a `RetF` head IS an iota step
   inside `observe` (p529 law 4) - the spine collapses to its final `RetF`, one
   observation.  The emitted Clight is therefore value-faithful straight-line
   code: the terminal write is pinned through the landed `Lower.v` machinery,
   never re-derived.  `BrF` is the `br2` candidate decision (p529 law 3); the
   scheduler that may answer it - the candidate-existence certificate of
   decision 15 - lands with the choice corner (D4), so in D1 the algebra's `g`
   is the documented TRAP: a choice the determinacy analysis has not yet earned
   has no defined emitted C at all, which is the `FoldCTree.v` CounterExample
   horn (p529 law 3) stated instead of smuggled.

   TWO STUCKS, permanently distinct (p529 law 2; decision 12f).  A kernel fuel
   exhaustion is a RESULT: `denE rho e 0 = sret SStuck` propagates through the
   bind spine and the compile carries it as a `CDone` value (specimen
   `c_kernel_fuel_nest` - no `CLoop`, nothing loop-shaped).  A compile fuel
   exhaustion is a VERDICT: the target's fuel-decreasing `iter` cannot ask for
   the next observation, and `compile` stops at `CLoop` (`c_compile_fuel`).  The
   strategy makes the loop node's absence the claim: the resumption boundary is
   the `CLoop` verdict itself, a claim about the verdict, not an invented
   instruction.

   BUILD-UNIT POLICY (decision 12e, strategy sec. 5): `Compile.v` is a LEAF -
   the hub `Realize.v` is untouched - and it joins the fan-in family that reads
   the hub (RealizeBridges/RealizeDiv/RealizeCorners/RealizeCompose).  Budget:
   every unit under 1 GiB; D1's peak is the CTree+Clight import (~454 MiB
   measured at p529), not the proofs.

   AUDIT.  CompCert-cone-facing: audited by the flake timbda-kernel buildPhase
   cone sweep, which gains `Timbda.Compile` as a third root; the 13-axiom
   context (decision 10a) must print UNCHANGED - the fold path adds no axioms
   (p529: four `Closed under the global context` outputs on the fold's central
   goals), and this file's Clight side is the already-pinned Realize cone.  No
   `Print Assumptions` line here - forbidden in the whole cone family: its
   output would land in build.log and break the kernel sweep. *)

(* Import order follows the RealizeCompose ruling (toolchain, DESIGN-NOTES sec.
   13.15): compcert block first, then the ctrees/ExtLib/ITree classes, then the
   Timbda tree; Z scope and list notations open only after those windows.  The
   p529 trap list is respected throughout: patterns on the parameterized
   `CRes`/`ctreeF` carry `@`; class-supplied binders are parenthesized;
   `MonadIter`'s field order is {R I}; morphisms are spelled with named
   binders; `ctree_scope` stays CLOSED so `~>` is unambiguous. *)
From Stdlib Require Import ZArith List.
Require Import compcert.lib.Coqlib compcert.lib.Integers compcert.lib.Maps
  compcert.common.Values compcert.common.AST compcert.common.Memory
  compcert.common.Events compcert.common.Globalenvs
  compcert.cfrontend.Ctypes compcert.cfrontend.Cop compcert.cfrontend.Clight
  compcert.cfrontend.ClightBigstep.
From CTree Require Import CTree Eq Core.Utils Interp.Fold.
From ITree Require Import Basics.Basics.
From ExtLib Require Import Structures.Functor Structures.Monad.
Import ListNotations.
(* No Z scope here (measured on the first D1 build): `Require Import ZArith`
   already opens Z_scope globally, and a second `Open Scope Z_scope` inside the
   Clight window resolves the bare numerals in `SResult -> nat` positions
   (fuel arguments) against BinNums.Z - "Found a constructor of inductive type
   Z while a constructor of nat is expected".  Lower.v and the Realize fan-in
   get away without their own Z-scope line for the same reason; the
   RealizeCompose line this line originally copied opens the scope where no
   fuel-shaped argument is in range. *)
Require Import Timbda.Syntax Timbda.Semantics Timbda.Checks Timbda.Lower
  Timbda.Realize.

(* ============================================================================
   1. The target monad: a Clight accumulator the fold runs over.
   `cstate` carries the compile-side budget, the accumulated fragment, and the
   scheduler hint slot the D4 candidate-peek will fill (unused in D1 - the D1
   `g` traps - but the STATE SHAPE is ruled now so D3/D4 grow it, not replace
   it; strategy sec. 3's accumulator fields `temps`/`slots` are inert for the
   landed straight-line fragment: `lower_res`/`slot_ident` already name every
   temp the checked fragment writes, decision 10's spelling). ============================================================================ *)

Record cstate := mkCS
  { cfuel  : nat;                     (* compile-side budget, consumed per observation *)
    cfrag  : list Clight.statement;   (* the accumulated Clight fragment, in order *)
    chint  : option bool              (* D4 scheduler hint; None until the choice corner *)
  }.

Definition cstate0 (n : nat) : cstate := mkCS n nil None.

(* The algebra's three verdicts (strategy sec. 2): append-and-continue,
   emit-and-stop-unrolling (the resumption boundary as DATA - the CLoop verdict
   itself), trap (only for compilations whose C is not defined: in D1 that is
   exactly the unanswered choice). *)
Inductive CRes (X : Type) : Type :=
| CDone : list Clight.statement -> X -> CRes X
| CLoop : list Clight.statement -> CRes X
| CTrap : list Clight.statement -> CRes X.

Definition M (X : Type) : Type := cstate -> CRes X.

(* Class-supplied binders parenthesized (p529 trap: implicit binders are
   refused in Functor/Monad fields). *)
Definition retM (X : Type) (x : X) : M X := fun s => @CDone X (cfrag s) x.

Definition bindM (X Y : Type) (m : M X) (k : X -> M Y) : M Y :=
  fun s => match m s with
           | @CDone  _ l x => k x (mkCS (cfuel s) l (chint s))
           | @CLoop  _ l   => @CLoop Y l
           | @CTrap  _ l   => @CTrap Y l
           end.

Definition fmapM (X Y : Type) (f : X -> Y) (m : M X) : M Y :=
  fun s => match m s with
           | @CDone  _ l x => @CDone Y l (f x)
           | @CLoop  _ l   => @CLoop Y l
           | @CTrap  _ l   => @CTrap Y l
           end.

#[global] Instance Functor_M : Functor M := { fmap := fmapM }.
#[global] Instance Monad_M  : Monad  M := { ret := retM; bind := bindM }.

(* The target supplies `iter` (p529 verdict: this is where the budget lives;
   FoldStateT's transformer `iter` encodes no resumption policy - do not build
   on it).  D1 shape: the step function appends NOTHING (the D1 arms - h empty,
   g trap, mstep/mstuck append-free - make this a fact, lemma
   `iterF_appends_nothing` below), and the exhausted budget yields the `CLoop`
   verdict with no appended construct: the compile-fuel artifact IS the verdict
   (header: two stucks).  Field order {R I} per ITree/Basics/Basics.v:92-93. *)
(* Fix measured on the first D1 build (the trap, restated for the next reader):
   the compcert import window (`Integers`/`Values`) leaves a Z-flavored numeral
   scope in effect, so every bare nat literal in this file resolves to `Z0` -
   including `iterF`'s `0` PATTERN against `n : nat` ("Found a constructor of
   inductive type Z while a constructor of nat is expected"; patterns are not
   type-directed, and the Realize family never sees this because it has no bare
   nat literals).  Nat literals here are qualified (`Datatypes.O`) or scoped
   (`%nat`). *)
Fixpoint iterF (I R : Type) (f : I -> M (I + R)) (n : nat) (i : I) (s : cstate) : CRes R :=
  match n with
  | Datatypes.O => @CLoop R (cfrag s)
  | Datatypes.S n' =>
      match f i s with
      | @CDone  _ l (inl i') => @iterF I R f n' i' (mkCS n' l (chint s))
      | @CDone  _ l (inr r)  => @CDone R l r
      | @CLoop  _ l          => @CLoop R l
      | @CTrap  _ l          => @CTrap R l
      end
  end.

#[global] Instance MonadIter_M : MonadIter M :=
  { iter := fun R I f i s => @iterF I R f (cfuel s) i s }.

(* Kernel trees over `void1` never expose `StepF`, and the checked fragment
   never exposes `StuckF`: mstep/mstuck exist only because `fold`'s dictionary
   demands them; both spellings append nothing. *)
#[global] Instance MonadStep_M : MonadStep M :=
  { mstep := fun s => @CDone unit (cfrag s) tt }.

#[global] Instance MonadStuck_M : MonadStuck M :=
  { mstuck := fun X => fun s => @CTrap X (cfrag s) }.

(* ============================================================================
   2. The two half-morphisms. ============================================================================ *)

(* The coalgebra side is pure: `void1` has no constructor, so h is the empty
   match (p529 trap: an empty match in term position needs BOTH `return` and
   `with`).  This is strategy sec. 3's `h : void1 ~> M := ... (kernel is pure)`
   verbatim. *)
Definition h : void1 ~> M :=
  fun (X : Type) (e : void1 X) => match e return M X with end.

(* D1's branch answer: TRAP.  Decision 15's law is that the bool at a `BrF`
   site is forced by a candidate-existence certificate ("left priority" alone
   is wrong on `Choice Fail (Ret 1)` - p529 law 3), and that certificate is the
   choice corner (D4).  Until then the leaf emits NO C for a choice program -
   the honest reading of the FoldCTree horn: a fold that resolves branches
   need not preserve weak bisimilarity, so the emitted C is only defined on
   determinate programs, and an uncertified choice IS undefined behavior of the
   compiler, not a silent pick.  `chint` is the seam D4 fills. *)
Definition g : B2 ~> M :=
  fun (X : Type) (b : B2 X) (s : cstate) =>
    match (chint s) with
    | Some b' => match b in B2 Y return CRes Y with
                 | branch2 => @CDone bool (cfrag s) b'
                 end
    | None    => match b in B2 Y return CRes Y with
                 | branch2 => @CTrap bool (cfrag s)
                 end
    end.

(* ============================================================================
   3. compile: one fold, one terminal policy. ============================================================================ *)

(* The terminal write is the ONLY construct D1 emits, and it is the landed
   `Lower.v` spelling, not a re-derivation: `Sset lower_res (vconst v)` is
   exactly the statement `lower (Ret v)` writes (Lower.v:162), evaluated by the
   already-attested `eval_vconst_val` (Realize.v increment B).  The verdicts
   without a value write - `SFail` ("fail as zero", PLAN T2: a value candidate
   of zero, so no candidate is written; p529 `b_fail`) and the kernel budget's
   `SStuck` (a result, not a rule) - terminate with `Sskip` and keep their
   meaning in the `CDone` value. *)
Definition terminal_stmt (r : SResult) : Clight.statement :=
  match r with
  | SOk v   => Clight.Sset Lower.lower_res (Lower.vconst v)
  | SFail   => Clight.Sskip
  | SStuck  => Clight.Sskip
  end.

(* The hylo (strategy sec. 3, verbatim shape): `compile` folds `denE` output
   through the algebra at one shared budget - the kernel-side fuel bounds the
   denotation, the same number seeds the accumulator's `iter` (the strategy's
   single-`fuel` spelling), and the terminal policy appends the one write from
   the observed result.  No goal in this file asks `compile` for a normal form
   of a tree (decision 14's checkable guard rail: the budget law makes the
   working set proportional to the observations the goal mentions). *)
Definition compile (p : Expr) (fuel : nat) : CRes SResult :=
  match fold h g (denE nil p fuel) (cstate0 fuel) with
  | @CDone _ frag r => @CDone SResult (frag ++ [terminal_stmt r]) r
  | @CLoop _ frag   => @CLoop SResult frag
  | @CTrap _ frag   => @CTrap SResult frag
  end.

(* ============================================================================
   4. The budget law, first-class so a lane can cite it (strategy sec. 5:
   "fragment length <= fuel by construction (a two-line induction on iterF,
   which I'd make a first-class lemma precisely so it can be cited when a lane
   starts costing too much)").  D1's exact statement is even smaller than the
   strategy's bound: the D1 algebra appends NOTHING during unrolling - every
   arm `fold`'s step function can take through this target (retM, fmapM over
   the hint `g`, mstep, mstuck) carries the state's fragment unchanged.

   How this proof had to be written, measured on the first D1 builds (each is
   the budget law teaching itself):
   (a) The first draft quantified the lemma over an ARBITRARY step function and
   was false - an arbitrary algebra may append; the stability fact belongs to
   THIS algebra (`h` empty, `g` the hint-trap), exactly as stated.
   (b) `fold h g t s` mentions no fuel: the budget rides in the state (`iter`
   resolves to the target's `iterF` at `cfuel s`), so an induction on a
   `fold`-headed goal yields no IH, and Rocq 9.1.1 will not unfold the
   class-resolved `iter` for you (`unfold iter`, `cbn [iter]` both fail -
   "Cannot find a relation to rewrite").  The induction therefore runs on the
   target's own `iterF` applied to an explicit step mirror `cstep`;
   `fold_bridge` pins the mirror to the library `fold` at pure convertibility
   (`reflexivity`), which is the point: a mirror that drifted from
   Interp/Fold.v:35-43 would make the pin fail.
   (c) Neither cbn nor cbv can peel the step goal: cbn's delta policy refuses
   unfoldings that land on a stuck match (`cbn [cstep]` never even exposes
   `observe t` to `destruct`), and cbv expands everything whitelisted -
   including the recursive call - leaving a raw fix and an inlined step
   function with no occurrence the IH could apply at.  The peel is two Leibniz
   lemmas, `iterF_S` and `cstep_observe`, REWRITTEN into the goal: rewriting
   fires only at the applied occurrence, so the recursive call's bare `cstep`
   argument survives intact in the library spelling the IH consumes.
   (d) `t` and `s` must be generalized BEFORE the induction (an IH formed
   after `induction fuel` is already pinned to the original tree and state),
   and the conclusion states the fragment against a named `acc` instead of
   `cfrag s`: with `cfrag s` in the conclusion, the match unifier binds the
   IH's state metavariable from the ARMS (`cfrag ?s` vs `cfrag s` decomposes
   to `?s := s`) before the scrutinee can force the `mkCS` update, and the
   unification dies on "s vs record".  With `acc` the arms carry no metavariable
   clash, and the discharged side condition `cfrag (mkCS ...) = acc` is just
   the IH hypothesis after one projection step.
   (e) `B2`'s single constructor is `branch2 : B2 bool` (CTree/Core/Index.v:19):
   a branch is always answered in `bool`, but the goal keeps it as the partial
   application `g X c`, and `(g X c) s` is not a subterm - the BrF arm needs
   `destruct c` (the index refinement) plus the pin `fmap_g_answer` before
   `chint s` can be case-split. ============================================================ *)

(* The mirror of `fold`'s step function (Interp/Fold.v:35-43), spelled in the
   constructor order `fold` matches on: RetF / StuckF / StepF / GuardF / VisF /
   BrF per CTreeDefinitions.v.  `void1`'s VisF arm and the hintless BrF arm are
   where `h`'s empty match and the trap live. *)
Definition cstep (u : ctree void1 B2 SResult) : M (ctree void1 B2 SResult + SResult) :=
  match observe u with
  | RetF r => ret (inr r)
  | StuckF => mstuck _
  | StepF u1 => fmap (fun _ : unit => inl u1) mstep
  | GuardF u1 => ret (inl u1)
  | @VisF _ _ _ _ X e k => fmap (fun x : X => inl (k x)) (h _ e)
  | @BrF _ _ _ _ X c k => fmap (fun x : X => inl (k x)) (g _ c)
  end.

(* The sanity pin: the library fold IS this target's `iterF` over `cstep`, with
   the budget taken from the state.  It proves by pure conversion - that is the
   claim: a mirror that drifted from the library would make this fail. *)
Lemma fold_bridge : forall (t : ctree void1 B2 SResult) (s : cstate),
  fold h g t s = @iterF (ctree void1 B2 SResult) SResult cstep (cfuel s) t s.
Proof. intros t s. reflexivity. Qed.

(* The peel lemmas: each an iota step of `iterF` / one delta step of `cstep`,
   stated as Leibniz equalities (each closes by `reflexivity`).  They exist so
   the induction below peels by REWRITING - which (i) does not care whether the
   unfolding "would reduce" (cbn's veto, fact (c) above) and (ii) rewrites only
   the applied occurrence, keeping the recursive call `@iterF ... cstep ...` in
   the library spelling the IH consumes. *)
Lemma iterF_S : forall (f : ctree void1 B2 SResult -> M (ctree void1 B2 SResult + SResult))
    (k : nat) (i : ctree void1 B2 SResult) (s : cstate),
  @iterF (ctree void1 B2 SResult) SResult f (Datatypes.S k) i s
  = match f i s with
    | @CDone _ l (inl i') =>
        @iterF (ctree void1 B2 SResult) SResult f k i' (mkCS k l (chint s))
    | @CDone _ l (inr r) => @CDone SResult l r
    | @CLoop _ l => @CLoop SResult l
    | @CTrap _ l => @CTrap SResult l
    end.
Proof. reflexivity. Qed.

Lemma cstep_observe : forall (t : ctree void1 B2 SResult) (s : cstate),
  cstep t s
  = (match observe t return M (ctree void1 B2 SResult + SResult) with
     | RetF r => ret (inr r)
     | StuckF => mstuck _
     | StepF u1 => fmap (fun _ : unit => inl u1) mstep
     | GuardF u1 => ret (inl u1)
     | @VisF _ _ _ _ X e k => fmap (fun x : X => inl (k x)) (h _ e)
     | @BrF _ _ _ _ X c k => fmap (fun x : X => inl (k x)) (g _ c)
     end) s.
Proof. reflexivity. Qed.

(* One BrF-specific pin.  `B2` has a single constructor, `branch2 : B2 bool`
   (CTree/Core/Index.v:19), so a tree's branch is always answered in `bool`,
   but the goal holds it as the PARTIAL application `g X c` fed into fmap -
   `(g X c) s` is not a subterm, so `destruct (g _ c s)` has nothing to catch.
   The pin evaluates the whole partial application at `s` as one Leibniz step
   cbv-expands the composition, `destruct (chint s)` substitutes at BOTH
   sides' visible scrutinees, and both reduce to the same arms.  (A bare
   `reflexivity` fails here: after delta the left is the NESTED match
   `match (match chint s with ...) with ... end`, and Coq does not convert a
   nested match to a flattened one - distribution needs the case split.) *)
Lemma fmap_g_answer : forall (k0 : bool -> ctree void1 B2 SResult) (s : cstate),
  (fmap (fun x : bool => inl (k0 x)) (g bool branch2)) s
  = match chint s with
    | Some ans => @CDone (ctree void1 B2 SResult + SResult) (cfrag s) (inl (k0 ans))
    | None => @CTrap (ctree void1 B2 SResult + SResult) (cfrag s)
    end.
Proof.
  intros k0 s. cbv [fmap g Functor_M fmapM]. destruct (chint s); reflexivity.
Qed.

(* The stability law, with the fragment compared to a named accumulator `acc`
   (fact (d) above: this is what makes the recursive `apply IH` unify at all). *)
Lemma iterF_frag_stable :
  forall (fuel : nat) (t : ctree void1 B2 SResult) (s : cstate)
    (acc : list Clight.statement),
  cfrag s = acc ->
  match @iterF (ctree void1 B2 SResult) SResult cstep fuel t s with
  | @CDone _ l _ => l = acc
  | @CLoop _ l   => l = acc
  | @CTrap _ l   => l = acc
  end.
Proof.
  intros fuel. induction fuel as [| k IH].
  - intros t s acc H. cbn [iterF]. exact H.
  - intros t s acc H. rewrite iterF_S, cstep_observe.
    (* Peel one observation, exactly as `fold` does. *)
    destruct (observe t).
    + (* RetF: `ret (inr r)` - retM appends nothing; the whole verdict
         converts to `cfrag s = acc`, which IS the hypothesis. *)
      exact H.
    + (* StuckF: `mstuck _` appends nothing. *)
      exact H.
    + (* StepF: `fmap _ mstep` - mstep appends nothing; the residual re-enters
         iterF with the same fragment, so the IH hypothesis is H up to one
         projection step (cfrag of mkCS reduces). *)
      apply IH. cbn [cfrag]. exact H.
    + (* GuardF: `ret (inl u1)` - the residual re-enters, fragment unchanged. *)
      apply IH. cbn [cfrag]. exact H.
    + (* VisF: `void1` has no constructor - `h`'s empty match closes the arm. *)
      destruct e.
    + (* BrF: `fmap (inl o) (g _ c)`.  `destruct c` is the index refinement
         `branch2 : B2 bool` (fact (e) above); then `fmap_g_answer` evaluates
         the partial application at `s`, so `destruct (chint s)` sees its own
         scrutinee.  The trapped answer converts to `cfrag s = acc` (the
         hypothesis, no recursion); the hinted answer re-enters with the
         fragment unchanged. *)
      destruct c; rewrite fmap_g_answer.
      destruct (chint s); first [ (apply IH; cbn [cfrag]; exact H) | exact H ].
Qed.

(* The fold-side corollary at the initial state: before the single terminal
   append, the accumulated fragment is EMPTY. *)
Lemma c_frag_of_fold : forall (p : Expr) (fuel : nat),
  match fold h g (denE nil p fuel) (cstate0 fuel) with
  | @CDone _ frag _ => frag = @nil Clight.statement
  | @CLoop _ frag   => frag = @nil Clight.statement
  | @CTrap _ frag   => frag = @nil Clight.statement
  end.
Proof.
  intros p fuel. rewrite fold_bridge.
  apply iterF_frag_stable.
  cbn [cfrag cstate0]. reflexivity.
Qed.

(* Consuming the verdict: an empty pre-terminal fragment means a `CDone`
   fragment is EXACTLY the one terminal write and a `CLoop`/`CTrap` fragment is
   empty.  The hypothesis states stability for the fold verdict, the conclusion
   for the verdict AFTER the terminal append (the `compile` arm spelling), so
   the lane lemma below never destructs a fuel-stuck fold term. *)
Lemma frag_bound_of_verdict : forall (v : CRes SResult),
  (match v with
   | @CDone _ frag _ => frag = @nil Clight.statement
   | @CLoop _ frag   => frag = @nil Clight.statement
   | @CTrap _ frag   => frag = @nil Clight.statement
   end) ->
  match (match v with
         | @CDone _ frag r => @CDone SResult (frag ++ [terminal_stmt r]) r
         | @CLoop _ frag   => @CLoop SResult frag
         | @CTrap _ frag   => @CTrap SResult frag
         end) with
  | @CDone _ l _ => Datatypes.length l = 1%nat
  | @CLoop _ l   => Datatypes.length l = 0%nat
  | @CTrap _ l   => Datatypes.length l = 0%nat
  end.
Proof.
  intros v Hr.
  destruct v as [frag r | frag | frag];
    cbn [Datatypes.length Datatypes.app] in Hr |- *.
  - rewrite Hr. reflexivity.
  - rewrite Hr. reflexivity.
  - rewrite Hr. reflexivity.
Qed.

(* The citable budget law, strategy strength at D1 exactness. *)
Lemma c_compile_frag_bound : forall (p : Expr) (fuel : nat),
  match compile p fuel with
  | @CDone _ l _ => Datatypes.length l = 1%nat
  | @CLoop _ l   => Datatypes.length l = 0%nat
  | @CTrap _ l   => Datatypes.length l = 0%nat
  end.
Proof.
  intros p fuel. unfold compile.
  apply frag_bound_of_verdict.
  apply c_frag_of_fold.
Qed.

(* ============================================================================
   5. Corner 1 (strategy sec. 8): Ret / Fail / Seq, at Leibniz `=`, `reflexivity`
   only - the p529 specimens lifted onto the Clight accumulator, with the
   terminal write appended.  Corner names carry the p529 lineage. ============================================================================ *)

(* Arm `Ret`: one `RetF` observation, the value is `SOk v`, the fragment is the
   terminal write at the landed `vconst` spelling (p529 `b_ret`, plus terminal). *)
Lemma c_ret :
  compile (Ret (VInt 3)) 1%nat
  = @CDone SResult [Clight.Sset Lower.lower_res (Lower.vconst (VInt 3))] (SOk (VInt 3)).
Proof. reflexivity. Qed.

(* Arm `Fail`: fail as zero (p529 `b_fail`) - a result, so no trap, and no
   candidate to write. *)
Lemma c_fail :
  compile Fail 1%nat = @CDone SResult [Clight.Sskip] SFail.
Proof. reflexivity. Qed.

(* Arm `Seq`: the `>>=` spine collapses inside `observe` (p529 law 4; `b_seq`
   compiled at zero emitted cost) - one observation, one terminal write, and it
   is the SECOND value, because the kernel's `Seq` arm discards the prefix's
   (Semantics.v:219-224; the very shape T5's lemmas license reordering
   around). *)
Lemma c_seq :
  compile (Seq (Ret (VInt 1)) (Ret (VInt 2))) 2%nat
  = @CDone SResult [Clight.Sset Lower.lower_res (Lower.vconst (VInt 2))] (SOk (VInt 2)).
Proof. reflexivity. Qed.

(* The two-stucks guard, leaf-side (p529 keeps these adjacent for exactly this
   reason).  Kernel fuel exhaustion is DATA: a four-deep `Seq` at fuel 3 spends
   the kernel budget one unit per nesting layer (Semantics.v:127, decision 2),
   the innermost `Ret` meets `denE rho e 0 = sret SStuck`, the stuck value
   propagates through the bind spine, and the compile carries it as a `CDone` -
   `Sskip` terminal (nothing to write), NO loop-shaped verdict. *)
Definition e_nest4 : Expr :=
  Seq (Seq (Seq (Ret (VInt 1)) (Ret (VInt 2))) (Ret (VInt 3))) (Ret (VInt 4)).

Lemma c_kernel_fuel_nest :
  compile e_nest4 3%nat = @CDone SResult [Clight.Sskip] SStuck.
Proof. reflexivity. Qed.

(* Compile fuel exhaustion is the VERDICT: `iter` cannot ask for the next
   observation, so `compile` stops at `CLoop` with an empty fragment and no
   terminal write - and this holds even for the simplest program, because the
   compile-side budget is about OBSERVATIONS, not about the program. *)
Lemma c_compile_fuel :
  compile (Ret (VInt 3)) 0%nat = @CLoop SResult nil.
Proof. reflexivity. Qed.

(* The D1 negative corner: an uncertified choice has no defined emitted C
   (header section 2).  `denE` maps `Choice` to `br2` (Semantics.v:217), the
   fold exposes `BrF`, D1's `g` traps with the fragment untouched.  This is the
   corner D4 replaces with the candidate-peek scheduler - pinned now so the
   replacement is a measured delta, not a silent change. *)
Lemma c_choice_traps :
  compile (Choice (Ret (VInt 1)) Fail) 2%nat = @CTrap SResult nil.
Proof. reflexivity. Qed.

(* ============================================================================
   6. Gluing to the landed estate: the terminal write EXECUTES to the kernel
   value, and it does so through the already-gate-attested lemmas only -
   `eval_vconst_val` (Realize.v:404) and `exec_Sset`.  This is the per-arm
   instance of strategy sec. 6's chain link 1 (the simulation, in its D1 form:
   the observation trace is one `RetF`, the statement trace is one `exec_Sset`
   derivation); the general `Compile_Sim` grows with the corners, and this
   lemma is the shape every corner instance slots into.  Stated for every
   value, not for a corner: the lemma is one line because the lowering is
   already attested. *)

Lemma c_terminal_exec : forall (v : Val),
  Clight1.exec_stmt Realize.ge0 Clight.empty_env Realize.le0 Mem.empty
    (terminal_stmt (SOk v)) Events.E0
    (PTree.set Lower.lower_res (Realize.clight_of_val v) Realize.le0)
    Mem.empty ClightBigstep.Out_normal.
Proof.
  intros v. apply ClightBigstep.exec_Sset. apply Realize.eval_vconst_val.
Qed.

(* And the fragment `compile` pins is the fragment `lower` pins on the same
   value corner - `lower (Ret v) = Lclight (Sset lower_res (vconst v))`
   (Lower.v:162), flattened by `clight_of` (Realize.v:62).  D1's fusion reading
   in its purest specimen: the hylo and the landed lowering agree CONSTRUCT FOR
   CONSTRUCT on the value corner, at Leibniz `=`. *)
Lemma c_agrees_with_lower : forall (v : Val),
  clight_of (lower (Ret v)) = terminal_stmt (SOk v).
Proof. intros v. reflexivity. Qed.

(* ============================================================================
   7. Corner 2 (strategy sec. 8's second stop): primops through the fold -
   value-faithful straight-line, pins only.

   The corner spelling mirrors RealizeCorners.v:70's `prim_corner` (decision 5:
   `op[a1..an]` = `App (Ret (VPrim p)) (TupE (map Ret vs))`), redefined LOCAL to
   this leaf so the compile leaf never depends on a Realize-family leaf.

   Measured kernel budget (not estimated): the prim spine - `App` head, `TupE`
   argument evaluation, the prim application - spends one unit per nesting layer
   (Semantics.v:127, decision 2), and it needs FIVE: fuel 4 exhibits the stuck
   specimen, fuel 5 completes (pinned as a lemma pair below; the `Ret`/`Seq`
   corners of section 5 were 1 and 2 - prim depth is measured, like everything
   here).

   What compile EMITS for a primop: nothing but the final constant write.  The
   kernel's `prim_total` (Syntax.v:344) runs INSIDE the observation; the fold
   sees only its resulting `RetF` (p529 law 4).  Three consequences, recorded as
   pins rather than prose:

   (a) The guards are the paper's test shape (Fig. 10, lines 452-459):
       `PGt a b` success carries the LEFT operand forward (`PRes (VInt a)`),
       failure is `PFail` -> `SFail` -> `Sskip` (fail as zero).  T6's Vint-1
       guard map (`prim_guard_match_*`, RealizeCompose.v:177) is the C-side
       spelling of the SAME fact for its binop-emitting lowering; the two
       spellings agree on value and the golden test pins THIS one (strategy
       sec. 9 amendment A).
   (b) The div semantics fork (decision 11, probe p528) cannot bite here: the
       kernel value is `Z.div` - true floor, `7 / (-2) = (-7) / 2 = -4`
       (RealizeCompose's `floor_literal_*` rungs) - and compile emits NO division
       node: it writes the constant, so the emitted C executes what the kernel
       computed, by construction.  The truncating `Int64.divs` leg and its `divZ`
       ladder belong to T6's `prim_clight` binop spelling (pinned there by
       `divZ_ladder_div`), not to this algebra.
   (c) A `PStuck` prim result (the zero-divisor arm, Syntax.v:349) arrives as
       `SStuck` DATA in a `CDone` verdict - the third stuck specimen, and an
       honesty note the corpus must keep: at the verdict level prim-guard stuck
       and kernel-fuel stuck are the SAME observable shape (`CDone [Sskip]
       SStuck`); the distinction is provenance, not output.  Section 5's
       `c_kernel_fuel_nest` pins the fuel side on a division-free program.

   Every corner below satisfies the budget law (`c_compile_frag_bound`):
   exactly one write for the value corners, zero for the fail/stuck corners. *)

Definition cprim (p : Prim) (vs : list Val) : Expr :=
  App (Ret (VPrim p)) (TupE (map Ret vs)).

(* The measured minimum: spine stuck at 4, complete at 5. *)
Lemma c_prim_fuel4_stuck :
  compile (cprim PAdd [VInt 2; VInt 3]) 4%nat
  = @CDone SResult [Clight.Sskip] SStuck.
Proof. reflexivity. Qed.

Lemma c_prim_add :
  compile (cprim PAdd [VInt 2; VInt 3]) 5%nat
  = @CDone SResult [Clight.Sset Lower.lower_res (Lower.vconst (VInt 5))] (SOk (VInt 5)).
Proof. reflexivity. Qed.

(* (a) Guard success carries the left operand (Fig. 10's `gt1` witness shape). *)
Lemma c_prim_gt_left :
  compile (cprim PGt [VInt 3; VInt 2]) 5%nat
  = @CDone SResult [Clight.Sset Lower.lower_res (Lower.vconst (VInt 3))] (SOk (VInt 3)).
Proof. reflexivity. Qed.

(* (a) Guard failure is fail-as-zero: a result (not a trap), no candidate written. *)
Lemma c_prim_gt_fail :
  compile (cprim PGt [VInt 2; VInt 3]) 5%nat
  = @CDone SResult [Clight.Sskip] SFail.
Proof. reflexivity. Qed.

(* (b) The two negative quadrants of the floor ladder, as constants: the kernel
       floors (Z.div), and C never sees a division. *)
Lemma c_prim_div_floor_negq :
  compile (cprim PDiv [VInt 7; VInt (-2)]) 5%nat
  = @CDone SResult [Clight.Sset Lower.lower_res (Lower.vconst (VInt (-4)))] (SOk (VInt (-4))).
Proof. reflexivity. Qed.

Lemma c_prim_div_floor_negp :
  compile (cprim PDiv [VInt (-7); VInt 2]) 5%nat
  = @CDone SResult [Clight.Sset Lower.lower_res (Lower.vconst (VInt (-4)))] (SOk (VInt (-4))).
Proof. reflexivity. Qed.

(* (c) The prim-guard stuck: zero divisor is `PStuck` in prim_total, SStuck data
       in a CDone verdict, `Sskip` terminal - the third stuck specimen. *)
Lemma c_prim_div_zero :
  compile (cprim PDiv [VInt 1; VInt 0]) 5%nat
  = @CDone SResult [Clight.Sskip] SStuck.
Proof. reflexivity. Qed.

(* `PNEq` in both directions: equal is `PFail` (the paper's negative-guard
   polarity, Syntax.v:357), different carries the left operand. *)
Lemma c_prim_neq_equal_fail :
  compile (cprim PNEq [VInt 1; VInt 1]) 5%nat
  = @CDone SResult [Clight.Sskip] SFail.
Proof. reflexivity. Qed.

Lemma c_prim_neq_diff :
  compile (cprim PNEq [VInt 1; VInt 2]) 5%nat
  = @CDone SResult [Clight.Sset Lower.lower_res (Lower.vconst (VInt 1))] (SOk (VInt 1)).
Proof. reflexivity. Qed.
