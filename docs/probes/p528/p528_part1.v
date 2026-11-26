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
