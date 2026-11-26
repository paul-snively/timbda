From Stdlib Require Import ZArith Lia List.
Require Import Timbda.Syntax Timbda.Checks Timbda.Semantics Timbda.Eval.
Require Import Timbda.Realize Timbda.RealizeBridges Timbda.RealizeCorners.
Import ListNotations.
Local Open Scope Z_scope.

Lemma prim_total_res_PGt_true : forall x y : Z,
  Z.ltb y x = true -> prim_total_res PGt [VInt x; VInt y] = true.
Proof.
  intros x y Hg. unfold prim_total_res. cbn [prim_total]. rewrite Hg. reflexivity.
Qed.

Lemma prim_total_res_PDiv_true : forall x y : Z,
  Z.eqb y 0 = false -> prim_total_res PDiv [VInt x; VInt y] = true.
Proof.
  intros x y Hz. unfold prim_total_res. cbn [prim_total]. rewrite Hz. reflexivity.
Qed.

Ltac hds_corner :=
  unfold prim_corner;
  unfold det_struct, apps_okE, tup_rets_okE, app_node_ok, prim_operand_vals, rets_of, map.

Example hds_add : forall x y : Z, det_struct (prim_corner PAdd [VInt x; VInt y]) = true.
Proof.
  intros x y. hds_corner.
  cbn [bans_okE blocks_closed_okE unify_okE apps_okE tup_rets_okE app_node_ok
       all_int Rewriting.is_int_val prim_total_res prim_total andb forallb].
  reflexivity.
Qed.

Example hds_gt : forall x y : Z,
  Z.ltb y x = true -> det_struct (prim_corner PGt [VInt x; VInt y]) = true.
Proof.
  intros x y Hg. hds_corner.
  cbn [bans_okE blocks_closed_okE unify_okE andb forallb all_int Rewriting.is_int_val].
  rewrite (prim_total_res_PGt_true x y Hg).
  cbn [apps_okE tup_rets_okE app_node_ok prim_total_res prim_total andb forallb].
  reflexivity.
Qed.

Example hds_div : forall x y : Z,
  Z.eqb y 0 = false -> det_struct (prim_corner PDiv [VInt x; VInt y]) = true.
Proof.
  intros x y Hz. hds_corner.
  cbn [bans_okE blocks_closed_okE unify_okE andb forallb all_int Rewriting.is_int_val].
  rewrite (prim_total_res_PDiv_true x y Hz).
  cbn [apps_okE tup_rets_okE app_node_ok prim_total_res prim_total andb forallb].
  reflexivity.
Qed.
