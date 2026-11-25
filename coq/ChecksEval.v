(* Timbda-0 kernel: the evaluation leg of T4's soundness (coq/ChecksEval.v - M2,
   docs/PLAN.md § 5 M2 status; the claim shapes are the ones tests/corpus/m2-det.texpr
   pinned, docs/DESIGN-NOTES.md § 11 and § 12).

   WHAT THIS FILE IS.  `Checks.v` is the checker and its sem-side leg (`T4_sem`).
   This module is the eval-side leg, over the same `det_check`:

     T4_eval   det_check e = true -> cand_bag (norm fuel e) = norm fuel e :: nil

   proved as three steps, each the honest version of one move of the evaluator:

     head_redex_det  one selected head step (`Eval.v`'s `head_redex`) preserves
                     `det_struct` - the guards do this as PINNING, not as filtering:
                     G5 forces an App head to `Ret (VPrim p)`, which shadows the
                     `R_BetaL`/`R_BetaT` arms (the only rows in the selected table that
                     can mint a `Choice`), G4 leaves `EqK1` as the only live `Unify` row
                     and its contractum is a literal, G3's `slots_closed_ok` kills the
                     promote rows inside `body_walk` so the only live block row is
                     `R_Subst`, which leaves the slot list untouched;
     norm_det        induction on fuel: at a stuck root the reconstruction re-reads
                     G4/G5/G6 on children that `det_struct` already pinned to stuck
                     syntax, so the node is reassembled from the hypothesis;
     cand_bag_single structural induction on the term: a G3-closed block reads through
                     its valued slots and each alternative collapses by the IH.

   WHY A SEPARATE MODULE (measured 2026-11-23, docs/DESIGN-NOTES.md § 12).  With this
   leg inside `Checks.v` the checker was the kernel's heaviest compilation unit: a cold
   `dune build` of `coq/` needed about 5 GiB and 27 minutes at the pinned `jobs 2`
   concurrency, which no envelope this box can host (a 42 GiB resident neighbour) covers -
   `tools/build/coq-build.sh` OOM-killed a worker inside its own 2G/3G cgroup and the gate
   watchdog refused the nix bill.  Splitting the leg out keeps every statement, proof and
   axiom status identical (`T4_eval` here is `Closed under the global context`, so this
   module needs no ctrees import at all) and makes the two heaviest units smaller than the
   one it replaces.

   No bridge between the two legs is claimed here either way: that is T8 at M3
   (docs/PLAN.md § 3 item 8, the RULES-AUDIT ll. 57/159 correction in decision 8). *)

From Stdlib Require Import ZArith List.
Import ListNotations.

Require Import Timbda.Syntax Timbda.Rewriting Timbda.RewRules Timbda.Semantics Timbda.Eval.
Require Import Timbda.RuleAst.   (* generated RuleID/selected_rows (M1 item 1) *)
Require Import Timbda.Checks.

(* `lia` for the two fuel/cutoff steps; `&&` needs the bool scope opened, not a direct
   Stdlib.Bool import (Checks.v records the notation clash). *)
From Stdlib Require Import Lia.
Local Open Scope bool_scope.

(* ---------------------------------------------------------------------
   Part 1 - the guard machinery the eval leg reads.
   --------------------------------------------------------------------- *)

(* =====================================================================
   Chunk C (part 1) - the guard machinery T4's eval-side leg reads.

   T4_eval talks about `norm` / `cand_bag`, i.e. about terms AFTER rewrite
   steps.  What every live head row must preserve is the frame-free conjunct
   bundle of `det_struct` (G2 bans, G3 closed blocks, G4 EqK1-only Unify
   pairs, G5 canonical apps, G6 TupE-of-values); G1 (ws_expr) is the only
   frame-aware guard and the eval-side leg never reads it.  This part packs
   the inversion lemmas, reconstruction (mk) lemmas, value-class bridges and
   the stuck-node identities of `norm` that parts 2 and 3 consume. *)

(* ---------- value classes ---------- *)

Lemma is_int_or_var_okV : forall v,
  is_int_or_var v = true -> bans_okV v = true /\ blocks_closed_okV v = true.
Proof.
  intros v H. destruct v; cbn [is_int_or_var] in H; try discriminate H;
  cbn [bans_okV blocks_closed_okV]; split; reflexivity.
Qed.

Lemma is_lit_okV : forall v,
  is_lit_val v = true -> bans_okV v = true /\ blocks_closed_okV v = true.
Proof.
  intros v H. destruct v; cbn [is_lit_val] in H; try discriminate H;
  cbn [bans_okV blocks_closed_okV]; split; reflexivity.
Qed.

(* Ret nodes are guard-neutral except for the value class itself. *)
Lemma det_struct_ret_okV : forall v,
  bans_okV v = true -> blocks_closed_okV v = true -> det_struct (Ret v) = true.
Proof.
  intros v Hb Hc. apply det_struct_mk.
  - cbn [bans_okE]; exact Hb.
  - cbn [blocks_closed_okE]; exact Hc.
  - cbn [unify_okE]; reflexivity.
  - cbn [apps_okE]; reflexivity.
  - cbn [tup_rets_okE]; reflexivity.
Qed.

Lemma det_struct_ret_intvar : forall v,
  is_int_or_var v = true -> det_struct (Ret v) = true.
Proof.
  intros v H. apply det_struct_ret_okV; apply is_int_or_var_okV; exact H.
Qed.

(* Rewriting.v slotShiftV at a slot value: VInt/VVar stay VInt/VVar (the VVar
   arm only recomputes the index; every non-VVar non-lambda non-tuple value is
   the identity arm). *)
(* The VVar arm of slotShiftV nests two Nat.ltb guards whose scrutinees are
   opaque, so `cbn` cannot collapse them; this shape lemma reads the arm
   instead: every branch returns a VVar. *)
Lemma is_int_or_var_ifVVar : forall (b1 b2 : bool) (x y z : nat),
  is_int_or_var (if b1 then VVar x else if b2 then VVar y else VVar z) = true.
Proof. intros b1 b2 x y z. destruct b1; destruct b2; reflexivity. Qed.

Lemma slotShift_int_or_var : forall n p off v,
  is_int_or_var v = true -> is_int_or_var (slotShiftV n p off v) = true.
Proof.
  intros n p off v H.
  destruct v; cbn [is_int_or_var] in H; try discriminate H;
  [ cbn [slotShiftV is_int_or_var]; reflexivity
  | cbn [slotShiftV]; apply is_int_or_var_ifVVar ].
Qed.

(* ---------- inversion at composite nodes ---------- *)

Lemma bans_okE_Seq_inv : forall e1 e2,
  bans_okE (Seq e1 e2) = true -> bans_okE e1 = true /\ bans_okE e2 = true.
Proof. intros e1 e2 H. cbn [bans_okE] in H. apply andb_and in H. exact H. Qed.

Lemma bans_okE_App_inv : forall f a,
  bans_okE (App f a) = true -> bans_okE f = true /\ bans_okE a = true.
Proof. intros f a H. cbn [bans_okE] in H. apply andb_and in H. exact H. Qed.

Lemma bans_okE_Unify_inv : forall e1 e2,
  bans_okE (Unify e1 e2) = true -> bans_okE e1 = true /\ bans_okE e2 = true.
Proof. intros e1 e2 H. cbn [bans_okE] in H. apply andb_and in H. exact H. Qed.

Lemma bans_okE_Block_slots : forall sl body,
  bans_okE (Block sl body) = true -> slots_bans_ok sl = true.
Proof.
  intros sl body H. cbn [bans_okE slots_bans_ok] in H.
  apply andb_and in H. exact (proj1 H).
Qed.

Lemma blocks_closed_okE_App_inv : forall f a,
  blocks_closed_okE (App f a) = true ->
  blocks_closed_okE f = true /\ blocks_closed_okE a = true.
Proof. intros f a H. cbn [blocks_closed_okE] in H. apply andb_and in H. exact H. Qed.

(* G3 consed: the tail of a closed slot list is closed. *)
Lemma slots_closed_tail : forall t ov rest,
  slots_closed_ok ((t, ov) :: rest) = true -> slots_closed_ok rest = true.
Proof.
  intros t ov rest H. destruct ov as [v |];
  [ destruct v; cbn [slots_closed_ok] in H; try discriminate H; exact H
  | cbn [slots_closed_ok] in H; discriminate H ].
Qed.

(* G3 read positionally: an in-range index of a closed slot list holds a
   valued entry, and that entry is an int or a slot variable. *)
Lemma slots_closed_at : forall sl p,
  slots_closed_ok sl = true -> Nat.ltb p (length sl) = true ->
  exists v, slot_value_at sl p = Some v /\ is_int_or_var v = true.
Proof.
  induction sl as [| [t ov] rest IH]; intros p Hc Hp.
  - cbn [length] in Hp. apply Nat.ltb_lt in Hp. exfalso; lia.
  - cbn [length] in Hp. destruct p as [| p'].
    + cbn [slot_value_at slot_at nth_error]. destruct ov as [v |].
      * eexists; split; [reflexivity |].
        apply slots_closed_head in Hc. cbn [is_int_or_var] in Hc. exact Hc.
      * apply slots_closed_head in Hc. cbn in Hc. discriminate Hc.
    + cbn [slot_value_at slot_at nth_error].
      apply Nat.ltb_lt in Hp.
      assert (Hp' : Nat.ltb p' (length rest) = true) by (apply Nat.ltb_lt; lia).
      destruct (IH p' (slots_closed_tail t ov rest Hc) Hp') as [v [E1 Hint]].
      exists v; split; [exact E1 | exact Hint].
Qed.

(* A valued slot kills the promote guards: RewPromoteL/R quantify over
   `exists X,x{hp}`, a declared-only entry (Eval.v promote_guard). *)
Lemma promote_guard_dead : forall n sl p v,
  slot_value_at sl p = Some v -> promote_guard n sl p v = false.
Proof.
  intros n sl p v H. unfold promote_guard. rewrite H. reflexivity.
Qed.

(* ---------- reconstruction (mk) at composite nodes ---------- *)

Lemma bans_okE_Seq2 : forall e1 e2, bans_okE e1 = true -> bans_okE e2 = true ->
  bans_okE (Seq e1 e2) = true.
Proof. intros e1 e2 H1 H2. cbn [bans_okE]. apply andb_true2; assumption. Qed.

Lemma bans_okE_App2 : forall e1 e2, bans_okE e1 = true -> bans_okE e2 = true ->
  bans_okE (App e1 e2) = true.
Proof. intros e1 e2 H1 H2. cbn [bans_okE]. apply andb_true2; assumption. Qed.

Lemma bans_okE_Unify2 : forall e1 e2, bans_okE e1 = true -> bans_okE e2 = true ->
  bans_okE (Unify e1 e2) = true.
Proof. intros e1 e2 H1 H2. cbn [bans_okE]. apply andb_true2; assumption. Qed.

Lemma blocks_closed_okE_Seq2 : forall e1 e2,
  blocks_closed_okE e1 = true -> blocks_closed_okE e2 = true ->
  blocks_closed_okE (Seq e1 e2) = true.
Proof.
  intros e1 e2 H1 H2. cbn [blocks_closed_okE]. apply andb_true2; assumption.
Qed.

Lemma blocks_closed_okE_App2 : forall e1 e2,
  blocks_closed_okE e1 = true -> blocks_closed_okE e2 = true ->
  blocks_closed_okE (App e1 e2) = true.
Proof.
  intros e1 e2 H1 H2. cbn [blocks_closed_okE]. apply andb_true2; assumption.
Qed.

Lemma blocks_closed_okE_Unify2 : forall e1 e2,
  blocks_closed_okE e1 = true -> blocks_closed_okE e2 = true ->
  blocks_closed_okE (Unify e1 e2) = true.
Proof.
  intros e1 e2 H1 H2. cbn [blocks_closed_okE]. apply andb_true2; assumption.
Qed.

Lemma unify_okE_Seq2 : forall e1 e2,
  unify_okE e1 = true -> unify_okE e2 = true -> unify_okE (Seq e1 e2) = true.
Proof. intros e1 e2 H1 H2. cbn [unify_okE]. apply andb_true2; assumption. Qed.

Lemma unify_okE_App2 : forall e1 e2,
  unify_okE e1 = true -> unify_okE e2 = true -> unify_okE (App e1 e2) = true.
Proof. intros e1 e2 H1 H2. cbn [unify_okE]. apply andb_true2; assumption. Qed.

Lemma apps_okE_Seq2 : forall e1 e2,
  apps_okE e1 = true -> apps_okE e2 = true -> apps_okE (Seq e1 e2) = true.
Proof. intros e1 e2 H1 H2. cbn [apps_okE]. apply andb_true2; assumption. Qed.

Lemma apps_okE_Unify2 : forall e1 e2,
  apps_okE e1 = true -> apps_okE e2 = true -> apps_okE (Unify e1 e2) = true.
Proof. intros e1 e2 H1 H2. cbn [apps_okE]. apply andb_true2; assumption. Qed.

Lemma apps_okE_ret : forall v, apps_okE (Ret v) = true.
Proof. intros v. cbn [apps_okE]. reflexivity. Qed.

Lemma tup_rets_okE_ret : forall v, tup_rets_okE (Ret v) = true.
Proof. intros v. reflexivity. Qed.

Lemma tup_rets_okE_Seq2 : forall e1 e2,
  tup_rets_okE e1 = true -> tup_rets_okE e2 = true -> tup_rets_okE (Seq e1 e2) = true.
Proof. intros e1 e2 H1 H2. cbn [tup_rets_okE]. apply andb_true2; assumption. Qed.

Lemma tup_rets_okE_App2 : forall e1 e2,
  tup_rets_okE e1 = true -> tup_rets_okE e2 = true -> tup_rets_okE (App e1 e2) = true.
Proof. intros e1 e2 H1 H2. cbn [tup_rets_okE]. apply andb_true2; assumption. Qed.

Lemma tup_rets_okE_Unify2 : forall e1 e2,
  tup_rets_okE e1 = true -> tup_rets_okE e2 = true -> tup_rets_okE (Unify e1 e2) = true.
Proof. intros e1 e2 H1 H2. cbn [tup_rets_okE]. apply andb_true2; assumption. Qed.

(* `&&` is left-associative in the checker source, so the three-way conjuncts
   the guard fixpoints produce peel as (a && b) && c. *)
Lemma andb3_true3 : forall a b c,
  a = true -> b = true -> c = true -> a && b && c = true.
Proof. intros a b c Ha Hb Hc. apply andb_true2; [apply andb_true2; assumption | assumption]. Qed.

(* Full-bundle reconstruction at one node. *)

Lemma det_struct_mk_Seq : forall e1 e2,
  det_struct e1 = true -> det_struct e2 = true -> det_struct (Seq e1 e2) = true.
Proof.
  intros e1 e2 H1 H2.
  destruct (det_struct_components e1 H1) as [Hb1 [Hl1 [Hu1 [Ha1 Ht1]]]].
  destruct (det_struct_components e2 H2) as [Hb2 [Hl2 [Hu2 [Ha2 Ht2]]]].
  apply det_struct_mk.
  - apply bans_okE_Seq2; assumption.
  - apply blocks_closed_okE_Seq2; assumption.
  - apply unify_okE_Seq2; assumption.
  - apply apps_okE_Seq2; assumption.
  - apply tup_rets_okE_Seq2; assumption.
Qed.

Lemma det_struct_mk_App : forall f a,
  app_node_ok f a = true -> det_struct f = true -> det_struct a = true ->
  det_struct (App f a) = true.
Proof.
  intros f a Hann Hf Ha.
  destruct (det_struct_components f Hf) as [Hbf [Hlf [Huf [Haf Htf]]]].
  destruct (det_struct_components a Ha) as [Hba [Hla [Hua [Haa Hta]]]].
  apply det_struct_mk.
  - apply bans_okE_App2; assumption.
  - apply blocks_closed_okE_App2; assumption.
  - apply unify_okE_App2; assumption.
  - cbn [apps_okE]; apply andb3_true3; assumption.
  - apply tup_rets_okE_App2; assumption.
Qed.

Lemma det_struct_mk_Unify : forall e1 e2,
  eq_pair_ok e1 e2 = true -> det_struct e1 = true -> det_struct e2 = true ->
  det_struct (Unify e1 e2) = true.
Proof.
  intros e1 e2 Heq H1 H2.
  destruct (det_struct_components e1 H1) as [Hb1 [Hl1 [Hu1 [Ha1 Ht1]]]].
  destruct (det_struct_components e2 H2) as [Hb2 [Hl2 [Hu2 [Ha2 Ht2]]]].
  apply det_struct_mk.
  - apply bans_okE_Unify2; assumption.
  - apply blocks_closed_okE_Unify2; assumption.
  - cbn [unify_okE]; apply andb3_true3; assumption.
  - apply apps_okE_Unify2; assumption.
  - apply tup_rets_okE_Unify2; assumption.
Qed.

Lemma det_struct_mk_Block : forall sl body,
  slots_bans_ok sl = true -> slots_closed_ok sl = true -> det_struct body = true ->
  det_struct (Block sl body) = true.
Proof.
  intros sl body Hslots Hclosed Hbody.
  destruct (det_struct_components body Hbody) as [Hb [Hl [Hu [Ha Ht]]]].
  apply det_struct_mk.
  - cbn [bans_okE slots_bans_ok]; apply andb_true2; assumption.
  - cbn [blocks_closed_okE]; apply andb_true2; assumption.
  - cbn [unify_okE]; exact Hu.
  - cbn [apps_okE]; exact Ha.
  - cbn [tup_rets_okE]; exact Ht.
Qed.

(* G5's prim arm at the bare `Ret v` operand shape, once the operand class is
   known: the `prim_bare_ok` guard (neg[v] at an int-or-var value) is exactly
   what app_node_ok reads there, and the all-int branch closes on its own. *)
Lemma app_node_ok_ret_intvar : forall p v,
  prim_bare_ok p v = true -> is_int_or_var v = true ->
  app_node_ok (Ret (VPrim p)) (Ret v) = true.
Proof.
  intros p v Hbare Hiv.
  destruct p; cbn [prim_bare_ok] in Hbare; try discriminate Hbare;
  destruct v; cbn [is_int_or_var] in Hiv; try discriminate Hiv;
  cbn [app_node_ok prim_operand_vals all_int prim_total_res prim_total prim_bare_ok];
  reflexivity.
Qed.

(* ---------- operand-list bridges ---------- *)

Lemma operand_vals_bans : forall a vs,
  prim_operand_vals a = Some vs -> bans_okE a = true ->
  forall v, In v vs -> bans_okV v = true.
Proof.
  intros a vs Heap Hb v Hv.
  apply prim_operand_vals_inv in Heap.
  destruct Heap as [HeapL | HeapR].
  - destruct HeapL as [es Hconj]. destruct Hconj as [Hshape Hret].
    rewrite Hshape in Hb. cbn [bans_okE] in Hb.
    rewrite (rets_of_map_rets es vs Hret) in Hb.
    assert (Hfa : forall x, In x (map Ret vs) -> bans_okE x = true)
      by (apply (forallb_In Expr bans_okE (map Ret vs)); exact Hb).
    change (bans_okE (Ret v) = true). apply Hfa. apply In_map_ret. exact Hv.
  - destruct HeapR as [v0 Hconj2]. destruct Hconj2 as [Hshape0 Hvs].
    rewrite Hvs in Hv. cbn [In] in Hv. destruct Hv as [Hid | Hv'].
    + subst v. rewrite Hshape0 in Hb. cbn [bans_okE] in Hb. exact Hb.
    + destruct Hv'.
Qed.

Lemma operand_vals_closed : forall a vs,
  prim_operand_vals a = Some vs -> blocks_closed_okE a = true ->
  forall v, In v vs -> blocks_closed_okV v = true.
Proof.
  intros a vs Heap Hl v Hv.
  apply prim_operand_vals_inv in Heap.
  destruct Heap as [HeapL | HeapR].
  - destruct HeapL as [es Hconj]. destruct Hconj as [Hshape Hret].
    rewrite Hshape in Hl. cbn [blocks_closed_okE] in Hl.
    rewrite (rets_of_map_rets es vs Hret) in Hl.
    assert (Hfa : forall x, In x (map Ret vs) -> blocks_closed_okE x = true)
      by (apply (forallb_In Expr blocks_closed_okE (map Ret vs)); exact Hl).
    change (blocks_closed_okE (Ret v) = true). apply Hfa. apply In_map_ret. exact Hv.
  - destruct HeapR as [v0 Hconj2]. destruct Hconj2 as [Hshape0 Hvs].
    rewrite Hvs in Hv. cbn [In] in Hv. destruct Hv as [Hid | Hv'].
    + subst v. rewrite Hshape0 in Hl. cbn [blocks_closed_okE] in Hl. exact Hl.
    + destruct Hv'.
Qed.

(* ---------- stuck-node identities of norm ---------- *)

Lemma norm_ret : forall (v : Val) (fuel : nat), norm fuel (Ret v) = Ret v.
Proof. induction fuel; cbn [norm head_redex]; reflexivity. Qed.

Lemma map_norm_ret : forall (vs : list Val) (fuel : nat),
  map (norm fuel) (map Ret vs) = map Ret vs.
Proof.
  intros vs fuel. induction vs as [| v rest IH]; cbn [map];
  [reflexivity | rewrite (norm_ret v fuel); rewrite IH; reflexivity].
Qed.

Lemma norm_tup_rets : forall (es : list Expr) (vs : list Val) (fuel : nat),
  rets_of es = Some vs -> norm fuel (TupE es) = TupE es.
Proof.
  intros es vs fuel H. rewrite (rets_of_map_rets es vs H).
  destruct fuel; cbn [norm head_redex]; [reflexivity | rewrite map_norm_ret; reflexivity].
Qed.

(* An App whose G5 guard passed has a stuck head value and a stuck operand
   node (Eval.v prim_operand_vals only succeeds at `Ret`/`TupE`-of-`Ret`), so
   fuel descent leaves the whole application fixed.  Used as two rewrite
   rules, one per operand shape. *)
Lemma norm_operand_ret : forall a vs (fuel : nat),
  prim_operand_vals a = Some vs -> norm fuel a = a.
Proof.
  intros a vs fuel Heapr.
  apply prim_operand_vals_inv in Heapr.
  destruct Heapr as [HeapL | HeapR].
  - destruct HeapL as [es Hconj]. destruct Hconj as [Hshape Hret].
    rewrite Hshape. apply (norm_tup_rets es vs fuel Hret).
  - destruct HeapR as [v0 Hconj2]. destruct Hconj2 as [Hshape0 _].
    rewrite Hshape0. apply (norm_ret v0 fuel).
Qed.
(* ---------- Chunk C (part 2) - prim results preserve value guards ----------
   The R_Prim arm of `head_redex` (Eval.v) computes `prim_total p vs` and
   returns `Ret w` when it says `PRes w`.  The G5 guard passed for that App
   node means the operand list `vs` passed the guard bundle (G2/G3 see it
   through `bans_okE`/`blocks_closed_okE` of the operand node, read
   value-by-value by `operand_vals_bans`/`operand_vals_closed`).
   `prim_result_okV` is the one table reading that closes the square:
   inspecting Syntax.v's 18-arm table, every `PRes` result is either a
   literal, or a `VTup` whose entries are operands or literal images, so
   operand-guarded inputs produce guard-clean results.  The `PFail` arms are
   not excluded here: a `PFail` arm makes the contractum `Fail`, which G2
   discriminates directly in `head_redex_det`.  Every prim bullet inspects
   the four list shapes nil, [v], [v1; v2], (v1 :: v2 :: _ :: _); every arm
   reads at most two values, so the long shape always collapses to the
   `PStuck` default.  Arms that peek a value constructor need that value
   destructed before `cbn [prim_total]` can finish the reduction; `Z.eqb`
   and `Z.ltb` guards are opened with `remember ... in`. *)

Lemma bans_okV_VTup_all : forall vs,
  (forall v, In v vs -> bans_okV v = true) -> bans_okV (VTup vs) = true.
Proof.
  intros vs H. change (forallb bans_okV vs = true). apply In_forallb; exact H.
Qed.

Lemma blocks_closed_okV_VTup_all : forall vs,
  (forall v, In v vs -> blocks_closed_okV v = true) -> blocks_closed_okV (VTup vs) = true.
Proof.
  intros vs H. change (forallb blocks_closed_okV vs = true). apply In_forallb; exact H.
Qed.

Ltac prim_case H w :=
  cbn [prim_total] in H; try discriminate H;
  inversion H; subst w; cbn [bans_okV blocks_closed_okV]; split; try reflexivity.

Lemma prim_result_okV : forall p vs w,
  prim_total p vs = PRes w ->
  (forall v, In v vs -> bans_okV v = true) ->
  (forall v, In v vs -> blocks_closed_okV v = true) ->
  bans_okV w = true /\ blocks_closed_okV w = true.
Proof.
  intros p vs w H Hb Hc.
  destruct p.
  (* PAdd *)
  - destruct vs as [| v1 [| v2 [| v3 rest]]].
    + cbn [prim_total] in H; discriminate H.
    + destruct v1; cbn [prim_total] in H; discriminate H.
    + destruct v1 as [| | | z1 | | | | |]; destruct v2 as [| | | z2 | | | | |];
      prim_case H w.
    + destruct v1; destruct v2; cbn [prim_total] in H; discriminate H.
  (* PSub *)
  - destruct vs as [| v1 [| v2 [| v3 rest]]].
    + cbn [prim_total] in H; discriminate H.
    + destruct v1; cbn [prim_total] in H; discriminate H.
    + destruct v1 as [| | | z1 | | | | |]; destruct v2 as [| | | z2 | | | | |];
      prim_case H w.
    + destruct v1; destruct v2; cbn [prim_total] in H; discriminate H.
  (* PMul *)
  - destruct vs as [| v1 [| v2 [| v3 rest]]].
    + cbn [prim_total] in H; discriminate H.
    + destruct v1; cbn [prim_total] in H; discriminate H.
    + destruct v1 as [| | | z1 | | | | |]; destruct v2 as [| | | z2 | | | | |];
      prim_case H w.
    + destruct v1; destruct v2; cbn [prim_total] in H; discriminate H.
  (* PDiv: the only guard-carrying arithmetic arm *)
  - destruct vs as [| v1 [| v2 [| v3 rest]]].
    + cbn [prim_total] in H; discriminate H.
    + destruct v1; cbn [prim_total] in H; discriminate H.
    + destruct v1 as [| | | z1 | | | | |]; destruct v2 as [| | | z2 | | | | |];
      cbn [prim_total] in H; try discriminate H;
      remember (Z.eqb z2 0) as Q eqn:HQ in H; destruct Q; cbn in H;
      try discriminate H; prim_case H w.
    + destruct v1; destruct v2; cbn [prim_total] in H; discriminate H.
  (* PNeg *)
  - destruct vs as [| v1 [| v2 [| v3 rest]]].
    + cbn [prim_total] in H; discriminate H.
    + destruct v1 as [| | | z | | | | |]; prim_case H w.
    + destruct v1; cbn [prim_total] in H; discriminate H.
    + destruct v1; destruct v2; cbn [prim_total] in H; discriminate H.
  (* PPls *)
  - destruct vs as [| v1 [| v2 [| v3 rest]]].
    + cbn [prim_total] in H; discriminate H.
    + destruct v1 as [| | | z | | | | |]; cbn [prim_total] in H; try discriminate H;
      prim_case H w.
    + destruct v1; cbn [prim_total] in H; discriminate H.
    + destruct v1; destruct v2; cbn [prim_total] in H; discriminate H.
  (* PGt *)
  - destruct vs as [| v1 [| v2 [| v3 rest]]].
    + cbn [prim_total] in H; discriminate H.
    + destruct v1; cbn [prim_total] in H; discriminate H.
    + destruct v1 as [| | | z1 | | | | |]; destruct v2 as [| | | z2 | | | | |];
      cbn [prim_total] in H; try discriminate H;
      remember (Z.ltb z2 z1) as Q eqn:HQ in H; destruct Q; cbn in H;
      try discriminate H; prim_case H w.
    + destruct v1; destruct v2; cbn [prim_total] in H; discriminate H.
  (* PLt *)
  - destruct vs as [| v1 [| v2 [| v3 rest]]].
    + cbn [prim_total] in H; discriminate H.
    + destruct v1; cbn [prim_total] in H; discriminate H.
    + destruct v1 as [| | | z1 | | | | |]; destruct v2 as [| | | z2 | | | | |];
      cbn [prim_total] in H; try discriminate H;
      remember (Z.ltb z1 z2) as Q eqn:HQ in H; destruct Q; cbn in H;
      try discriminate H; prim_case H w.
    + destruct v1; destruct v2; cbn [prim_total] in H; discriminate H.
  (* PGEq *)
  - destruct vs as [| v1 [| v2 [| v3 rest]]].
    + cbn [prim_total] in H; discriminate H.
    + destruct v1; cbn [prim_total] in H; discriminate H.
    + destruct v1 as [| | | z1 | | | | |]; destruct v2 as [| | | z2 | | | | |];
      cbn [prim_total] in H; try discriminate H;
      remember (Z.ltb z2 z1 || Z.eqb z1 z2) as Q eqn:HQ in H; destruct Q; cbn in H;
      try discriminate H; prim_case H w.
    + destruct v1; destruct v2; cbn [prim_total] in H; discriminate H.
  (* PLEq *)
  - destruct vs as [| v1 [| v2 [| v3 rest]]].
    + cbn [prim_total] in H; discriminate H.
    + destruct v1; cbn [prim_total] in H; discriminate H.
    + destruct v1 as [| | | z1 | | | | |]; destruct v2 as [| | | z2 | | | | |];
      cbn [prim_total] in H; try discriminate H;
      remember (Z.ltb z1 z2 || Z.eqb z1 z2) as Q eqn:HQ in H; destruct Q; cbn in H;
      try discriminate H; prim_case H w.
    + destruct v1; destruct v2; cbn [prim_total] in H; discriminate H.
  (* PNEq *)
  - destruct vs as [| v1 [| v2 [| v3 rest]]].
    + cbn [prim_total] in H; discriminate H.
    + destruct v1; cbn [prim_total] in H; discriminate H.
    + destruct v1 as [| | | z1 | | | | |]; destruct v2 as [| | | z2 | | | | |];
      cbn [prim_total] in H; try discriminate H;
      remember (Z.eqb z1 z2) as Q eqn:HQ in H; destruct Q; cbn in H;
      try discriminate H; prim_case H w.
    + destruct v1; destruct v2; cbn [prim_total] in H; discriminate H.
  (* PIsInt *)
  - destruct vs as [| v1 [| v2 [| v3 rest]]].
    + cbn [prim_total] in H; discriminate H.
    + destruct v1 as [| | | z | | | | |]; cbn [prim_total] in H; try discriminate H;
      prim_case H w.
    + destruct v1; cbn [prim_total] in H; discriminate H.
    + destruct v1; destruct v2; cbn [prim_total] in H; discriminate H.
  (* PIsBool *)
  - destruct vs as [| v1 [| v2 [| v3 rest]]].
    + cbn [prim_total] in H; discriminate H.
    + destruct v1; cbn [prim_total] in H; try discriminate H; prim_case H w.
    + destruct v1; cbn [prim_total] in H; discriminate H.
    + destruct v1; destruct v2; cbn [prim_total] in H; discriminate H.
  (* PIsUnit *)
  - destruct vs as [| v1 [| v2 [| v3 rest]]].
    + cbn [prim_total] in H; discriminate H.
    + destruct v1; cbn [prim_total] in H; try discriminate H; prim_case H w.
    + destruct v1; cbn [prim_total] in H; discriminate H.
    + destruct v1; destruct v2; cbn [prim_total] in H; discriminate H.
  (* PCons: result ⟨v1 . ws⟩, entries read through the operand pair *)
  - destruct vs as [| v1 [| v2 [| v3 rest]]].
    + cbn [prim_total] in H; discriminate H.
    + cbn [prim_total] in H; discriminate H.
    + destruct v2 as [| | | | | vs0 | | |]; cbn [prim_total] in H; try discriminate H;
      inversion H; subst w; split.
      * apply bans_okV_VTup_all; intros x Hx; cbn [In] in Hx; destruct Hx as [Ex | Hm];
        [ subst x; apply Hb; cbn [In]; left; reflexivity
        | assert (Htw : bans_okV (VTup vs0) = true)
            by (apply Hb; cbn [In]; right; cbn [In]; left; reflexivity);
          cbn [bans_okV] in Htw;
          apply (forallb_In Val bans_okV vs0 Htw); exact Hm ].
      * apply blocks_closed_okV_VTup_all; intros x Hx; cbn [In] in Hx;
        destruct Hx as [Ex | Hm];
        [ subst x; apply Hc; cbn [In]; left; reflexivity
        | assert (Htw : blocks_closed_okV (VTup vs0) = true)
            by (apply Hc; cbn [In]; right; cbn [In]; left; reflexivity);
          cbn [blocks_closed_okV] in Htw;
          apply (forallb_In Val blocks_closed_okV vs0 Htw); exact Hm ].
    + destruct v2; cbn [prim_total] in H; discriminate H.
  (* PCons2: result ⟨v1, v2⟩ - the operand list itself *)
  - destruct vs as [| v1 [| v2 [| v3 rest]]].
    + cbn [prim_total] in H; discriminate H.
    + cbn [prim_total] in H; discriminate H.
    + cbn [prim_total] in H; inversion H; subst w; split;
      [ apply bans_okV_VTup_all; intros x Hx; apply Hb; exact Hx
      | apply blocks_closed_okV_VTup_all; intros x Hx; apply Hc; exact Hx ].
    + destruct v1; destruct v2; cbn [prim_total] in H; discriminate H.
  (* PDotDot: result map VInt over the range - all entries are literals *)
  - destruct vs as [| v1 [| v2 [| v3 rest]]].
    + cbn [prim_total] in H; discriminate H.
    + destruct v1; cbn [prim_total] in H; discriminate H.
    + destruct v1 as [| | | z1 | | | | |]; destruct v2 as [| | | z2 | | | | |];
      cbn [prim_total] in H; try discriminate H; inversion H; subst w; split;
      [ apply bans_okV_VTup_all; intros x Hx; apply in_map_iff in Hx; destruct Hx as [z [Ez _]]; subst x; reflexivity
      | apply blocks_closed_okV_VTup_all; intros x Hx; apply in_map_iff in Hx; destruct Hx as [z [Ez _]]; subst x; reflexivity ].
    + destruct v1; destruct v2; cbn [prim_total] in H; discriminate H.
  (* PArrLen: result is the length, an int literal *)
  - destruct vs as [| v1 [| v2 [| v3 rest]]].
    + cbn [prim_total] in H; discriminate H.
    + destruct v1; cbn [prim_total] in H; try discriminate H; prim_case H w.
    + destruct v1; cbn [prim_total] in H; discriminate H.
    + destruct v1; destruct v2; cbn [prim_total] in H; discriminate H.
Qed.

(* =====================================================================
   Chunk C3a: the Fig. 8 Subst row under the guards, and the guard-preserved
   body walk.

   On a det_struct-clean term the only live Fig. 8 arm is Subst.  A promote
   row needs a declared-only slot or a VVar side in a unification pair; G4
   (`eq_pair_ok`) pins every guard-clean Unify node to two literal Ret sides,
   so a promote pattern can only meet a term whose pair guard already failed.
   `walk_ret_subst` / `walk_app_subst` read everything a firing Subst implies;
   `subst_ok_app` closes the one square where Subst rewrites a bare
   `Ret (VVar i)` operand of a canonical application (the PNeg bare-operand
   branch of G5); `body_walk_det` threads the guard bundle through the walk's
   context grammars. *)

(* ---------- closed slots read as int-or-var values ---------- *)

Lemma slots_closed_valued : forall sl p v,
  slots_closed_ok sl = true -> slot_value_at sl p = Some v -> is_int_or_var v = true.
Proof.
  induction sl as [| [t ov] rest IH]; intros p v Hc Hv.
  - destruct p; cbn [slot_value_at slot_at nth_error] in Hv; discriminate Hv.
  - cbn [slot_value_at slot_at nth_error] in Hv. destruct p as [| p'].
    + cbn in Hv. destruct ov as [w |].
      * injection Hv as Ew. subst v.
        destruct w; cbn [slots_closed_ok is_int_or_var] in Hc |- *;
        try discriminate Hc; reflexivity.
      * discriminate Hv.
    + apply (IH p' v (slots_closed_tail t ov rest Hc) Hv).
Qed.

(* ---------- the substituted value keeps the guard-clean int-or-var class ---------- *)

Lemma shift_guards : forall n p v,
  is_int_or_var v = true ->
  bans_okV (slotValueFromBody n p v) = true
  /\ blocks_closed_okV (slotValueFromBody n p v) = true.
Proof.
  intros n p v Hint.
  assert (Hs : is_int_or_var (slotValueFromBody n p v) = true).
  { unfold slotValueFromBody. apply slotShift_int_or_var. exact Hint. }
  apply is_int_or_var_okV; exact Hs.
Qed.

(* ---------- what a firing Subst implies (subst_here, Eval.v) ---------- *)

Lemma walk_ret_subst : forall (n : nat) (sl0 : list (Ty * option Val)) i r sl body',
  slots_closed_ok sl0 = true ->
  body_walk n sl0 (Ret (VVar i)) = Some (r, sl, body') ->
  sl = sl0 /\ exists x, body' = Ret x
    /\ bans_okV x = true /\ blocks_closed_okV x = true /\ is_int_or_var x = true.
Proof.
  intros n sl0 i r sl body' Hc Hw.
  cbn [body_walk promote_here subst_here] in Hw.
  destruct (Nat.ltb i n) eqn:HQ; [cbn in HQ | cbn in Hw; discriminate Hw].
  remember (slot_value_at sl0 (slot_of_body_idx n i)) as O eqn:EO.
  destruct O as [v |]; cbn in Hw; try discriminate Hw.
  assert (HintV : is_int_or_var v = true).
  { apply (slots_closed_valued sl0 (slot_of_body_idx n i) v Hc). symmetry; exact EO. }
  assert (Hint : is_int_or_var (slotValueFromBody n (slot_of_body_idx n i) v) = true).
  { unfold slotValueFromBody. apply slotShift_int_or_var. exact HintV. }
  destruct (shift_guards n (slot_of_body_idx n i) v HintV) as [Hg1 Hg2].
  inversion Hw; subst.
  split; [reflexivity |].
  exists (slotValueFromBody n (slot_of_body_idx n i) v).
  split; [reflexivity |].
  split; [exact Hg1 |].
  split; [exact Hg2 | exact Hint].
Qed.

Lemma walk_app_subst : forall (n : nat) (sl0 : list (Ty * option Val)) i p r sl body',
  slots_closed_ok sl0 = true ->
  body_walk n sl0 (App (Ret (VPrim p)) (Ret (VVar i))) = Some (r, sl, body') ->
  sl = sl0 /\ exists x, body' = App (Ret (VPrim p)) (Ret x)
    /\ bans_okV x = true /\ blocks_closed_okV x = true /\ is_int_or_var x = true.
Proof.
  intros n sl0 i p r sl body' Hc Hw.
  cbn [body_walk promote_here subst_here] in Hw.
  destruct (Nat.ltb i n) eqn:HQ; [cbn in HQ | cbn in Hw; discriminate Hw].
  remember (slot_value_at sl0 (slot_of_body_idx n i)) as O eqn:EO.
  destruct O as [v |]; cbn in Hw; try discriminate Hw.
  assert (HintV : is_int_or_var v = true).
  { apply (slots_closed_valued sl0 (slot_of_body_idx n i) v Hc). symmetry; exact EO. }
  assert (Hint : is_int_or_var (slotValueFromBody n (slot_of_body_idx n i) v) = true).
  { unfold slotValueFromBody. apply slotShift_int_or_var. exact HintV. }
  destruct (shift_guards n (slot_of_body_idx n i) v HintV) as [Hg1 Hg2].
  inversion Hw; subst.
  split; [reflexivity |].
  exists (slotValueFromBody n (slot_of_body_idx n i) v).
  split; [reflexivity |].
  split; [exact Hg1 |].
  split; [exact Hg2 | exact Hint].
Qed.

(* G5 (bare-operand branch) is stable at the substituted operand: a guard-clean
   `App (Ret (VPrim p)) (Ret (VVar i))` is canonical only via PNeg (for every
   other row prim_total says PStuck or PFail at a one-element VVar list, so the
   all-int branch is false and prim_bare_ok is false), and PNeg stays canonical
   at any int-or-var replacement value. *)
Lemma subst_ok_app : forall p i w,
  app_node_ok (Ret (VPrim p)) (Ret (VVar i)) = true ->
  is_int_or_var w = true ->
  app_node_ok (Ret (VPrim p)) (Ret w) = true.
Proof.
  intros p i w Hn Hint.
  destruct p;
    cbn [prim_bare_ok is_int_or_var app_node_ok prim_operand_vals all_int
         prim_total_res prim_total] in Hn; try discriminate Hn.
  cbn [app_node_ok prim_operand_vals].
  remember (all_int (w :: nil) && prim_total_res PNeg (w :: nil)) as Q eqn:HQ.
  destruct Q; cbn in HQ; [reflexivity | cbn [prim_bare_ok]; exact Hint].
Qed.

(* ---------- guard inversions used by the walk and by norm ---------- *)

Lemma blocks_closed_okE_Seq_g : forall e1 e2,
  blocks_closed_okE (Seq e1 e2) = true ->
  blocks_closed_okE e1 = true /\ blocks_closed_okE e2 = true.
Proof. intros e1 e2 H. cbn [blocks_closed_okE] in H. apply andb_and in H. exact H. Qed.

Lemma eq_pair_ok_Unify_g : forall e1 e2,
  unify_okE (Unify e1 e2) = true -> eq_pair_ok e1 e2 = true.
Proof. exact unify_okE_pair. Qed.

Lemma blocks_closed_okE_Block_g : forall sl body,
  blocks_closed_okE (Block sl body) = true ->
  slots_closed_ok sl = true /\ blocks_closed_okE body = true.
Proof. intros sl body H. cbn [blocks_closed_okE] in H. apply andb_and in H. exact H. Qed.

Lemma bans_okE_TupE_g : forall es,
  bans_okE (TupE es) = true -> forall e, In e es -> bans_okE e = true.
Proof.
  intros es H e He. cbn [bans_okE] in H.
  apply (forallb_In Expr bans_okE es); [exact H | exact He].
Qed.

Lemma blocks_closed_okE_TupE_g : forall es,
  blocks_closed_okE (TupE es) = true -> forall e, In e es -> blocks_closed_okE e = true.
Proof.
  intros es H e He. cbn [blocks_closed_okE] in H.
  apply (forallb_In Expr blocks_closed_okE es); [exact H | exact He].
Qed.

Lemma unify_okE_TupE_g : forall es,
  unify_okE (TupE es) = true -> forall e, In e es -> unify_okE e = true.
Proof.
  intros es H e He. cbn [unify_okE] in H.
  apply (forallb_In Expr unify_okE es); [exact H | exact He].
Qed.

Lemma apps_okE_TupE_g : forall es,
  apps_okE (TupE es) = true -> forall e, In e es -> apps_okE e = true.
Proof.
  intros es H e He. cbn [apps_okE] in H.
  apply (forallb_In Expr apps_okE es); [exact H | exact He].
Qed.

Lemma tup_rets_okE_TupE_g : forall es,
  tup_rets_okE (TupE es) = true -> tup_node_ok es = true
  /\ forall e, In e es -> tup_rets_okE e = true.
Proof.
  intros es H. cbn [tup_rets_okE] in H. apply andb_and in H. destruct H as [Hn Hf].
  split; [exact Hn |].
  intros e He. apply (forallb_In Expr tup_rets_okE es); [exact Hf | exact He].
Qed.

(* ---------- the guard-preserved walk ----------
   `no_hole` closes a node the walk cannot descend: with the arms' helper
   functions exposed, every branch of the walk reduces to None there. *)

Ltac no_hole Hw := cbn [body_walk promote_here subst_here] in Hw; discriminate Hw.
Ltac no_g5_head Happs := cbn [app_node_ok] in Happs; discriminate Happs.
Ltac no_g5_operand Happs := cbn [app_node_ok prim_operand_vals] in Happs; discriminate Happs.

(* The applications are explicit on every binder: a bare `apply subst_ok_app`
   leaves its evars buried inside the unfolded `app_node_ok` match, where
   unification cannot reach them (probe p184). *)

(* Unify side close: inside ONE literal-u1v branch, concretize the second
   side and read the walk. A flat `destruct; [list]` or `first` after a
   multi-goal destruct is unsafe: destruct and first act on the first goal
   only (probes p192/p194), so the close lives in a focused single-goal item. *)
Ltac unify_lit2_close Hw Lu2 u2v :=
  cbn [body_walk promote_here subst_here] in Hw;
  destruct u2v as [ | | | u2z | u2p | u2t | u2ty u2e | u2d | u2i];
  [ cbn [body_walk promote_here subst_here] in Hw; discriminate Hw
  | cbn [body_walk promote_here subst_here] in Hw; discriminate Hw
  | cbn [body_walk promote_here subst_here] in Hw; discriminate Hw
  | cbn [body_walk promote_here subst_here] in Hw; discriminate Hw
  | cbn [is_lit_val] in Lu2; discriminate Lu2
  | cbn [is_lit_val] in Lu2; discriminate Lu2
  | cbn [is_lit_val] in Lu2; discriminate Lu2
  | cbn [is_lit_val] in Lu2; discriminate Lu2
  | cbn [is_lit_val] in Lu2; discriminate Lu2 ].

Ltac finish_ret_subst n sl0 i r sl body' Hc Hw :=
  destruct (walk_ret_subst n sl0 i r sl body' Hc Hw) as [Es [x [Ee [Hg1 [Hg2 Hx]]]]];
  split; [ exact Es | rewrite Ee; apply (det_struct_ret_okV x); [ exact Hg1 | exact Hg2 ] ].

Ltac finish_app_subst n sl0 i p r sl body' Hc Hw Happs Hf :=
  destruct (walk_app_subst n sl0 i p r sl body' Hc Hw) as [Es [x [Ee [Hg1 [Hg2 Hx]]]]];
  split; [ exact Es
         | rewrite Ee; apply (det_struct_mk_App (Ret (VPrim p)) (Ret x));
           [ apply (subst_ok_app p i x); [ exact Happs | exact Hx ]
           | exact Hf
           | apply (det_struct_ret_okV x); [ exact Hg1 | exact Hg2 ] ] ].

Lemma body_walk_det : forall (n : nat) (sl0 : list (Ty * option Val)) (body : Expr),
  det_struct body = true -> slots_closed_ok sl0 = true ->
  forall (r : RuleID) (sl : list (Ty * option Val)) (body' : Expr),
    body_walk n sl0 body = Some (r, sl, body') ->
    sl = sl0 /\ det_struct body' = true.
Proof.
  intros n sl0 body Hd Hc r sl body' Hw.
  revert Hd r sl body' Hw.
  induction body as [v |  | f IHf a IHa | es | e1 IH1 e2 IH2 | u1 IHu1 u2 IHu2
                    | c1 IHc1 c2 IHc2 |  | sl2 body2 IHb2 | ic b2 IHb3 r2];
    intros Hd r sl body' Hw.
  - (* Ret: the walk fires only at Subst, and only at a bare slot variable *)
    destruct v as [ | | | zv | pv | vs | tv ev | dv | i];
      [ no_hole Hw | no_hole Hw | no_hole Hw | no_hole Hw | no_hole Hw
      | no_hole Hw | no_hole Hw | no_hole Hw
      | finish_ret_subst n sl0 i r sl body' Hc Hw ].
  - (* Glob: the walk has no hole through it *)
    no_hole Hw.
  - (* App: G5 pins the head to a canonical `Ret (VPrim p)`, and the walk's
       left descent there is stuck (no Subst under a VPrim head).  The only
       live square is the operand's own Subst firing, closed by subst_ok_app *)
    destruct (det_struct_App_inv f a Hd) as [Hf _].
    destruct (det_struct_components (App f a) Hd) as [_ [_ [_ [Happs _]]]].
    apply apps_okE_node in Happs.                    (* Happs : app_node_ok f a *)
    destruct f as [vf |  | f1f f2f | esf | s1f s2f | u1f u2f | c1f c2f |  | slf bd1f | icf b1f r1f];
      [ destruct vf as [ | | | zv | p | vs2 | tv2 ev2 | dv2 | i2];
        [ no_g5_head Happs | no_g5_head Happs | no_g5_head Happs | no_g5_head Happs
        | destruct a as [va |  | a1a a2a | esa | s1a s2a | u1a u2a | c1a c2a |  | sla bda | ica bda2 rca];
          [ destruct va as [ | | | vaz | vap | vat | vaty vate | vad | i3];
            [ no_hole Hw | no_hole Hw | no_hole Hw | no_hole Hw | no_hole Hw
            | no_hole Hw | no_hole Hw | no_hole Hw
            | finish_app_subst n sl0 i3 p r sl body' Hc Hw Happs Hf ]
          | no_g5_operand Happs | no_g5_operand Happs | no_hole Hw | no_g5_operand Happs
          | no_g5_operand Happs | no_g5_operand Happs | no_g5_operand Happs
          | no_g5_operand Happs | no_g5_operand Happs ]
        | no_g5_head Happs | no_g5_head Happs | no_g5_head Happs | no_g5_head Happs ]
      | no_g5_head Happs | no_g5_head Happs | no_g5_head Happs | no_g5_head Happs
      | no_g5_head Happs | no_g5_head Happs | no_g5_head Happs | no_g5_head Happs
      | no_g5_head Happs ].
  - (* TupE: no hole through a tuple *)
    no_hole Hw.
  - (* Seq: descent through either side reconstructs *)
    cbn [body_walk promote_here subst_here] in Hw.
    destruct (det_struct_Seq_inv e1 e2 Hd) as [H1 H2].
    remember (body_walk n sl0 e1) as W1 eqn:EW1. symmetry in EW1.
    destruct W1 as [[[r1 sl1] e1'] |].
    + destruct (IH1 H1 r1 sl1 e1' eq_refl) as [Es G1].
      cbn in Hw. inversion Hw; subst.
      split; [first [exact Es | assumption | reflexivity] | apply det_struct_mk_Seq; [exact G1 | exact H2]].
    + cbn in Hw.
      remember (body_walk n sl0 e2) as W2 eqn:EW2. symmetry in EW2.
      destruct W2 as [[[r2 sl2] e2'] |]; cbn in Hw; try discriminate Hw.
      destruct (IH2 H2 r2 sl2 e2' eq_refl) as [Es G2].
      inversion Hw; subst.
      split; [first [exact Es | assumption | reflexivity] | apply det_struct_mk_Seq; [exact H1 | exact G2]].
  - (* Unify: G4 pins the pair to two literal Ret sides; no promote pattern
       matches a literal pair, no Subst fires at a literal Ret, and the
       descent through the pinned sides then reaches no redex *)
    destruct (det_struct_components (Unify u1 u2) Hd) as [_ [_ [Hu _]]].
    apply eq_pair_ok_Unify_g in Hu.
    apply (eq_pair_ok_shape u1 u2) in Hu.
    destruct Hu as [u1v [u2v [Eu1 [Eu2 [Lu1 [Lu2 _]]]]]].
    subst u1. subst u2.
    cbn [body_walk promote_here subst_here] in Hw.
    destruct u1v as [ | | | u1z | u1p | u1t | u1ty u1e | u1d | u1i];
      [ unify_lit2_close Hw Lu2 u2v
      | unify_lit2_close Hw Lu2 u2v
      | unify_lit2_close Hw Lu2 u2v
      | unify_lit2_close Hw Lu2 u2v
      | cbn [is_lit_val] in Lu1; discriminate Lu1
      | cbn [is_lit_val] in Lu1; discriminate Lu1
      | cbn [is_lit_val] in Lu1; discriminate Lu1
      | cbn [is_lit_val] in Lu1; discriminate Lu1
      | cbn [is_lit_val] in Lu1; discriminate Lu1 ].
  - (* Choice: banned node, so Hd is false before the walk *)
    no_hole Hw.
  - (* Fail: likewise banned *)
    no_hole Hw.
  - (* Block: body_walk looks through no block boundary *)
    no_hole Hw.
  - (* Iter: no hole *)
    no_hole Hw.
Qed.

(* =====================================================================
   Chunk C3b: the head-redex table under the guards, fuel normalization,
   and the singleton candidate bag.

   Which head_redex arms can still fire at a det-clean term:
     R_Seq / R_Norm5 at a Seq root (both read their bundle through the
     Seq inversion); R_EqK1 at a G4-pinned literal pair (R_EqK2 needs
     lit_eqb false, which G4 forbids); R_Prim at a G5-pinned canonical
     application (every arm G5 admits is a PRes or PStuck arm of the
     Syntax.v table - prim_args_ok_not_pfail); the Fig. 8 Subst walk
     inside a Block root (body_walk_det).  Everything else is pinned out:
     the Norm1-4 rows need a Seq/Unify side under a G4 node, the beta
     arms need a VLam/VTup head under a G5 node, the EqTup/EqFail arms
     need a non-literal side under G4, and Choice/Fail/Glob/Iter roots
     have det_struct false outright. *)

(* ---------- G5 admits no PFail row ---------- *)

(* prim_args_ok's table rows are exactly the value-insensitive PRes/PStuck
   rows of Syntax.v prim_total (Checks.v, G5 section).  A PFail verdict
   therefore needs either an arity prim_args_ok rejects (the comparisons,
   type tests, PPls, PDiv are absent on purpose) or an all-int list the
   `all_int && prim_total` path already demands be PRes.  The flow below
   closes every (p, list-shape) combination: shapes whose arm peeks a
   value constructor get the operands destructed, and prim_total then
   reduces to a constructor other than PFail. *)
Lemma prim_args_ok_not_pfail : forall p vs,
  prim_args_ok p vs = true -> prim_total p vs <> PFail.
Proof.
  intros p vs Hargs Hfail.
  destruct p; cbn [prim_args_ok] in Hargs; try discriminate Hargs;
  destruct vs as [| v1 [| v2 [| v3 rest]]];
  cbn [prim_args_ok prim_total] in Hargs, Hfail;
  try discriminate Hargs; try discriminate Hfail;
  destruct v1; cbn [prim_args_ok prim_total] in Hargs, Hfail;
  try discriminate Hargs; try discriminate Hfail;
  destruct v2; cbn [prim_total] in Hfail; discriminate Hfail.
Qed.

(* ---------- normalization identity at pinned nodes ---------- *)

(* A TupE whose entries are all Ret (G6's tup_node_ok) normalizes entrywise
   to itself (C1's map_norm_ret). *)
Lemma map_norm_rets : forall (es : list Expr) (vs : list Val) (fuel : nat),
  rets_of es = Some vs -> map (norm fuel) es = es.
Proof.
  intros es vs fuel H.
  rewrite (rets_of_map_rets es vs H).
  rewrite map_norm_ret. reflexivity.
Qed.

(* G3's int-or-var slots are valued in cand_bag's sense.  (C3a's
   slots_closed_valued names a different slot fact; this one is about
   Eval.v's all_slots_valued.) *)
Lemma slots_closed_all_valued : forall sl,
  slots_closed_ok sl = true -> all_slots_valued sl = true.
Proof.
  induction sl as [| [t ov] rest IH]; intros H.
  - reflexivity.
  - destruct ov as [v |];
    [ cbn [slots_closed_ok all_slots_valued] in H;
      destruct v; cbn [slots_closed_ok all_slots_valued] in H;
        try discriminate H; apply IH; exact H
    | cbn [slots_closed_ok all_slots_valued] in H; discriminate H ].
Qed.

(* ---------- the head table ---------- *)

(* Coq 9 intro patterns destructure one conjunction node at a time:
   [a b] splits a /\\ once; deeper positions need nested bracket lists. *)
Ltac bans_not Hd g notlemma :=
  destruct (det_struct_components g Hd) as [Hb _];
  rewrite notlemma in Hb; discriminate Hb.

(* One EqK1 half-step with the G4-pinned pair.  Hh keeps `lit_eqb v1 v2`
   visible (no cbn of lit_eqb here!) so the shape equation Heq rewrites
   the branch choice directly; the second item only guards rows the grid
   hands over with a non-lit L2. *)
Ltac eq_lit_side2 Hh Heq cont :=
  cbn [head_redex is_lit_val] in Hh;
  first [ rewrite Heq in Hh; cbn in Hh
        | cbn [is_lit_val lit_eqb] in Heq; discriminate Heq
        | idtac ];
  inversion Hh; subst cont; apply det_struct_ret_okV;
  cbn [bans_okV blocks_closed_okV]; reflexivity.

(* Membership in a singleton.  (Case analysis on `In v0 [v]` leaves a dead
   tail case with residual `In v0 []`, which its own inversion closes -
   probes p216/p217.)  `P` is a BOOLEAN predicate, spelled out deliberately: inside
   `Checks.v` the same call elaborated only because the ctrees imports there load
   Stdlib `Bool` with its `Coercion Is_true : bool >-> Sortclass`, silently re-reading
   `fun x => bans_okV x` as a `Val -> Prop`.  `ChecksEval.v` imports no ctrees, so that
   coercion is not registered and the honest statement is the bool one - which is also
   exactly the shape `prim_result_okV` consumes. *)
Lemma singleton_guards_ok : forall (v : Val) (P : Val -> bool),
  P v = true -> forall v0, In v0 [v] -> P v0 = true.
Proof.
  intros v P Hv v0 Hin.
  destruct Hin; subst; [exact Hv | inversion H].
Qed.

(* Ret operand of a pinned App head: prim_operand_vals reads it as [va].
   Every hypothesis the body touches is a parameter (probe p209: Ltac
   resolves bare identifiers in an Ltac body against the parameter list
   at DEFINITION time - "Hypothesis zz was not found").

   `destruct (prim_total p [va])` fires dependent elimination ON SPOT
   wherever that term is a match scrutinee (probe p212: Hh becomes
   `Some (R_Prim, Ret w) = Some (r, cont)` with Hp agreeing), so there is
   nothing left to rewrite with Hp - the branches read Hh directly.  The
   PFail branch dies on G5's three paths: (a) prim_total_res is false at
   PFail, (b) TupE-shape contradicts a Ret operand, (c) prim_bare_ok only
   admits PNeg, and prim_total PNeg [va] is PRes at ints (probe
   Syntax.v:346-351) and PStuck otherwise via the catch-all row. *)
Ltac head_app_ret Hh Hba Hlb HG Hop va p vs cont :=
  cbn [head_redex prim_operand_vals] in Hh;
  cbn [prim_operand_vals] in Hop;
  injection Hop as Hvs; subst vs;
  destruct (prim_total p [va]) as [w | | ] eqn:Hp;
  [ inversion Hh; subst cont; cbn [bans_okE blocks_closed_okE] in Hba, Hlb;
    destruct (prim_result_okV p [va] w Hp
      (singleton_guards_ok va (fun x => bans_okV x) Hba)
      (singleton_guards_ok va (fun x => blocks_closed_okV x) Hlb)) as [Hw1 Hw2];
    apply det_struct_ret_okV; [exact Hw1 | exact Hw2]
  | destruct HG as [HA | [HB | HC]];
    [ apply andb_and in HA; destruct HA as [_ Hres];
      unfold prim_total_res in Hres; rewrite Hp in Hres; discriminate Hres
    | destruct HB as [esx [Eshape _]]; discriminate Eshape
    | destruct HC as [v0 [Eshape Hbare]]; inversion Eshape; subst v0;
      destruct p; cbn [prim_bare_ok prim_total] in Hbare, Hp;
        try discriminate Hbare;
      destruct va; cbn [prim_total] in Hp; discriminate Hp ]
  | discriminate Hh ].

(* TupE operand of a pinned App head: rewrite Hop first (cbn [head_redex]
   keeps `prim_operand_vals (TupE es2)` visible for it - probe p213), then
   the constructor match iota-reduces and prim_total p vs stays intact as
   the scrutinee.  The PFail case dies on the pinned paths: (a) as above,
   (b) prim_args_ok_not_pfail, (c) Ret-shape contradicts the TupE operand. *)
Ltac head_app_tup Hh HG Hop Hba Hlb es2 p vs cont :=
  cbn [head_redex] in Hh;
  rewrite Hop in Hh; cbn [head_redex] in Hh;
  destruct (prim_total p vs) as [w | | ] eqn:Hp;
  [ inversion Hh; subst cont;
    destruct (prim_result_okV p vs w Hp
      (operand_vals_bans (TupE es2) vs Hop Hba)
      (operand_vals_closed (TupE es2) vs Hop Hlb)) as [Hw1 Hw2];
    apply det_struct_ret_okV; [exact Hw1 | exact Hw2]
  | destruct HG as [HA | [HB | HC]];
    [ apply andb_and in HA; destruct HA as [_ Hres];
      unfold prim_total_res in Hres; rewrite Hp in Hres; discriminate Hres
    | destruct HB as [es [Eshape [Eret Hargs]]];
      exfalso; apply (prim_args_ok_not_pfail p vs Hargs); exact Hp
    | destruct HC as [v0 [Eshape _]]; discriminate Eshape ]
  | discriminate Hh ].

Lemma head_redex_det : forall (e : Expr) (r : RuleID) (cont : Expr),
  det_struct e = true -> head_redex e = Some (r, cont) -> det_struct cont = true.
Proof.
  intros e r cont Hd Hh.
  destruct e as [v | gid | f a | es | s1 s2 | u1 u2 | c1 c2 | | sl body | ic b ir].

  - (* Ret: no arm has a value root *)
    cbn [head_redex] in Hh; discriminate Hh.

  - (* Glob: G2 rejects it before the table *)
    bans_not Hd (Glob gid) (bans_okE_not_glob gid).

  - (* App: G5 pins the head to a `Ret (VPrim p)` and the operand to a list
       the table reads; beta arms are shadowed by the pinned head, and the
       delta arm is R_Prim with prim_result_okV guarding the contractum *)
    destruct (det_struct_App_inv f a Hd) as [Hf Ha].
    destruct (det_struct_components (App f a) Hd) as [_ [_ [_ [Happs _]]]].
    destruct (det_struct_components a Ha) as [Hba [Hlb _]].
    apply apps_okE_node in Happs.
    apply app_node_ok_shape in Happs.
    destruct Happs as [p [vs [Ef [Hop HG]]]].
    subst f.
    destruct a as [va | g2 | f2 a2 | es2 | s3 s4 | u3 u4 | c3 c4 | | sl2 b2 | ic2 b2 r2];
    [ head_app_ret Hh Hba Hlb HG Hop va p vs cont
    | cbn [prim_operand_vals] in Hop; discriminate Hop
    | cbn [prim_operand_vals] in Hop; discriminate Hop
    | head_app_tup Hh HG Hop Hba Hlb es2 p vs cont
    | cbn [prim_operand_vals] in Hop; discriminate Hop
    | cbn [prim_operand_vals] in Hop; discriminate Hop
    | cbn [prim_operand_vals] in Hop; discriminate Hop
    | cbn [prim_operand_vals] in Hop; discriminate Hop
    | cbn [prim_operand_vals] in Hop; discriminate Hop
    | cbn [prim_operand_vals] in Hop; discriminate Hop ].

  - (* TupE: no arm reads a tuple root *)
    cbn [head_redex] in Hh; discriminate Hh.

  - (* Seq: R_Seq drops the value prefix; R_Norm5 reassociates *)
    destruct (det_struct_Seq_inv s1 s2 Hd) as [Hs1 Hs2].
    cbn [head_redex] in Hh.
    destruct s1 as [v1 | g3 | f3 a3 | es3 | s5 s6 | u5 u6 | c5 c6 | | sl3 b3 | ic3 b3 r3];
      cbn in Hh;
    (* item 5 (s1 a Seq) is the R_Norm5 reassociation; the other non-Ret
       constructors hit the catch-all None *)
    [ inversion Hh; subst cont; exact Hs2
    | discriminate Hh
    | discriminate Hh
    | discriminate Hh
    | inversion Hh; subst cont;
      destruct (det_struct_Seq_inv s5 s6 Hs1) as [H5 H6];
      apply det_struct_mk_Seq; [exact H5 | apply det_struct_mk_Seq; [exact H6 | exact Hs2]]
    | discriminate Hh
    | discriminate Hh
    | discriminate Hh
    | discriminate Hh
    | discriminate Hh ].

  - (* Unify: G4 pins both sides to literal Ret; only EqK1 survives and its
       contractum is the literal value itself *)
    destruct (det_struct_components (Unify u1 u2) Hd) as [_ [_ [Hu _]]].
    apply unify_okE_pair in Hu.
    apply (eq_pair_ok_shape u1 u2) in Hu.
    destruct Hu as [v1 [v2 [Eu1 [Eu2 [L1 [L2 Heq]]]]]].
    subst u1. subst u2.
    cbn [head_redex] in Hh.
    destruct v1 as [ | | | z1 | p1 | ts1 | lv1 le1 | d1 | i1];
      [ destruct v2 as [ | | | z2 | p2 | ts2 | lv2 le2 | d2 | i2];
        [ eq_lit_side2 Hh Heq cont
        | eq_lit_side2 Hh Heq cont
        | eq_lit_side2 Hh Heq cont
        | eq_lit_side2 Hh Heq cont
        | cbn [is_lit_val] in L2; discriminate L2
        | cbn [is_lit_val] in L2; discriminate L2
        | cbn [is_lit_val] in L2; discriminate L2
        | cbn [is_lit_val] in L2; discriminate L2
        | cbn [is_lit_val] in L2; discriminate L2 ]
      | destruct v2 as [ | | | z2 | p2 | ts2 | lv2 le2 | d2 | i2];
        [ eq_lit_side2 Hh Heq cont
        | eq_lit_side2 Hh Heq cont
        | eq_lit_side2 Hh Heq cont
        | eq_lit_side2 Hh Heq cont
        | cbn [is_lit_val] in L2; discriminate L2
        | cbn [is_lit_val] in L2; discriminate L2
        | cbn [is_lit_val] in L2; discriminate L2
        | cbn [is_lit_val] in L2; discriminate L2
        | cbn [is_lit_val] in L2; discriminate L2 ]
      | destruct v2 as [ | | | z2 | p2 | ts2 | lv2 le2 | d2 | i2];
        [ eq_lit_side2 Hh Heq cont
        | eq_lit_side2 Hh Heq cont
        | eq_lit_side2 Hh Heq cont
        | eq_lit_side2 Hh Heq cont
        | cbn [is_lit_val] in L2; discriminate L2
        | cbn [is_lit_val] in L2; discriminate L2
        | cbn [is_lit_val] in L2; discriminate L2
        | cbn [is_lit_val] in L2; discriminate L2
        | cbn [is_lit_val] in L2; discriminate L2 ]
      | destruct v2 as [ | | | z2 | p2 | ts2 | lv2 le2 | d2 | i2];
        [ eq_lit_side2 Hh Heq cont
        | eq_lit_side2 Hh Heq cont
        | eq_lit_side2 Hh Heq cont
        | eq_lit_side2 Hh Heq cont
        | cbn [is_lit_val] in L2; discriminate L2
        | cbn [is_lit_val] in L2; discriminate L2
        | cbn [is_lit_val] in L2; discriminate L2
        | cbn [is_lit_val] in L2; discriminate L2
        | cbn [is_lit_val] in L2; discriminate L2 ]
      | cbn [is_lit_val] in L1; discriminate L1
      | cbn [is_lit_val] in L1; discriminate L1
      | cbn [is_lit_val] in L1; discriminate L1
      | cbn [is_lit_val] in L1; discriminate L1
      | cbn [is_lit_val] in L1; discriminate L1 ].

  - (* Choice: G2 rejects it *)
    bans_not Hd (Choice c1 c2) (bans_okE_not_choice c1 c2).

  - (* Fail: likewise *)
    bans_not Hd Fail bans_okE_not_fail.

  - (* Block: the Fig. 8 walk inside the body (R_Subst; the promote rows
       are dead under slots_closed_ok).  cbn first: the body_walk call is
       the scrutinee of block_redex's own match, so it only becomes
       visible in Hh after the two whitelisted unfoldings. *)
    destruct (det_struct_components (Block sl body) Hd) as [Hb _].
    destruct (det_struct_Block_inv sl body Hd) as [Hbody Hclosed].
    destruct (body_walk (length sl) sl body) as [[[r' sl'] b'] |] eqn:Hw.
    (* cbn refuses to unfold block_redex: its unfolding is stuck on the walk
       call, so cbn treats it as unproductive.  unfold exposes the scrutinee,
       after which Hw rewrites and the match iota-reduces. *)
    + cbn [head_redex] in Hh; unfold block_redex in Hh; rewrite Hw in Hh; cbn in Hh.
      inversion Hh; subst cont;
      destruct (body_walk_det (length sl) sl body Hbody Hclosed r' sl' b' Hw)
        as [Es Hb'].
      subst sl'.
      apply (det_struct_mk_Block sl b');
        [exact (bans_okE_Block_slots sl body Hb) | exact Hclosed | exact Hb'].
    + cbn [head_redex] in Hh; unfold block_redex in Hh; rewrite Hw in Hh; cbn in Hh;
      discriminate Hh.

  - (* Iter: G2 rejects it *)
    bans_not Hd (Iter ic b ir) (bans_okE_not_iter ic b ir).
Qed.

(* ---------- fuel normalization ---------- *)

(* At a stuck root the fuel step reconstructs the node from normalized
   children; every guard the reconstruction re-reads (G4 on a Unify pair,
   G5 on an App pair, G6 on a TupE) is pinned by det_struct to stuck
   syntax, so the children normalize to themselves and the node is
   reassembled from the original hypothesis.

   `destruct (head_redex e)` eliminates its occurrence in the
   reconstruction match on spot (probes p212/p213), so the equations
   `rewrite Hh` below usually have nothing to rewrite - hence the
   first [rewrite Hh | idtac] hedge, which also covers the case where
   Coq generalizes the occurrence instead. *)
Lemma norm_det : forall (fuel : nat) (e : Expr),
  det_struct e = true -> det_struct (norm fuel e) = true.
Proof.
  intro fuel. induction fuel as [| n IH].
  - intros e Hd. cbn [norm]. exact Hd.
  - intros e Hd. cbn [norm].
    destruct (head_redex e) as [[r cont] |] eqn:Hh.
    + first [ rewrite Hh | idtac ]; cbn [norm];
      apply IH; exact (head_redex_det e r cont Hd Hh).
    + first [ rewrite Hh | idtac ].
      destruct e as [v | gid | f a | es | s1 s2 | u1 u2 | c1 c2 | | sl body | ic b ir];
      [ cbn [norm]; exact Hd
      | cbn [norm]; bans_not Hd (Glob gid) (bans_okE_not_glob gid)
      | cbn [norm];
        destruct (det_struct_components (App f a) Hd) as [_ [_ [_ [Happs _]]]];
        apply apps_okE_node in Happs;
        apply app_node_ok_shape in Happs;
        destruct Happs as [p [vs [Ef [Hop _]]]];
        subst f;
        rewrite (norm_ret (VPrim p) n); rewrite (norm_operand_ret a vs n Hop);
        exact Hd
      | cbn [norm];
        destruct (det_struct_components (TupE es) Hd) as [_ [_ [_ [_ Ht]]]];
        cbn [tup_rets_okE] in Ht;
        apply andb_and in Ht; destruct Ht as [Hnode _];
        apply tup_node_ok_rets in Hnode; destruct Hnode as [vs HR];
        rewrite (map_norm_rets es vs n HR); exact Hd
      | cbn [norm];
        destruct (det_struct_Seq_inv s1 s2 Hd) as [H1 H2];
        apply det_struct_mk_Seq; [apply IH; exact H1 | apply IH; exact H2]
      | cbn [norm];
        destruct (det_struct_components (Unify u1 u2) Hd) as [_ [_ [Hu _]]];
        apply unify_okE_pair in Hu;
        apply (eq_pair_ok_shape u1 u2) in Hu;
        destruct Hu as [v1 [v2 [Eu1 [Eu2 _]]]];
        subst u1; subst u2;
        rewrite (norm_ret v1 n); rewrite (norm_ret v2 n);
        exact Hd
      | cbn [norm]; bans_not Hd (Choice c1 c2) (bans_okE_not_choice c1 c2)
      | cbn [norm]; bans_not Hd Fail bans_okE_not_fail
      | cbn [norm];
        destruct (det_struct_components (Block sl body) Hd) as [Hb _];
        destruct (det_struct_Block_inv sl body Hd) as [Hbody Hclosed];
        apply (det_struct_mk_Block sl (norm n body));
          [apply (bans_okE_Block_slots sl body); exact Hb
          |exact Hclosed |apply IH; exact Hbody]
      | cbn [norm]; bans_not Hd (Iter ic b ir) (bans_okE_not_iter ic b ir) ].
Qed.

(* ---------- the candidate bag ---------- *)

(* Choice/Glob/Fail/Iter roots are pinned away by G2 (so the Choice split
   arm and everything exotic are unreachable); a G3-closed block reads
   through its valued slots (Eval.v cand_bag) and the IH collapses the
   mapped singleton. *)
Lemma cand_bag_single : forall (e : Expr),
  det_struct e = true -> cand_bag e = e :: nil.
(* Plain `induction e`: the auto-named IHs keep the proof independent of the
   constructor argument names, which `as [...]` would have to name together
   with the induction hypotheses (probe p251).  The two live roots are read
   straight off the goal. *)
Proof.
  induction e; intros Hd; try reflexivity.
  - (* Choice: G2 rejects the root, so cand_bag's split arm is unreachable *)
    match goal with
    | |- cand_bag (Choice ?a ?b) = _ :: nil =>
        bans_not Hd (Choice a b) (bans_okE_not_choice a b)
    end.
  - (* Block: G3's valued slots make cand_bag read through the body *)
    match goal with
    | H : det_struct (Block ?sl ?body) = true,
      IHb : det_struct ?body = true -> cand_bag ?body = ?body :: nil |- _ =>
      cbn [cand_bag];
      destruct (det_struct_Block_inv sl body H) as [Hbody Hclosed];
      rewrite (slots_closed_all_valued sl Hclosed); cbn [cand_bag];
      rewrite (IHb Hbody); cbn [map]; reflexivity
    end.
Qed.

(* =====================================================================
   T4 soundness, eval leg: a checker-accepted expression normalizes, at
   any fuel, to exactly one candidate. *)

Theorem T4_eval : forall (e : Expr) (fuel : nat),
  det_check e = true -> cand_bag (norm fuel e) = norm fuel e :: nil.
Proof.
  intros e fuel H.
  apply det_check_components in H. destruct H as [_ Hs].
  apply (cand_bag_single (norm fuel e)).
  exact (norm_det fuel e Hs).
Qed.
