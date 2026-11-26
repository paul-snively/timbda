(* p528 part1 (rebuilt after the server restart, 2026-11-26) - the Int64<->Z
   bridges for increment C.

   Surfaces re-measured against the installed store tree (Integers.v of the
   CompCert 3.17 source):
   - Int64.add/sub/mul are repr-of-unsigned sums (l.185-190), neg = repr (-
     unsigned) (l.184): repr-level bridges hold UNCONDITIONALLY via eqm_samerepr.
   - Int64.divs = repr (Z.quot (signed .) (signed .)) (l.193): truncation, NOT
     floor; Int64.mods = repr (Z.rem .) (dividend-signed).
   - Int64.eq = zeq over UNSIGNED (l.177), Int.lt = zlt over SIGNED (l.179);
     Int64.cmp (l.282): Cgt = lt y x, Cge = negb (lt x y), Cle = negb (lt y x),
     Cne = negb (eq x y).
   - int64_range (Realize.v l.62) = the signed window; int64_range_signed (l.342)
     is the value-preservation fact. *)

From Stdlib Require Import ZArith Lia Ring List.
Require Import compcert.lib.Coqlib compcert.lib.Integers compcert.lib.Zbits compcert.lib.Maps
  compcert.common.Values compcert.common.AST compcert.common.Memory
  compcert.common.Events compcert.common.Globalenvs
  compcert.cfrontend.Ctypes compcert.cfrontend.Cop compcert.cfrontend.Clight
  compcert.cfrontend.ClightBigstep.
Require Import Timbda.Syntax Timbda.Rewriting Timbda.Semantics Timbda.Eval
  Timbda.Checks Timbda.Lower Timbda.Realize.
Import ListNotations.

(* Z scope AFTER the compcert imports (toolchain ruling: opening it before the
   compcert Require block clashes); without it, numerals default to nat and
   `-(...)` is a syntax error. *)
Local Open Scope Z_scope.

(* ---------- repr-level arith bridges (no range hypotheses needed) ---------- *)

(* The arith bridges run through CompCert's own eqm_unsigned_repr
   (Integers.v 469: eqm z (unsigned (repr z))) - no div_mod rewriting at all
   (a rewrite of Z.div_mod also replaces x inside the Z.quot/Z.modulo argument
   positions and derails the goal; lia refuses to interpret Z.quot/Z.modulo
   against a non-numeric modulus). *)

Lemma bridge_add : forall x y : Z,
  Int64.add (Int64.repr x) (Int64.repr y) = Int64.repr (x + y).
Proof.
  intros x y. unfold Int64.add. apply Int64.eqm_samerepr. apply Int64.eqm_add.
  - apply Int64.eqm_sym. apply Int64.eqm_unsigned_repr.
  - apply Int64.eqm_sym. apply Int64.eqm_unsigned_repr.
Qed.

Lemma bridge_sub : forall x y : Z,
  Int64.sub (Int64.repr x) (Int64.repr y) = Int64.repr (x - y).
Proof.
  intros x y. unfold Int64.sub. apply Int64.eqm_samerepr. apply Int64.eqm_sub.
  - apply Int64.eqm_sym. apply Int64.eqm_unsigned_repr.
  - apply Int64.eqm_sym. apply Int64.eqm_unsigned_repr.
Qed.

Lemma bridge_mul : forall x y : Z,
  Int64.mul (Int64.repr x) (Int64.repr y) = Int64.repr (x * y).
Proof.
  intros x y. unfold Int64.mul. apply Int64.eqm_samerepr. apply Int64.eqm_mult.
  - apply Int64.eqm_sym. apply Int64.eqm_unsigned_repr.
  - apply Int64.eqm_sym. apply Int64.eqm_unsigned_repr.
Qed.

Lemma bridge_neg : forall x : Z,
  Int64.neg (Int64.repr x) = Int64.repr (- x).
Proof.
  intros x. unfold Int64.neg. apply Int64.eqm_samerepr. apply Int64.eqm_neg.
  apply Int64.eqm_sym. apply Int64.eqm_unsigned_repr.
Qed.

(* ---------- signed-level cmp bridges (range hypotheses needed) ----------
   Int64.lt compares via zlt (Integers.v 179) while Z.ltb is defined via
   `?=`/compare in 9.1 - convertible but not syntactically equal, so bridge
   proofs case-split the sumbool and pin the Z.ltb side via Z.ltb_lt / Z.ltb_ge. *)

Lemma bridge_cmp_Cgt : forall x y : Z,
  int64_range x = true -> int64_range y = true ->
  Int64.cmp Cgt (Int64.repr x) (Int64.repr y) = Z.ltb y x.
Proof.
  intros x y Hx Hy. unfold Int64.cmp, Int64.lt.
  rewrite (int64_range_signed y Hy), (int64_range_signed x Hx).
  destruct (zlt y x) as [Hlt | Hge].
  - rewrite (proj2 (Z.ltb_lt y x)); [reflexivity | lia].
  - rewrite (proj2 (Z.ltb_ge y x)); [reflexivity | lia].
Qed.

Lemma bridge_cmp_Clt : forall x y : Z,
  int64_range x = true -> int64_range y = true ->
  Int64.cmp Clt (Int64.repr x) (Int64.repr y) = Z.ltb x y.
Proof.
  intros x y Hx Hy. unfold Int64.cmp, Int64.lt.
  rewrite (int64_range_signed x Hx), (int64_range_signed y Hy).
  destruct (zlt x y) as [Hlt | Hge].
  - rewrite (proj2 (Z.ltb_lt x y)); [reflexivity | lia].
  - rewrite (proj2 (Z.ltb_ge x y)); [reflexivity | lia].
Qed.

Lemma bridge_cmp_Cge : forall x y : Z,
  int64_range x = true -> int64_range y = true ->
  Int64.cmp Cge (Int64.repr x) (Int64.repr y) = negb (Z.ltb x y).
Proof.
  intros x y Hx Hy. unfold Int64.cmp, Int64.lt.
  rewrite (int64_range_signed x Hx), (int64_range_signed y Hy).
  destruct (zlt x y) as [Hlt | Hge].
  - rewrite (proj2 (Z.ltb_lt x y)); [reflexivity | lia].
  - rewrite (proj2 (Z.ltb_ge x y)); [reflexivity | lia].
Qed.

Lemma bridge_cmp_Cle : forall x y : Z,
  int64_range x = true -> int64_range y = true ->
  Int64.cmp Cle (Int64.repr x) (Int64.repr y) = negb (Z.ltb y x).
Proof.
  intros x y Hx Hy. unfold Int64.cmp, Int64.lt.
  rewrite (int64_range_signed y Hy), (int64_range_signed x Hx).
  destruct (zlt y x) as [Hlt | Hge].
  - rewrite (proj2 (Z.ltb_lt y x)); [reflexivity | lia].
  - rewrite (proj2 (Z.ltb_ge y x)); [reflexivity | lia].
Qed.

Lemma signed_eq_of_eqm : forall x y : Z,
  Int64.eqm x y ->
  int64_range x = true -> int64_range y = true -> x = y.
Proof.
  intros x y He Hx Hy.
  transitivity (Int64.signed (Int64.repr x)).
  - symmetry. apply Int64.signed_repr.
    unfold int64_range in Hx. apply andb_and in Hx. destruct Hx as [Hx1 Hx2].
    apply Z.leb_le in Hx1. apply Z.leb_le in Hx2. split; assumption.
  - transitivity (Int64.signed (Int64.repr y)).
    + apply f_equal. apply Int64.eqm_samerepr. exact He.
    + apply Int64.signed_repr.
      unfold int64_range in Hy. apply andb_and in Hy. destruct Hy as [Hy1 Hy2].
      apply Z.leb_le in Hy1. apply Z.leb_le in Hy2. split; assumption.
Qed.

(* NB: in the caller, each premise is passed with "apply ...; [ ... ]" so that
   the bracketed closers cannot leak across the apply-generated goals (the
   unbracketed form let later tactics steal later goals). *)
Lemma signed_eq_of_mod_eq : forall x y : Z,
  Z.modulo x Int64.modulus = Z.modulo y Int64.modulus ->
  int64_range x = true -> int64_range y = true -> x = y.
Proof.
  intros x y Hm Hx Hy.
  (* eqmod unfolds to the bare "exists k, x = k*modulus + y", so the modular
     equality must be carried through eqm_unsigned_repr / unsigned_repr_eq. *)
  assert (H1 : Int64.eqm x (Z.modulo x Int64.modulus)).
  { rewrite <- (Int64.unsigned_repr_eq x). apply Int64.eqm_unsigned_repr. }
  assert (H2 : Int64.eqm (Z.modulo y Int64.modulus) y).
  { apply Int64.eqm_sym. rewrite <- (Int64.unsigned_repr_eq y).
    apply Int64.eqm_unsigned_repr. }
  apply signed_eq_of_eqm; [
    apply Int64.eqm_trans with (Z.modulo x Int64.modulus); [
      exact H1
    | apply Int64.eqm_trans with (Z.modulo y Int64.modulus); [
        rewrite Hm; unfold Int64.eqm, eqmod; exists 0; lia
      | exact H2 ] ]
  | exact Hx | exact Hy ].
Qed.

(* Int64.eq compares the UNSIGNED views.  After unfold + unsigned_repr_eq the
   left side sits in unfold-form (`if zeq ... then`), so neither fold nor
   destruct sees a Z.eqb application there: destruct the right side (folded)
   first, then destruct the zeq scrutinee itself, which collapses the match. *)
Lemma int64_eq_signed : forall x y : Z,
  int64_range x = true -> int64_range y = true ->
  Int64.eq (Int64.repr x) (Int64.repr y) = Z.eqb x y.
Proof.
  intros x y Hx Hy. unfold Int64.eq. rewrite !Int64.unsigned_repr_eq.
  destruct (Z.eqb x y) eqn:E.
  - destruct (zeq (Z.modulo x Int64.modulus) (Z.modulo y Int64.modulus))
      as [Heq | Hne].
    + reflexivity.
    + exfalso. rewrite (Z.eqb_eq x y) in E. subst y. apply Hne. reflexivity.
  - destruct (zeq (Z.modulo x Int64.modulus) (Z.modulo y Int64.modulus))
      as [Heq | Hne].
    + exfalso. rewrite (Z.eqb_neq x y) in E. apply E.
      apply signed_eq_of_mod_eq; [exact Heq | exact Hx | exact Hy].
    + reflexivity.
Qed.

Lemma bridge_cmp_Cne : forall x y : Z,
  int64_range x = true -> int64_range y = true ->
  Int64.cmp Cne (Int64.repr x) (Int64.repr y) = negb (Z.eqb x y).
Proof.
  intros x y Hx Hy. unfold Int64.cmp. cbn [negb].
  rewrite (int64_eq_signed x y Hx Hy). reflexivity.
Qed.

(* ---------- leb plumbing for the guard match (decision 10d guards) ---------- *)

(* leb/ltb rewrite plumbing (calibrated against the 9.1 iff forms):
   rewrite Z.leb_le turns `(a <=? b) = true` into `a <= b`,
   rewrite Z.leb_gt turns `(a <=? b) = false` into `b < a`,
   rewrite Z.ltb_ge in H turns `(a <? b) = false` into `b <= a`. *)

Lemma leb_as_or_lt_eq : forall a b : Z, (a <=? b) = (a <? b) || (a =? b).
Proof.
  intros a b.
  destruct (Z.ltb a b) eqn:HL; destruct (Z.eqb a b) eqn:HE; cbn [orb].
  - rewrite Z.leb_le. rewrite Z.ltb_lt in HL. lia.
  - rewrite Z.leb_le. rewrite Z.ltb_lt in HL. lia.
  - rewrite Z.leb_le. rewrite Z.ltb_ge in HL. rewrite Z.eqb_eq in HE. lia.
  - rewrite Z.leb_gt. rewrite Z.ltb_ge in HL. rewrite Z.eqb_neq in HE. lia.
Qed.

Lemma leb_as_neg_lt : forall a b : Z, (a <=? b) = negb (b <? a).
Proof.
  intros a b. destruct (Z.ltb a b) eqn:HL; destruct (Z.ltb b a) eqn:HR; cbn [negb].
  - rewrite Z.ltb_lt in HL. rewrite Z.ltb_lt in HR. lia.
  - rewrite Z.leb_le. rewrite Z.ltb_lt in HL. lia.
  - rewrite Z.leb_gt. rewrite Z.ltb_lt in HR. exact HR.
  - rewrite Z.leb_le. rewrite Z.ltb_ge in HR. exact HR.
Qed.

(* ---------- the signed reading of a lowered operand (increment-C helper) ---------- *)

(* vint_z reads a Val the way the emitted Int64 constant holds it: signed . z64.
   For in-range VInt operands this is exactly the kernel Z value. *)
Definition vint_z (v : Val) : Z := Int64.signed (z64 v).

Lemma vint_z_VInt : forall z : Z,
  int64_range z = true -> vint_z (VInt z) = z.
Proof.
  intros z Hz. unfold vint_z. cbn [z64]. apply int64_range_signed. exact Hz.
Qed.
(* p528 part2 (rebuilt) - the div semantics fork (decision 12 calibration).

   Measured (micro4 pre-restart): kernel Z.div is true FLOOR -
     7/2 = 3, 7/(-2) = -4, (-7)/2 = -4, (-7)/(-2) = 3;
   CompCert Int64.divs = repr (Z.quot (signed .) (signed .)) (Integers.v 193):
   TRUNCATION on signed views; Int64.mods = repr (Z.rem .) (dividend-signed).
   The dialect divZ (TimbdaCanonicalization.cpp 176-183) is truncation plus the
   ladder correction; these rungs pin it to Z.div.

   Kit rulings (micro6-9 pre-restart, re-confirmed here):
   - lia cannot prove div/quot identities head-on ("Cannot find witness");
     route through Z.div_unique (disjunct 0 <= r < b \/ b < r <= 0).
   - inside ring/lia, shield Z.quot/Z.rem atoms with `set (q := Z.quot x y) in *.`
     - the div/rem pattern rewriting otherwise derails ring ("not a valid ring
     equation"). *)

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
(* p528 part3 (rebuilt) - the kernel<->lowered correspondence (decision 10d),
   the exact corner denotation (beta fixed: cbv fires the bind chains - cbn in
   Rocq 9.1 is by-name and leaves the beta-redexes), and the T6 composition.

   Rulings re-baked from the pre-restart micro runs:
   - `unfold a b` (space-separated constants) is a syntax error in Rocq 9.1 -
     use commas (micro22-25).
   - `Compute`/`Eval` vernaculars clash with the Ltac tactic names - machine
     checks run as `vm_compute. reflexivity.` lemmas.
   - Vtrue = Vint Int.one, Vfalse = Vint Int.zero; `Vint (Int.repr 1) <>
     Vint Int.zero` closes by bare `inversion`.
   - cbn of the denotation leaves the monadic beta-redexes; use cbv over the
     evaluator constants. *)

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

Lemma prim_clight_old_divs : forall x y : Z,
  int64_range x = true -> int64_range y = true ->
  prim_clight PDiv [VInt x; VInt y] = Vlong (Int64.repr (Z.quot x y)).
Proof.
  intros x y Hx Hy. unfold prim_clight. cbn [z64].
  rewrite bridge_divs_quot; [reflexivity | exact Hx | exact Hy].
Qed.

(* increment-C targets (mirrors of the planned Lower.v / Realize.v arms): *)
Definition prim_clight_new (p : Prim) (vs : list Val) : val :=
  match p, vs with
  | PDiv, a :: b :: nil => Vlong (Int64.repr (Z.div (vint_z a) (vint_z b)))
  | _, _ => prim_clight p vs
  end.

Definition prim_expr_new (p : Prim) (vs : list Val) : Clight.expr :=
  match p, vs with
  | PDiv, a :: b :: nil =>
      Clight.Econst_long (Int64.repr (Z.div (vint_z a) (vint_z b))) Lower.tint64
  | _, _ => Lower.prim_expr p vs
  end.

(* three-way match, kernel side: prim_total PDiv = PRes (VInt (Z.div .)) directly *)
Lemma prim_match_PDiv : forall x y : Z,
  int64_range x = true -> int64_range y = true ->
  prim_clight_new PDiv [VInt x; VInt y] = clight_of_val (VInt (Z.div x y)).
Proof.
  intros x y Hx Hy. unfold prim_clight_new, clight_of_val.
  cbn [vint_z z64].
  rewrite (vint_z_VInt x Hx), (vint_z_VInt y Hy). reflexivity.
Qed.

Lemma prim_expr_new_eval_PDiv : forall (x y : Z) (le : Clight.temp_env),
  int64_range x = true -> int64_range y = true ->
  Clight.eval_expr ge0 Clight.empty_env le Mem.empty
    (prim_expr_new PDiv [VInt x; VInt y]) (prim_clight_new PDiv [VInt x; VInt y]).
Proof.
  intros x y le Hx Hy. unfold prim_expr_new, prim_clight_new.
  cbn [vint_z z64].
  rewrite (vint_z_VInt x Hx), (vint_z_VInt y Hy). apply eval_const64.
Qed.

(* guard-free lowering: the folded arm needs no Odiv guard at all *)
Lemma prim_expr_new_PDiv_literal :
  prim_expr_new PDiv [VInt 7; VInt (-2)] = Clight.Econst_long (Int64.repr (-4)) Lower.tint64.
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

(* ---------- the exact kernel-side corner denotation ---------- *)

Definition prim_corner (p : Prim) (vs : list Val) : Expr :=
  App (Ret (VPrim p)) (TupE (map Ret vs)).

Lemma rets_of_map_ret : forall (vs : list Val),
  rets_of (map Ret vs) = Some vs.
Proof.
  induction vs as [| v vs IHvs]; cbn [map rets_of];
    [reflexivity | rewrite IHvs; reflexivity].
Qed.

Lemma e_fuel_prim_corner2 : forall (p : Prim) (u v : Val),
  e_fuel (prim_corner p [u; v]) = 6%nat.
Proof.
  intros p u v. unfold prim_corner.
  cbn [e_fuel sumE map].
  (* nat `+` is a Fixpoint not in the delta list (lia also refuses the bare
     numeral equation here - "Cannot find witness"); full cbn reduces it. *)
  cbn. reflexivity.
Qed.

(* machine check (the cbv/cbn beta question, micro27/28 ruling): the concrete
   corner really denotes VInt 5 at fuel 5 *)
Lemma denote_add_corner_2_3 :
  denote (prim_corner PAdd [VInt 2; VInt 3]) 6%nat = sret (SOk (VInt 5)).
Proof. unfold prim_corner, denote. vm_compute. reflexivity. Qed.

(* symbolic corners: cbv over the evaluator constants fires the bind beta-chains;
   the kernel Z guards stay stuck until the guard hypothesis rewrites *)
Ltac denorm :=
  cbv [prim_corner denote denE denE_tup apply_c closeV prim_sres sret go
      CTreeDefinitions.CTree.bind prim_total].

Lemma denote_prim_corner_PAdd : forall x y : Z,
  denote (prim_corner PAdd [VInt x; VInt y]) (e_fuel (prim_corner PAdd [VInt x; VInt y]))
  = sret (SOk (VInt (x + y))).
Proof.
  intros x y. rewrite e_fuel_prim_corner2. denorm. reflexivity.
Qed.

Lemma denote_prim_corner_PSub : forall x y : Z,
  denote (prim_corner PSub [VInt x; VInt y]) (e_fuel (prim_corner PSub [VInt x; VInt y]))
  = sret (SOk (VInt (x - y))).
Proof.
  intros x y. rewrite e_fuel_prim_corner2. denorm. reflexivity.
Qed.

Lemma denote_prim_corner_PDiv : forall x y : Z,
  Z.eqb y 0 = false ->
  denote (prim_corner PDiv [VInt x; VInt y]) (e_fuel (prim_corner PDiv [VInt x; VInt y]))
  = sret (SOk (VInt (Z.div x y))).
Proof.
  intros x y Hz. rewrite e_fuel_prim_corner2. denorm.
  rewrite Hz. cbn [prim_sres]. reflexivity.
Qed.

Lemma denote_prim_corner_PNeg : forall x : Z,
  denote (prim_corner PNeg [VInt x]) (e_fuel (prim_corner PNeg [VInt x]))
  = sret (SOk (VInt (- x))).
Proof.
  intros x. unfold prim_corner, e_fuel. cbn [sumE map]. denorm. reflexivity.
Qed.

Lemma denote_prim_corner_PGt : forall x y : Z,
  Z.ltb y x = true ->
  denote (prim_corner PGt [VInt x; VInt y]) (e_fuel (prim_corner PGt [VInt x; VInt y]))
  = sret (SOk (VInt x)).
Proof.
  intros x y Hg. rewrite e_fuel_prim_corner2. denorm.
  rewrite Hg. cbn [prim_sres]. reflexivity.
Qed.

Lemma denote_prim_corner_PGEq : forall x y : Z,
  (Z.ltb y x || Z.eqb x y) = true ->
  denote (prim_corner PGEq [VInt x; VInt y]) (e_fuel (prim_corner PGEq [VInt x; VInt y]))
  = sret (SOk (VInt x)).
Proof.
  intros x y Hg. rewrite e_fuel_prim_corner2. denorm.
  rewrite Hg. cbn [prim_sres]. reflexivity.
Qed.

(* ---------- composition (decision 10c/10d): the add corner ---------- *)

Theorem T6_T4_match_add : forall x y : Z,
  int64_range x = true -> int64_range y = true -> int64_range (x + y) = true ->
  denote (prim_corner PAdd [VInt x; VInt y]) 6%nat = sret (SOk (VInt (x + y))) / \
  exists le',
    Clight1.exec_stmt ge0 Clight.empty_env le0 Mem.empty
      (clight_of (Lower.lower (prim_corner PAdd [VInt x; VInt y])))
      Events.E0 le' Mem.empty ClightBigstep.Out_normal
    /\ PTree.get Lower.lower_res le' = Some (Vlong (Int64.repr (x + y))).
Proof.
  intros x y Hx Hy Hxy.
  assert (Hden : denote (prim_corner PAdd [VInt x; VInt y]) 6%nat = sret (SOk (VInt (x + y)))).
  { rewrite (denote_prim_corner_PAdd x y). rewrite e_fuel_prim_corner2. reflexivity. }
  assert (Hws : forall d, ws_expr d (prim_corner PAdd [VInt x; VInt y]) = true).
  { intros d. unfold prim_corner. cbn [ws_expr]. rewrite !rets_of_map_ret. cbn. reflexivity. }
  assert (Hds : det_struct (prim_corner PAdd [VInt x; VInt y]) = true).
  { unfold prim_corner.
    cbn [det_struct bans_okE blocks_closed_okE unify_okE apps_okE tup_rets_okE app_node_ok].
    reflexivity. }
  assert (Hrg : range_ok (prim_corner PAdd [VInt x; VInt y]) = true).
  { unfold prim_corner. cbn [range_ok]. rewrite !rets_of_map_ret.
    rewrite Hx, Hy. cbn [range_ok val_int64_ok prim_node_range_ok]. rewrite Hxy. reflexivity. }
  destruct (T6_exec_ws (prim_corner PAdd [VInt x; VInt y]) 0 le0 (Hws 0) Hds Hrg)
    as [le' [Hex Hpin]].
  split; [exact Hden |].
  exists le'; split; [exact Hex |].
  rewrite Hpin. cbn [lower_final Lower.prim_head prim_operand_vals].
  rewrite rets_of_map_ret. cbn [lower_final Lower.prim_head prim_operand_vals].
  rewrite prim_match_add. cbn [clight_of_val z64]. reflexivity.
Qed.

(* ---------- composition: the guard corner (PGt, guard success) ---------- *)

Theorem T6_T4_match_PGt : forall x y : Z,
  int64_range x = true -> int64_range y = true -> Z.ltb y x = true ->
  denote (prim_corner PGt [VInt x; VInt y]) 6%nat = sret (SOk (VInt x)) / \
  exists le',
    Clight1.exec_stmt ge0 Clight.empty_env le0 Mem.empty
      (clight_of (Lower.lower (prim_corner PGt [VInt x; VInt y])))
      Events.E0 le' Mem.empty ClightBigstep.Out_normal
    /\ PTree.get Lower.lower_res le' = Some (Vint (Int.repr 1)).
Proof.
  intros x y Hx Hy Hg.
  assert (Hden : denote (prim_corner PGt [VInt x; VInt y]) 6%nat = sret (SOk (VInt x))).
  { rewrite (denote_prim_corner_PGt x y Hg). rewrite e_fuel_prim_corner2. reflexivity. }
  assert (Hws : forall d, ws_expr d (prim_corner PGt [VInt x; VInt y]) = true).
  { intros d. unfold prim_corner. cbn [ws_expr]. rewrite !rets_of_map_ret. cbn. reflexivity. }
  assert (Hds : det_struct (prim_corner PGt [VInt x; VInt y]) = true).
  { unfold prim_corner.
    cbn [det_struct bans_okE blocks_closed_okE unify_okE apps_okE tup_rets_okE app_node_ok].
    reflexivity. }
  assert (Hrg : range_ok (prim_corner PGt [VInt x; VInt y]) = true).
  { unfold prim_corner. cbn [range_ok]. rewrite !rets_of_map_ret.
    rewrite Hx, Hy. cbn [range_ok val_int64_ok prim_node_range_ok]. rewrite Hx. reflexivity. }
  destruct (T6_exec_ws (prim_corner PGt [VInt x; VInt y]) 0 le0 (Hws 0) Hds Hrg)
    as [le' [Hex Hpin]].
  split; [exact Hden |].
  exists le'; split; [exact Hex |].
  rewrite Hpin. cbn [lower_final Lower.prim_head prim_operand_vals].
  rewrite rets_of_map_ret. cbn [lower_final Lower.prim_head prim_operand_vals].
  rewrite prim_guard_match_PGt. reflexivity.
Qed.

(* ---------- composition: the div corner under the new floor fold ---------- *)

Theorem T6_T4_match_PDiv_fold : forall x y : Z,
  int64_range x = true -> int64_range y = true ->
  int64_range (Z.div x y) = true -> Z.eqb y 0 = false ->
  denote (prim_corner PDiv [VInt x; VInt y]) 6%nat = sret (SOk (VInt (Z.div x y))).
Proof.
  intros x y Hx Hy Hq Hz.
  rewrite (denote_prim_corner_PDiv x y Hz). rewrite e_fuel_prim_corner2. reflexivity.
Qed.
