(* p529 part A - can the compile be a SPECIALIZED fold, i.e. a hylomorphism whose
   carrier is never materialized?

   Facts this probe is testing, all read out of the pinned packages on this box:
     CTree/Core/CTreeDefinitions.v:231-241  `cofix _subst ...` / `bind u k := subst k u`
         -> the source-side monad is corecursive; no fold is chosen there, so nothing
            of the shape `denote p = value` can ever compute.
     CTree/Interp/Fold.v:29-45  `fold (h : E ~> M) (g : B ~> M) : ctree E B ~> M`, defined
         as `iter (fun t => match observe t with ... end)` - ONE observation per step, a
         residual (`inl`) handed back instead of a tower kept.
     CTree/Interp/FoldCTree.v:25-29  the library's own warning that generic fold results
         need "heavy axiomatization" of M and it "simply specializes results to specific Ms".
     CTree/Core/Index.v:19  `Variant B2 : Type -> Type := | branch2 : B2 bool` - the branch
         payload is a bool, so a DETERMINATE branch algebra is literally a decision that
         returns a bool.  That is where the candidate-set semantics becomes compilation.
     ITree/Basics/Basics.v:93  `iter : forall {R I}, (I -> M (I + R)) -> I -> M R` - the loop
         operator is supplied by the TARGET monad, i.e. the target decides what a loop is.
     CTree/Interp/FoldCTree.v CounterExample  `~ (interp h t1 ~ interp h t2)` although
         `t1 ~ t2` (br2 commutes/stucks): a fold that resolves branches does NOT preserve
         weak bisimilarity in general.  Recorded because it is the same horn our
         RULES-AUDIT sec. 4 T2-vs-Fig-13 row is about.

   Design under test: M accumulates emitted code, carries the unrolling budget in its
   state, and implements `iter` by a fuel-decreasing Fixpoint whose exhausted-budget case
   EMITS A LOOP (the resumption boundary) instead of demanding the rest of the tower.
   Everything here is Leibniz `=` and `reflexivity`-level: no `bind`, no cbn/cbv cascade. *)

(* Two binder traps measured on this box (Rocq 9.1.1), both from the ctrees-side import
   style.  (i) `Definition foo {A : Type} ...` makes A IMPLICIT, and ExtLib's Functor/Monad
   class fields want them explicit - `fmap := fmapM` is then refused with
   "The term \"fmapM\" has type \"(?X -> ?Y) -> M ?X -> M ?Y\" while it is expected to have type
   \'forall A B : Type, (A -> B) -> M A -> M B\'".  Spell the class-supplied binders with
   parentheses.  (ii) For `Inductive MRes (X : Type) : Type`,
   a PATTERN must supply the parameter - `| MDone l x` is refused with "constructor MDone (in
   type MRes) is expected to be applied to 3 arguments while it is actually applied to 2",
   and a `return` annotation does not fix it; `| @MDone _ l x` does.  Terms in a typed
   position are fine, but the goals below spell the index anyway so the probe says what it
   means. *)
From CTree Require Import CTree Eq Core.Utils Interp.Fold.
From ITree Require Import Basics.Basics.
From ExtLib Require Import Structures.Functor Structures.Monad.
From Stdlib Require Import Init.Datatypes Lists.List.

(* Third trap: `Import ListNotations` is what the repo's files carry for `[]` and `++`.  Without
   it the ctrees scope leaves `++` unparsed ("[term level 60] expected after '++'"), and in Rocq
   9.1 it is reachable only as an `Import` of a child of the loaded Lists.List, not as a
   top-level `From ... Require Import ListNotations` ("Cannot find module ListNotations"). *)
Import ListNotations.

(* A stand-in for the kernel's effect signature: no external events (the kernel denotation
   is `ctree void1 B2 SResult`, so the compile's real work is in the branch algebra). *)
Variant E0 : Type -> Type := .

Variant Res0 : Type := rok | rfail.

(* ---------------- the target monad: an accumulating fragment ---------------- *)

(* emitted instructions, not text: the target has a step, a resolved branch, a trap,
   and a loop node for a budget it could not finish spending *)
Variant Instr : Type := i_step | i_branch_left | i_trap | i_loop.
Definition frag := list Instr.

(* `out` is taken by the ctrees/itrees namespace; the field is named ofrag *)
Record st := mkSt { fuel : nat; ofrag : frag }.
Definition st0 (n : nat) : st := mkSt n nil.

Inductive MRes (X : Type) : Type :=
| MDone  : frag -> X -> MRes X        (* emitted, resolved *)
| MLoopR : frag -> MRes X             (* emitted, unresolved: a loop node in the target *)
| MTrap  : frag -> MRes X.            (* emitted, stuck *)

Definition M (X : Type) := st -> MRes X.

(* The ctrees/itrees namespace does not clash; what bites is that a constructor of an
   indexed inductive takes its index positionally when the expected type is a Definition
   (`M X` does not drive index insertion).  Spell the index with `@`. *)
Definition retM (X : Type) (x : X) : M X := fun s => @MDone X (ofrag s) x.

Definition bindM (X Y : Type) (m : M X) (k : X -> M Y) : M Y :=
  fun s => match m s with
           | @MDone  _ l x => k x (mkSt (fuel s) l)
           | @MLoopR _ l   => @MLoopR Y l
           | @MTrap  _ l   => @MTrap  Y l
           end.

Definition fmapM (X Y : Type) (f : X -> Y) (m : M X) : M Y :=
  fun s => match m s with
           | @MDone  _ l x => @MDone Y l (f x)
           | @MLoopR _ l   => @MLoopR Y l
           | @MTrap  _ l   => @MTrap  Y l
           end.

#[global] Instance Functor_M : Functor M := { fmap := fmapM }.
#[global] Instance Monad_M  : Monad  M := { ret := retM; bind := bindM }.

(* The loop operator, supplied by the TARGET: unroll while the budget lasts, and when it is
   spent emit a loop node rather than asking for the rest of the carrier.  Structurally
   recursive on the budget - there is no cofix and no partiality anywhere on this path. *)
Fixpoint iterF (I R : Type) (f : I -> M (I + R)) (n : nat) (i : I) (s : st) : MRes R :=
  match n with
  | 0 => @MLoopR R (ofrag s ++ [ i_loop ])
  | S n' =>
      match f i (mkSt n' (ofrag s)) with
      | @MDone  _ l (inl i') => @iterF I R f n' i' (mkSt n' l)
      | @MDone  _ l (inr r)  => @MDone R l r
      | @MLoopR _ l          => @MLoopR R l
      | @MTrap  _ l          => @MTrap  R l
      end
  end.

#[global] Instance MonadIter_M : MonadIter M :=
  (* NOTE the class order: itrees declares `iter : forall {R I}, (I -> M (I + R)) -> I -> M R`,
     i.e. the *result* binder is named first.  Bind them in the class order. *)
  { iter := fun R I f i s => @iterF I R f (fuel s) i s }.

#[global] Instance MonadStep_M : MonadStep M :=
  (* mstep : M unit, and M unfolds to `st -> MRes unit`, so the state binder IS the
     argument: one lambda, not two. *)
  { mstep := fun s => @MDone unit (ofrag s ++ [ i_step ]) tt }.

#[global] Instance MonadStuck_M : MonadStuck M :=
  { mstuck := fun X => fun s => @MTrap X (ofrag s ++ [ i_trap ]) }.

(* ---------------- the two half-morphisms the fold wants ---------------- *)

(* No effects to implement: E0 is empty.  An empty match in term position needs BOTH `return T`
   and `with`: `match e end` and `match e with end` are parse errors (Rocq 9.1.1). *)
Definition h0 : E0 ~> M := fun (X : Type) (e : E0 X) => match e return M X with end.

(* THE branch algebra - and here the probe found something real, not cosmetic.

   `g : B ~> M` means `forall X, B X -> M X`: the algebra must produce a value of the PAYLOAD
   type X, for every X, out of the branch token alone.  `Variant B2 : Type -> Type :=
   | branch2 : B2 bool` (CTree/Core/Index.v:19) means the only inhabitant is `branch2 : B2 bool`,
   so dependent pattern matching on `b : B2 X` is what forces the index equation X = bool and
   licenses `true : X`.  In other words: a determinate branch scheduler is not "a function
   returning true" - it is a pattern match that decides the payload type, and the decision
   (which candidate, hence which equation) is exactly where the DCont/WAMI candidate semantics
   enters the compile.  Eta-short forms (`fun _ _ => ...`) do not survive this: Coq's
   eta-expansion eats the payload binder, and the `~>` notation is ambiguous under
   `Local Open Scope ctree_scope` for several payload arities.  Spell the binders. *)
Definition g0 : B2 ~> M :=
  fun (X : Type) (b : B2 X) (s : st) =>
    match b in B2 Y return MRes Y with
    | branch2 => @MDone bool (ofrag s ++ [ i_branch_left ]) true
    end.

(* ---------------- the compile, as ctrees' specialized fold ---------------- *)

Definition compile (X : Type) (t : ctree E0 B2 X) : M X := fold h0 g0 t.

(* ---------------- per-arm Leibniz equalities, one arm per goal ---------------- *)

Definition c_ret : ctree E0 B2 Res0 := go (RetF rok).
Goal compile _ c_ret (st0 6) = @MDone Res0 nil rok.
Proof. reflexivity. Qed.

Definition c_step : ctree E0 B2 Res0 := go (StepF (go (RetF rok))).
Goal compile _ c_step (st0 6) = @MDone Res0 [ i_step ] rok.
Proof. reflexivity. Qed.

Definition c_stuck : ctree E0 B2 Res0 := go StuckF.
Goal compile _ c_stuck (st0 6) = @MTrap Res0 [ i_trap ].
Proof. reflexivity. Qed.

Definition c_guard : ctree E0 B2 Res0 := go (GuardF (go (RetF rok))).
Goal compile _ c_guard (st0 1) = @MLoopR Res0 [ i_loop ].
Proof. reflexivity. Qed.

Definition c_branch : ctree E0 B2 Res0 :=
  go (BrF branch2 (fun b : bool => if b then go (RetF rok) else go (RetF rfail))).
Goal compile _ c_branch (st0 6) = @MDone Res0 [ i_branch_left ] rok.
Proof. reflexivity. Qed.

(* The resumption boundary, measured rather than asserted: a three-step chain compiled with
   a budget of two emits two steps and then a LOOP node, i.e. the carrier is never demanded. *)
Definition c_chain : ctree E0 B2 Res0 :=
  go (StepF (go (StepF (go (StepF (go (RetF rok))))))).
Goal compile _ c_chain (st0 2) = @MLoopR Res0 [ i_step; i_step; i_loop ].
Proof. reflexivity. Qed.
(* A measurement worth recording, not just a goal: the budget is consumed ONE observation per
   arm, `RetF` included.  Three `StepF` arms therefore spend three observations and never get
   to see the final `RetF` - the compile stops with a loop node, having emitted exactly three
   instructions.  The working set is bounded by the budget, by construction. *)
Goal compile _ c_chain (st0 3) = @MLoopR Res0 [ i_step; i_step; i_step; i_loop ].
Proof. reflexivity. Qed.

Goal compile _ c_chain (st0 4) = @MDone Res0 [ i_step; i_step; i_step ] rok.
Proof. reflexivity. Qed.

(* And the fold is a morphism in the only sense we need operationally: the emitted fragment
   of a composed pair is the concatenation of the fragments, checked at `=` for this target
   (a generic version is exactly the "heavy axiomatization" FoldCTree.v warns about). *)
Definition c_seq : ctree E0 B2 Res0 :=
  go (StepF (go (StepF (go (RetF rok))))).
Goal compile _ c_seq (st0 6) = @MDone Res0 [ i_step; i_step ] rok.
Proof. reflexivity. Qed.
