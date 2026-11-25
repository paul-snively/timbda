(* ---------- the div guards, derived from the checked fragment ---------- *)

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
