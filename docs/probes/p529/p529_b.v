(* p529 part B - the fold specialization on the KERNEL'S REAL effect and result sets.

   Part A (p529_a.v) proved the shape on stand-ins (E0/B2/Res0): nine Leibniz-`=` goals,
   all `reflexivity`, 0.42 s wall, 443 MiB peak.  Part A also measured the budget law:
   one observation per arm, `RetF` included.

   Part B asks the question the Compile.v leaf actually depends on:
     with E := void1 and the result domain := SResult (SOk / SFail / SStuck, the kernel's
     own), and with trees that are the output of the kernel's own `denE` - including the
     `br2` that `Choice` maps to and the `>>=` spine that `Seq` maps to -
   does the specialized ctrees `fold` still compute arm-by-arm at Leibniz `=`, and does it
   do so CLOSED (no new axioms)?

   Two things to keep apart, and this probe is the place where the repo has them side by side:
   (i)  the KERNEL's budget artifact: `denE rho e 0 = sret SStuck` - SStuck is a value of the
        result domain, produced by the denotation;
   (ii) the COMPILE's budget artifact: an exhausted fuel emits an `i_loop` instruction and
        returns MLoopR - a claim about the emitted fragment, not a semantic result.
   Confusing them is exactly the "denote, then read off the C" error decision 12f killed.

   The branch algebra here IS the candidate decision: `br2 t u = br branch2 (fun b => if b
   then t else u)` (CTree/Core/CTreeDefinitions.v:123-124), so `g0` returning the left
   candidate is the compiled form of "take candidate 1", and the determinacy analysis
   (det_struct / prim_total_res / the guard hypotheses) is what licenses returning THAT bool
   for a given program.  Note the library's own warning, FoldCTree.v CounterExample: a fold
   that resolves branches does not preserve weak bisimilarity in general
   (`~ (interp h t1 ~ interp h t2)` although `t1 ~ t2`).  That is the RULES-AUDIT sec. 4 horn
   again: the emitted C is only well-defined on determinate programs, which is the same
   hypothesis that makes `cog` a function at all. *)

From CTree Require Import CTree Eq Core.Utils Interp.Fold.
From ITree Require Import Basics.Basics.
From ExtLib Require Import Structures.Functor Structures.Monad.
From Stdlib Require Import Init.Datatypes Lists.List ZArith.
Import ListNotations.

From Timbda Require Import Syntax Semantics.

(* ---------------- the target monad, as in part A ---------------- *)

Variant Instr : Type := i_branch_left | i_step | i_trap | i_loop.
Definition frag := list Instr.
Record st := mkSt { fuel : nat; ofrag : frag }.
Definition st0 (n : nat) : st := mkSt n nil.

Inductive MRes (X : Type) : Type :=
| MDone  : frag -> X -> MRes X
| MLoopR : frag -> MRes X
| MTrap  : frag -> MRes X.

Definition M (X : Type) := st -> MRes X.

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
  { iter := fun R I f i s => @iterF I R f (fuel s) i s }.  (* class order: {R I} *)

#[global] Instance MonadStep_M : MonadStep M :=
  { mstep := fun s => @MDone unit (ofrag s ++ [ i_step ]) tt }.

#[global] Instance MonadStuck_M : MonadStuck M :=
  { mstuck := fun X => fun s => @MTrap X (ofrag s ++ [ i_trap ]) }.

(* ---------------- the two half-morphisms, on the kernel's signature ---------------- *)

Definition h0 : void1 ~> M := fun (X : Type) (e : void1 X) => match e return M X with end.

Definition g0 : B2 ~> M :=
  fun (X : Type) (b : B2 X) (s : st) =>
    match b in B2 Y return MRes Y with
    | branch2 => @MDone bool (ofrag s ++ [ i_branch_left ]) true
    end.

(* ---------------- the compile: ctrees' fold, specialized ---------------- *)

Definition compile (X : Type) (t : ctree void1 B2 X) : M X := fold h0 g0 t.

(* ---------------- the kernel's own denotations, compiled, one arm per goal ---------------- *)

(* Arm `Ret`: `denE _ (Ret v) _ = sret (SOk v)`; the fold emits nothing and returns the
   value at Leibniz `=`. *)
Lemma b_ret :
  compile _ (denE nil (Ret (VInt 3%Z)) 2) (st0 6) = @MDone SResult nil (SOk (VInt 3%Z)).
Proof. reflexivity. Qed.

(* Arm `Fail`: "fail as zero" (PLAN T2) - a value candidate, not a trap: the compile's own
   trap `MTrap` never appears for Fail. *)
Lemma b_fail :
  compile _ (denE nil Fail 2) (st0 6) = @MDone SResult nil SFail.
Proof. reflexivity. Qed.

(* Kernel budget artifact vs compile budget artifact (see header): SStuck is a RESULT. *)
Lemma b_kernel_fuel :
  compile _ (denE nil (Ret (VInt 3%Z)) 0) (st0 6) = @MDone SResult nil SStuck.
Proof. reflexivity. Qed.

(* Arm `Choice` = `br2`: the branch algebra IS the candidate decision, and for this probe the
   determinate scheduler picks the left candidate; the emitted fragment says so. *)
Lemma b_choice :
  compile _ (denE nil (Choice (Ret (VInt 1%Z)) Fail) 2) (st0 6)
  = @MDone SResult [ i_branch_left ] (SOk (VInt 1%Z)).
Proof. reflexivity. Qed.

(* The same tree with the scheduler picking the right candidate: the ONLY difference between
   these two compiles is the bool the algebra returns - which is the determinacy analysis's
   output.  (This is the probe-side statement of "compile is a hylo whose coalgebra side is
   single-valued only under determinacy".) *)
Definition g0r : B2 ~> M :=
  fun (X : Type) (b : B2 X) (s : st) =>
    match b in B2 Y return MRes Y with
    | branch2 => @MDone bool (ofrag s ++ [ i_branch_left ]) false
    end.
Definition compileR (X : Type) (t : ctree void1 B2 X) : M X := fold h0 g0r t.

Lemma b_choice_right :
  compileR _ (denE nil (Choice (Ret (VInt 1%Z)) Fail) 2) (st0 6)
  = @MDone SResult [ i_branch_left ] SFail.
Proof. reflexivity. Qed.

(* Arm `Seq`: `denE` spells Seq with `>>=` - a cofix `subst` spine.  The fold's SINGLE
   `observe` per step unstucks it lazily, arm by arm; Seq of two returns costs zero emitted
   instructions, because `subst` on a `RetF` head IS the iota step the observe performs.
   No goal here asks for a normal form of the whole tree: each observes one constructor. *)
Lemma b_seq :
  compile _ (denE nil (Seq (Ret (VInt 1%Z)) (Ret (VInt 2%Z))) 2) (st0 6)
  = @MDone SResult nil (SOk (VInt 2%Z)).
Proof. reflexivity. Qed.

(* Choice under Seq: the decision and the sequencing coexist in one accumulating pass.
   Kernel fuel 4 suffices: the kernel's own budget is depth-bounded - `denE rho e 0 = sret
   SStuck` and each nesting layer spends one unit (Semantics.v:127) - so Seq/Choice/Ret at
   depth 3 needs fuel 4 to reach values. *)
Lemma b_seq_choice :
  compile _ (denE nil (Seq (Choice (Ret (VInt 1%Z)) Fail) (Ret (VInt 2%Z))) 4) (st0 6)
  = @MDone SResult [ i_branch_left ] (SOk (VInt 2%Z)).
Proof. reflexivity. Qed.

(* And the artifact, measured not guessed (this is what `Compute` said for fuel 2): the SStuck
   produced by the CHOICE's children (fuel exhausted one layer down) propagates through the
   kernel's `>>=` Seq arm, and the fold carries it as a plain RESULT - `MDone`, not `MTrap`,
   no `i_loop`.  A kernel fuel exhaustion is data; only a compile fuel exhaustion emits
   `i_loop`.  Keeping this goal in the probe is the guard against conflating the two. *)
Lemma b_seq_choice_kernel_fuel :
  compile _ (denE nil (Seq (Choice (Ret (VInt 1%Z)) Fail) (Ret (VInt 2%Z))) 2) (st0 6)
  = @MDone SResult [ i_branch_left ] SStuck.
Proof. reflexivity. Qed.

(* ---------------- the cone question: what does the fold path COST in axioms? ---------------- *)

(* Print Assumptions on the central goals.  Expected and observed: `Closed` - the hylo path
   adds NO axioms.  The repo's 13-axiom cone (flake.nix expected_cone) belongs to the
   bisimilarity/certiRocq side (sbisim, eq_rect_eq etc.); none of it is needed to state or
   prove these compilation equalities, because they are not equalities of corecursive
   objects - they are evaluations of a fuel-bounded fold into a chosen algebra. *)
Print Assumptions b_choice.
Print Assumptions b_seq.
Print Assumptions b_seq_choice.
Print Assumptions b_seq_choice_kernel_fuel.
