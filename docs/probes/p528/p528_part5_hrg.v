From Stdlib Require Import ZArith Lia List.
Require Import Timbda.Syntax Timbda.Checks Timbda.Semantics Timbda.Eval.
Require Import Timbda.Realize Timbda.RealizeBridges Timbda.RealizeCorners.
Import ListNotations.
Local Open Scope Z_scope.

Ltac range_hyp_step :=
  unfold prim_corner;
  cbn [range_ok prim_operand_vals];
  rewrite !rets_of_map_ret;
  cbn [range_ok val_int64_ok andb forallb map];
  unfold prim_node_range_ok, prim_total.

Example hrg_add : forall x y : Z,
  int64_range x = true -> int64_range y = true -> int64_range (x + y) = true ->
  range_ok (prim_corner PAdd [VInt x; VInt y]) = true.
Proof.
  intros x y Hx Hy Hxy. range_hyp_step.
  cbn [andb forallb]. rewrite Hx, Hy, Hxy. cbn. reflexivity.
Qed.

Example hrg_gt : forall x y : Z,
  int64_range x = true -> int64_range y = true -> Z.ltb y x = true ->
  range_ok (prim_corner PGt [VInt x; VInt y]) = true.
Proof.
  intros x y Hx Hy Hg. range_hyp_step.
  rewrite Hg. cbn [andb forallb]. rewrite Hx, Hy. cbn. reflexivity.
Qed.

Example hrg_div : forall x y : Z,
  int64_range x = true -> int64_range y = true -> int64_range (Z.div x y) = true ->
  Z.eqb y 0 = false ->
  range_ok (prim_corner PDiv [VInt x; VInt y]) = true.
Proof.
  intros x y Hx Hy Hq Hz. range_hyp_step.
  rewrite Hz. cbn [andb forallb]. rewrite Hx, Hy, Hq. cbn. reflexivity.
Qed.
