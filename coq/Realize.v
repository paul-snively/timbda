(* Realize.v — docs/PLAN.md § 3 item 6 (T6), increment A, per decision 10 (2026-11-25):
   the checked fragment realized against CompCert's own big-step rules at statement
   level (docs/DESIGN-NOTES.md § 13.14, probes p519).

   WHAT THIS FILE IS.  The scaffold of T6: the empty Clight context of the
   realization (ge0/le0), the flattening of a switch-free lowered tree
   (clight_of - over the checked fragment T7 guarantees there is no Lswitch),
   the computable 64-bit range guard (range_ok, decision 10c), and the
   per-node realization lemmas of decision 10's three-way correspondence:
   the arithmetic map claims final lower_res = Vlong (Int64.repr of the
   kernel result, realized via eval_Econst_long/eval_Ebinop; the guard map
   claims final lower_res = Vint (Int.repr 1) exactly when the kernel's
   first-argument prim guard (prim_total, Syntax.v l.344-357) succeeds;
   every other admitted arm gets exec-existence only.  The full induction
   over Seq/Block/TupE sequencing and the composition with T4_sem's value
   witness are the next increments; the end-to-end corners here
   (add[2,3], gt[3,2], Ret 2) fix the shapes those increments must generalize.

   AUDIT.  This file is part of the CompCert-facing cone (decision 10a): its
   axioms - six for any derivation's Print Assumptions (the Flocq pair,
   functional_extensionality_dep, classic, and CompCert's two event-semantics
   parameters), thirteen for the full rocqchk cone context - are audited by
   the CONE SWEEP in flake.nix's timbda-kernel buildPhase (rocq check -silent
   -o Timbda.Realize, allow-list pinned verbatim), NOT by the kernel's
   eq_rect_eq-only sweep.  For that sweep to stay clean: no `Print
   Assumptions` line may ever appear in this file - its output would land in
   build.log and break the kernel audit. *)

From Stdlib Require Import ZArith List.
Require Import compcert.lib.Coqlib compcert.lib.Integers compcert.lib.Maps
  compcert.common.Values compcert.common.AST compcert.common.Memory
  compcert.common.Events compcert.common.Globalenvs
  compcert.cfrontend.Ctypes compcert.cfrontend.Cop compcert.cfrontend.Clight
  compcert.cfrontend.ClightBigstep.
Require Import Timbda.Syntax Timbda.Rewriting Timbda.Semantics Timbda.Eval
  Timbda.Checks Timbda.Lower.

(* ---------- the empty Clight context of the realization (p519 spelling) ---------- *)

Definition ge0 : Clight.genv :=
  {| genv_genv := Genv.empty_genv Clight.fundef Ctypes.type nil;
     genv_cenv := PTree.empty composite |}.

Definition le0 : Clight.temp_env := PTree.empty val.

(* Flatten a switch-free lowered tree to a Clight statement.  Over the
   checked fragment T7 guarantees there is no Lswitch to flatten; the Sskip
   arm of Lswitch is what keeps clight_of total, not something T6 reasons
   about (no_switch_l pins it away, Lower.v T7). *)
Fixpoint clight_of (l : Lower.lstmt) : Clight.statement :=
  match l with
  | Lower.Lclight s => s
  | Lower.Lswitch _ => Clight.Sskip
  | Lower.Lseq l1 l2 => Clight.Ssequence (clight_of l1) (clight_of l2)
  end.

(* ---------- the 64-bit range guard (decision 10c) ---------- *)

(* The signed window [Int64.min_signed, Int64.max_signed] - the exact interval
   on which Int64.repr is value-preserving (signed_repr_eq, Integers.v). *)
Definition int64_range (z : Z) : bool :=
  Z.leb Int64.min_signed z && Z.leb z Int64.max_signed.

Definition val_int64_ok (v : Val) : bool :=
  match v with VInt z => int64_range z | _ => true end.

(* Admitted App nodes have literal operands (app_node_ok pins this, Checks.v),
   so the kernel result is inspectable syntactically: only int results carry
   a range obligation.  This mirrors prim_total's reading, it does not
   re-derive it. *)
Definition prim_node_range_ok (p : Prim) (vs : list Val) : bool :=
  match prim_total p vs with
  | PRes (VInt r) => int64_range r
  | _ => true
  end.

Fixpoint range_ok (e : Expr) : bool :=
  match e with
  | Ret v => val_int64_ok v
  | Glob _ => true
  | App f a =>
      let base := andb (range_ok f) (range_ok a) in
      match f, prim_operand_vals a with
      | Ret (VPrim p), Some vs => andb base (prim_node_range_ok p vs)
      | _, _ => base
      end
  | TupE es => forallb range_ok es
  | Seq e1 e2 => andb (range_ok e1) (range_ok e2)
  | Unify e1 e2 => andb (range_ok e1) (range_ok e2)
  | Choice e1 e2 => andb (range_ok e1) (range_ok e2)
  | Fail => true
  | Block sl body0 =>
      andb (forallb (fun s => match snd s with
                              | Some v => val_int64_ok v
                              | None => true end) sl)
           (range_ok body0)
  | Iter _ b _ => range_ok b
  end.

(* ---------- per-node realization lemmas (decision 10's three-way split) ---------- *)

(* Any Sset arm, from any starting temp env: 3.17's exec_Sset has the single
   eval_expr premise (p519 spelling ledger). *)
Lemma realize_set (a : Clight.expr) (v : val) :
  Clight.eval_expr ge0 Clight.empty_env le0 Mem.empty a v ->
  Clight1.exec_stmt ge0 Clight.empty_env le0 Mem.empty
    (Clight.Sset Lower.lower_res a) Events.E0
    (PTree.set Lower.lower_res v le0) Mem.empty ClightBigstep.Out_normal.
Proof.
  intros He. apply ClightBigstep.exec_Sset. exact He.
Qed.

(* Arithmetic class corner: add[2,3].  The kernel value (Z) and the Clight
   value (Int64) meet at Int64.repr under the range guard (see bridge below). *)
Definition e_add23 : Expr :=
  App (Ret (VPrim PAdd)) (TupE (Ret (VInt 2) :: Ret (VInt 3) :: nil)).

Lemma realize_add23 :
  Clight1.exec_stmt ge0 Clight.empty_env le0 Mem.empty
    (clight_of (Lower.lower e_add23)) Events.E0
    (PTree.set Lower.lower_res (Vlong (Int64.repr 5)) le0)
    Mem.empty ClightBigstep.Out_normal.
Proof.
  cbn [Clight1.exec_stmt clight_of Lower.lower].
  apply ClightBigstep.exec_Sset.
  eapply Clight.eval_Ebinop.
  - apply Clight.eval_Econst_long.
  - apply Clight.eval_Econst_long.
  - vm_compute. reflexivity.
Qed.

(* Guard class corner: prim_total admits gt[3,2] because 2 < 3 and RETURNS THE
   FIRST ARGUMENT (Syntax.v l.353); CompCert's order test realizes the same
   guard as Vint (Int.repr 1) (measured, p520). *)
Definition e_gt32 : Expr :=
  App (Ret (VPrim PGt)) (TupE (Ret (VInt 3) :: Ret (VInt 2) :: nil)).

Lemma realize_gt32 :
  Clight1.exec_stmt ge0 Clight.empty_env le0 Mem.empty
    (clight_of (Lower.lower e_gt32)) Events.E0
    (PTree.set Lower.lower_res (Vint (Int.repr 1)) le0)
    Mem.empty ClightBigstep.Out_normal.
Proof.
  cbn [Clight1.exec_stmt clight_of Lower.lower].
  apply ClightBigstep.exec_Sset.
  eapply Clight.eval_Ebinop.
  - apply Clight.eval_Econst_long.
  - apply Clight.eval_Econst_long.
  - vm_compute. reflexivity.
Qed.

(* Ret arm: a literal lands as its own assignment. *)
Lemma realize_ret2 :
  Clight1.exec_stmt ge0 Clight.empty_env le0 Mem.empty
    (clight_of (Lower.lower (Ret (VInt 2)))) Events.E0
    (PTree.set Lower.lower_res (Vlong (Int64.repr 2)) le0)
    Mem.empty ClightBigstep.Out_normal.
Proof.
  cbn [Clight1.exec_stmt clight_of Lower.lower].
  apply ClightBigstep.exec_Sset.
  apply Clight.eval_Econst_long.
Qed.

(* Observation half: the final temp env read at lower_res (PTree.gss). *)
Lemma observe_add23 :
  PTree.get Lower.lower_res
    (PTree.set Lower.lower_res (Vlong (Int64.repr 5)) le0)
  = Some (Vlong (Int64.repr 5)).
Proof. apply PTree.gss. Qed.

(* Bridge lemma shape for the general arithmetic class (the full increment
   proves it with the signed_repr_eq/eq_spec machinery and int64_range as
   hypothesis; the corner closes by computation). *)
Lemma int64_bridge_add23 :
  Int64.add (Int64.repr 2) (Int64.repr 3) = Int64.repr 5.
Proof. vm_compute. reflexivity. Qed.

(* Sanity: the corners are in the fragment, in range, and range_ok agrees. *)
Compute det_check e_add23.        (* true *)
Compute det_check e_gt32.         (* true *)
Compute range_ok e_add23.         (* true *)
Compute range_ok e_gt32.          (* true *)
