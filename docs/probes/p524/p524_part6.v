(* ---------- the div guards at the prim-node level ---------- *)

(* prim_guard_ok is exactly the guard conjunction eval_bin64_Odiv needs, stated
   syntactically for the prim_expr shape (true for every arm that is not a
   two-operand PDiv). *)
Definition prim_guard_ok (p : Prim) (vs : list Val) : bool :=
  match p, vs with
  | PDiv, a :: b :: nil =>
      negb (Int64.eq (z64 b) Int64.zero)
      && (negb (Int64.eq (z64 a) (Int64.repr Int64.min_signed))
          || negb (Int64.eq (z64 b) Int64.mone))
  | _, _ => true
  end.

(* A checked App node's guards follow from the kernel facts: on the canon path
   the operands are VInt (prim_total_res pins the shape), in range (range_ok of
   the operand list), and the PDiv divisor is nonzero; the table and bare paths
   contain no PDiv (Checks.v prim_args_ok / prim_bare_ok reject it), so there
   the guards are vacuous. *)
Lemma prim_guard_ok_canon : forall (p : Prim) (vs : list Val) (a : Expr),
  prim_operand_vals a = Some vs ->
  range_ok a = true ->
  ((all_int vs && prim_total_res p vs = true)
   \/ (exists es, a = TupE es /\ rets_of es = Some vs /\ prim_args_ok p vs = true)
   \/ (exists v, a = Ret v /\ prim_bare_ok p v = true)) ->
  prim_node_range_ok p vs = true ->
  prim_guard_ok p vs = true.
Proof.
  intros p vs a He Ha Hpath Hnode.
  destruct p; cbn [prim_guard_ok prim_args_ok prim_bare_ok]; try reflexivity.
  (* the only nontrivial arm is the two-operand PDiv *)
  destruct Hpath as [Hcanon | [Htab | Hbare]].
  - apply andb_and in Hcanon. destruct Hcanon as [Hall Htot].
    destruct vs as [ | v1 [ | v2 [ | v3 rest ] ] ];
    [ cbv [prim_total_res prim_total] in Htot; discriminate
    | destruct v1; cbv [prim_total_res prim_total] in Htot; discriminate
    | destruct v1 as [ | | | x | | | | | ]; destruct v2 as [ | | | y | | | | | ];
      cbv [prim_total_res prim_total] in Htot;
      try discriminate;
      destruct (Z.eqb y 0) eqn:Hy0; [ discriminate | ];
      (* vs = VInt x :: VInt y :: nil, Z.eqb y 0 = false *)
      destruct a; cbn [prim_operand_vals] in He; try discriminate;
      rewrite (rets_of_map_rets _ _ He) in Ha;
      cbn [range_ok map forallb] in Ha;
      apply andb_and in Ha; destruct Ha as [Hx Hrest];
      apply andb_and in Hrest; destruct Hrest as [Hy _];
      cbv [val_int64_ok] in Hx, Hy;
      cbv [prim_node_range_ok prim_total] in Hnode; rewrite Hy0 in Hnode;
      cbv [prim_node_range_ok prim_total] in Hnode;
      (* Hnode now states int64_range (x / y) = true *)
      cbn [prim_guard_ok z64];
      destruct (Int64.eq (Int64.repr y) Int64.zero) eqn:Ez;
      [ exfalso;
        assert (Hf : Int64.eq (Int64.repr y) Int64.zero = false)
          by (apply (int64_eq_zero_ne y Hy Hy0));
        rewrite Hf in Ez; discriminate Ez
      | cbn [negb orb andb];
        destruct (Int64.eq (Int64.repr x) (Int64.repr Int64.min_signed)) eqn:Ex;
        destruct (Int64.eq (Int64.repr y) Int64.mone) eqn:Ey;
        [ pose proof (int64_mone_guard x y Hx Hy Hnode Ex) as Hm;
          rewrite Ey in Hm; discriminate Hm
        | cbn [negb orb andb]; reflexivity
        | cbn [negb orb andb]; reflexivity
        | cbn [negb orb andb]; reflexivity ]
      ]
    | destruct v1; destruct v2; cbv [prim_total_res prim_total] in Htot; discriminate
    ].
  - destruct Htab as [es [Hea [Hrs Hargs]]].
    cbv [prim_args_ok] in Hargs. discriminate.
  - destruct Hbare as [v [Hev Hbare']].
    cbv [prim_bare_ok] in Hbare'. discriminate.
Qed.

(* The PDiv eval guards, packaged from prim_guard_ok so the per-arm dispatch in
   prim_expr_eval never nests brackets. *)
Lemma odiv_ready : forall (a b : Val) (le : Clight.temp_env),
  prim_guard_ok PDiv (a :: b :: nil) = true ->
  Clight.eval_expr ge0 Clight.empty_env le Mem.empty
    (Clight.Ebinop Cop.Odiv (Clight.Econst_long (z64 a) Lower.tint64)
                            (Clight.Econst_long (z64 b) Lower.tint64) Lower.tint64)
    (Vlong (Int64.divs (z64 a) (z64 b))).
Proof.
  intros a b le Hg.
  cbn [prim_guard_ok] in Hg. apply andb_and in Hg. destruct Hg as [Hg1 Hg2].
  apply (eval_bin64_Odiv (z64 a) (z64 b)).
  - destruct (Int64.eq (z64 b) Int64.zero) eqn:E1.
    + cbn [negb] in Hg1. discriminate Hg1.
    + reflexivity.
  - intro E2.
    destruct (Int64.eq (z64 a) (Int64.repr Int64.min_signed)) eqn:Ex.
    + cbn [negb orb] in Hg2.
      destruct (Int64.eq (z64 b) Int64.mone) eqn:E3.
      * cbn [negb] in Hg2. discriminate Hg2.
      * reflexivity.
    + discriminate E2.
Qed.

(* Every emitted prim_expr is realized by the matching eval lemma, with the
   Odiv guards taken from prim_guard_ok. *)
(* Every emitted prim_expr is realized by the matching eval lemma; the dispatch
   is per-prim explicit because Rocq 9.1 multi-goal match/solve dispatch silently
   under-covers.  Arms in Syntax.v Prim constructor order. *)
Lemma prim_expr_eval : forall (p : Prim) (vs : list Val) (le : Clight.temp_env),
  prim_guard_ok p vs = true ->
  Clight.eval_expr ge0 Clight.empty_env le Mem.empty
    (Lower.prim_expr p vs) (prim_clight p vs).
Proof.
  intros p vs le Hg.
  destruct p.
  - (* PAdd *)
    destruct vs as [ | a [ | b [ | c rest ] ] ]; cbn [Lower.prim_expr prim_clight];
    [ apply eval_const64 | apply eval_const64
    | rewrite !vconst_z64; apply eval_bin64_Oadd
    | apply eval_const64 ].
  - (* PSub *)
    destruct vs as [ | a [ | b [ | c rest ] ] ]; cbn [Lower.prim_expr prim_clight];
    [ apply eval_const64 | apply eval_const64
    | rewrite !vconst_z64; apply eval_bin64_Osub
    | apply eval_const64 ].
  - (* PMul *)
    destruct vs as [ | a [ | b [ | c rest ] ] ]; cbn [Lower.prim_expr prim_clight];
    [ apply eval_const64 | apply eval_const64
    | rewrite !vconst_z64; apply eval_bin64_Omul
    | apply eval_const64 ].
  - (* PDiv *)
    destruct vs as [ | a [ | b [ | c rest ] ] ]; cbn [Lower.prim_expr prim_clight];
    [ apply eval_const64 | apply eval_const64
    | rewrite !vconst_z64; apply (odiv_ready a b le Hg)
    | apply eval_const64 ].
  - (* PNeg *)
    destruct vs as [ | a [ | b [ | c rest ] ] ]; cbn [Lower.prim_expr prim_clight];
    [ apply eval_const64
    | rewrite vconst_z64; apply eval_un64_Oneg
    | apply eval_const64 | apply eval_const64 ].
  - (* PPls: placeholder arms only *)
    destruct vs as [ | a [ | b [ | c rest ] ] ]; cbn [Lower.prim_expr prim_clight];
    [ apply eval_const64 | apply eval_const64 | apply eval_const64 | apply eval_const64 ].
  - (* PGt *)
    destruct vs as [ | a [ | b [ | c rest ] ] ]; cbn [Lower.prim_expr prim_clight];
    [ apply eval_const64 | apply eval_const64
    | rewrite !vconst_z64; apply eval_bin64_Ogt
    | apply eval_const64 ].
  - (* PLt *)
    destruct vs as [ | a [ | b [ | c rest ] ] ]; cbn [Lower.prim_expr prim_clight];
    [ apply eval_const64 | apply eval_const64
    | rewrite !vconst_z64; apply eval_bin64_Olt
    | apply eval_const64 ].
  - (* PGEq *)
    destruct vs as [ | a [ | b [ | c rest ] ] ]; cbn [Lower.prim_expr prim_clight];
    [ apply eval_const64 | apply eval_const64
    | rewrite !vconst_z64; apply eval_bin64_Oge
    | apply eval_const64 ].
  - (* PLEq *)
    destruct vs as [ | a [ | b [ | c rest ] ] ]; cbn [Lower.prim_expr prim_clight];
    [ apply eval_const64 | apply eval_const64
    | rewrite !vconst_z64; apply eval_bin64_Ole
    | apply eval_const64 ].
  - (* PNEq *)
    destruct vs as [ | a [ | b [ | c rest ] ] ]; cbn [Lower.prim_expr prim_clight];
    [ apply eval_const64 | apply eval_const64
    | rewrite !vconst_z64; apply eval_bin64_One
    | apply eval_const64 ].
  - (* PIsInt: placeholder arms only *)
    destruct vs as [ | a [ | b [ | c rest ] ] ]; cbn [Lower.prim_expr prim_clight];
    [ apply eval_const64 | apply eval_const64 | apply eval_const64 | apply eval_const64 ].
  - (* PIsBool: placeholder arms only *)
    destruct vs as [ | a [ | b [ | c rest ] ] ]; cbn [Lower.prim_expr prim_clight];
    [ apply eval_const64 | apply eval_const64 | apply eval_const64 | apply eval_const64 ].
  - (* PIsUnit: placeholder arms only *)
    destruct vs as [ | a [ | b [ | c rest ] ] ]; cbn [Lower.prim_expr prim_clight];
    [ apply eval_const64 | apply eval_const64 | apply eval_const64 | apply eval_const64 ].
  - (* PCons: placeholder arms only *)
    destruct vs as [ | a [ | b [ | c rest ] ] ]; cbn [Lower.prim_expr prim_clight];
    [ apply eval_const64 | apply eval_const64 | apply eval_const64 | apply eval_const64 ].
  - (* PCons2: placeholder arms only *)
    destruct vs as [ | a [ | b [ | c rest ] ] ]; cbn [Lower.prim_expr prim_clight];
    [ apply eval_const64 | apply eval_const64 | apply eval_const64 | apply eval_const64 ].
  - (* PDotDot: placeholder arms only *)
    destruct vs as [ | a [ | b [ | c rest ] ] ]; cbn [Lower.prim_expr prim_clight];
    [ apply eval_const64 | apply eval_const64 | apply eval_const64 | apply eval_const64 ].
  - (* PArrLen: placeholder arms only *)
    destruct vs as [ | a [ | b [ | c rest ] ] ]; cbn [Lower.prim_expr prim_clight];
    [ apply eval_const64 | apply eval_const64 | apply eval_const64 | apply eval_const64 ].
Qed.
