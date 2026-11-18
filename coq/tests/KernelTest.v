(* Timbda-0 kernel tests (M0 gate of docs/PLAN.md § 5: "T1 for ~12 core rules").
   Four families:
   A. every discharged T1 row instantiates its `Rew` ctor (ctor <-> soundness
      pair per rule); plus witnesses that the deferred rows' ctors are
      inhabited (their RewSound_* statements are M3 targets, Denotation.v header);
   B. RewSound_* applied to concrete kernel terms (fuel transfers as stated);
   C. rw_step context-closure witnesses and the br2 candidate-set bridge;
   D. the Eval.v head table: selection, the Fig. 9 taxonomy agreement
      (stuck lambda/variable pairs, lines 441-445), and normalization probes.
   Zero `Admitted` in the kernel theory, and Timbda introduces no axioms; every
   `≈`-level lemma inherits exactly one stdlib axiom, `Eqdep.Eq_rect_eq.eq_rect_eq`,
   from the vendored ctrees Program machinery (docs/RULES-AUDIT.md § 6); the Print
   Assumptions commands at the end of this file print that status at build time.

   Constructor witnesses are written with `@`-prefixes so their arity never
   depends on Coq's automatic implicit-argument insertion. *)

From Stdlib Require Import ZArith List.
(* No direct Stdlib.Bool import: its level-40 `&&&` notation clashes with the
   ctrees chain (see Denotation.v header); Bool arrives transitively.
   `Z.neq` witnesses below use `discriminate` on the pinned integer literals
   rather than `lia`, to keep this file's notation environment identical to
   Denotation.v's. *)
From CTree Require Import CTree Eq.
From CTree.Eq Require Import WBisim.
Import WBisimNotations.
Import ListNotations.
Import CTreeNotations.
Local Open Scope ctree_scope.

Require Import Timbda.Syntax Timbda.Rewriting Timbda.Semantics
                Timbda.Denotation Timbda.Eval.

(* ---------- A. ctor <-> discharged-rule pairs ---------- *)

Example ctor_Seq      : Rew (Seq (Ret VUnit) Fail) Fail := @RewSeq VUnit Fail.
Example ctor_Norm1    : Rew (Unify (Ret VUnit) (Seq Fail Fail))
                            (Seq Fail (Unify (Ret VUnit) Fail)) :=
  @RewNorm1 VUnit Fail Fail.
Example ctor_Norm2    : Rew (Unify (Ret VUnit) (Unify Fail Fail))
                            (Seq (Unify (Ret VUnit) Fail) (Unify (Ret VUnit) Fail)) :=
  @RewNorm2 VUnit Fail Fail.
Example ctor_Norm3    : Rew (Unify (Seq Fail Fail) Fail)
                            (Seq Fail (Unify Fail Fail)) :=
  @RewNorm3 Fail Fail Fail.
Example ctor_Norm4    : Rew (Unify (Unify (Ret VUnit) Fail) Fail)
                            (Seq (Unify (Ret VUnit) Fail) (Unify (Ret VUnit) Fail)) :=
  @RewNorm4 VUnit Fail Fail.
Example ctor_Norm5    : Rew (Seq (Seq Fail Fail) Fail)
                            (Seq Fail (Seq Fail Fail)) :=
  @RewNorm5 Fail Fail Fail.
Example ctor_EqK1     : Rew (Unify (Ret (VInt 42)) (Ret (VInt 42))) (Ret (VInt 42)) :=
  @RewEqK1 (VInt 42) eq_refl.
Example ctor_EqK2     : Rew (Unify (Ret (VInt 1)) (Ret (VInt 2))) Fail :=
  @RewEqK2 (VInt 1) (VInt 2) eq_refl eq_refl ltac:(intros Heq; discriminate).
Example ctor_EqTup2   : Rew (Unify (Ret (VTup [VUnit])) (Ret (VTup [VUnit; VUnit]))) Fail :=
  @RewEqTup2 [VUnit] [VUnit; VUnit] ltac:(intros H; cbn [length] in H; discriminate).
Example ctor_EqFail   : Rew (Unify (Ret VUnit) (Ret (VInt 3))) Fail :=
  @RewEqFail VUnit (VInt 3) eq_refl.
Example ctor_BetaT0   : Rew (App (Ret (VTup nil)) (TupE [Ret VTrue])) Fail :=
  @RewBetaT0 (TupE [Ret VTrue]).
Example ctor_Add      : Rew (prim_app PAdd [Ret (VInt 7); Ret (VInt 35)]) (Ret (VInt 42)) :=
  @RewAdd 7 35.
Example ctor_Gt1      : Rew (prim_app PGt [Ret (VInt 5); Ret (VInt 2)]) (Ret (VInt 5)) :=
  @RewGt1 5 2 eq_refl.
Example ctor_Gt2      : Rew (prim_app PGt [Ret (VInt 2); Ret (VInt 5)]) Fail :=
  @RewGt2 2 5 eq_refl.
Example ctor_IsInt1   : Rew (prim_app PIsInt [Ret (VInt 5)]) (Ret (VInt 5)) :=
  @RewIsInt1 5.
Example ctor_IsInt2   : Rew (prim_app PIsInt [Ret VTrue]) Fail :=
  @RewIsInt2 VTrue eq_refl.
Example ctor_Cons     : Rew (prim_app PCons [Ret VTrue; Ret (VTup [VUnit])])
                            (Ret (VTup [VTrue; VUnit])) :=
  @RewCons VTrue [VUnit].
Example ctor_DotDot   : Rew (prim_app PDotDot [Ret (VInt 1); Ret (VInt 3)])
                            (Ret (VTup (map VInt (seq_z 1 3)))) :=
  @RewDotDot 1 3.
Example ctor_Prim     : Rew (prim_app PAdd [Ret (VInt 7); Ret (VInt 35)]) (Ret (VInt 42)) :=
  @RewPrim PAdd [VInt 7; VInt 35] (VInt 42) eq_refl.
Example ctor_PrimFail : Rew (prim_app PIsInt [Ret VTrue]) Fail :=
  @RewPrimFail PIsInt [VTrue] eq_refl.
Example ctor_HpAlpha  : Rew (Block [(TAny, Some VUnit)] Fail) (Block [(TAny, Some VUnit)] Fail) :=
  @RewHpAlpha [(TAny, Some VUnit)] Fail.
Example ctor_LamAlpha : Rew (Ret (VLam TAny (Glob xH))) (Ret (VLam TAny (Glob xH))) :=
  @RewLamAlpha TAny (Glob xH).

(* Deferred-row ctor witnesses (soundness statements are M3 targets). *)

Example ctor_BetaL :
  Rew (App (Ret (VLam TAny (Glob xH))) (Ret VUnit))
      (Block [(TAny, @None Val)] (Seq (Unify (Ret (VVar 0)) (Ret VUnit)) (Glob xH))) :=
  @RewBetaL TAny (Glob xH) (Ret VUnit).

Example ctor_BetaT :
  Rew (App (Ret (VTup [VUnit; VTrue])) (Ret VUnit))
      (Block [(@TAny, @None Val)]
             (Seq (Unify (Ret (VVar 0)) (Ret VUnit))
                  (Choice (Block nil (Seq (Unify (Ret (VVar 0)) (Ret (VInt 0)))
                                          (Ret (liftV 1 0 VUnit))))
                          (Block nil (Seq (Unify (Ret (VVar 0)) (Ret (VInt 1)))
                                          (Ret (liftV 1 0 VTrue))))))) :=
  @RewBetaT [VUnit; VTrue] (Ret VUnit) ltac:(intros H; discriminate).

Example ctor_EqTup1 :
  Rew (Unify (Ret (VTup [VUnit])) (Ret (VTup [VUnit])))
      (Seq (Unify (Ret VUnit) (Ret VUnit)) (Ret (VTup [VUnit]))) :=
  @RewEqTup1 [VUnit] [VUnit] eq_refl.

Example ctor_Subst :
  Rew (Block [(TAny, Some VUnit)] (Ret (VVar 0)))
      (Block [(TAny, Some VUnit)] (Ret VUnit)) :=
  @RewSubst [(TAny, Some VUnit)] 0 VUnit HS_Hole eq_refl.

Example ctor_Gc1 :
  (* dropSlot of the only slot + shrinkE of the body: the RHS normalizes to the
     empty-block term `Block [] Fail` (docs/DESIGN-NOTES.md, Fig. 8 GC1). *)
  Rew (Block [(TAny, Some VUnit)] Fail) (Block [] Fail) :=
  @RewGc1 [(TAny, Some VUnit)] 0 Fail
    ltac:(intros H; cbv in H; discriminate)
    ltac:(cbv; reflexivity).

Example ctor_PromoteL :
  Rew (Block [(TAny, @None Val)] (Unify (Ret (VVar 0)) (Ret VUnit)))
      (Block [(TAny, Some VUnit)] (Ret VUnit)) :=
  @RewPromoteL [(TAny, @None Val)] 0 HC_Hole VUnit
    ltac:(cbv; reflexivity)
    ltac:(cbv; reflexivity)
    ltac:(cbv; reflexivity).

Example ctor_PromoteR :
  Rew (Block [(TAny, @None Val)] (Unify (Ret VUnit) (Ret (VVar 0))))
      (Block [(TAny, Some VUnit)] (Ret VUnit)) :=
  @RewPromoteR [(TAny, @None Val)] 0 HC_Hole VUnit
    ltac:(cbv; reflexivity)
    ltac:(cbv; reflexivity)
    ltac:(cbv; reflexivity).

Example ctor_IterFail  : Rew (Iter IAll (Block nil Fail) Fail) Fail :=
  @RewIterFail IAll nil HC_Hole Fail.
Example ctor_IterChoice :
  Rew (Iter IAll (Block nil (Choice Fail Fail)) Fail)
      (Iter IAll (Block nil (Block nil Fail))
              (Iter IAll (Block nil (Block nil Fail)) Fail)) :=
  @RewIterChoice IAll nil HC_Hole Fail Fail Fail
    ltac:(cbv; reflexivity).
Example ctor_IterIf    : Rew (Iter IIf (Block nil (Ret (VDelay Fail))) Fail)
                             (Block nil (Block nil Fail)) :=
  @RewIterIf nil Fail Fail.
Example ctor_IterAll   : Rew (Iter IAll (Block nil (Ret VUnit)) Fail)
                             (prim_app PCons [Block nil (Ret VUnit); Fail]) :=
  @RewIterAll nil VUnit Fail.
Example ctor_IterFor   : Rew (Iter IFor (Block nil (Ret VUnit)) Fail)
                             (Block [(@TAny, @None Val)]
                                    (prim_app PCons2
                                      [TupE [Ret (VVar 0); Block nil (Ret VUnit)]; Fail])) :=
  @RewIterFor nil VUnit Fail.

(* ---------- B. RewSound_* applied to concrete kernel terms (discharged rows) *)

Example sound_Seq :
  denE nil (Seq (Ret VUnit) Fail) (S (S 2)) ≈ denE nil Fail (S 2) :=
  RewSound_Seq VUnit Fail nil 2.

Example sound_BetaT0 :
  denE nil (App (Ret (VTup nil)) (TupE [Ret VTrue])) (S (S 1))
    ≈ denE nil Fail (S (S 1)) :=
  RewSound_BetaT0 (TupE [Ret VTrue]) nil 1.

Example sound_EqK1_int :
  denE nil (Unify (Ret (VInt 42)) (Ret (VInt 42))) (S (S 8))
    ≈ denE nil (Ret (VInt 42)) (S (S 8)) :=
  RewSound_EqK1 (VInt 42) nil 8 eq_refl.

Example sound_EqK1_unit :
  denE nil (Unify (Ret VUnit) (Ret VUnit)) (S (S 8))
    ≈ denE nil (Ret VUnit) (S (S 8)) :=
  RewSound_EqK1 VUnit nil 8 eq_refl.

Example sound_EqK1_false :
  denE nil (Unify (Ret VFalse) (Ret VFalse)) (S (S 8))
    ≈ denE nil (Ret VFalse) (S (S 8)) :=
  RewSound_EqK1 VFalse nil 8 eq_refl.

Example sound_EqK2_int :
  denE nil (Unify (Ret (VInt 1)) (Ret (VInt 2))) (S (S 3))
    ≈ denE nil Fail (S (S 3)) :=
  RewSound_EqK2 (VInt 1) (VInt 2) nil 3 eq_refl eq_refl
    ltac:(intros Heq; discriminate).

Example sound_EqK2_cross :
  denE nil (Unify (Ret VTrue) (Ret (VInt 1))) (S (S 3))
    ≈ denE nil Fail (S (S 3)) :=
  RewSound_EqK2 VTrue (VInt 1) nil 3 eq_refl eq_refl
    ltac:(intros Heq; discriminate).

Example sound_EqTup2 :
  denE nil (Unify (Ret (VTup [VUnit])) (Ret (VTup [VUnit; VUnit]))) (S (S 1))
    ≈ denE nil Fail (S (S 1)) :=
  RewSound_EqTup2 [VUnit] [VUnit; VUnit] nil 1
    ltac:(intros Heq; cbn [length] in Heq; discriminate).

Example sound_EqFail :
  denE nil (Unify (Ret VUnit) (Ret (VInt 3))) (S (S 1))
    ≈ denE nil Fail (S (S 1)) :=
  RewSound_EqFail VUnit (VInt 3) nil 1 eq_refl.

Example sound_Add :
  denE nil (prim_app PAdd [Ret (VInt 7); Ret (VInt 35)]) (S (S (S (S (S 2)))))
    ≈ denE nil (Ret (VInt 42)) (S (S (S (S (S 2))))) :=
  RewSound_Add 7 35 nil 2.

Example sound_Gt1 :
  denE nil (prim_app PGt [Ret (VInt 5); Ret (VInt 2)]) (S (S (S (S (S 2)))))
    ≈ denE nil (Ret (VInt 5)) (S (S (S (S (S 2))))) :=
  RewSound_Gt1 5 2 nil 2 eq_refl.

Example sound_Gt2 :
  denE nil (prim_app PGt [Ret (VInt 2); Ret (VInt 5)]) (S (S (S (S (S 2)))))
    ≈ denE nil Fail (S (S (S (S (S 2))))) :=
  RewSound_Gt2 2 5 nil 2 eq_refl.

Example sound_IsInt1 :
  denE nil (prim_app PIsInt [Ret (VInt 5)]) (S (S (S (S 1))))
    ≈ denE nil (Ret (VInt 5)) (S (S (S (S 1)))) :=
  RewSound_IsInt1 5 nil 1.

Example sound_IsInt2 :
  denE nil (prim_app PIsInt [Ret VTrue]) (S (S (S (S 1))))
    ≈ denE nil Fail (S (S (S (S 1)))) :=
  RewSound_IsInt2 VTrue nil 1 eq_refl.

Example sound_Cons :
  denE nil (prim_app PCons [Ret VTrue; Ret (VTup [VUnit])]) (S (S (S (S (S 2)))))
    ≈ denE nil (Ret (VTup [VTrue; VUnit])) (S (S (S (S (S 2))))) :=
  RewSound_Cons VTrue [VUnit] nil 2.

Example sound_DotDot :
  denE nil (prim_app PDotDot [Ret (VInt 1); Ret (VInt 3)]) (S (S (S (S (S 2)))))
    ≈ denE nil (Ret (VTup (map VInt (seq_z 1 3)))) (S (S (S (S (S 2))))) :=
  RewSound_DotDot 1 3 nil 2.

(* PrimSchema rows, at the two arities the kernel prim_total table uses.  The
   hypothesis is the closed instance (Denotation.v convention G1); `eq_refl`
   checks it because every value here is already a literal. *)
Example t1_prim1_isint :
  denE nil (prim_app PIsInt [Ret (VInt 5)]) (S (S (S (S 1))))
    ≈ denE nil (Ret (VInt 5)) (S (S (S (S 1)))) :=
  @RewSound_Prim1 PIsInt (VInt 5) (VInt 5) nil 1 eq_refl.

Example t1_prim2_add :
  denE nil (prim_app PAdd [Ret (VInt 7); Ret (VInt 35)]) (S (S (S (S (S 2)))))
    ≈ denE nil (Ret (VInt 42)) (S (S (S (S (S 2))))) :=
  @RewSound_Prim2 PAdd (VInt 7) (VInt 35) (VInt 42) nil 2 eq_refl.

Example t1_prim2_dotdot :
  denE nil (prim_app PDotDot [Ret (VInt 1); Ret (VInt 3)]) (S (S (S (S (S 2)))))
    ≈ denE nil (Ret (VTup (map VInt (seq_z 1 3)))) (S (S (S (S (S 2))))) :=
  @RewSound_Prim2 PDotDot (VInt 1) (VInt 3) (VTup (map VInt (seq_z 1 3))) nil 2 eq_refl.

Example t1_primfail1_isint :
  denE nil (prim_app PIsInt [Ret VTrue]) (S (S (S (S 1))))
    ≈ denE nil Fail (S (S (S (S 1)))) :=
  @RewSound_PrimFail1 PIsInt VTrue nil 1 eq_refl.

Example t1_primfail2_gt :
  denE nil (prim_app PGt [Ret (VInt 2); Ret (VInt 5)]) (S (S (S (S (S 2)))))
    ≈ denE nil Fail (S (S (S (S (S 2))))) :=
  @RewSound_PrimFail2 PGt (VInt 2) (VInt 5) nil 2 eq_refl.

Example sound_HpAlpha :
  denE nil (Block [(TAny, Some VUnit)] Fail) 4 ≈ denE nil (Block [(TAny, Some VUnit)] Fail) 4 :=
  RewSound_HpAlpha [(TAny, Some VUnit)] Fail nil 4.

Example sound_LamAlpha :
  denE nil (Ret (VLam TAny (Glob xH))) 4 ≈ denE nil (Ret (VLam TAny (Glob xH))) 4 :=
  RewSound_LamAlpha TAny (Glob xH) nil 4.

(* ---------- C. choice = br2 (candidate-set bridge, T2 seeds) ---------- *)

Example choice_denote :
  denE nil (Choice Fail (Unify (Ret VUnit) (Ret VUnit))) (S 3)
    ≈ br2 (denE nil Fail 3) (denE nil (Unify (Ret VUnit) (Ret VUnit)) 3) :=
  Denote_Choice Fail (Unify (Ret VUnit) (Ret VUnit)) nil 3.

Example choice_comm : forall (t u : ctree void1 B2 SResult), br2 t u ≈ br2 u t :=
  Br2_Commut_W.

Example choice_assoc : forall (t u v : ctree void1 B2 SResult),
  br2 (br2 t u) v ≈ br2 t (br2 u v) := Br2_Assoc_W.

Example choice_idem : forall (t : ctree void1 B2 SResult), br2 t t ≈ t :=
  Br2_Idem_W.

Example choice_stuck_unit : forall (t : ctree void1 B2 SResult), br2 Stuck t ≈ t :=
  Br2_StuckL_W.

(* ---------- rw_step context-closure witnesses ---------- *)

Example rw_here_demo : rewrites (Seq (Ret VUnit) Fail) Fail :=
  @rw_here (Seq (Ret VUnit) Fail) Fail (@RewSeq VUnit Fail).

Example rw_ctx_demo :
  rewrites (Seq (Seq (Ret VUnit) Fail) Fail) (Seq Fail Fail) :=
  @rw_ctx (HC_SeqR HC_Hole Fail) (Seq (Ret VUnit) Fail) Fail rw_here_demo.

Example rw_blk_demo :
  rewrites (Block [(TAny, Some VUnit)] (Seq (Ret VTrue) Fail))
           (Block [(TAny, Some VUnit)] Fail) :=
  @rw_blk [(TAny, Some VUnit)] (Seq (Ret VTrue) Fail) Fail
    (@rw_here (Seq (Ret VTrue) Fail) Fail (@RewSeq VTrue Fail)).

(* ---------- D. Eval head table probes (evaluation strategy) ---------- *)

Example head_seq   : head_redex (Seq (Ret VUnit) Fail) = Some (R_Seq, Fail).
Proof. reflexivity. Qed.
Example head_norm5 : head_redex (Seq (Seq Fail Fail) Fail) =
  Some (R_Norm5, Seq Fail (Seq Fail Fail)).
Proof. reflexivity. Qed.
Example head_eqk2  : head_redex (Unify (Ret (VInt 1)) (Ret (VInt 2))) = Some (R_EqK2, Fail).
Proof. reflexivity. Qed.
Example head_eqtup1 : head_redex (Unify (Ret (VTup [VUnit])) (Ret (VTup [VUnit]))) =
  Some (R_EqTup1, Seq (Unify (Ret VUnit) (Ret VUnit)) (Ret (VTup [VUnit]))).
Proof. reflexivity. Qed.
Example head_add   : head_redex (prim_app PAdd [Ret (VInt 7); Ret (VInt 35)]) =
  Some (R_Prim, Ret (VInt 42)).
Proof. reflexivity. Qed.
Example head_isint_fail : head_redex (prim_app PIsInt [Ret VTrue]) = Some (R_PrimFail, Fail).
Proof. reflexivity. Qed.
Example head_betat0 : head_redex (App (Ret (VTup nil)) Fail) = Some (R_BetaT0, Fail).
Proof. reflexivity. Qed.

(* Fig. 9 note (lines 441-445): lambda=lambda and var=var have no rule: *)
Example head_stuck_lam_lam :
  head_redex (Unify (Ret (VLam TAny (Glob xH))) (Ret (VLam TAny (Glob xH)))) = None.
Proof. reflexivity. Qed.
Example head_stuck_var_var :
  head_redex (Unify (Ret (VVar 3)) (Ret (VVar 3))) = None.
Proof. reflexivity. Qed.
Example head_stuck_delay_delay :
  head_redex (Unify (Ret (VDelay Fail)) (Ret (VDelay Fail))) = None.
Proof. reflexivity. Qed.
(* VUnit vs VInt is a *literal pair* (both sides take EqK2 in the head table);
   EqFail is what fires when a literal meets a non-literal root: *)
Example head_eqfail_unit_lam :
  head_redex (Unify (Ret VUnit) (Ret (VLam TAny (Glob xH)))) = Some (R_EqFail, Fail).
Proof. reflexivity. Qed.

Example norm_add : norm 10 (prim_app PAdd [Ret (VInt 7); Ret (VInt 35)]) = Ret (VInt 42).
Proof. reflexivity. Qed.
Example norm_seq_pair : norm 10 (Seq (Seq (Ret VUnit) (Ret VTrue)) Fail) = Fail.
Proof. reflexivity. Qed.
Example norm_beta_seq :
  norm 10 (App (Ret (VLam TAny (Glob xH))) (Ret VUnit))
    = Block [(TAny, @None Val)] (Seq (Unify (Ret (VVar 0)) (Ret VUnit)) (Glob xH)).
Proof. reflexivity. Qed.

(* ---------- axiom audit (build-time evidence) ---------- *)

Print Assumptions RewSound_Seq.
Print Assumptions RewSound_EqK1.
Print Assumptions RewSound_EqK2.
Print Assumptions RewSound_EqTup2.
Print Assumptions RewSound_EqFail.
Print Assumptions RewSound_Add.
Print Assumptions RewSound_Gt1.
Print Assumptions RewSound_Gt2.
Print Assumptions RewSound_IsInt1.
Print Assumptions RewSound_IsInt2.
Print Assumptions RewSound_Cons.
Print Assumptions RewSound_DotDot.
Print Assumptions RewSound_BetaT0.
Print Assumptions RewSound_HpAlpha.
Print Assumptions RewSound_LamAlpha.
Print Assumptions Br2_Commut_W.
(* Bind_Br2_Dist (the bind/br2 interchange IterChoice leans on) is deferred to
   M3 - see the note at the end of Denotation.v - so it is not audited here. *)
Print Assumptions RewSound_Prim1.
Print Assumptions RewSound_Prim2.
Print Assumptions RewSound_PrimFail1.
Print Assumptions RewSound_PrimFail2.
Print Assumptions Denote_Choice.
Print Assumptions Br2_Idem_W.
Print Assumptions Br2_Assoc_W.
Print Assumptions Br2_StuckL_W.
