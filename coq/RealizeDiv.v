(* RealizeDiv.v - the div semantics fork, measured (docs/PLAN.md decision 12;
   docs/DESIGN-NOTES.md sec. 13.15): the kernel Z.div is a true FLOOR,
   CompCert's Int64.divs truncates, the dialect divZ is truncation plus a
   ladder correction, and `divZ_ladder` + `divZ_ladder_div` pin the ladder to
   Z.div exactly (the five divZ_* rungs are the quadrant proof).  The gap
   literals `divs_floor_gap_*` and `floor_literal_*` are the measured -3 vs -4
   corner; bridge_divs_quot pins Int64.divs itself (it lives in RealizeBridges).

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
Import ListNotations.
(* Z scope AFTER the compcert imports (toolchain ruling: opening it before the
   compcert Require block clashes). *)
Local Open Scope Z_scope.
Require Import Timbda.RealizeBridges.

(* [SAME] rung: exact division - the ladder never fires. *)
Lemma divZ_exact : forall x y : Z,
  Z.rem x y = 0 -> Z.quot x y = Z.div x y.
Proof.
  intros x y Hr.
  (* NB: destructing a Z goes to 3 branches (Z0/Zpos/Zneg) - decide against 0
     instead and let div_unique handle the sign disjunction. *)
  destruct (Z.eq_dec y 0) as [Hy0 | Hnz].
  - rewrite Hy0. cbn [Z.quot Z.div]. reflexivity.
  - assert (HQ := Z.quot_rem x y Hnz).
    assert (HD : Z.quot x y = Z.div x y).
    { apply (Z.div_unique x y (Z.quot x y) 0).
      + lia.   (* r := 0 already instantiated by apply; Hnz decides the disjunct *)
      + rewrite Hr in HQ. lia. }
    exact HD.
Qed.

(* [SAME] rung: same signs, inexact - truncation already floors. *)
Lemma divZ_same_pos : forall x y : Z,
  0 <= x -> 0 < y -> Z.quot x y = Z.div x y.
Proof.
  intros x y Hx Hy.
  destruct (Z.eq_dec x 0) as [Hx0 | Hx0].
  - rewrite Hx0.
    assert (H1 : Z.quot 0 y = 0) by (apply Z.quot_0_l; lia).
    assert (H2 : Z.div 0 y = 0) by (apply Z.div_0_l; lia).
    rewrite H1, H2. reflexivity.
  - assert (Hx0' : 0 < x) by lia.
    assert (Hnz : y <> 0) by lia.
    assert (HQ := Z.quot_rem x y Hnz).
    assert (HR := Z.rem_bound_pos x y Hx Hy).
    set (q := Z.quot x y) in *.
    assert (HD : q = Z.div x y).
    { apply (Z.div_unique x y q (Z.rem x y)).
      - left; lia.
      - lia. }
    lia.
Qed.

Lemma divZ_same_neg : forall x y : Z,
  x <= 0 -> y < 0 -> Z.quot x y = Z.div x y.
Proof.
  intros x y Hx Hy.
  assert (Hnz : y <> 0) by lia.
  assert (HQ := Z.quot_rem x y Hnz).
  assert (HR := Z.rem_bound_neg_neg x y Hy Hx).
  set (q := Z.quot x y) in *.
  assert (HD : q = Z.div x y).
  { apply (Z.div_unique x y q (Z.rem x y)).
    - right; lia.
    - lia. }
  lia.
Qed.

(* [LADDER] rung: x >= 0, y < 0, inexact - truncation overshoots by exactly 1. *)
Lemma divZ_mixed_pos_neg : forall x y : Z,
  0 <= x -> y < 0 -> Z.rem x y <> 0 -> Z.quot x y = Z.div x y + 1.
Proof.
  intros x y Hx Hy Hr.
  assert (Hnz : y <> 0) by lia.
  assert (HQ := Z.quot_rem x y Hnz).
  assert (HR := Z.rem_bound_neg_pos x y Hy Hx).
  (* set shields the Z.quot/Z.rem atoms from the div/rem pattern rewriting in
     lia and ring (both choke on `x ÷ y` inside ring expressions). *)
  set (q := Z.quot x y) in *.
  set (r := Z.rem x y) in *.
  assert (HD : q - 1 = Z.div x y).
  { apply (Z.div_unique x y (q - 1) (r + y)).
    - right; lia.
    - rewrite HQ; ring. }
  lia.
Qed.

(* [LADDER] rung: x < 0, y > 0, inexact - the other overshoot pair. *)
Lemma divZ_mixed_neg_pos : forall x y : Z,
  x < 0 -> 0 < y -> Z.rem x y <> 0 -> Z.quot x y = Z.div x y + 1.
Proof.
  intros x y Hx Hy Hr.
  assert (Hx0 : x <= 0) by lia.
  assert (Hnz : y <> 0) by lia.
  assert (HQ := Z.quot_rem x y Hnz).
  assert (HR := Z.rem_bound_pos_neg x y Hy Hx0).
  set (q := Z.quot x y) in *.
  set (r := Z.rem x y) in *.
  assert (HD : q - 1 = Z.div x y).
  { apply (Z.div_unique x y (q - 1) (r + y)).
    - left; lia.
    - rewrite HQ; ring. }
  lia.
Qed.

(* ---------- the Int64 side of the fork ---------- *)

Lemma bridge_divs_quot : forall x y : Z,
  int64_range x = true -> int64_range y = true ->
  Int64.divs (Int64.repr x) (Int64.repr y) = Int64.repr (Z.quot x y).
Proof.
  intros x y Hx Hy. unfold Int64.divs.
  rewrite (int64_range_signed x Hx), (int64_range_signed y Hy).
  reflexivity.
Qed.

(* The gap the increment closes (measured literals): 7 divs -2 truncates to -3,
   the kernel floor 7 / (-2) is -4. *)
Lemma divs_floor_gap_neg :
  Int64.signed (Int64.divs (Int64.repr 7) (Int64.repr (-2))) = -3.
Proof. vm_compute. reflexivity. Qed.

Lemma divs_floor_gap_pos :
  Int64.signed (Int64.divs (Int64.repr (-7)) (Int64.repr 2)) = -3.
Proof. vm_compute. reflexivity. Qed.

Lemma floor_literal_neg : Int64.signed (Int64.repr (Z.div 7 (-2))) = -4.
Proof. vm_compute. reflexivity. Qed.

Lemma floor_literal_pos : Int64.signed (Int64.repr (Z.div (-7) 2)) = -4.
Proof. vm_compute. reflexivity. Qed.

(* ---------- fold match: the Coq mirror of the dialect divZ ladder ---------- *)

(* divZ_ladder transcribes TimbdaCanonicalization.cpp 176-183:
   q = sdiv (Z.quot), r = srem (Z.rem); q -= 1 iff r <> 0 and sign r <> sign y. *)
(* NB: core Coq has no bool-equality function (Datatypes.eqb does not exist
   for bool), so the sign comparison is encoded as a nested if over Z.ltb -
   the direct transcription of "q -= 1 iff r <> 0 && sign r <> sign y". *)
Definition divZ_ladder (x y : Z) : Z :=
  let q := Z.quot x y in
  let r := Z.rem x y in
  if Z.eqb r 0 then q
  else if Z.ltb r 0 then if Z.ltb y 0 then q else q - 1
       else if Z.ltb y 0 then q - 1 else q.

Lemma divZ_ladder_div : forall x y : Z,
  y <> 0 -> divZ_ladder x y = Z.div x y.
Proof.
  intros x y Hnz.
  cbv [divZ_ladder].
  destruct (Z.eqb (Z.rem x y) 0) eqn:E0.
  - rewrite (Z.eqb_eq _ _) in E0.
    rewrite (divZ_exact x y E0). reflexivity.
  - rewrite (Z.eqb_neq _ _) in E0.
    destruct (Z_lt_ge_dec x 0) as [Hx | Hxge];
    destruct (Z_lt_ge_dec y 0) as [Hy | Hyn].
    + (* x < 0, y < 0: r in (y, 0], r <> 0 -> sign r = sign y -> no correction *)
      assert (Hx0 : x <= 0) by lia.
      assert (HR := Z.rem_bound_neg_neg x y Hy Hx0).
      replace (Z.ltb (Z.rem x y) 0) with true
        by (symmetry; rewrite (Z.ltb_lt _ _); lia).
      replace (Z.ltb y 0) with true
        by (symmetry; rewrite (Z.ltb_lt _ _); lia).
      cbn.
      rewrite (divZ_same_neg x y); [reflexivity | lia | lia].
    + (* x < 0, y >= 0 (hence y > 0): r in (-y, 0], sign r <> sign y -> ladder fires *)
      assert (Hx0 : x <= 0) by lia.
      assert (Hy0 : 0 < y) by lia.
      assert (HR := Z.rem_bound_pos_neg x y Hy0 Hx0).
      replace (Z.ltb (Z.rem x y) 0) with true
        by (symmetry; rewrite (Z.ltb_lt _ _); lia).
      replace (Z.ltb y 0) with false
        by (symmetry; rewrite (Z.ltb_ge _ _); lia).
      cbn.
      rewrite (divZ_mixed_neg_pos x y); [lia | exact Hx | exact Hy0 | exact E0].
    + (* 0 <= x, y < 0: r in [0, -y), signs differ -> ladder fires *)
      assert (Hxle : 0 <= x) by lia.
      assert (HR := Z.rem_bound_neg_pos x y Hy Hxle).
      replace (Z.ltb (Z.rem x y) 0) with false
        by (symmetry; rewrite (Z.ltb_ge _ _); lia).
      replace (Z.ltb y 0) with true
        by (symmetry; rewrite (Z.ltb_lt _ _); lia).
      cbn.
      rewrite (divZ_mixed_pos_neg x y); [lia | lia | exact Hy | exact E0].
    + (* 0 <= x, 0 <= y (hence y > 0): r in [0, y) -> no correction *)
      assert (Hxle : 0 <= x) by lia.
      assert (Hy0 : 0 < y) by lia.
      assert (HR := Z.rem_bound_pos x y Hxle Hy0).
      replace (Z.ltb (Z.rem x y) 0) with false
        by (symmetry; rewrite (Z.ltb_ge _ _); lia).
      replace (Z.ltb y 0) with false
        by (symmetry; rewrite (Z.ltb_ge _ _); lia).
      cbn.
      rewrite (divZ_same_pos x y); [reflexivity | lia | lia].
Qed.
