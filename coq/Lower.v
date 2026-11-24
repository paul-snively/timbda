(* Lower.v — docs/PLAN.md § 3 items 6 (T6) and 7 (T7): determinate fragments -> Clight;
   general -> CPS calls back into the Eval machine.

   WHAT THIS FILE IS.  `lower` maps a Timbda-0 expression to an `lstmt` tree: Clight
   statements where the kernel's own determinacy checker says straight-line code is
   justified, `Lswitch` nodes ("context calls": hand the residual Expr to the Eval
   scheduler) everywhere else.  T7 (`T7_no_switch`) is the anti-naivety guarantee verbatim:
   over the CHECKED fragment the lowering emits no context call at all, structural
   induction on `lower` against the five guards of `Checks.det_struct`
   (ws_expr / bans_okE / blocks_closed_okE / unify_okE / apps_okE / tup_rets_okE).
   T7 proves NO semantic claim — it is a purely syntactic statement about the tree
   `lower` builds.  The refinement claim (T6: Wbisim (sem e) (ClightSem c)) is a later
   increment with its own design obligations, pinned here so nothing is smuggled:

   - The accepted fragment (measured against Checks.v 2026-11-25): bans_okE rejects
     Glob/Choice/Fail/Iter outright; apps_okE admits only `Ret (VPrim p)` application
     heads on literal operand lists (app_node_ok_shape: f = Ret (VPrim p) and
     prim_operand_vals a = Some vs — NO lambda beta in the determinate fragment);
     unify_okE admits only equal literal `Ret` pairs (eq_pair_ok); tup_rets_okE admits
     only all-Ret tuples (rets_of); blocks_closed_okE restricts Block slots to
     `Some (VInt _) / Some (VVar _)`.  So the checked fragment is purely straight-line.
   - Value encoding hazard (docs/DESIGN-NOTES.md § 13.7 ledger): Timbda VInt is an
     unbounded Z (Syntax.v) while Clight integer arithmetic is 64-bit (Tlong Signed
     noattr, Vlong, Econst_long on Int64; Econst_int is the 32-bit C int literal).
     `vconst` below wraps via Int64.repr.  T6 must
     carry an explicit 64-bit-range hypothesis on every intermediate value of the
     evaluated fragment — or scope the fragment to corpus-verified terms.  T7 is
     insensitive to this: it never inspects emitted statements.
   - Placeholder arms, flagged: prims outside the int-arithmetic/relational map
     (PIsInt/PIsBool/PIsUnit/PCons/PCons2/PDotDot/PArrLen/PPls), tuple layout
     (TupE of Ret), `Some (VVar _)` Block slots, and lambda/delay VALUES reaching
     `vconst` carry structurally-present but semantically vacuous statements
     (Sskip / constant 0) until T6 settles the value encoding.  They never affect
     `no_switch`: admitted nodes EMIT (which is all T7 needs), and T6 must either
     extend these maps or restrict the emitted fragment.
   - Audit lane (docs/DESIGN-NOTES.md § 13.7, measured 2026-11-25): the Clight
     SYNTAX cone (statement/expr types, constructors) prints `Closed under the
     global context`; only the Clight SEMANTICS cone (Clight.step & co.) carries
     Flocq's two ClassicalDedekindReals axioms.  T7 lives in the kernel's strict
     eq_rect_eq-only Print-Assumptions gate unchanged; a Print Assumptions on the
     T6 statement would legitimately break it and needs its own lane.
*)

From Stdlib Require Import ZArith List.
Require Import compcert.lib.Integers compcert.common.Values compcert.common.AST
  compcert.cfrontend.Csyntax compcert.cfrontend.Ctypes compcert.cfrontend.Clight.
Require Import Timbda.Syntax Timbda.Rewriting Timbda.Semantics Timbda.Eval.
Require Import Timbda.Checks.

(* ---------- value -> Clight expression (Int64; hazard note above) ---------- *)

Definition tint64 : Ctypes.type := Tlong Signed noattr.
Definition tint32 : Ctypes.type := Tint I32 Signed noattr.

(* The lowered tree writes each expression's value into this tempvar. *)
Definition lower_res : AST.ident := xH.

(* Econst_long is the 64-bit constant ctor (Econst_int is 32-bit `int`);
   Vlong/Econst_long/Tlong is the one value-width story T6 will carry. *)
Definition vconst (v : Val) : Clight.expr :=
  match v with
  | VInt z    => Clight.Econst_long (Int64.repr z) tint64
  | VTrue     => Clight.Econst_long (Int64.repr 1) tint64
  | VFalse    => Clight.Econst_long (Int64.repr 0) tint64
  | VUnit     => Clight.Econst_long (Int64.repr 0) tint64
  | _         => Clight.Econst_long (Int64.repr 0) tint64   (* placeholder arm *)
  end.

(* prim -> Clight operation: the int-arithmetic/relational core, one-to-one. *)
Definition prim_expr (p : Prim) (vs : list Val) : Clight.expr :=
  match p, vs with
  | PAdd, a :: b :: nil => Clight.Ebinop Cop.Oadd (vconst a) (vconst b) tint64
  | PSub, a :: b :: nil => Clight.Ebinop Cop.Osub (vconst a) (vconst b) tint64
  | PMul, a :: b :: nil => Clight.Ebinop Cop.Omul (vconst a) (vconst b) tint64
  | PDiv, a :: b :: nil => Clight.Ebinop Cop.Odiv (vconst a) (vconst b) tint64
  | PLt,  a :: b :: nil => Clight.Ebinop Cop.Olt  (vconst a) (vconst b) tint32
  | PGt,  a :: b :: nil => Clight.Ebinop Cop.Ogt  (vconst a) (vconst b) tint32
  | PLEq, a :: b :: nil => Clight.Ebinop Cop.Ole  (vconst a) (vconst b) tint32
  | PGEq, a :: b :: nil => Clight.Ebinop Cop.Oge  (vconst a) (vconst b) tint32
  | PNEq, a :: b :: nil => Clight.Ebinop Cop.One  (vconst a) (vconst b) tint32
  | PNeg, a :: nil      => Clight.Eunop Cop.Oneg (vconst a) tint64
  | _, _                => Clight.Econst_long (Int64.repr 0) tint64   (* placeholder arm *)
  end.

Definition prim_head (f : Expr) : option Prim :=
  match f with Ret (VPrim p) => Some p | _ => None end.

(* Block slot prelude: VInt slots become assignments; VVar/None slots are the
   documented placeholder arm (T6 environment story).  Slot i names tempvar
   (i+1) so slot 0 never collides with lower_res = xH ... which IS xH = #1;
   slot i therefore maps to Z.to_pos (i+2). *)
Definition slot_ident (i : nat) : AST.ident := Z.to_pos (Z.of_nat (S (S i))).

Fixpoint slots_prelude (slots : list (Ty * option Val)) : Clight.statement :=
  match slots with
  | nil => Clight.Sskip
  | (_, Some (VInt z)) :: rest =>
      Clight.Ssequence (Clight.Sset (slot_ident (length rest)) (vconst (VInt z)))
                       (slots_prelude rest)
  | _ :: rest => Clight.Ssequence Clight.Sskip (slots_prelude rest)
  end.

(* ---------- the lowered tree ---------- *)

Inductive lstmt : Type :=
| Lclight : Clight.statement -> lstmt
| Lswitch : Expr -> lstmt        (* context call: hand the residual to the Eval machine *)
| Lseq    : lstmt -> lstmt -> lstmt.

Fixpoint lower (e : Expr) : lstmt :=
  match e with
  | Ret v => Lclight (Clight.Sset lower_res (vconst v))
  | Glob _ => Lswitch e
  | App f a =>
      match prim_head f, prim_operand_vals a with
      | Some p, Some vs => Lclight (Clight.Sset lower_res (prim_expr p vs))
      | _, _ => Lswitch e
      end
  | TupE es =>
      match rets_of es with
      | Some vs => Lclight (fold_right Clight.Ssequence Clight.Sskip
                          (map (fun v => Clight.Sset lower_res (vconst v)) vs))
      | None => Lswitch e
      end
  | Seq e1 e2 => Lseq (lower e1) (lower e2)
  | Unify e1 e2 =>
      if eq_pair_ok e1 e2 then Lclight Clight.Sskip else Lswitch e
  | Choice _ _ => Lswitch e
  | Fail => Lswitch e
  | Iter _ _ _ => Lswitch e
  | Block slots body => Lseq (Lclight (slots_prelude slots)) (lower body)
  end.

Fixpoint no_switch_l (l : lstmt) : bool :=
  match l with
  | Lclight _ => true
  | Lswitch _ => false
  | Lseq l1 l2 => no_switch_l l1 && no_switch_l l2
  end.

(* ---------- T7: the no-context-call theorem ---------- *)

(* The ws_expr guard is depth-indexed (a Block body is checked at
   `length slots + d`), so the induction carries the depth universally. *)
Theorem T7_no_switch_ws : forall (e : Expr) (d : nat),
  ws_expr d e = true -> det_struct e = true -> no_switch_l (lower e) = true.
Proof.
  (* Constructor order per Syntax.v: Ret Glob App TupE Seq Unify Choice Fail Block
     Iter.  Each bullet is self-contained (the guards are destructed and peeled
     per branch); the shared phase is only the induction and the intros. *)
  induction e as [v | gid | f IHf a IHav | es IHes | s1 IHs1 s2 IHs2
                 | u1 IHu1 u2 IHu2 | c1 IHc1 c2 IHc2 | | sl body0 IHbody
                 | ic0 b0 IHb r0 IHr];
    intros d Hw Hd.
  - (* Ret: emit Sset *)
    cbn [lower no_switch_l]. reflexivity.
  - (* Glob: bans_okE = false *)
    apply det_struct_components in Hd. destruct Hd as [Hb [Hc [Hu [Ha Ht]]]].
    cbn [bans_okE] in Hb. discriminate.
  - (* App: app_node_ok pins the shape the emitted arm matches *)
    apply det_struct_components in Hd. destruct Hd as [Hb [Hc [Hu [Ha Ht]]]].
    cbn [apps_okE] in Ha. apply andb3_and in Ha. destruct Ha as [Ha1 [Ha2 Ha3]].
    destruct (app_node_ok_shape _ _ Ha1) as [p [vs [Hf [Hvs _]]]].
    cbn [lower no_switch_l]. rewrite Hf, Hvs. cbn [prim_head no_switch_l]. reflexivity.
  - (* TupE: tup_node_ok pins rets_of = Some *)
    apply det_struct_components in Hd. destruct Hd as [Hb [Hc [Hu [Ha Ht]]]].
    cbn [tup_rets_okE] in Ht. apply andb_and in Ht. destruct Ht as [Ht1 Ht2].
    destruct (tup_node_ok_rets _ Ht1) as [vs Hrs].
    cbn [lower no_switch_l]. rewrite Hrs. cbn [no_switch_l]. reflexivity.
  - (* Seq: both halves carry their guards down *)
    apply det_struct_components in Hd. destruct Hd as [Hb [Hc [Hu [Ha Ht]]]].
    cbn [ws_expr] in Hw. cbn [bans_okE] in Hb; cbn [blocks_closed_okE] in Hc;
    cbn [unify_okE] in Hu; cbn [apps_okE] in Ha; cbn [tup_rets_okE] in Ht.
    apply andb_and in Hw. destruct Hw as [Hw1 Hw2].
    apply andb_and in Hb. destruct Hb as [Hb1 Hb2].
    apply andb_and in Hc. destruct Hc as [Hc1 Hc2].
    apply andb_and in Hu. destruct Hu as [Hu1 Hu2].
    apply andb_and in Ha. destruct Ha as [Ha1 Ha2].
    apply andb_and in Ht. destruct Ht as [Ht1 Ht2].
    cbn [lower no_switch_l].
    rewrite (IHs1 d Hw1 (det_struct_mk _ Hb1 Hc1 Hu1 Ha1 Ht1)).
    rewrite (IHs2 d Hw2 (det_struct_mk _ Hb2 Hc2 Hu2 Ha2 Ht2)).
    reflexivity.
  - (* Unify: eq_pair_ok = true takes the emitted (Sskip) arm *)
    apply det_struct_components in Hd. destruct Hd as [Hb [Hc [Hu [Ha Ht]]]].
    cbn [unify_okE] in Hu. apply andb3_and in Hu. destruct Hu as [Hu1 [Hu2 Hu3]].
    cbn [lower no_switch_l]. rewrite Hu1. cbn [no_switch_l]. reflexivity.
  - (* Choice: bans_okE = false *)
    apply det_struct_components in Hd. destruct Hd as [Hb [Hc [Hu [Ha Ht]]]].
    cbn [bans_okE] in Hb. discriminate.
  - (* Fail: bans_okE = false *)
    apply det_struct_components in Hd. destruct Hd as [Hb [Hc [Hu [Ha Ht]]]].
    cbn [bans_okE] in Hb. discriminate.
  - (* Block: body checked at length slots + d.  After cbn the unify/apps/tup
     guards are already the body's (single arm); bans/blocks/ws are conjunctive
     (slot checks on the left). *)
    apply det_struct_components in Hd. destruct Hd as [Hb [Hc [Hu [Ha Ht]]]].
    cbn [ws_expr] in Hw. cbn [bans_okE] in Hb; cbn [blocks_closed_okE] in Hc.
    apply andb_and in Hw. destruct Hw as [_ Hw2].
    apply andb_and in Hb. destruct Hb as [_ Hb2].
    apply andb_and in Hc. destruct Hc as [_ Hc2].
    cbn [lower no_switch_l].
    rewrite (IHbody (Datatypes.length sl + d) Hw2
      (det_struct_mk _ Hb2 Hc2 Hu Ha Ht)).
    reflexivity.
  - (* Iter: bans_okE = false *)
    apply det_struct_components in Hd. destruct Hd as [Hb [Hc [Hu [Ha Ht]]]].
    cbn [bans_okE] in Hb. discriminate.
Qed.

Theorem T7_no_switch : forall e, det_check e = true -> no_switch_l (lower e) = true.
Proof.
  intros e H. apply det_check_components in H. destruct H as [Hw Hd].
  apply (T7_no_switch_ws e 0 Hw Hd).
Qed.
