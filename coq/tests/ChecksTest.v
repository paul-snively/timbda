(* Timbda-0 kernel: the M2 determinacy-checker mirror tests (docs/PLAN.md § 5 M2).

   WHAT THIS FILE IS.  Every `..._det` pin below is the Gallina-side mirror of one
   pinned verdict in tests/corpus/m2-det.texpr: the same expression, read by
   `det_check`, with the verdict the corpus derives from docs/PLAN.md § 8 decision 8
   (a)-(d) - a classification written by hand from the rule text on 2026-11-21
   (decision 6's ritual), never from evaluator output.  Group letters and case names
   are the corpus's own, so a red pin here is a readable disagreement between the
   checker and the corpus, not a test to be adjusted until it passes.

   Verdict tally, as the corpus states it: 17 accept (the nine Group A sign-matrix
   rows, Group C's EqK1 row, the five Group D out-of-order rows, and Group F's two
   `dotdot` span rows) and 12 reject (Group C's EqK2 row and its `norm4_revisit_partial`
   probe, Group E's five rejection witnesses, Group F's `iter_ifor_absent` absence claim,
   and the four Group G flex probes).  The rejects
   split the way decision 8 splits them: a `Choice`/`Fail`/`Iter` node (8b, node
   class), an open block (8a, fragment boundary), a `Div-0` or unequal-literal
   unification (8b, guaranteed stuck or guaranteed fail).

   Where the corpus also pins the evaluator's reading - the nine `norm` fields it states
   for an accepted row (Group A's first row, Group C's EqK1 row, the five Group D rows,
   Group F's two span rows) and the candidate bags of seven cases - the matching Gallina
   pins are
   here too (`..._norm`, `..._bag`).  A bag pin for an accepted term is discharged
   through `T4_eval`, so it is the theorem doing the work, not a computation of the
   bag; the two bag pins on *rejected* terms are plain evaluations of `cand_bag`,
   which is exactly what the corpus says they are: the evaluator's bag, not a
   determinate fragment.

   Fuel is the corpus default (`defaults fuel 24`).  No `Admitted` here, and the
   `Print Assumptions` block at the end prints the checker's own axiom status at
   build time: `T4_eval` is Gallina-only, `T4_sem` inherits the single stdlib axiom
   the vendored ctrees machinery contributes (docs/RULES-AUDIT.md § 6). *)

From Stdlib Require Import ZArith List.
Import ListNotations.

Require Import Timbda.Syntax Timbda.Eval Timbda.Checks Timbda.ChecksEval.

Local Open Scope bool_scope.

(* ---------- group A: div/sub/mul sign matrix - all nine det=yes ---------- *)

Definition e_div_pp : Expr :=
  App (Ret (VPrim PDiv)) (TupE [Ret (VInt 7); Ret (VInt 2)]).
Example arith_div_pos_pos_det : det_check e_div_pp = true.
Proof. reflexivity. Qed.
Example arith_div_pos_pos_norm : norm 24 e_div_pp = Ret (VInt 3).
Proof. reflexivity. Qed.

Example arith_div_pos_neg_det :
  det_check (App (Ret (VPrim PDiv)) (TupE [Ret (VInt 7); Ret (VInt (-2))])) = true.
Proof. reflexivity. Qed.

Example arith_div_neg_neg_halves_det :
  det_check (App (Ret (VPrim PDiv)) (TupE [Ret (VInt (-7)); Ret (VInt (-2))])) = true.
Proof. reflexivity. Qed.

Example arith_div_neg_pos_det :
  det_check (App (Ret (VPrim PDiv)) (TupE [Ret (VInt (-6)); Ret (VInt 4)])) = true.
Proof. reflexivity. Qed.

Example arith_div_neg_neg_quarter_det :
  det_check (App (Ret (VPrim PDiv)) (TupE [Ret (VInt (-6)); Ret (VInt (-4))])) = true.
Proof. reflexivity. Qed.

Example arith_div_exact_neg_det :
  det_check (App (Ret (VPrim PDiv)) (TupE [Ret (VInt (-8)); Ret (VInt (-2))])) = true.
Proof. reflexivity. Qed.

Example arith_sub_neg_neg_det :
  det_check (App (Ret (VPrim PSub)) (TupE [Ret (VInt (-5)); Ret (VInt (-3))])) = true.
Proof. reflexivity. Qed.

Example arith_mul_neg_pos_det :
  det_check (App (Ret (VPrim PMul)) (TupE [Ret (VInt 7); Ret (VInt (-4))])) = true.
Proof. reflexivity. Qed.

(* A unary prim written with a BARE operand (`pls -9`): G5's all-literals path (a)
   reads `[k]` exactly as `apply_c` does for a non-tuple argument, so this is an
   accept without `prim_bare_ok` - which is PNeg-only by design (Checks.v header on
   `prim_bare_ok`: unpacking a bare tuple operand is what makes path (b) unsafe). *)
Example arith_ppls_neg_identity_det :
  det_check (App (Ret (VPrim PPls)) (Ret (VInt (-9)))) = true.
Proof. reflexivity. Qed.

(* ---------- group C: the EqK1-only taxonomy, and the Norm4 revisit probe ------ *)

Example unify_seq_left_drop_eqk1_det :
  det_check (Seq (Ret (VInt 1)) (Unify (Ret (VInt 4)) (Ret (VInt 4)))) = true.
Proof. reflexivity. Qed.
Example unify_seq_left_drop_eqk1_norm :
  norm 24 (Seq (Ret (VInt 1)) (Unify (Ret (VInt 4)) (Ret (VInt 4)))) = Ret (VInt 4).
Proof. reflexivity. Qed.

(* EqK2: unequal literals.  G4 is the EqK1-only rule (`eq_pair_ok` demands
   `lit_eqb`), so a guaranteed fail is rejected at the gate, as decision 8b says it
   must be: T4's witness `sem e = ret (v, s')` has none. *)
Example unify_seq_left_drop_eqk2_det :
  det_check (Seq (Ret (VInt 1)) (Unify (Ret (VInt 4)) (Ret (VInt 5)))) = false.
Proof. reflexivity. Qed.

(* Norm4 at the root, then a re-visited root with no row: the corpus pins this as a
   PROBE (the fair semantics reaches fail; the one-pass rebuild leaves a partial
   shape).  The checker's reading is a rejection, and for the structural reason the
   corpus names: G4 reads a `Unify` pair as two literal values, and the left side
   here is a `Unify` node.  The partial normal form the evaluator does produce is the
   probe content, not a fragment claim. *)
Example norm4_revisit_partial_det :
  det_check (Unify (Unify (Ret (VInt 6))
                          (App (Ret (VPrim PAdd)) (TupE [Ret (VInt 2); Ret (VInt 3)])))
                (Ret (VInt 6))) = false.
Proof. reflexivity. Qed.

(* ---------- group D: out-of-order and independence - the T5 pins ------------- *)

Definition e_oo_left : Expr :=
  Seq (Seq (App (Ret (VPrim PAdd)) (TupE [Ret (VInt 2); Ret (VInt 3)]))
           (App (Ret (VPrim PMul)) (TupE [Ret (VInt 4); Ret (VInt 5)])))
      (App (Ret (VPrim PSub)) (TupE [Ret (VInt 9); Ret (VInt 1)])).

Example oo_left_assoc_det : det_check e_oo_left = true.
Proof. reflexivity. Qed.
Example oo_left_assoc_norm :
  norm 24 e_oo_left = Seq (Ret (VInt 5)) (Seq (Ret (VInt 20)) (Ret (VInt 8))).
Proof. reflexivity. Qed.
Example oo_left_assoc_bag :
  cand_bag (norm 24 e_oo_left) =
    Seq (Ret (VInt 5)) (Seq (Ret (VInt 20)) (Ret (VInt 8))) :: nil.
Proof.
  rewrite (T4_eval e_oo_left 24 oo_left_assoc_det).
  rewrite oo_left_assoc_norm. reflexivity.
Qed.

Definition e_oo_right : Expr :=
  Seq (App (Ret (VPrim PAdd)) (TupE [Ret (VInt 2); Ret (VInt 3)]))
      (Seq (App (Ret (VPrim PMul)) (TupE [Ret (VInt 4); Ret (VInt 5)]))
           (App (Ret (VPrim PSub)) (TupE [Ret (VInt 9); Ret (VInt 1)]))).

Example oo_assoc_right_det : det_check e_oo_right = true.
Proof. reflexivity. Qed.
Example oo_assoc_right_norm :
  norm 24 e_oo_right = Seq (Ret (VInt 5)) (Seq (Ret (VInt 20)) (Ret (VInt 8))).
Proof. reflexivity. Qed.
Example oo_assoc_right_bag :
  cand_bag (norm 24 e_oo_right) =
    Seq (Ret (VInt 5)) (Seq (Ret (VInt 20)) (Ret (VInt 8))) :: nil.
Proof.
  rewrite (T4_eval e_oo_right 24 oo_assoc_right_det).
  rewrite oo_assoc_right_norm. reflexivity.
Qed.

Definition e_oo_swap : Expr :=
  Seq (Seq (App (Ret (VPrim PMul)) (TupE [Ret (VInt 4); Ret (VInt 5)]))
           (App (Ret (VPrim PAdd)) (TupE [Ret (VInt 2); Ret (VInt 3)])))
      (App (Ret (VPrim PSub)) (TupE [Ret (VInt 9); Ret (VInt 1)])).

Example oo_swap_prefix_det : det_check e_oo_swap = true.
Proof. reflexivity. Qed.
Example oo_swap_prefix_norm :
  norm 24 e_oo_swap = Seq (Ret (VInt 20)) (Seq (Ret (VInt 5)) (Ret (VInt 8))).
Proof. reflexivity. Qed.
Example oo_swap_prefix_bag :
  cand_bag (norm 24 e_oo_swap) =
    Seq (Ret (VInt 20)) (Seq (Ret (VInt 5)) (Ret (VInt 8))) :: nil.
Proof.
  rewrite (T4_eval e_oo_swap 24 oo_swap_prefix_det).
  rewrite oo_swap_prefix_norm. reflexivity.
Qed.

(* The amended Group D pair (tests/corpus/README.md § 8): closed blocks, slot-disjoint,
   one with an app body the M0 row set cannot reach (block 1 keeps its body), one that
   Subst does reach (body index 0 is slot 1, value 9).  The checker sees closed slots
   and an int-or-var prim application, which is decision 8a's fragment; the *partial*
   shape of the normal form is the evaluator's artifact the amendment records. *)
Definition e_oo_blocks_fwd : Expr :=
  Seq (Block [(TInt, Some (VInt 5))]
           (App (Ret (VPrim PAdd)) (TupE [Ret (VVar 0); Ret (VInt 1)])))
      (Block [(TInt, Some (VInt 7)); (TInt, Some (VInt 9))] (Ret (VVar 0))).

Example oo_indep_blocks_fwd_det : det_check e_oo_blocks_fwd = true.
Proof. reflexivity. Qed.
Example oo_indep_blocks_fwd_norm :
  norm 24 e_oo_blocks_fwd =
    Seq (Block [(TInt, Some (VInt 5))]
             (App (Ret (VPrim PAdd)) (TupE [Ret (VVar 0); Ret (VInt 1)])))
        (Block [(TInt, Some (VInt 7)); (TInt, Some (VInt 9))] (Ret (VInt 9))).
Proof. reflexivity. Qed.
Example oo_indep_blocks_fwd_bag :
  cand_bag (norm 24 e_oo_blocks_fwd) =
    Seq (Block [(TInt, Some (VInt 5))]
             (App (Ret (VPrim PAdd)) (TupE [Ret (VVar 0); Ret (VInt 1)])))
        (Block [(TInt, Some (VInt 7)); (TInt, Some (VInt 9))] (Ret (VInt 9))) :: nil.
Proof.
  rewrite (T4_eval e_oo_blocks_fwd 24 oo_indep_blocks_fwd_det).
  rewrite oo_indep_blocks_fwd_norm. reflexivity.
Qed.

Definition e_oo_blocks_rev : Expr :=
  Seq (Block [(TInt, Some (VInt 7)); (TInt, Some (VInt 9))] (Ret (VVar 0)))
      (Block [(TInt, Some (VInt 5))]
             (App (Ret (VPrim PAdd)) (TupE [Ret (VVar 0); Ret (VInt 1)]))).

Example oo_indep_blocks_rev_det : det_check e_oo_blocks_rev = true.
Proof. reflexivity. Qed.
Example oo_indep_blocks_rev_norm :
  norm 24 e_oo_blocks_rev =
    Seq (Block [(TInt, Some (VInt 7)); (TInt, Some (VInt 9))] (Ret (VInt 9)))
        (Block [(TInt, Some (VInt 5))]
             (App (Ret (VPrim PAdd)) (TupE [Ret (VVar 0); Ret (VInt 1)]))).
Proof. reflexivity. Qed.
Example oo_indep_blocks_rev_bag :
  cand_bag (norm 24 e_oo_blocks_rev) =
    Seq (Block [(TInt, Some (VInt 7)); (TInt, Some (VInt 9))] (Ret (VInt 9)))
        (Block [(TInt, Some (VInt 5))]
             (App (Ret (VPrim PAdd)) (TupE [Ret (VVar 0); Ret (VInt 1)]))) :: nil.
Proof.
  rewrite (T4_eval e_oo_blocks_rev 24 oo_indep_blocks_rev_det).
  rewrite oo_indep_blocks_rev_norm. reflexivity.
Qed.

(* ---------- group E: rejection witnesses - what det_check must say no to ------ *)

(* Choice: decision 8b rejects the NODE CLASS, conservatively - the checker never
   looks at a candidate bag, so the duplicate-alternative shape (which br2 would
   identify with {3}) is rejected exactly like a distinct pair. *)
Example wtn_choice_dup_two_entries_det :
  det_check (Choice (Ret (VInt 3)) (Ret (VInt 1))) = false.
Proof. reflexivity. Qed.

(* The bag the evaluator nevertheless hands back, pinned as the corpus states it: two
   entries, because cand_bag splits a Choice and the denotation-side br2 algebra is a
   separate claim (docs/DESIGN-NOTES.md § 9). *)
Example wtn_choice_dup_two_entries_bag :
  cand_bag (Choice (Ret (VInt 3)) (Ret (VInt 1))) = [Ret (VInt 3); Ret (VInt 1)].
Proof. reflexivity. Qed.

Example wtn_fail_root_no_value_det : det_check Fail = false.
Proof. reflexivity. Qed.

(* An open block (declared slot, no value) is outside the fragment per decision 8a -
   and the corpus names the structural witness: no Subst (premise needs a valued
   slot), no promote (premise needs a unification), so R_Seq never fires either.
   G3 is that same structural reading: `slots_closed_ok` fails on the `None`. *)
Example wtn_open_block_in_seq_stays_det :
  det_check (Seq (Block [(TAny, @None Val)] (Ret (VVar 0))) (Ret (VInt 1))) = false.
Proof. reflexivity. Qed.
Example wtn_open_block_in_seq_stays_bag :
  cand_bag (Seq (Block [(TAny, @None Val)] (Ret (VVar 0))) (Ret (VInt 1))) =
    Seq (Block [(TAny, @None Val)] (Ret (VVar 0))) (Ret (VInt 1)) :: nil.
Proof. reflexivity. Qed.

(* `3 = fail`: not a value against a literal, so no Eq row and G4 refuses the pair
   (tools/corpus/README.md § 1's worked example: stuck, not fail). *)
Example wtn_unify_value_fail_stuck_det :
  det_check (Unify (Ret (VInt 3)) Fail) = false.
Proof. reflexivity. Qed.

(* Div-0 behind a dead prefix: G5 admits a `PDiv` pair only through the all-literals
   path, and `prim_total` answers PStuck at a zero divisor (Syntax.v), so
   `prim_args_ok` deliberately omits PDiv (Checks.v § G5: value-dependent arms are
   path (a) only).  This is the shape T7's division site may assume absent. *)
Example wtn_div0_after_seq_drop_det :
  det_check (Seq (Ret (VInt 1))
                 (App (Ret (VPrim PDiv)) (TupE [Ret (VInt 9); Ret (VInt 0)]))) = false.
Proof. reflexivity. Qed.

(* ---------- group F: materialisation - the DEV-20 span cases ----------------- *)

Example dotdot_zero_start_det :
  det_check (App (Ret (VPrim PDotDot)) (TupE [Ret (VInt 0); Ret (VInt 4)])) = true.
Proof. reflexivity. Qed.
Example dotdot_zero_start_norm :
  norm 24 (App (Ret (VPrim PDotDot)) (TupE [Ret (VInt 0); Ret (VInt 4)])) =
    Ret (VTup [VInt 0; VInt 1; VInt 2; VInt 3; VInt 4]).
Proof. reflexivity. Qed.

(* Negative start: the corpus marks this a probe ("pinned here, not yet measured") on
   the *value* of the span; the checker verdict is the same reading as the row above -
   an all-literal `PDotDot` pair, admitted by path (a) whatever the span says. *)
Example dotdot_negative_span_det :
  det_check (App (Ret (VPrim PDotDot)) (TupE [Ret (VInt (-3)); Ret (VInt 1)])) = true.
Proof. reflexivity. Qed.
Example dotdot_negative_span_norm :
  norm 24 (App (Ret (VPrim PDotDot)) (TupE [Ret (VInt (-3)); Ret (VInt 1)])) =
    Ret (VTup [VInt (-3); VInt (-2); VInt (-1); VInt 0; VInt 1]).
Proof. reflexivity. Qed.

(* Iter family absent from the head table (RULES-AUDIT § 5): G2 rejects the node, so
   nothing in M2 may assume a Fig. 13 row fires. *)
Example iter_ifor_absent_det :
  det_check (Iter IFor (Block [(TInt, @None Val)] (Ret (VInt 1))) (Ret (VInt 2))) = false.
Proof. reflexivity. Qed.

(* ---------- group G: the flex probes - the even/odd limbs the kernel denies ---- *)

(* All four are open blocks (decision 8a keeps them out of the fragment), pinned here
   so the refusal the corpus shapes survives whatever the flex layer becomes.  The
   divergence the corpus describes - kernel `promote_ok` vs the paper's line-416
   freshness - is a *row-selection* question the checker does not consult: it rejects
   the block before any row is discussed, which is the M2-side shadow of the same
   refusal. *)
Example probe_forwardref_tuple_fill_det :
  det_check (Block [(TAny, @None Val); (TAny, @None Val)]
                (Unify (Ret (VVar 1)) (Ret (VTup [VInt 1; VVar 0])))) = false.
Proof. reflexivity. Qed.

Example probe_forwardref_lam_fill_det :
  det_check (Block [(TAny, @None Val); (TAny, @None Val)]
                (Unify (Ret (VVar 0)) (Ret (VLam TAny (Ret (VVar 2)))))) = false.
Proof. reflexivity. Qed.

Example probe_selfref_tuple_direct_det :
  det_check (Block [(TAny, @None Val); (TAny, @None Val)]
                (Unify (Ret (VVar 1)) (Ret (VTup [VInt 1; VVar 1])))) = false.
Proof. reflexivity. Qed.

Example probe_overfresh_declared_slot_det :
  det_check (Block [(TAny, @None Val); (TAny, @None Val)]
                (Unify (Ret (VVar 1)) (Ret (VLam TAny (Ret (VVar 1)))))) = false.
Proof. reflexivity. Qed.

(* ---------- axiom audit (build-time evidence, same form as KernelTest.v) ------ *)

Print Assumptions T4_eval.
Print Assumptions T4_sem.
Print Assumptions T4_value_unique.
