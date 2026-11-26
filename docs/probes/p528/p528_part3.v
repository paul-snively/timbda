(* p528 part3 (rebuilt) - the kernel<->lowered correspondence (decision 10d),
   the exact corner denotation (beta fixed: cbv fires the bind chains - cbn in
   Rocq 9.1 is by-name and leaves the beta-redexes), and the T6 composition.
   SUPERSEDED 2026-11-26: this file's `denorm` full-cbv and its Leibniz-`=`
   corner statements do not compile at fuel 6 (cofix `subst` cannot be fired
   by any delta list); the landed spellings are `≅` plus the arm-equation
   machine - see p528_part4_corner_equ.v and README.md.

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
