(* RealizeBridges.v - the Int64<->Z bridge layer of the T6 realization cone,
   plus the signed-window facts it rests on (docs/PLAN.md decision 12;
   docs/DESIGN-NOTES.md sec. 13.15): repr-level arith bridges, signed-level
   cmp bridges, the equality machinery (signed_eq_of_eqm /
   signed_eq_of_mod_eq / int64_eq_signed), the leb plumbing, vint_z_VInt.

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
(* eqmod (the Prop behind Int64.eqm) lives in Zbits' namespace; this file's
   signed_eq_of_mod_eq unfolds it bare. *)
Import Zbits.
(* vint_z / z64 live in Lower.v (the prim_expr floor fold needs them there);
   the bridge vint_z_VInt reads them here.  andb_and/andb3_and are Timbda's
   own boolean-split lemmas, defined in Checks.v; VInt/Val are kernel ctors
   in Syntax.v - the Require Import chain does not re-export (CompCert-style:
   every module a file reads is required explicitly). *)
Require Import Timbda.Syntax Timbda.Checks Timbda.Lower.

(* ---------- the 64-bit signed window (moved here from Realize.v) ---------- *)

(* The signed window [Int64.min_signed, Int64.max_signed] - the exact interval
   on which Int64.repr is value-preserving (signed_repr_eq, Integers.v). *)
Definition int64_range (z : Z) : bool :=
  Z.leb Int64.min_signed z && Z.leb z Int64.max_signed.
(* int64_range is exactly the interval on which Int64.repr preserves the value
   (Int64.signed_repr, Integers.v). *)
Lemma int64_range_signed : forall z : Z,
  int64_range z = true -> Int64.signed (Int64.repr z) = z.
Proof.
  intros z Hz.
  unfold int64_range in Hz. apply andb_and in Hz.
  destruct Hz as [H1 H2]. apply Z.leb_le in H1. apply Z.leb_le in H2.
  apply Int64.signed_repr. lia.
Qed.

Lemma signed_repr_min : Int64.signed (Int64.repr Int64.min_signed) = Int64.min_signed.
Proof.
  apply Int64.signed_repr. unfold Int64.min_signed, Int64.max_signed.
  generalize Int64.half_modulus_pos. lia.
Qed.

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

(* vint_z itself landed in Lower.v (the prim_expr fold needs it there); the
   reading: signed . z64 - a Val as the emitted Int64 constant holds it. *)

Lemma vint_z_VInt : forall z : Z,
  int64_range z = true -> vint_z (VInt z) = z.
Proof.
  intros z Hz. unfold vint_z. cbn [z64]. apply int64_range_signed. exact Hz.
Qed.
