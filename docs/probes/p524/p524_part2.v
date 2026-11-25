(* ---------- bridges on the CompCert side, symbolic operands (p522/p523) ---------- *)

Lemma sem_Oadd_long : forall m (i1 i2 : Int64.int),
  sem_binary_operation ge0 Cop.Oadd (Vlong i1) Lower.tint64 (Vlong i2) Lower.tint64 m
  = Some (Vlong (Int64.add i1 i2)).
Proof. intros. simpl. reflexivity. Qed.

Lemma sem_Osub_long : forall m (i1 i2 : Int64.int),
  sem_binary_operation ge0 Cop.Osub (Vlong i1) Lower.tint64 (Vlong i2) Lower.tint64 m
  = Some (Vlong (Int64.sub i1 i2)).
Proof. intros. simpl. reflexivity. Qed.

Lemma sem_Omul_long : forall m (i1 i2 : Int64.int),
  sem_binary_operation ge0 Cop.Omul (Vlong i1) Lower.tint64 (Vlong i2) Lower.tint64 m
  = Some (Vlong (Int64.mul i1 i2)).
Proof. intros. simpl. reflexivity. Qed.

(* Odiv: the guard spelling, measured in p523c.  The guard is a disjunction
   whose second term is a conjunction; a stuck conjunction only needs the
   implication form below (range_ok pins the min_signed / mone case away). *)
Lemma sem_Odiv_long : forall m (i1 i2 : Int64.int),
  Int64.eq i2 Int64.zero = false ->
  (Int64.eq i1 (Int64.repr Int64.min_signed) = true -> Int64.eq i2 Int64.mone = false) ->
  sem_binary_operation ge0 Cop.Odiv (Vlong i1) Lower.tint64 (Vlong i2) Lower.tint64 m
  = Some (Vlong (Int64.divs i1 i2)).
Proof.
  intros m0 i10 i20 H1 H2.
  cbv [sem_binary_operation sem_div sem_binarith classify_binarith
       binarith_type sem_cast classify_cast orb andb Archi.ptr64 Lower.tint64].
  rewrite H1.
  cbv [orb andb].
  (* destruct also peels the destructed term inside H2's premise *)
  destruct (Int64.eq i10 (Int64.repr Int64.min_signed)) eqn:He.
  - rewrite (H2 eq_refl). reflexivity.
  - reflexivity.
Qed.

Lemma sem_Olt_long : forall m (i1 i2 : Int64.int),
  sem_binary_operation ge0 Cop.Olt (Vlong i1) Lower.tint64 (Vlong i2) Lower.tint64 m
  = Some (Val.of_bool (Int64.cmp Clt i1 i2)).
Proof. intros. cbn [sem_binary_operation sem_cmp sem_binarith]. reflexivity. Qed.

Lemma sem_Ogt_long : forall m (i1 i2 : Int64.int),
  sem_binary_operation ge0 Cop.Ogt (Vlong i1) Lower.tint64 (Vlong i2) Lower.tint64 m
  = Some (Val.of_bool (Int64.cmp Cgt i1 i2)).
Proof. intros. cbn [sem_binary_operation sem_cmp sem_binarith]. reflexivity. Qed.

Lemma sem_Ole_long : forall m (i1 i2 : Int64.int),
  sem_binary_operation ge0 Cop.Ole (Vlong i1) Lower.tint64 (Vlong i2) Lower.tint64 m
  = Some (Val.of_bool (Int64.cmp Cle i1 i2)).
Proof. intros. cbn [sem_binary_operation sem_cmp sem_binarith]. reflexivity. Qed.

Lemma sem_Oge_long : forall m (i1 i2 : Int64.int),
  sem_binary_operation ge0 Cop.Oge (Vlong i1) Lower.tint64 (Vlong i2) Lower.tint64 m
  = Some (Val.of_bool (Int64.cmp Cge i1 i2)).
Proof. intros. cbn [sem_binary_operation sem_cmp sem_binarith]. reflexivity. Qed.

Lemma sem_One_long : forall m (i1 i2 : Int64.int),
  sem_binary_operation ge0 Cop.One (Vlong i1) Lower.tint64 (Vlong i2) Lower.tint64 m
  = Some (Val.of_bool (Int64.cmp Cne i1 i2)).
Proof. intros. cbn [sem_binary_operation sem_cmp sem_binarith]. reflexivity. Qed.

Lemma sem_Oneg_long : forall m (i1 : Int64.int),
  sem_unary_operation Cop.Oneg (Vlong i1) Lower.tint64 m
  = Some (Vlong (Int64.neg i1)).
Proof.
  intros. cbv [sem_unary_operation sem_neg classify_neg Lower.tint64]. reflexivity.
Qed.
