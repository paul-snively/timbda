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
   over Seq/Block/TupE/Block sequencing is INCREMENT B below (the T6_exec_ws
   theorem); the composition with T4_sem's value witness is increment C.  The
   end-to-end corners here (add[2,3], gt[3,2], Ret 2) fix the shapes that
   increment B generalizes.  Since the increment-C split (2026-11-26) the
   realization side is a fan-in - RealizeBridges, RealizeDiv, RealizeCorners
   composing in RealizeCompose - and this file is the CompCert-side hub they
   read; increment D (CertiRocq->C) lands in its own leaf, never by
   inflating this one.

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
(* The Int64<->Z bridge layer, the signed window (int64_range /
   int64_range_signed / signed_repr_min) and the increment-C div/bridge
   measurements live in the leaf modules since the 2026-11-26 split - see
   RealizeBridges.v's header.  The range GUARD machinery
   (val_int64_ok / prim_node_range_ok / range_ok) stays here: it is T6's
   hypothesis, not a bridge. *)
Require Import Timbda.RealizeBridges.

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

(* ============================================================================
   INCREMENT B (probe p524, 2026-11-25): the general induction.

   The T6 statement of decision 10: every checked tree (ws_expr + det_struct
   + the computable range guard range_ok) executes in Clight from the empty
   context, and the final lower_res tempvar is characterized computably by
   the monadic fold lower_final e o (Seq threads the value through, Block's
   prelude passes it, placeholder arms mirror vconst).  The bridge layer:
   z64/prim_clight name the Int64 constants the emitted expressions evaluate
   to (the sem_*_long lemmas pin CompCert's own semantics of the long
   operators at Int64); prim_guard_ok carries the PDiv eval guards and
   prim_guard_ok_canon discharges them from the kernel check facts
   (app_node_ok_shape path).  T6_exec_ws is the depth-indexed statement;
   T6_exec is its corollary at le0.  Composition with T4_sem's value
   witness is increment C (docs/PLAN.md decision 10b).
   ============================================================================ *)


(* z64 lives in Lower.v since increment C (the PDiv floor fold needs it at the
   prim_expr arm); its definition is unchanged - the syntactic mirror of
   Lower.v's vconst, every Val shape to the Int64 constant vconst emits. *)

Definition clight_of_val (v : Val) : val := Vlong (z64 v).

Definition prim_clight (p : Prim) (vs : list Val) : val :=
  match p, vs with
  | PAdd, a :: b :: nil => Vlong (Int64.add (z64 a) (z64 b))
  | PSub, a :: b :: nil => Vlong (Int64.sub (z64 a) (z64 b))
  | PMul, a :: b :: nil => Vlong (Int64.mul (z64 a) (z64 b))
  (* PDiv: floor fold, decision 12 - matches the folded Lower.prim_expr constant
     and the kernel prim_total Z.div; the truncating Int64.divs is NOT used
     (the measured gap lives in the increment C section below). *)
  | PDiv, a :: b :: nil => Vlong (Int64.repr (Z.div (vint_z a) (vint_z b)))
  | PNeg, a :: nil      => Vlong (Int64.neg (z64 a))
  | PLt,  a :: b :: nil => Val.of_bool (Int64.cmp Clt (z64 a) (z64 b))
  | PGt,  a :: b :: nil => Val.of_bool (Int64.cmp Cgt (z64 a) (z64 b))
  | PLEq, a :: b :: nil => Val.of_bool (Int64.cmp Cle (z64 a) (z64 b))
  | PGEq, a :: b :: nil => Val.of_bool (Int64.cmp Cge (z64 a) (z64 b))
  | PNEq, a :: b :: nil => Val.of_bool (Int64.cmp Cne (z64 a) (z64 b))
  | _, _                 => Vlong (Int64.repr 0)
  end.

Fixpoint last_val (vs : list Val) : option Val :=
  match vs with
  | nil => None
  | v :: nil => Some v
  | _ :: rest => last_val rest
  end.

(* The value the lowered statement leaves in lower_res, computed from the tree:
   a monoid fold over the writes clight_of (lower e) performs, threaded through
   the incoming value o (Seq composes, Block's prelude never names lower_res). *)
Fixpoint lower_final (e : Expr) (o : option val) : option val :=
  match e with
  | Ret v => Some (clight_of_val v)
  | Glob _ => o
  | App f a =>
      match Lower.prim_head f, prim_operand_vals a with
      | Some p, Some vs => Some (prim_clight p vs)
      | _, _ => o
      end
  | TupE es =>
      match rets_of es with
      | Some vs => match last_val vs with
                   | Some v => Some (clight_of_val v)
                   | None => o
                   end
      | None => o
      end
  | Seq e1 e2 => lower_final e2 (lower_final e1 o)
  | Unify _ _ => o
  | Choice _ _ => o
  | Fail => o
  | Iter _ _ _ => o
  | Block _ b => lower_final b o
  end.

(* vconst = Econst_long (z64 v), constructor for constructor. *)
Lemma vconst_z64 : forall v : Val,
  Lower.vconst v = Clight.Econst_long (z64 v) Lower.tint64.
Proof. destruct v; cbn [Lower.vconst z64]; reflexivity. Qed.
(* ---------- bridges on the CompCert side, symbolic operands (p522/p523) ---------- *)

Lemma sem_Oadd_long : forall m (i1 i2 : Int64.int),
  sem_binary_operation ge0 Cop.Oadd (Vlong i1) Lower.tint64 (Vlong i2) Lower.tint64 m
  = Some (Vlong (Int64.add i1 i2)).
Proof. intros. simpl. reflexivity. Qed.

Lemma sem_Osub_long : forall m (i1 i2 : Int64.int),
  sem_binary_operation ge0 Cop.Osub (Vlong i1) Lower.tint64 (Vlong i2) Lower.tint64 m
  = Some (Vlong (Int64.sub i1 i2)).
Proof. intros. simpl. reflexivity. Qed.

Lemma sem_Omul_long : forall m (i1 i2 : Int64.int),
  sem_binary_operation ge0 Cop.Omul (Vlong i1) Lower.tint64 (Vlong i2) Lower.tint64 m
  = Some (Vlong (Int64.mul i1 i2)).
Proof. intros. simpl. reflexivity. Qed.

(* Odiv: the guard spelling, measured in p523c.  The guard is a disjunction
   whose second term is a conjunction; a stuck conjunction only needs the
   implication form below (range_ok pins the min_signed / mone case away). *)
Lemma sem_Odiv_long : forall m (i1 i2 : Int64.int),
  Int64.eq i2 Int64.zero = false ->
  (Int64.eq i1 (Int64.repr Int64.min_signed) = true -> Int64.eq i2 Int64.mone = false) ->
  sem_binary_operation ge0 Cop.Odiv (Vlong i1) Lower.tint64 (Vlong i2) Lower.tint64 m
  = Some (Vlong (Int64.divs i1 i2)).
Proof.
  intros m0 i10 i20 H1 H2.
  cbv [sem_binary_operation sem_div sem_binarith classify_binarith
       binarith_type sem_cast classify_cast orb andb Archi.ptr64 Lower.tint64].
  rewrite H1.
  cbv [orb andb].
  (* destruct also peels the destructed term inside H2's premise *)
  destruct (Int64.eq i10 (Int64.repr Int64.min_signed)) eqn:He.
  - rewrite (H2 eq_refl). reflexivity.
  - reflexivity.
Qed.

Lemma sem_Olt_long : forall m (i1 i2 : Int64.int),
  sem_binary_operation ge0 Cop.Olt (Vlong i1) Lower.tint64 (Vlong i2) Lower.tint64 m
  = Some (Val.of_bool (Int64.cmp Clt i1 i2)).
Proof. intros. cbn [sem_binary_operation sem_cmp sem_binarith]. reflexivity. Qed.

Lemma sem_Ogt_long : forall m (i1 i2 : Int64.int),
  sem_binary_operation ge0 Cop.Ogt (Vlong i1) Lower.tint64 (Vlong i2) Lower.tint64 m
  = Some (Val.of_bool (Int64.cmp Cgt i1 i2)).
Proof. intros. cbn [sem_binary_operation sem_cmp sem_binarith]. reflexivity. Qed.

Lemma sem_Ole_long : forall m (i1 i2 : Int64.int),
  sem_binary_operation ge0 Cop.Ole (Vlong i1) Lower.tint64 (Vlong i2) Lower.tint64 m
  = Some (Val.of_bool (Int64.cmp Cle i1 i2)).
Proof. intros. cbn [sem_binary_operation sem_cmp sem_binarith]. reflexivity. Qed.

Lemma sem_Oge_long : forall m (i1 i2 : Int64.int),
  sem_binary_operation ge0 Cop.Oge (Vlong i1) Lower.tint64 (Vlong i2) Lower.tint64 m
  = Some (Val.of_bool (Int64.cmp Cge i1 i2)).
Proof. intros. cbn [sem_binary_operation sem_cmp sem_binarith]. reflexivity. Qed.

Lemma sem_One_long : forall m (i1 i2 : Int64.int),
  sem_binary_operation ge0 Cop.One (Vlong i1) Lower.tint64 (Vlong i2) Lower.tint64 m
  = Some (Val.of_bool (Int64.cmp Cne i1 i2)).
Proof. intros. cbn [sem_binary_operation sem_cmp sem_binarith]. reflexivity. Qed.

Lemma sem_Oneg_long : forall m (i1 : Int64.int),
  sem_unary_operation Cop.Oneg (Vlong i1) Lower.tint64 m
  = Some (Vlong (Int64.neg i1)).
Proof.
  intros. cbv [sem_unary_operation sem_neg classify_neg Lower.tint64]. reflexivity.
Qed.
(* ---------- the div guards, derived from the checked fragment ---------- *)

(* a nonzero in-range divisor survives Int64.eq against zero *)
Lemma int64_eq_zero_ne : forall z : Z,
  int64_range z = true -> Z.eqb z 0 = false ->
  Int64.eq (Int64.repr z) Int64.zero = false.
Proof.
  intros z Hz H0.
  case_eq (Int64.eq (Int64.repr z) Int64.zero); intros He; [| reflexivity].
  rewrite (Int64.eq_signed (Int64.repr z) Int64.zero) in He.
  destruct (zeq (Int64.signed (Int64.repr z)) (Int64.signed Int64.zero)) as [H1 | H1].
  - rewrite (int64_range_signed z Hz), Int64.signed_zero in H1. subst z.
    cbn in H0. discriminate.
  - cbn in He. discriminate.
Qed.

(* the min_signed / mone overflow: if the dividend is min_signed and the divisor
   is mone, the kernel quotient 2^63 is out of range, which range_ok already
   excluded at the node (prim_node_range_ok). *)
Lemma int64_mone_guard : forall x y : Z,
  int64_range x = true -> int64_range y = true -> int64_range (x / y) = true ->
  Int64.eq (Int64.repr x) (Int64.repr Int64.min_signed) = true ->
  Int64.eq (Int64.repr y) Int64.mone = false.
Proof.
  intros x y Hx Hy Hr Heqx.
  case_eq (Int64.eq (Int64.repr y) Int64.mone); intros Heqy; [| reflexivity].
  rewrite (Int64.eq_signed (Int64.repr x) (Int64.repr Int64.min_signed)) in Heqx.
  rewrite (Int64.eq_signed (Int64.repr y) Int64.mone) in Heqy.
  destruct (zeq (Int64.signed (Int64.repr x)) (Int64.signed (Int64.repr Int64.min_signed))) as [Hx0 | Hx0].
  - (* dividend is min_signed *)
    rewrite (int64_range_signed x Hx), signed_repr_min in Hx0. subst x.
    destruct (zeq (Int64.signed (Int64.repr y)) (Int64.signed Int64.mone)) as [Hy0 | Hy0].
    + (* divisor is mone: the kernel quotient 2^63 is out of range *)
      rewrite (int64_range_signed y Hy), Int64.signed_mone in Hy0. subst y.
      unfold int64_range in Hr. apply andb_and in Hr.
      destruct Hr as [K1 K2]. apply Z.leb_le in K1. apply Z.leb_le in K2.
      unfold Int64.min_signed, Int64.max_signed in K1, K2.
      (* kernel quotient: min_signed / -1 = 2^63 *)
      assert (Hc : ((- Int64.half_modulus) / (-1))%Z = Int64.half_modulus).
      { symmetry. apply Z.div_unique with (a := (- Int64.half_modulus))
                           (b := (-1)) (q := Int64.half_modulus) (r := 0).
        - lia. - ring. }
      rewrite Hc in K1, K2. generalize Int64.half_modulus_pos. lia.
    + cbn in Heqy. discriminate.
  - cbn in Heqx. discriminate.
Qed.

(* a checked div node never divides by zero (the kernel PStuck arm) *)
Lemma prim_total_res_PDiv_ne : forall x y : Z,
  prim_total_res PDiv (VInt x :: VInt y :: nil) = true -> Z.eqb y 0 = false.
Proof.
  intros x y H.
  cbv [prim_total_res prim_total] in H.
  destruct (Z.eqb y 0) eqn:H0.
  - discriminate.
  - reflexivity.
Qed.

(* ---------- eval derivations from an arbitrary temp env ---------- *)

Lemma eval_const64 : forall (i : Int64.int) (ty : Ctypes.type) (le : Clight.temp_env),
  Clight.eval_expr ge0 Clight.empty_env le Mem.empty (Clight.Econst_long i ty) (Vlong i).
Proof. intros i ty le. apply Clight.eval_Econst_long. Qed.

Lemma eval_vconst_val : forall (v : Val) (le : Clight.temp_env),
  Clight.eval_expr ge0 Clight.empty_env le Mem.empty (Lower.vconst v) (clight_of_val v).
Proof.
  intros v le. destruct v; cbn [Lower.vconst clight_of_val z64]; apply eval_const64.
Qed.
(* ---------- per-class eval lemmas for the emitted prim nodes ---------- *)

Lemma eval_bin64_Oadd : forall (i1 i2 : Int64.int) (le : Clight.temp_env),
  Clight.eval_expr ge0 Clight.empty_env le Mem.empty
    (Clight.Ebinop Cop.Oadd (Clight.Econst_long i1 Lower.tint64)
                            (Clight.Econst_long i2 Lower.tint64) Lower.tint64)
    (Vlong (Int64.add i1 i2)).
Proof.
  intros i1 i2 le. eapply Clight.eval_Ebinop.
  - apply eval_const64. - apply eval_const64. - apply sem_Oadd_long.
Qed.

Lemma eval_bin64_Osub : forall (i1 i2 : Int64.int) (le : Clight.temp_env),
  Clight.eval_expr ge0 Clight.empty_env le Mem.empty
    (Clight.Ebinop Cop.Osub (Clight.Econst_long i1 Lower.tint64)
                            (Clight.Econst_long i2 Lower.tint64) Lower.tint64)
    (Vlong (Int64.sub i1 i2)).
Proof.
  intros i1 i2 le. eapply Clight.eval_Ebinop.
  - apply eval_const64. - apply eval_const64. - apply sem_Osub_long.
Qed.

Lemma eval_bin64_Omul : forall (i1 i2 : Int64.int) (le : Clight.temp_env),
  Clight.eval_expr ge0 Clight.empty_env le Mem.empty
    (Clight.Ebinop Cop.Omul (Clight.Econst_long i1 Lower.tint64)
                            (Clight.Econst_long i2 Lower.tint64) Lower.tint64)
    (Vlong (Int64.mul i1 i2)).
Proof.
  intros i1 i2 le. eapply Clight.eval_Ebinop.
  - apply eval_const64. - apply eval_const64. - apply sem_Omul_long.
Qed.

Lemma eval_bin64_Odiv : forall (i1 i2 : Int64.int) (le : Clight.temp_env),
  Int64.eq i2 Int64.zero = false ->
  (Int64.eq i1 (Int64.repr Int64.min_signed) = true -> Int64.eq i2 Int64.mone = false) ->
  Clight.eval_expr ge0 Clight.empty_env le Mem.empty
    (Clight.Ebinop Cop.Odiv (Clight.Econst_long i1 Lower.tint64)
                            (Clight.Econst_long i2 Lower.tint64) Lower.tint64)
    (Vlong (Int64.divs i1 i2)).
Proof.
  intros i1 i2 le H1 H2. eapply Clight.eval_Ebinop.
  - apply eval_const64. - apply eval_const64. - apply (sem_Odiv_long _ i1 i2 H1 H2).
Qed.

Lemma eval_bin64_Olt : forall (i1 i2 : Int64.int) (le : Clight.temp_env),
  Clight.eval_expr ge0 Clight.empty_env le Mem.empty
    (Clight.Ebinop Cop.Olt (Clight.Econst_long i1 Lower.tint64)
                           (Clight.Econst_long i2 Lower.tint64) Lower.tint32)
    (Val.of_bool (Int64.cmp Clt i1 i2)).
Proof.
  intros i1 i2 le. eapply Clight.eval_Ebinop.
  - apply eval_const64. - apply eval_const64. - apply sem_Olt_long.
Qed.

Lemma eval_bin64_Ogt : forall (i1 i2 : Int64.int) (le : Clight.temp_env),
  Clight.eval_expr ge0 Clight.empty_env le Mem.empty
    (Clight.Ebinop Cop.Ogt (Clight.Econst_long i1 Lower.tint64)
                           (Clight.Econst_long i2 Lower.tint64) Lower.tint32)
    (Val.of_bool (Int64.cmp Cgt i1 i2)).
Proof.
  intros i1 i2 le. eapply Clight.eval_Ebinop.
  - apply eval_const64. - apply eval_const64. - apply sem_Ogt_long.
Qed.

Lemma eval_bin64_Ole : forall (i1 i2 : Int64.int) (le : Clight.temp_env),
  Clight.eval_expr ge0 Clight.empty_env le Mem.empty
    (Clight.Ebinop Cop.Ole (Clight.Econst_long i1 Lower.tint64)
                           (Clight.Econst_long i2 Lower.tint64) Lower.tint32)
    (Val.of_bool (Int64.cmp Cle i1 i2)).
Proof.
  intros i1 i2 le. eapply Clight.eval_Ebinop.
  - apply eval_const64. - apply eval_const64. - apply sem_Ole_long.
Qed.

Lemma eval_bin64_Oge : forall (i1 i2 : Int64.int) (le : Clight.temp_env),
  Clight.eval_expr ge0 Clight.empty_env le Mem.empty
    (Clight.Ebinop Cop.Oge (Clight.Econst_long i1 Lower.tint64)
                           (Clight.Econst_long i2 Lower.tint64) Lower.tint32)
    (Val.of_bool (Int64.cmp Cge i1 i2)).
Proof.
  intros i1 i2 le. eapply Clight.eval_Ebinop.
  - apply eval_const64. - apply eval_const64. - apply sem_Oge_long.
Qed.

Lemma eval_bin64_One : forall (i1 i2 : Int64.int) (le : Clight.temp_env),
  Clight.eval_expr ge0 Clight.empty_env le Mem.empty
    (Clight.Ebinop Cop.One (Clight.Econst_long i1 Lower.tint64)
                           (Clight.Econst_long i2 Lower.tint64) Lower.tint32)
    (Val.of_bool (Int64.cmp Cne i1 i2)).
Proof.
  intros i1 i2 le. eapply Clight.eval_Ebinop.
  - apply eval_const64. - apply eval_const64. - apply sem_One_long.
Qed.

Lemma eval_un64_Oneg : forall (i : Int64.int) (le : Clight.temp_env),
  Clight.eval_expr ge0 Clight.empty_env le Mem.empty
    (Clight.Eunop Cop.Oneg (Clight.Econst_long i Lower.tint64) Lower.tint64)
    (Vlong (Int64.neg i)).
Proof.
  intros i le. eapply Clight.eval_Eunop.
  - apply eval_const64. - apply sem_Oneg_long.
Qed.
(* ---------- composition machinery over arbitrary temp envs ---------- *)

(* E0 ** E0 reduces to E0 by iota, so the goal is stated in the convertible
   (E0 ** E0) form first (change), and exec_Sseq_1 then unifies syntactically;
   le1/m1 (premise-only variables) are pinned by with.  Measured in p523e. *)
Lemma exec_seq_close (s1 s2 : Clight.statement) (le le1 le2 : Clight.temp_env) :
  Clight1.exec_stmt ge0 Clight.empty_env le Mem.empty s1 Events.E0 le1 Mem.empty
    ClightBigstep.Out_normal ->
  Clight1.exec_stmt ge0 Clight.empty_env le1 Mem.empty s2 Events.E0 le2 Mem.empty
    ClightBigstep.Out_normal ->
  Clight1.exec_stmt ge0 Clight.empty_env le Mem.empty (Clight.Ssequence s1 s2)
    Events.E0 le2 Mem.empty ClightBigstep.Out_normal.
Proof.
  intros H1 H2.
  change (Clight1.exec_stmt ge0 Clight.empty_env le Mem.empty
            (Clight.Ssequence s1 s2) (Events.E0 ** Events.E0) le2 Mem.empty
            ClightBigstep.Out_normal).
  apply ClightBigstep.exec_Sseq_1 with (le1 := le1) (m1 := Mem.empty); eauto.
Qed.

(* slot tempvars (slot i maps to #i+2) never name lower_res (= xH = #1) *)
Lemma lower_res_ne_slot : forall i : nat, Lower.lower_res <> Lower.slot_ident i.
Proof.
  intros i H. unfold Lower.slot_ident, Lower.lower_res in H.
  symmetry in H. apply (f_equal Z.pos) in H.
  rewrite Z2Pos.id in H; [lia|]. lia.
Qed.

Lemma get_slot_neutral : forall (i : nat) (x : val) (m : Clight.temp_env),
  PTree.get Lower.lower_res (PTree.set (Lower.slot_ident i) x m)
  = PTree.get Lower.lower_res m.
Proof.
  intros i x m. apply (PTree.gso (i := Lower.lower_res) (j := Lower.slot_ident i)).
  apply lower_res_ne_slot.
Qed.

Lemma last_val_ne_none : forall (v : Val) (w : list Val), last_val (v :: w) <> None.
Proof.
  intros v w H. revert v H.
  induction w as [| w0 w' IH]; intros v H; cbn [last_val] in H.
  - discriminate.
  - exfalso. apply (IH w0). exact H.
Qed.

(* TupE lowering: the sequence of Ssets, "last ret wins" *)
Lemma exec_rets_sets : forall (vs : list Val) (le : Clight.temp_env),
  exists le',
    Clight1.exec_stmt ge0 Clight.empty_env le Mem.empty
      (fold_right Clight.Ssequence Clight.Sskip
         (map (fun v => Clight.Sset Lower.lower_res (Lower.vconst v)) vs))
      Events.E0 le' Mem.empty ClightBigstep.Out_normal
    /\ PTree.get Lower.lower_res le' =
       match last_val vs with
       | Some v => Some (clight_of_val v)
       | None => PTree.get Lower.lower_res le
       end.
Proof.
  induction vs as [| v vs IH]; intros le.
  - exists le. split.
    + apply ClightBigstep.exec_Sskip.
    + reflexivity.
  - cbn [map fold_right].
    destruct (IH (PTree.set Lower.lower_res (clight_of_val v) le)) as [le' [Hexec Hget]].
    exists le'. split.
    + apply exec_seq_close with
        (le1 := PTree.set Lower.lower_res (clight_of_val v) le).
      * apply ClightBigstep.exec_Sset. apply eval_vconst_val.
      * exact Hexec.
    + cbn [last_val] in Hget |- *.
      destruct vs as [| v2 vs2].
      * cbn [last_val] in Hget. rewrite Hget. apply PTree.gss.
      * destruct (last_val (v2 :: vs2)) eqn:Hl.
        -- exact Hget.
        -- exfalso. apply (last_val_ne_none v2 vs2). exact Hl.
Qed.

(* Block prelude: only VInt slots emit an assignment (to a slot tempvar);
   lower_res is untouched. *)
Lemma exec_slots_prelude : forall (sl : list (Ty * option Val)) (le : Clight.temp_env),
  exists le',
    Clight1.exec_stmt ge0 Clight.empty_env le Mem.empty (Lower.slots_prelude sl)
      Events.E0 le' Mem.empty ClightBigstep.Out_normal
    /\ PTree.get Lower.lower_res le' = PTree.get Lower.lower_res le.
Proof.
  induction sl as [ | [t ov] sl IH ]; intros le.
  - exists le. split.
    + apply ClightBigstep.exec_Sskip.
    + reflexivity.
  - destruct ov as [v |]; cbn [Lower.slots_prelude].
    + (* the VInt slot is the only one that writes (to a slot tempvar); the
       other eight Val shapes fall into the Sskip arm of slots_prelude *)
      destruct v as [ | | | z | | | | | ] ; cbn [Lower.slots_prelude];
      [ destruct (IH le) as [le' [Hexec Hget]]; exists le'; split;
        [ apply exec_seq_close with (le1 := le);
          [ apply ClightBigstep.exec_Sskip | exact Hexec ]
        | exact Hget ]
      | destruct (IH le) as [le' [Hexec Hget]]; exists le'; split;
        [ apply exec_seq_close with (le1 := le);
          [ apply ClightBigstep.exec_Sskip | exact Hexec ]
        | exact Hget ]
      | destruct (IH le) as [le' [Hexec Hget]]; exists le'; split;
        [ apply exec_seq_close with (le1 := le);
          [ apply ClightBigstep.exec_Sskip | exact Hexec ]
        | exact Hget ]
      | destruct (IH (PTree.set (Lower.slot_ident (Datatypes.length sl))
                               (clight_of_val (VInt z)) le)) as [le' [Hexec Hget]];
        exists le'; split;
        [ apply exec_seq_close with
            (le1 := PTree.set (Lower.slot_ident (Datatypes.length sl))
                              (clight_of_val (VInt z)) le);
          [ apply ClightBigstep.exec_Sset; apply eval_vconst_val | exact Hexec ]
        | rewrite Hget; apply (get_slot_neutral (Datatypes.length sl)) ]
      | destruct (IH le) as [le' [Hexec Hget]]; exists le'; split;
        [ apply exec_seq_close with (le1 := le);
          [ apply ClightBigstep.exec_Sskip | exact Hexec ]
        | exact Hget ]
      | destruct (IH le) as [le' [Hexec Hget]]; exists le'; split;
        [ apply exec_seq_close with (le1 := le);
          [ apply ClightBigstep.exec_Sskip | exact Hexec ]
        | exact Hget ]
      | destruct (IH le) as [le' [Hexec Hget]]; exists le'; split;
        [ apply exec_seq_close with (le1 := le);
          [ apply ClightBigstep.exec_Sskip | exact Hexec ]
        | exact Hget ]
      | destruct (IH le) as [le' [Hexec Hget]]; exists le'; split;
        [ apply exec_seq_close with (le1 := le);
          [ apply ClightBigstep.exec_Sskip | exact Hexec ]
        | exact Hget ]
      | destruct (IH le) as [le' [Hexec Hget]]; exists le'; split;
        [ apply exec_seq_close with (le1 := le);
          [ apply ClightBigstep.exec_Sskip | exact Hexec ]
        | exact Hget ]
      ].
    + destruct (IH le) as [le' [Hexec Hget]].
      exists le'. split.
      * apply exec_seq_close with (le1 := le).
        -- apply ClightBigstep.exec_Sskip.
        -- exact Hexec.
      * exact Hget.
Qed.
(* ---------- the div guards at the prim-node level ---------- *)

(* prim_guard_ok is exactly the guard conjunction eval_bin64_Odiv needs, stated
   syntactically for the prim_expr shape (true for every arm that is not a
   two-operand PDiv). *)
Definition prim_guard_ok (p : Prim) (vs : list Val) : bool :=
  match p, vs with
  | PDiv, a :: b :: nil =>
      negb (Int64.eq (z64 b) Int64.zero)
      && (negb (Int64.eq (z64 a) (Int64.repr Int64.min_signed))
          || negb (Int64.eq (z64 b) Int64.mone))
  | _, _ => true
  end.

(* A checked App node's guards follow from the kernel facts: on the canon path
   the operands are VInt (prim_total_res pins the shape), in range (range_ok of
   the operand list), and the PDiv divisor is nonzero; the table and bare paths
   contain no PDiv (Checks.v prim_args_ok / prim_bare_ok reject it), so there
   the guards are vacuous. *)
Lemma prim_guard_ok_canon : forall (p : Prim) (vs : list Val) (a : Expr),
  prim_operand_vals a = Some vs ->
  range_ok a = true ->
  ((all_int vs && prim_total_res p vs = true)
   \/ (exists es, a = TupE es /\ rets_of es = Some vs /\ prim_args_ok p vs = true)
   \/ (exists v, a = Ret v /\ prim_bare_ok p v = true)) ->
  prim_node_range_ok p vs = true ->
  prim_guard_ok p vs = true.
Proof.
  intros p vs a He Ha Hpath Hnode.
  destruct p; cbn [prim_guard_ok prim_args_ok prim_bare_ok]; try reflexivity.
  (* the only nontrivial arm is the two-operand PDiv *)
  destruct Hpath as [Hcanon | [Htab | Hbare]].
  - apply andb_and in Hcanon. destruct Hcanon as [Hall Htot].
    destruct vs as [ | v1 [ | v2 [ | v3 rest ] ] ];
    [ cbv [prim_total_res prim_total] in Htot; discriminate
    | destruct v1; cbv [prim_total_res prim_total] in Htot; discriminate
    | destruct v1 as [ | | | x | | | | | ]; destruct v2 as [ | | | y | | | | | ];
      cbv [prim_total_res prim_total] in Htot;
      try discriminate;
      destruct (Z.eqb y 0) eqn:Hy0; [ discriminate | ];
      (* vs = VInt x :: VInt y :: nil, Z.eqb y 0 = false *)
      destruct a; cbn [prim_operand_vals] in He; try discriminate;
      rewrite (rets_of_map_rets _ _ He) in Ha;
      cbn [range_ok map forallb] in Ha;
      apply andb_and in Ha; destruct Ha as [Hx Hrest];
      apply andb_and in Hrest; destruct Hrest as [Hy _];
      cbv [val_int64_ok] in Hx, Hy;
      cbv [prim_node_range_ok prim_total] in Hnode; rewrite Hy0 in Hnode;
      cbv [prim_node_range_ok prim_total] in Hnode;
      (* Hnode now states int64_range (x / y) = true *)
      cbn [prim_guard_ok z64];
      destruct (Int64.eq (Int64.repr y) Int64.zero) eqn:Ez;
      [ exfalso;
        assert (Hf : Int64.eq (Int64.repr y) Int64.zero = false)
          by (apply (int64_eq_zero_ne y Hy Hy0));
        rewrite Hf in Ez; discriminate Ez
      | cbn [negb orb andb];
        destruct (Int64.eq (Int64.repr x) (Int64.repr Int64.min_signed)) eqn:Ex;
        destruct (Int64.eq (Int64.repr y) Int64.mone) eqn:Ey;
        [ pose proof (int64_mone_guard x y Hx Hy Hnode Ex) as Hm;
          rewrite Ey in Hm; discriminate Hm
        | cbn [negb orb andb]; reflexivity
        | cbn [negb orb andb]; reflexivity
        | cbn [negb orb andb]; reflexivity ]
      ]
    | destruct v1; destruct v2; cbv [prim_total_res prim_total] in Htot; discriminate
    ].
  - destruct Htab as [es [Hea [Hrs Hargs]]].
    cbv [prim_args_ok] in Hargs. discriminate.
  - destruct Hbare as [v [Hev Hbare']].
    cbv [prim_bare_ok] in Hbare'. discriminate.
Qed.

(* The PDiv eval guards, packaged from prim_guard_ok.  Since increment C the
   prim_expr_eval dispatch never uses them (the PDiv arm is a folded constant,
   decision 12); they stay as the measured bridges pinning CompCert's runtime
   Odiv behavior - the semantics the fold deliberately does NOT import. *)
Lemma odiv_ready : forall (a b : Val) (le : Clight.temp_env),
  prim_guard_ok PDiv (a :: b :: nil) = true ->
  Clight.eval_expr ge0 Clight.empty_env le Mem.empty
    (Clight.Ebinop Cop.Odiv (Clight.Econst_long (z64 a) Lower.tint64)
                            (Clight.Econst_long (z64 b) Lower.tint64) Lower.tint64)
    (Vlong (Int64.divs (z64 a) (z64 b))).
Proof.
  intros a b le Hg.
  cbn [prim_guard_ok] in Hg. apply andb_and in Hg. destruct Hg as [Hg1 Hg2].
  apply (eval_bin64_Odiv (z64 a) (z64 b)).
  - destruct (Int64.eq (z64 b) Int64.zero) eqn:E1.
    + cbn [negb] in Hg1. discriminate Hg1.
    + reflexivity.
  - intro E2.
    destruct (Int64.eq (z64 a) (Int64.repr Int64.min_signed)) eqn:Ex.
    + cbn [negb orb] in Hg2.
      destruct (Int64.eq (z64 b) Int64.mone) eqn:E3.
      * cbn [negb] in Hg2. discriminate Hg2.
      * reflexivity.
    + discriminate E2.
Qed.

(* Every emitted prim_expr is realized by the matching eval lemma, with the
   Odiv guards taken from prim_guard_ok. *)
(* Every emitted prim_expr is realized by the matching eval lemma; the dispatch
   is per-prim explicit because Rocq 9.1 multi-goal match/solve dispatch silently
   under-covers.  Arms in Syntax.v Prim constructor order. *)
Lemma prim_expr_eval : forall (p : Prim) (vs : list Val) (le : Clight.temp_env),
  prim_guard_ok p vs = true ->
  Clight.eval_expr ge0 Clight.empty_env le Mem.empty
    (Lower.prim_expr p vs) (prim_clight p vs).
Proof.
  intros p vs le Hg.
  destruct p.
  - (* PAdd *)
    destruct vs as [ | a [ | b [ | c rest ] ] ]; cbn [Lower.prim_expr prim_clight];
    [ apply eval_const64 | apply eval_const64
    | rewrite !vconst_z64; apply eval_bin64_Oadd
    | apply eval_const64 ].
  - (* PSub *)
    destruct vs as [ | a [ | b [ | c rest ] ] ]; cbn [Lower.prim_expr prim_clight];
    [ apply eval_const64 | apply eval_const64
    | rewrite !vconst_z64; apply eval_bin64_Osub
    | apply eval_const64 ].
  - (* PMul *)
    destruct vs as [ | a [ | b [ | c rest ] ] ]; cbn [Lower.prim_expr prim_clight];
    [ apply eval_const64 | apply eval_const64
    | rewrite !vconst_z64; apply eval_bin64_Omul
    | apply eval_const64 ].
  - (* PDiv: increment C floor fold - the emitted node is a folded Econst_long
       constant (decision 12), so all four arms close via eval_const64; no Odiv
       runtime dispatch remains. *)
    destruct vs as [ | a [ | b [ | c rest ] ] ]; cbn [Lower.prim_expr prim_clight];
    [ apply eval_const64 | apply eval_const64
    | apply eval_const64 | apply eval_const64 ].
  - (* PNeg *)
    destruct vs as [ | a [ | b [ | c rest ] ] ]; cbn [Lower.prim_expr prim_clight];
    [ apply eval_const64
    | rewrite vconst_z64; apply eval_un64_Oneg
    | apply eval_const64 | apply eval_const64 ].
  - (* PPls: placeholder arms only *)
    destruct vs as [ | a [ | b [ | c rest ] ] ]; cbn [Lower.prim_expr prim_clight];
    [ apply eval_const64 | apply eval_const64 | apply eval_const64 | apply eval_const64 ].
  - (* PGt *)
    destruct vs as [ | a [ | b [ | c rest ] ] ]; cbn [Lower.prim_expr prim_clight];
    [ apply eval_const64 | apply eval_const64
    | rewrite !vconst_z64; apply eval_bin64_Ogt
    | apply eval_const64 ].
  - (* PLt *)
    destruct vs as [ | a [ | b [ | c rest ] ] ]; cbn [Lower.prim_expr prim_clight];
    [ apply eval_const64 | apply eval_const64
    | rewrite !vconst_z64; apply eval_bin64_Olt
    | apply eval_const64 ].
  - (* PGEq *)
    destruct vs as [ | a [ | b [ | c rest ] ] ]; cbn [Lower.prim_expr prim_clight];
    [ apply eval_const64 | apply eval_const64
    | rewrite !vconst_z64; apply eval_bin64_Oge
    | apply eval_const64 ].
  - (* PLEq *)
    destruct vs as [ | a [ | b [ | c rest ] ] ]; cbn [Lower.prim_expr prim_clight];
    [ apply eval_const64 | apply eval_const64
    | rewrite !vconst_z64; apply eval_bin64_Ole
    | apply eval_const64 ].
  - (* PNEq *)
    destruct vs as [ | a [ | b [ | c rest ] ] ]; cbn [Lower.prim_expr prim_clight];
    [ apply eval_const64 | apply eval_const64
    | rewrite !vconst_z64; apply eval_bin64_One
    | apply eval_const64 ].
  - (* PIsInt: placeholder arms only *)
    destruct vs as [ | a [ | b [ | c rest ] ] ]; cbn [Lower.prim_expr prim_clight];
    [ apply eval_const64 | apply eval_const64 | apply eval_const64 | apply eval_const64 ].
  - (* PIsBool: placeholder arms only *)
    destruct vs as [ | a [ | b [ | c rest ] ] ]; cbn [Lower.prim_expr prim_clight];
    [ apply eval_const64 | apply eval_const64 | apply eval_const64 | apply eval_const64 ].
  - (* PIsUnit: placeholder arms only *)
    destruct vs as [ | a [ | b [ | c rest ] ] ]; cbn [Lower.prim_expr prim_clight];
    [ apply eval_const64 | apply eval_const64 | apply eval_const64 | apply eval_const64 ].
  - (* PCons: placeholder arms only *)
    destruct vs as [ | a [ | b [ | c rest ] ] ]; cbn [Lower.prim_expr prim_clight];
    [ apply eval_const64 | apply eval_const64 | apply eval_const64 | apply eval_const64 ].
  - (* PCons2: placeholder arms only *)
    destruct vs as [ | a [ | b [ | c rest ] ] ]; cbn [Lower.prim_expr prim_clight];
    [ apply eval_const64 | apply eval_const64 | apply eval_const64 | apply eval_const64 ].
  - (* PDotDot: placeholder arms only *)
    destruct vs as [ | a [ | b [ | c rest ] ] ]; cbn [Lower.prim_expr prim_clight];
    [ apply eval_const64 | apply eval_const64 | apply eval_const64 | apply eval_const64 ].
  - (* PArrLen: placeholder arms only *)
    destruct vs as [ | a [ | b [ | c rest ] ] ]; cbn [Lower.prim_expr prim_clight];
    [ apply eval_const64 | apply eval_const64 | apply eval_const64 | apply eval_const64 ].
Qed.
(* ---------- T6: the checked fragment is realized from the empty context ---------- *)

(* The ws_expr guard is depth-indexed (a Block body is checked at `length
   slots + d`), so the induction carries the depth universally; the temp env is
   universally quantified because sequencing threads it.  The conjunction with
   the final-value characterization is decision 10's reading, with lower_final
   as the computable claim. *)
Theorem T6_exec_ws : forall (e : Expr) (d : nat) (le : Clight.temp_env),
  ws_expr d e = true -> det_struct e = true -> range_ok e = true ->
  exists le',
    Clight1.exec_stmt ge0 Clight.empty_env le Mem.empty (clight_of (Lower.lower e))
      Events.E0 le' Mem.empty ClightBigstep.Out_normal
    /\ PTree.get Lower.lower_res le' = lower_final e (PTree.get Lower.lower_res le).
Proof.
  (* Constructor order per Syntax.v: Ret Glob App TupE Seq Unify Choice Fail
     Block Iter; the arm skeletons mirror T7_no_switch_ws (Lower.v). *)
  induction e as [v | gid | f IHf a IHav | es _ | s1 IHs1 s2 IHs2
                  | u1 IHu1 u2 IHu2 | c1 IHc1 c2 IHc2 | | sl body0 IHbody
                  | ic0 b0 IHb r0 IHr];
    intros d le Hw Hd Hr.
  - (* Ret: the Sset writes the value, eval_vconst_val mirrors vconst *)
    cbn [lower clight_of lower_final].
    exists (PTree.set Lower.lower_res (clight_of_val v) le); split.
    + apply ClightBigstep.exec_Sset. apply eval_vconst_val.
    + apply PTree.gss.
  - (* Glob: bans_okE = false *)
    apply det_struct_components in Hd. destruct Hd as [Hb [Hc [Hu [Ha Ht]]]].
    cbn [bans_okE] in Hb. discriminate.
  - (* App: the checked node shape (app_node_ok_shape) is exactly the arm
       prim_expr/prim_clight realize, with the kernel guards (PDiv) transferred
       by prim_guard_ok_canon *)
    apply det_struct_components in Hd. destruct Hd as [Hb [Hc [Hu [Ha Ht]]]].
    cbn [apps_okE] in Ha. apply andb3_and in Ha. destruct Ha as [Ha1 [Ha2 Ha3]].
    destruct (app_node_ok_shape _ _ Ha1) as [p [vs [Hf [Hvs Hpath]]]].
    cbn [range_ok] in Hr. rewrite Hf in Hr. rewrite Hvs in Hr. cbn [range_ok] in Hr.
    apply andb_and in Hr. destruct Hr as [Hbase Hnode].
    apply andb_and in Hbase. destruct Hbase as [Hrf Hra].
    assert (Hg : prim_guard_ok p vs = true).
    { apply (prim_guard_ok_canon p vs a Hvs Hra Hpath Hnode). }
    cbn [lower clight_of]. rewrite Hf. rewrite Hvs.
    cbn [Lower.prim_head prim_operand_vals lower_final].
    exists (PTree.set Lower.lower_res (prim_clight p vs) le); split.
    + apply ClightBigstep.exec_Sset. apply (prim_expr_eval p vs le Hg).
    + cbn [Lower.prim_head prim_operand_vals lower_final].
      rewrite Hvs.
      cbn [Lower.prim_head prim_operand_vals lower_final].
      apply PTree.gss.
  - (* TupE: tup_node_ok pins rets_of = Some; exec_rets_sets runs the Sset
       chain with "last ret wins" *)
    apply det_struct_components in Hd. destruct Hd as [Hb [Hc [Hu [Ha Ht]]]].
    cbn [tup_rets_okE] in Ht. apply andb_and in Ht. destruct Ht as [Ht1 Ht2].
    destruct (tup_node_ok_rets _ Ht1) as [vs Hrs].
    cbn [lower clight_of lower_final rets_of last_val].
    rewrite Hrs.
    cbn [lower clight_of lower_final rets_of last_val].
    apply (exec_rets_sets vs le).
  - (* Seq: both halves carry their guards down; exec_seq_close composes *)
    apply det_struct_components in Hd. destruct Hd as [Hb [Hc [Hu [Ha Ht]]]].
    cbn [ws_expr] in Hw. cbn [bans_okE] in Hb; cbn [blocks_closed_okE] in Hc;
    cbn [unify_okE] in Hu; cbn [apps_okE] in Ha; cbn [tup_rets_okE] in Ht.
    cbn [range_ok] in Hr.
    apply andb_and in Hw. destruct Hw as [Hw1 Hw2].
    apply andb_and in Hb. destruct Hb as [Hb1 Hb2].
    apply andb_and in Hc. destruct Hc as [Hc1 Hc2].
    apply andb_and in Hu. destruct Hu as [Hu1 Hu2].
    apply andb_and in Ha. destruct Ha as [Ha1 Ha2].
    apply andb_and in Ht. destruct Ht as [Ht1 Ht2].
    apply andb_and in Hr. destruct Hr as [Hr1 Hr2].
    destruct (IHs1 d le Hw1 (det_struct_mk _ Hb1 Hc1 Hu1 Ha1 Ht1) Hr1)
      as [le1 [Hex1 Hfin1]].
    destruct (IHs2 d le1 Hw2 (det_struct_mk _ Hb2 Hc2 Hu2 Ha2 Ht2) Hr2)
      as [le2 [Hex2 Hfin2]].
    exists le2; split.
    + cbn [lower clight_of].
      apply exec_seq_close with (le1 := le1); [exact Hex1 | exact Hex2].
    + cbn [lower_final]. rewrite Hfin2. rewrite Hfin1. reflexivity.
  - (* Unify: eq_pair_ok = true emits Sskip; lower_final passes the value through *)
    apply det_struct_components in Hd. destruct Hd as [Hb [Hc [Hu [Ha Ht]]]].
    cbn [unify_okE] in Hu. apply andb3_and in Hu. destruct Hu as [Hu1 [Hu2 Hu3]].
    cbn [lower clight_of]. rewrite Hu1. cbn [lower clight_of lower_final].
    exists le; split.
    + apply ClightBigstep.exec_Sskip.
    + reflexivity.
  - (* Choice: bans_okE = false *)
    apply det_struct_components in Hd. destruct Hd as [Hb [Hc [Hu [Ha Ht]]]].
    cbn [bans_okE] in Hb. discriminate.
  - (* Fail: bans_okE = false *)
    apply det_struct_components in Hd. destruct Hd as [Hb [Hc [Hu [Ha Ht]]]].
    cbn [bans_okE] in Hb. discriminate.
  - (* Block: prelude writes only slot tempvars (exec_slots_prelude), the body
       is checked at length slots + d *)
    apply det_struct_components in Hd. destruct Hd as [Hb [Hc [Hu [Ha Ht]]]].
    cbn [ws_expr] in Hw. cbn [bans_okE] in Hb; cbn [blocks_closed_okE] in Hc.
    cbn [range_ok] in Hr.
    apply andb_and in Hw. destruct Hw as [_ Hw2].
    apply andb_and in Hb. destruct Hb as [_ Hb2].
    apply andb_and in Hc. destruct Hc as [_ Hc2].
    apply andb_and in Hr. destruct Hr as [_ Hr2].
    destruct (exec_slots_prelude sl le) as [le1 [Hpre1 Hpre2]].
    destruct (IHbody ((Datatypes.length sl) + d)%nat le1 Hw2
      (det_struct_mk _ Hb2 Hc2 Hu Ha Ht) Hr2) as [le2 [Hex2 Hfin2]].
    exists le2; split.
    + cbn [lower clight_of].
      apply exec_seq_close with (le1 := le1); [exact Hpre1 | exact Hex2].
    + cbn [lower_final]. rewrite Hfin2. rewrite Hpre2. reflexivity.
  - (* Iter: bans_okE = false *)
    apply det_struct_components in Hd. destruct Hd as [Hb [Hc [Hu [Ha Ht]]]].
    cbn [bans_okE] in Hb. discriminate.
Qed.

Theorem T6_exec : forall (e : Expr),
  det_check e = true -> range_ok e = true ->
  exists le',
    Clight1.exec_stmt ge0 Clight.empty_env le0 Mem.empty (clight_of (Lower.lower e))
      Events.E0 le' Mem.empty ClightBigstep.Out_normal
    /\ PTree.get Lower.lower_res le' = lower_final e (PTree.get Lower.lower_res le0).
Proof.
  intros e H Hrange. apply det_check_components in H. destruct H as [Hw Hd].
  apply (T6_exec_ws e 0 le0 Hw Hd Hrange).
Qed.
