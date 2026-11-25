(* ---------- per-class eval lemmas for the emitted prim nodes ---------- *)

Lemma eval_bin64_Oadd : forall (i1 i2 : Int64.int) (le : Clight.temp_env),
  Clight.eval_expr ge0 Clight.empty_env le Mem.empty
    (Clight.Ebinop Cop.Oadd (Clight.Econst_long i1 Lower.tint64)
                            (Clight.Econst_long i2 Lower.tint64) Lower.tint64)
    (Vlong (Int64.add i1 i2)).
Proof.
  intros i1 i2 le. eapply Clight.eval_Ebinop.
  - apply eval_const64. - apply eval_const64. - apply sem_Oadd_long.
Qed.

Lemma eval_bin64_Osub : forall (i1 i2 : Int64.int) (le : Clight.temp_env),
  Clight.eval_expr ge0 Clight.empty_env le Mem.empty
    (Clight.Ebinop Cop.Osub (Clight.Econst_long i1 Lower.tint64)
                            (Clight.Econst_long i2 Lower.tint64) Lower.tint64)
    (Vlong (Int64.sub i1 i2)).
Proof.
  intros i1 i2 le. eapply Clight.eval_Ebinop.
  - apply eval_const64. - apply eval_const64. - apply sem_Osub_long.
Qed.

Lemma eval_bin64_Omul : forall (i1 i2 : Int64.int) (le : Clight.temp_env),
  Clight.eval_expr ge0 Clight.empty_env le Mem.empty
    (Clight.Ebinop Cop.Omul (Clight.Econst_long i1 Lower.tint64)
                            (Clight.Econst_long i2 Lower.tint64) Lower.tint64)
    (Vlong (Int64.mul i1 i2)).
Proof.
  intros i1 i2 le. eapply Clight.eval_Ebinop.
  - apply eval_const64. - apply eval_const64. - apply sem_Omul_long.
Qed.

Lemma eval_bin64_Odiv : forall (i1 i2 : Int64.int) (le : Clight.temp_env),
  Int64.eq i2 Int64.zero = false ->
  (Int64.eq i1 (Int64.repr Int64.min_signed) = true -> Int64.eq i2 Int64.mone = false) ->
  Clight.eval_expr ge0 Clight.empty_env le Mem.empty
    (Clight.Ebinop Cop.Odiv (Clight.Econst_long i1 Lower.tint64)
                            (Clight.Econst_long i2 Lower.tint64) Lower.tint64)
    (Vlong (Int64.divs i1 i2)).
Proof.
  intros i1 i2 le H1 H2. eapply Clight.eval_Ebinop.
  - apply eval_const64. - apply eval_const64. - apply (sem_Odiv_long _ i1 i2 H1 H2).
Qed.

Lemma eval_bin64_Olt : forall (i1 i2 : Int64.int) (le : Clight.temp_env),
  Clight.eval_expr ge0 Clight.empty_env le Mem.empty
    (Clight.Ebinop Cop.Olt (Clight.Econst_long i1 Lower.tint64)
                           (Clight.Econst_long i2 Lower.tint64) Lower.tint32)
    (Val.of_bool (Int64.cmp Clt i1 i2)).
Proof.
  intros i1 i2 le. eapply Clight.eval_Ebinop.
  - apply eval_const64. - apply eval_const64. - apply sem_Olt_long.
Qed.

Lemma eval_bin64_Ogt : forall (i1 i2 : Int64.int) (le : Clight.temp_env),
  Clight.eval_expr ge0 Clight.empty_env le Mem.empty
    (Clight.Ebinop Cop.Ogt (Clight.Econst_long i1 Lower.tint64)
                           (Clight.Econst_long i2 Lower.tint64) Lower.tint32)
    (Val.of_bool (Int64.cmp Cgt i1 i2)).
Proof.
  intros i1 i2 le. eapply Clight.eval_Ebinop.
  - apply eval_const64. - apply eval_const64. - apply sem_Ogt_long.
Qed.

Lemma eval_bin64_Ole : forall (i1 i2 : Int64.int) (le : Clight.temp_env),
  Clight.eval_expr ge0 Clight.empty_env le Mem.empty
    (Clight.Ebinop Cop.Ole (Clight.Econst_long i1 Lower.tint64)
                           (Clight.Econst_long i2 Lower.tint64) Lower.tint32)
    (Val.of_bool (Int64.cmp Cle i1 i2)).
Proof.
  intros i1 i2 le. eapply Clight.eval_Ebinop.
  - apply eval_const64. - apply eval_const64. - apply sem_Ole_long.
Qed.

Lemma eval_bin64_Oge : forall (i1 i2 : Int64.int) (le : Clight.temp_env),
  Clight.eval_expr ge0 Clight.empty_env le Mem.empty
    (Clight.Ebinop Cop.Oge (Clight.Econst_long i1 Lower.tint64)
                           (Clight.Econst_long i2 Lower.tint64) Lower.tint32)
    (Val.of_bool (Int64.cmp Cge i1 i2)).
Proof.
  intros i1 i2 le. eapply Clight.eval_Ebinop.
  - apply eval_const64. - apply eval_const64. - apply sem_Oge_long.
Qed.

Lemma eval_bin64_One : forall (i1 i2 : Int64.int) (le : Clight.temp_env),
  Clight.eval_expr ge0 Clight.empty_env le Mem.empty
    (Clight.Ebinop Cop.One (Clight.Econst_long i1 Lower.tint64)
                           (Clight.Econst_long i2 Lower.tint64) Lower.tint32)
    (Val.of_bool (Int64.cmp Cne i1 i2)).
Proof.
  intros i1 i2 le. eapply Clight.eval_Ebinop.
  - apply eval_const64. - apply eval_const64. - apply sem_One_long.
Qed.

Lemma eval_un64_Oneg : forall (i : Int64.int) (le : Clight.temp_env),
  Clight.eval_expr ge0 Clight.empty_env le Mem.empty
    (Clight.Eunop Cop.Oneg (Clight.Econst_long i Lower.tint64) Lower.tint64)
    (Vlong (Int64.neg i)).
Proof.
  intros i le. eapply Clight.eval_Eunop.
  - apply eval_const64. - apply sem_Oneg_long.
Qed.
