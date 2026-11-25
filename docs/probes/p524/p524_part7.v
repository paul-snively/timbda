(* ---------- T6: the checked fragment is realized from the empty context ---------- *)

(* The ws_expr guard is depth-indexed (a Block body is checked at `length
   slots + d`), so the induction carries the depth universally; the temp env is
   universally quantified because sequencing threads it.  The conjunction with
   the final-value characterization is decision 10's reading, with lower_final
   as the computable claim. *)
Theorem T6_exec_ws : forall (e : Expr) (d : nat) (le : Clight.temp_env),
  ws_expr d e = true -> det_struct e = true -> range_ok e = true ->
  exists le',
    Clight1.exec_stmt ge0 Clight.empty_env le Mem.empty (clight_of (Lower.lower e))
      Events.E0 le' Mem.empty ClightBigstep.Out_normal
    /\ PTree.get Lower.lower_res le' = lower_final e (PTree.get Lower.lower_res le).
Proof.
  (* Constructor order per Syntax.v: Ret Glob App TupE Seq Unify Choice Fail
     Block Iter; the arm skeletons mirror T7_no_switch_ws (Lower.v). *)
  induction e as [v | gid | f IHf a IHav | es _ | s1 IHs1 s2 IHs2
                  | u1 IHu1 u2 IHu2 | c1 IHc1 c2 IHc2 | | sl body0 IHbody
                  | ic0 b0 IHb r0 IHr];
    intros d le Hw Hd Hr.
  - (* Ret: the Sset writes the value, eval_vconst_val mirrors vconst *)
    cbn [lower clight_of lower_final].
    exists (PTree.set Lower.lower_res (clight_of_val v) le); split.
    + apply ClightBigstep.exec_Sset. apply eval_vconst_val.
    + apply PTree.gss.
  - (* Glob: bans_okE = false *)
    apply det_struct_components in Hd. destruct Hd as [Hb [Hc [Hu [Ha Ht]]]].
    cbn [bans_okE] in Hb. discriminate.
  - (* App: the checked node shape (app_node_ok_shape) is exactly the arm
       prim_expr/prim_clight realize, with the kernel guards (PDiv) transferred
       by prim_guard_ok_canon *)
    apply det_struct_components in Hd. destruct Hd as [Hb [Hc [Hu [Ha Ht]]]].
    cbn [apps_okE] in Ha. apply andb3_and in Ha. destruct Ha as [Ha1 [Ha2 Ha3]].
    destruct (app_node_ok_shape _ _ Ha1) as [p [vs [Hf [Hvs Hpath]]]].
    cbn [range_ok] in Hr. rewrite Hf in Hr. rewrite Hvs in Hr. cbn [range_ok] in Hr.
    apply andb_and in Hr. destruct Hr as [Hbase Hnode].
    apply andb_and in Hbase. destruct Hbase as [Hrf Hra].
    assert (Hg : prim_guard_ok p vs = true).
    { apply (prim_guard_ok_canon p vs a Hvs Hra Hpath Hnode). }
    cbn [lower clight_of]. rewrite Hf. rewrite Hvs.
    cbn [Lower.prim_head prim_operand_vals lower_final].
    exists (PTree.set Lower.lower_res (prim_clight p vs) le); split.
    + apply ClightBigstep.exec_Sset. apply (prim_expr_eval p vs le Hg).
    + cbn [Lower.prim_head prim_operand_vals lower_final].
      rewrite Hvs.
      cbn [Lower.prim_head prim_operand_vals lower_final].
      apply PTree.gss.
  - (* TupE: tup_node_ok pins rets_of = Some; exec_rets_sets runs the Sset
       chain with "last ret wins" *)
    apply det_struct_components in Hd. destruct Hd as [Hb [Hc [Hu [Ha Ht]]]].
    cbn [tup_rets_okE] in Ht. apply andb_and in Ht. destruct Ht as [Ht1 Ht2].
    destruct (tup_node_ok_rets _ Ht1) as [vs Hrs].
    cbn [lower clight_of lower_final rets_of last_val].
    rewrite Hrs.
    cbn [lower clight_of lower_final rets_of last_val].
    apply (exec_rets_sets vs le).
  - (* Seq: both halves carry their guards down; exec_seq_close composes *)
    apply det_struct_components in Hd. destruct Hd as [Hb [Hc [Hu [Ha Ht]]]].
    cbn [ws_expr] in Hw. cbn [bans_okE] in Hb; cbn [blocks_closed_okE] in Hc;
    cbn [unify_okE] in Hu; cbn [apps_okE] in Ha; cbn [tup_rets_okE] in Ht.
    cbn [range_ok] in Hr.
    apply andb_and in Hw. destruct Hw as [Hw1 Hw2].
    apply andb_and in Hb. destruct Hb as [Hb1 Hb2].
    apply andb_and in Hc. destruct Hc as [Hc1 Hc2].
    apply andb_and in Hu. destruct Hu as [Hu1 Hu2].
    apply andb_and in Ha. destruct Ha as [Ha1 Ha2].
    apply andb_and in Ht. destruct Ht as [Ht1 Ht2].
    apply andb_and in Hr. destruct Hr as [Hr1 Hr2].
    destruct (IHs1 d le Hw1 (det_struct_mk _ Hb1 Hc1 Hu1 Ha1 Ht1) Hr1)
      as [le1 [Hex1 Hfin1]].
    destruct (IHs2 d le1 Hw2 (det_struct_mk _ Hb2 Hc2 Hu2 Ha2 Ht2) Hr2)
      as [le2 [Hex2 Hfin2]].
    exists le2; split.
    + cbn [lower clight_of].
      apply exec_seq_close with (le1 := le1); [exact Hex1 | exact Hex2].
    + cbn [lower_final]. rewrite Hfin2. rewrite Hfin1. reflexivity.
  - (* Unify: eq_pair_ok = true emits Sskip; lower_final passes the value through *)
    apply det_struct_components in Hd. destruct Hd as [Hb [Hc [Hu [Ha Ht]]]].
    cbn [unify_okE] in Hu. apply andb3_and in Hu. destruct Hu as [Hu1 [Hu2 Hu3]].
    cbn [lower clight_of]. rewrite Hu1. cbn [lower clight_of lower_final].
    exists le; split.
    + apply ClightBigstep.exec_Sskip.
    + reflexivity.
  - (* Choice: bans_okE = false *)
    apply det_struct_components in Hd. destruct Hd as [Hb [Hc [Hu [Ha Ht]]]].
    cbn [bans_okE] in Hb. discriminate.
  - (* Fail: bans_okE = false *)
    apply det_struct_components in Hd. destruct Hd as [Hb [Hc [Hu [Ha Ht]]]].
    cbn [bans_okE] in Hb. discriminate.
  - (* Block: prelude writes only slot tempvars (exec_slots_prelude), the body
       is checked at length slots + d *)
    apply det_struct_components in Hd. destruct Hd as [Hb [Hc [Hu [Ha Ht]]]].
    cbn [ws_expr] in Hw. cbn [bans_okE] in Hb; cbn [blocks_closed_okE] in Hc.
    cbn [range_ok] in Hr.
    apply andb_and in Hw. destruct Hw as [_ Hw2].
    apply andb_and in Hb. destruct Hb as [_ Hb2].
    apply andb_and in Hc. destruct Hc as [_ Hc2].
    apply andb_and in Hr. destruct Hr as [_ Hr2].
    destruct (exec_slots_prelude sl le) as [le1 [Hpre1 Hpre2]].
    destruct (IHbody ((Datatypes.length sl) + d)%nat le1 Hw2
      (det_struct_mk _ Hb2 Hc2 Hu Ha Ht) Hr2) as [le2 [Hex2 Hfin2]].
    exists le2; split.
    + cbn [lower clight_of].
      apply exec_seq_close with (le1 := le1); [exact Hpre1 | exact Hex2].
    + cbn [lower_final]. rewrite Hfin2. rewrite Hpre2. reflexivity.
  - (* Iter: bans_okE = false *)
    apply det_struct_components in Hd. destruct Hd as [Hb [Hc [Hu [Ha Ht]]]].
    cbn [bans_okE] in Hb. discriminate.
Qed.

Theorem T6_exec : forall (e : Expr),
  det_check e = true -> range_ok e = true ->
  exists le',
    Clight1.exec_stmt ge0 Clight.empty_env le0 Mem.empty (clight_of (Lower.lower e))
      Events.E0 le' Mem.empty ClightBigstep.Out_normal
    /\ PTree.get Lower.lower_res le' = lower_final e (PTree.get Lower.lower_res le0).
Proof.
  intros e H Hrange. apply det_check_components in H. destruct H as [Hw Hd].
  apply (T6_exec_ws e 0 le0 Hw Hd Hrange).
Qed.
