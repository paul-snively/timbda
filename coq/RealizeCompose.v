(* RealizeCompose.v - the T6/T4 correspondence composition (decision 10d,
   closed by decision 12): the value maps (prim_match_*: prim_clight equals
   clight_of_val of the kernel result), the guard maps (prim_guard_match_*:
   kernel guard success <-> observed Vint (Int.repr 1)), the landed floor fold
   read through the value map and the emitted constant (`prim_clight_floor_div`,
   `prim_match_PDiv`, `prim_expr_fold_*`), and the composition theorems
   T6_T4_match_* gluing the corner denotation (RealizeCorners) to
   T6_exec_ws's exec-and-pin witness (Realize.v).

   BUILD-UNIT POLICY (measured 2026-11-26): the T6 realization side is a
   fan-in - leaves RealizeBridges / RealizeDiv / RealizeCorners compose in
   RealizeCompose, and Realize.v is the CompCert-side hub the leaves read.
   Each increment lands in its own leaf so a single coqc unit never re-checks
   the accumulated history; the gate's Coq lane runs dune with (jobs 1)
   (coq/dune-workspace).  Rationale (measured at the split as a ~15 GiB coqc
   peak for the pre-split monolith, RE-MEASURED 2026-11-26 after the ≅
   restatement: a clean full-lane dune build sampled at 0.3 s peaks at 655 MiB
   overall - Realize.v 499 MiB, tests/KernelTest.v 655 MiB - and the flake's
   rocq check cone sweep at 515 MiB; the 15 GiB figure was the broken
   Leibniz-`=` corner spellings grinding, not the hub): even the modest lane
   must not run twice at once next to the ~54 GiB model server, and the
   earlier silent dune RC=1 runs with no Coq error were exactly that
   (docs/DESIGN-NOTES.md sec. 4.2, 13.15, 13.16).
   AUDIT.  CompCert-cone-facing: audited by the flake timbda-kernel buildPhase
   cone sweep (rocq check on Timbda.Realize + Timbda.RealizeCompose, which
   transitively cover this file).  No `Print Assumptions` line here -
   forbidden in the whole Realize family: its output would land in build.log
   and break the kernel sweep. *)

From Stdlib Require Import ZArith Lia Ring List.
Require Import compcert.lib.Coqlib compcert.lib.Integers compcert.lib.Zbits compcert.lib.Maps
  compcert.common.Values compcert.common.AST compcert.common.Memory
  compcert.common.Events compcert.common.Globalenvs
  compcert.cfrontend.Ctypes compcert.cfrontend.Cop compcert.cfrontend.Clight
  compcert.cfrontend.ClightBigstep.
(* The corner conjuncts below are ctrees' structural equality `≅` (= `equ eq x
   y`, Denotation.v sec. 4.1 ruling: a cofix-headed denote can never be Leibniz
   equal to a sret - ctrees' own monad laws exist only at `equ`).  Only
   EquNotations is imported: WBisimNotations re-registers `&&&` at level 59 and
   clashes with compcert Coqlib's level-40 `&&&` (measured 2026-11-26). *)
From CTree Require Import CTree Eq.
Import EquNotations.
Import ListNotations.
(* Z scope AFTER the compcert imports (toolchain ruling: opening it before the
   compcert Require block clashes). *)
Local Open Scope Z_scope.
Require Import Timbda.Syntax Timbda.Checks Timbda.Semantics Timbda.Eval.
Require Import Timbda.Lower Timbda.Realize Timbda.RealizeBridges
  Timbda.RealizeDiv Timbda.RealizeCorners.
(* eqmod (the Prop behind Int64.eqm) lives in Zbits' namespace; the library
   exports it, but opening it keeps this file's own unfold honest. *)
Import Zbits.

(* ============================================================================
   INCREMENT C (probes p528, 2026-11-26): the div floor fold (docs/PLAN.md
   decision 12) and the T4/T6 correspondence composition.

   Measured fork (docs/DESIGN-NOTES.md sec. 13.14 - the earlier "Z.div
   truncates like CompCert's int64 division" line was FALSE and is corrected):
   - The kernel's Z.div (Syntax.v prim_total PDiv) is true FLOOR:
     Z.div 7 (-2) = -4 and Z.div (-7) 2 = -4 (floor_literal_* below).
   - CompCert's Int64.divs = Int64.repr (Z.quot (signed .) (signed .)) is
     TRUNCATION: 7 divs (-2) truncates to -3 (divs_floor_gap_* below);
     Int64.mods = repr (Z.rem .), dividend-signed.
   - The dialect divZ (dialect/TimbdaCanonicalization.cpp 176-183, fold site
     :359) is truncation plus a ladder correction (q -= 1 iff r <> 0 and
     sign r <> sign y); the Coq mirror divZ_ladder and divZ_ladder_div pin
     it to Z.div exactly (the five divZ_* rungs are the quadrant proof).
   - Ruling (decision 12): the fork is closed at LOWERING time - Lower.prim_expr's
     PDiv arm constant-folds Econst_long (Int64.repr (Z.div (vint_z a) (vint_z b)))
     and prim_clight mirrors it; no Odiv node is ever emitted, so CompCert's
     truncating runtime division (and its guard ladder) plays no role in T6.
     Out-of-range div results fail range_ok and are excluded from T6's claim;
     Z.div is total on the Coq side (0 at a zero divisor), prim_total's PStuck
     guard keeps the kernel-side meaning.
   Kit rulings re-confirmed against the store (micro runs + p528):
   - lia cannot prove div/quot identities head-on against symbolic operands
     ("Cannot find witness"); route through Z.div_unique (disjunct
     0 <= r < b \/ b < r <= 0) and shield Z.quot/Z.rem atoms with set-in-*.
   - 9.1's Z_lt_dec is a 3-way sumbool (< + = + >); use Z_lt_ge_dec for the
     binary sign split.  destructing a Z directly gives 3 constructors.
   - rewrite with a hypothesis-bearing lemma puts the MAIN goal first in the
     bullet sequence (apply puts it last) - the bridge/guard match lemmas
     below dispatch accordingly.
   - e_fuel of a two-operand prim corner is 6 (Checks.v TupE arm S (S (sumE
     ..))), not 5.  Full `cbn` after a delta-listed cbn finishes nat `+`
     (the Fixpoint is not in the delta list; lia refuses the bare numeral
     equation - "Cannot find witness").
   - cbn of the denotation leaves the monadic beta-redexes (Rocq 9.1 cbn is
     by-name); the `denorm` tactic is cbv over the evaluator constants and
     lives in RealizeCorners.v.
   ============================================================================ *)

(* ---------- value discrimination ---------- *)

Lemma vint_one_ne_zero : Vint (Int.repr 1) <> Vint Int.zero.
Proof.
  (* inversion reaches the IntWordRepr representation, where 1 <> 0 discriminates *)
  intro H. inversion H.
Qed.

(* ---------- arith map: prim_clight == clight_of_val of the kernel result ---------- *)

Lemma prim_match_add : forall x y : Z,
  prim_clight PAdd [VInt x; VInt y] = clight_of_val (VInt (x + y)).
Proof.
  intros x y. unfold prim_clight, clight_of_val. cbn [z64].
  rewrite bridge_add. reflexivity.
Qed.

Lemma prim_match_sub : forall x y : Z,
  prim_clight PSub [VInt x; VInt y] = clight_of_val (VInt (x - y)).
Proof.
  intros x y. unfold prim_clight, clight_of_val. cbn [z64].
  rewrite bridge_sub. reflexivity.
Qed.

Lemma prim_match_mul : forall x y : Z,
  prim_clight PMul [VInt x; VInt y] = clight_of_val (VInt (x * y)).
Proof.
  intros x y. unfold prim_clight, clight_of_val. cbn [z64].
  rewrite bridge_mul. reflexivity.
Qed.

Lemma prim_match_neg : forall x : Z,
  prim_clight PNeg [VInt x] = clight_of_val (VInt (- x)).
Proof.
  intros x. unfold prim_clight, clight_of_val. cbn [z64].
  rewrite bridge_neg. reflexivity.
Qed.

(* ---------- the div fork at prim_clight: old (truncation) vs new (floor fold) ---------- *)

(* The fork, measured at the value map (the pre-fold prim_clight arm was
   `Vlong (Int64.divs ..)`: the truncation side).  Post-fold snapshot: the arm
   is now the floor, exactly the kernel prim_total result (Z.div), mapped to a
   Vlong.  The truncation-vs-floor gap itself stays pinned by the divs_floor_gap
   / floor_literal lemmas above and bridge_divs_quot pins Int64.divs itself. *)
Lemma prim_clight_floor_div : forall x y : Z,
  int64_range x = true -> int64_range y = true ->
  prim_clight PDiv [VInt x; VInt y] = Vlong (Int64.repr (Z.div x y)).
Proof.
  (* NB: the range hypotheses are NOT decoration - the fold reads its operands
     through vint_z (signed . z64), so for an out-of-range operand the folded
     constant is the floor of the WRAPPED pair, not of x and y.  Out-of-range
     operands are exactly what range_ok excludes from T6.
     Kit trap (measured): `cbn [vint_z z64]` unfolds z64 but silently refuses
     vint_z (an applied constant under Z.div); `unfold vint_z` does fire. *)
  intros x y Hx Hy. unfold prim_clight, vint_z, z64.
  rewrite (int64_range_signed x Hx), (int64_range_signed y Hy). reflexivity.
Qed.

(* three-way match, kernel side: prim_total PDiv = PRes (VInt (Z.div .)) directly *)
Lemma prim_match_PDiv : forall x y : Z,
  int64_range x = true -> int64_range y = true ->
  prim_clight PDiv [VInt x; VInt y] = clight_of_val (VInt (Z.div x y)).
Proof.
  intros x y Hx Hy. unfold prim_clight, clight_of_val.
  cbn [z64].
  rewrite (vint_z_VInt x Hx), (vint_z_VInt y Hy). reflexivity.
Qed.

Lemma prim_expr_fold_eval_PDiv : forall (x y : Z) (le : Clight.temp_env),
  int64_range x = true -> int64_range y = true ->
  Clight.eval_expr ge0 Clight.empty_env le Mem.empty
    (Lower.prim_expr PDiv [VInt x; VInt y]) (prim_clight PDiv [VInt x; VInt y]).
Proof.
  intros x y le Hx Hy. unfold Lower.prim_expr, prim_clight.
  rewrite (vint_z_VInt x Hx), (vint_z_VInt y Hy). apply eval_const64.
Qed.

(* guard-free lowering: the folded arm needs no Odiv guard at all *)
Lemma prim_expr_fold_PDiv_literal :
  Lower.prim_expr PDiv [VInt 7; VInt (-2)] = Clight.Econst_long (Int64.repr (-4)) Lower.tint64.
Proof. vm_compute. reflexivity. Qed.

(* ---------- guard map: kernel guard success <-> observed Vint 1 ---------- *)

Lemma prim_guard_match_PGt : forall x y : Z,
  int64_range x = true -> int64_range y = true ->
  (prim_total PGt [VInt x; VInt y] = PRes (VInt x)) <->
  (prim_clight PGt [VInt x; VInt y] = Vint (Int.repr 1)).
Proof.
  intros x y Hx Hy. unfold prim_clight, prim_total. cbn [z64].
  rewrite (bridge_cmp_Cgt x y Hx Hy).
  destruct (Z.ltb y x) eqn:G; cbn [prim_total Val.of_bool Vtrue Vfalse].
  - split; intros H; reflexivity.
  - split.
    + intros Hc. discriminate Hc.
    + intros Heq. exfalso. apply vint_one_ne_zero. symmetry; exact Heq.
Qed.

(* the one-way reading the T4 pin needs: guard SUCCESS observed as Vint 1 *)
Lemma prim_guard_success_PGt : forall x y : Z,
  int64_range x = true -> int64_range y = true -> Z.ltb y x = true ->
  prim_clight PGt [VInt x; VInt y] = Vint (Int.repr 1).
Proof.
  intros x y Hx Hy Hg.
  apply (proj1 (prim_guard_match_PGt x y Hx Hy)).
  unfold prim_total. rewrite Hg. reflexivity.
Qed.

Lemma prim_guard_match_PLt : forall x y : Z,
  int64_range x = true -> int64_range y = true ->
  (prim_total PLt [VInt x; VInt y] = PRes (VInt x)) <->
  (prim_clight PLt [VInt x; VInt y] = Vint (Int.repr 1)).
Proof.
  intros x y Hx Hy. unfold prim_clight, prim_total. cbn [z64].
  rewrite (bridge_cmp_Clt x y Hx Hy).
  destruct (Z.ltb x y) eqn:G; cbn [prim_total Val.of_bool Vtrue Vfalse].
  - split; intros H; reflexivity.
  - split.
    + intros Hc. discriminate Hc.
    + intros Heq. exfalso. apply vint_one_ne_zero. symmetry; exact Heq.
Qed.

Lemma prim_guard_match_PGEq : forall x y : Z,
  int64_range x = true -> int64_range y = true ->
  (prim_total PGEq [VInt x; VInt y] = PRes (VInt x)) <->
  (prim_clight PGEq [VInt x; VInt y] = Vint (Int.repr 1)).
Proof.
  intros x y Hx Hy. unfold prim_clight, prim_total. cbn [z64].
  rewrite (bridge_cmp_Cge x y Hx Hy).
  rewrite <- leb_as_neg_lt.      (* negb (x <? y)  ->  (y <=? x) *)
  rewrite leb_as_or_lt_eq.       (* (y <? x) || (y =? x) *)
  rewrite (Z.eqb_sym y x).       (* (y <? x) || (x =? y) - the kernel spelling *)
  destruct (Z.ltb y x) eqn:G; destruct (Z.eqb x y) eqn:E;
    cbn [prim_total Val.of_bool orb Vtrue Vfalse].
  - split; intros H; reflexivity.
  - split; intros H; reflexivity.
  - split; intros H; reflexivity.
  - split.
    + intros Hc. discriminate Hc.
    + intros Heq. exfalso. apply vint_one_ne_zero. symmetry; exact Heq.
Qed.

Lemma prim_guard_match_PLEq : forall x y : Z,
  int64_range x = true -> int64_range y = true ->
  (prim_total PLEq [VInt x; VInt y] = PRes (VInt x)) <->
  (prim_clight PLEq [VInt x; VInt y] = Vint (Int.repr 1)).
Proof.
  intros x y Hx Hy. unfold prim_clight, prim_total. cbn [z64].
  rewrite (bridge_cmp_Cle x y Hx Hy).
  rewrite <- leb_as_neg_lt.      (* negb (y <? x)  ->  (x <=? y) *)
  rewrite leb_as_or_lt_eq.       (* (x <? y) || (x =? y) - the kernel spelling *)
  destruct (Z.ltb x y) eqn:G; destruct (Z.eqb x y) eqn:E;
    cbn [prim_total Val.of_bool orb Vtrue Vfalse].
  - split; intros H; reflexivity.
  - split; intros H; reflexivity.
  - split; intros H; reflexivity.
  - split.
    + intros Hc. discriminate Hc.
    + intros Heq. exfalso. apply vint_one_ne_zero. symmetry; exact Heq.
Qed.

Lemma prim_guard_match_PNEq : forall x y : Z,
  int64_range x = true -> int64_range y = true ->
  (prim_total PNEq [VInt x; VInt y] = PRes (VInt x)) <->
  (prim_clight PNEq [VInt x; VInt y] = Vint (Int.repr 1)).
Proof.
  intros x y Hx Hy. unfold prim_clight, prim_total. cbn [z64].
  rewrite (bridge_cmp_Cne x y Hx Hy).
  destruct (Z.eqb x y) eqn:E; cbn [prim_total Val.of_bool Vtrue Vfalse].
  - split.
    + intros Hc. discriminate Hc.
    + intros Heq. exfalso. apply vint_one_ne_zero. symmetry; exact Heq.
  - split; intros H; reflexivity.
Qed.

(* ---------- composition (decision 10c/10d): the add corner ---------- *)

Theorem T6_T4_match_add : forall x y : Z,
  int64_range x = true -> int64_range y = true -> int64_range (x + y) = true ->
  (denote (prim_corner PAdd [VInt x; VInt y]) 6%nat ≅ sret (SOk (VInt (x + y)))) /\
  (exists le',
    Clight1.exec_stmt ge0 Clight.empty_env le0 Mem.empty
      (clight_of (Lower.lower (prim_corner PAdd [VInt x; VInt y])))
      Events.E0 le' Mem.empty ClightBigstep.Out_normal
    /\ PTree.get Lower.lower_res le' = Some (Vlong (Int64.repr (x + y)))).
Proof.
  intros x y Hx Hy Hxy.
  assert (Hden : denote (prim_corner PAdd [VInt x; VInt y]) 6%nat
    ≅ sret (SOk (VInt (x + y)))).
  { apply (denote_prim_corner_PAdd x y). }
  assert (Hws : forall d, ws_expr d (prim_corner PAdd [VInt x; VInt y]) = true).
  { intros d. unfold prim_corner. cbn [ws_expr ws_val]. cbn. reflexivity. }
  assert (Hds : det_struct (prim_corner PAdd [VInt x; VInt y]) = true).
  { hds_corner_prologue. hds_corner_finish. }
  assert (Hrg : range_ok (prim_corner PAdd [VInt x; VInt y]) = true).
  { unfold prim_corner. cbn [range_ok prim_operand_vals]. rewrite !rets_of_map_ret.
    cbn [range_ok val_int64_ok andb forallb map].
    unfold prim_node_range_ok, prim_total.
    cbn [andb forallb]. rewrite Hx, Hy, Hxy. cbn. reflexivity. }
  destruct (T6_exec_ws (prim_corner PAdd [VInt x; VInt y]) 0%nat le0 (Hws 0%nat) Hds Hrg)
    as [le' [Hex Hpin]].
  split; [exact Hden |].
  exists le'; split; [exact Hex |].
  rewrite Hpin. cbn [lower_final Lower.prim_head prim_operand_vals prim_corner].
  rewrite rets_of_map_ret.
  cbn [lower_final Lower.prim_head prim_operand_vals prim_corner].
  rewrite prim_match_add. cbn [clight_of_val z64]. reflexivity.
Qed.

(* ---------- composition: the guard corner (PGt, guard success) ---------- *)

Theorem T6_T4_match_PGt : forall x y : Z,
  int64_range x = true -> int64_range y = true -> Z.ltb y x = true ->
  (denote (prim_corner PGt [VInt x; VInt y]) 6%nat ≅ sret (SOk (VInt x))) /\
  (exists le',
    Clight1.exec_stmt ge0 Clight.empty_env le0 Mem.empty
      (clight_of (Lower.lower (prim_corner PGt [VInt x; VInt y])))
      Events.E0 le' Mem.empty ClightBigstep.Out_normal
    /\ PTree.get Lower.lower_res le' = Some (Vint (Int.repr 1))).
Proof.
  intros x y Hx Hy Hg.
  assert (Hden : denote (prim_corner PGt [VInt x; VInt y]) 6%nat
    ≅ sret (SOk (VInt x))).
  { apply (denote_prim_corner_PGt x y Hg). }
  assert (Hws : forall d, ws_expr d (prim_corner PGt [VInt x; VInt y]) = true).
  { intros d. unfold prim_corner. cbn [ws_expr ws_val]. cbn. reflexivity. }
  assert (Hds : det_struct (prim_corner PGt [VInt x; VInt y]) = true).
  { hds_corner_prologue. hds_guarded (prim_total_res_PGt_true x y Hg). }
  assert (Hrg : range_ok (prim_corner PGt [VInt x; VInt y]) = true).
  { unfold prim_corner. cbn [range_ok prim_operand_vals]. rewrite !rets_of_map_ret.
    cbn [range_ok val_int64_ok andb forallb map].
    unfold prim_node_range_ok, prim_total.
    rewrite Hg. cbn [andb forallb]. rewrite Hx, Hy. cbn. reflexivity. }
  destruct (T6_exec_ws (prim_corner PGt [VInt x; VInt y]) 0%nat le0 (Hws 0%nat) Hds Hrg)
    as [le' [Hex Hpin]].
  split; [exact Hden |].
  exists le'; split; [exact Hex |].
  rewrite Hpin. cbn [lower_final Lower.prim_head prim_operand_vals prim_corner].
  rewrite rets_of_map_ret.
  cbn [lower_final Lower.prim_head prim_operand_vals prim_corner].
  rewrite (prim_guard_success_PGt x y Hx Hy Hg). reflexivity.
Qed.

(* ---------- composition: the div corner under the new floor fold ---------- *)

Theorem T6_T4_match_PDiv : forall x y : Z,
  int64_range x = true -> int64_range y = true ->
  int64_range (Z.div x y) = true -> Z.eqb y 0 = false ->
  (denote (prim_corner PDiv [VInt x; VInt y]) 6%nat ≅ sret (SOk (VInt (Z.div x y)))) /\
  (exists le',
    Clight1.exec_stmt ge0 Clight.empty_env le0 Mem.empty
      (clight_of (Lower.lower (prim_corner PDiv [VInt x; VInt y])))
      Events.E0 le' Mem.empty ClightBigstep.Out_normal
    /\ PTree.get Lower.lower_res le' = Some (Vlong (Int64.repr (Z.div x y)))).
Proof.
  intros x y Hx Hy Hq Hz.
  assert (Hden : denote (prim_corner PDiv [VInt x; VInt y]) 6%nat
    ≅ sret (SOk (VInt (Z.div x y)))).
  { apply (denote_prim_corner_PDiv x y Hz). }
  assert (Hws : forall d, ws_expr d (prim_corner PDiv [VInt x; VInt y]) = true).
  { intros d. unfold prim_corner. cbn [ws_expr ws_val]. cbn. reflexivity. }
  assert (Hds : det_struct (prim_corner PDiv [VInt x; VInt y]) = true).
  { hds_corner_prologue. hds_guarded (prim_total_res_PDiv_true x y Hz). }
  assert (Hrg : range_ok (prim_corner PDiv [VInt x; VInt y]) = true).
  { unfold prim_corner. cbn [range_ok prim_operand_vals]. rewrite !rets_of_map_ret.
    cbn [range_ok val_int64_ok andb forallb map].
    unfold prim_node_range_ok, prim_total.
    rewrite Hz. cbn [andb forallb]. rewrite Hx, Hy, Hq. cbn. reflexivity. }
  destruct (T6_exec_ws (prim_corner PDiv [VInt x; VInt y]) 0%nat le0 (Hws 0%nat) Hds Hrg)
    as [le' [Hex Hpin]].
  split; [exact Hden |].
  exists le'; split; [exact Hex |].
  rewrite Hpin. cbn [lower_final Lower.prim_head prim_operand_vals prim_corner].
  rewrite rets_of_map_ret.
  cbn [lower_final Lower.prim_head prim_operand_vals prim_corner].
  rewrite (prim_match_PDiv x y Hx Hy). cbn [clight_of_val z64]. reflexivity.
Qed.
