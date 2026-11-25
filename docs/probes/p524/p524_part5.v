(* ---------- composition machinery over arbitrary temp envs ---------- *)

(* E0 ** E0 reduces to E0 by iota, so the goal is stated in the convertible
   (E0 ** E0) form first (change), and exec_Sseq_1 then unifies syntactically;
   le1/m1 (premise-only variables) are pinned by with.  Measured in p523e. *)
Lemma exec_seq_close (s1 s2 : Clight.statement) (le le1 le2 : Clight.temp_env) :
  Clight1.exec_stmt ge0 Clight.empty_env le Mem.empty s1 Events.E0 le1 Mem.empty
    ClightBigstep.Out_normal ->
  Clight1.exec_stmt ge0 Clight.empty_env le1 Mem.empty s2 Events.E0 le2 Mem.empty
    ClightBigstep.Out_normal ->
  Clight1.exec_stmt ge0 Clight.empty_env le Mem.empty (Clight.Ssequence s1 s2)
    Events.E0 le2 Mem.empty ClightBigstep.Out_normal.
Proof.
  intros H1 H2.
  change (Clight1.exec_stmt ge0 Clight.empty_env le Mem.empty
            (Clight.Ssequence s1 s2) (Events.E0 ** Events.E0) le2 Mem.empty
            ClightBigstep.Out_normal).
  apply ClightBigstep.exec_Sseq_1 with (le1 := le1) (m1 := Mem.empty); eauto.
Qed.

(* slot tempvars (slot i maps to #i+2) never name lower_res (= xH = #1) *)
Lemma lower_res_ne_slot : forall i : nat, Lower.lower_res <> Lower.slot_ident i.
Proof.
  intros i H. unfold Lower.slot_ident, Lower.lower_res in H.
  symmetry in H. apply (f_equal Z.pos) in H.
  rewrite Z2Pos.id in H; [lia|]. lia.
Qed.

Lemma get_slot_neutral : forall (i : nat) (x : val) (m : Clight.temp_env),
  PTree.get Lower.lower_res (PTree.set (Lower.slot_ident i) x m)
  = PTree.get Lower.lower_res m.
Proof.
  intros i x m. apply (PTree.gso (i := Lower.lower_res) (j := Lower.slot_ident i)).
  apply lower_res_ne_slot.
Qed.

Lemma last_val_ne_none : forall (v : Val) (w : list Val), last_val (v :: w) <> None.
Proof.
  intros v w H. revert v H.
  induction w as [| w0 w' IH]; intros v H; cbn [last_val] in H.
  - discriminate.
  - exfalso. apply (IH w0). exact H.
Qed.

(* TupE lowering: the sequence of Ssets, "last ret wins" *)
Lemma exec_rets_sets : forall (vs : list Val) (le : Clight.temp_env),
  exists le',
    Clight1.exec_stmt ge0 Clight.empty_env le Mem.empty
      (fold_right Clight.Ssequence Clight.Sskip
         (map (fun v => Clight.Sset Lower.lower_res (Lower.vconst v)) vs))
      Events.E0 le' Mem.empty ClightBigstep.Out_normal
    /\ PTree.get Lower.lower_res le' =
       match last_val vs with
       | Some v => Some (clight_of_val v)
       | None => PTree.get Lower.lower_res le
       end.
Proof.
  induction vs as [| v vs IH]; intros le.
  - exists le. split.
    + apply ClightBigstep.exec_Sskip.
    + reflexivity.
  - cbn [map fold_right].
    destruct (IH (PTree.set Lower.lower_res (clight_of_val v) le)) as [le' [Hexec Hget]].
    exists le'. split.
    + apply exec_seq_close with
        (le1 := PTree.set Lower.lower_res (clight_of_val v) le).
      * apply ClightBigstep.exec_Sset. apply eval_vconst_val.
      * exact Hexec.
    + cbn [last_val] in Hget |- *.
      destruct vs as [| v2 vs2].
      * cbn [last_val] in Hget. rewrite Hget. apply PTree.gss.
      * destruct (last_val (v2 :: vs2)) eqn:Hl.
        -- exact Hget.
        -- exfalso. apply (last_val_ne_none v2 vs2). exact Hl.
Qed.

(* Block prelude: only VInt slots emit an assignment (to a slot tempvar);
   lower_res is untouched. *)
Lemma exec_slots_prelude : forall (sl : list (Ty * option Val)) (le : Clight.temp_env),
  exists le',
    Clight1.exec_stmt ge0 Clight.empty_env le Mem.empty (Lower.slots_prelude sl)
      Events.E0 le' Mem.empty ClightBigstep.Out_normal
    /\ PTree.get Lower.lower_res le' = PTree.get Lower.lower_res le.
Proof.
  induction sl as [ | [t ov] sl IH ]; intros le.
  - exists le. split.
    + apply ClightBigstep.exec_Sskip.
    + reflexivity.
  - destruct ov as [v |]; cbn [Lower.slots_prelude].
    + (* the VInt slot is the only one that writes (to a slot tempvar); the
       other eight Val shapes fall into the Sskip arm of slots_prelude *)
      destruct v as [ | | | z | | | | | ] ; cbn [Lower.slots_prelude];
      [ destruct (IH le) as [le' [Hexec Hget]]; exists le'; split;
        [ apply exec_seq_close with (le1 := le);
          [ apply ClightBigstep.exec_Sskip | exact Hexec ]
        | exact Hget ]
      | destruct (IH le) as [le' [Hexec Hget]]; exists le'; split;
        [ apply exec_seq_close with (le1 := le);
          [ apply ClightBigstep.exec_Sskip | exact Hexec ]
        | exact Hget ]
      | destruct (IH le) as [le' [Hexec Hget]]; exists le'; split;
        [ apply exec_seq_close with (le1 := le);
          [ apply ClightBigstep.exec_Sskip | exact Hexec ]
        | exact Hget ]
      | destruct (IH (PTree.set (Lower.slot_ident (Datatypes.length sl))
                               (clight_of_val (VInt z)) le)) as [le' [Hexec Hget]];
        exists le'; split;
        [ apply exec_seq_close with
            (le1 := PTree.set (Lower.slot_ident (Datatypes.length sl))
                              (clight_of_val (VInt z)) le);
          [ apply ClightBigstep.exec_Sset; apply eval_vconst_val | exact Hexec ]
        | rewrite Hget; apply (get_slot_neutral (Datatypes.length sl)) ]
      | destruct (IH le) as [le' [Hexec Hget]]; exists le'; split;
        [ apply exec_seq_close with (le1 := le);
          [ apply ClightBigstep.exec_Sskip | exact Hexec ]
        | exact Hget ]
      | destruct (IH le) as [le' [Hexec Hget]]; exists le'; split;
        [ apply exec_seq_close with (le1 := le);
          [ apply ClightBigstep.exec_Sskip | exact Hexec ]
        | exact Hget ]
      | destruct (IH le) as [le' [Hexec Hget]]; exists le'; split;
        [ apply exec_seq_close with (le1 := le);
          [ apply ClightBigstep.exec_Sskip | exact Hexec ]
        | exact Hget ]
      | destruct (IH le) as [le' [Hexec Hget]]; exists le'; split;
        [ apply exec_seq_close with (le1 := le);
          [ apply ClightBigstep.exec_Sskip | exact Hexec ]
        | exact Hget ]
      | destruct (IH le) as [le' [Hexec Hget]]; exists le'; split;
        [ apply exec_seq_close with (le1 := le);
          [ apply ClightBigstep.exec_Sskip | exact Hexec ]
        | exact Hget ]
      ].
    + destruct (IH le) as [le' [Hexec Hget]].
      exists le'. split.
      * apply exec_seq_close with (le1 := le).
        -- apply ClightBigstep.exec_Sskip.
        -- exact Hexec.
      * exact Hget.
Qed.
