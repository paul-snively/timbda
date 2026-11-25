(* Timbda-0 kernel: the determinacy checker (coq/Checks.v - M2, docs/PLAN.md § 3
   item 4: "T4 Determinacy soundness: det_check e = true -> exists v s',
   sem e = ret (v, s') ... Checker lives in Gallina (decision)").

   WHAT THIS FILE IS.  `det_check` is the Gallina checker of M2's determinate
   fragment, plus the sem-side soundness leg whose shape the m2 gate corpus fixed
   (docs/PLAN.md § 5 M2 status; docs/DESIGN-NOTES.md § 11).  The eval-side leg is in
   `coq/ChecksEval.v`, which `Require Import Timbda.Checks` and adds nothing back here;
   the split is a measured build-cost decision, recorded in docs/DESIGN-NOTES.md § 12.

     T4_sem   det_check e = true -> for every k, exists v,
              denote e (e_fuel e + k) ≈ sret (SOk v)
              - a single candidate, total, no control effect.  This is the PLAN
              § 3 claim: `ret (v, s')` has no state leg in the pure layer
              (Semantics.v header decision: the Get/Put signature is the M4
              host-verse layer), so the witness is `sret (SOk v)`.  Proved at
              ctrees structural equality `≅` (equ, Equ.v) and transported to ≈
              by ctrees' own `equ_wbisim_subrelation` (WBisim.v:310), the same
              idiom Denotation.v uses for every T1 row.
              Its corollary T4_value_unique (same file, after T4_sem) makes
              the accepted term's value unique at every fixed fuel at or
              above its own budget; the two-fuel strengthening § 13.2 recorded
              is now delivered as denE_total_pairwise (after denE_total):
              evaluations at any two fuels at or above the budget are
              equ-bisimilar (docs/DESIGN-NOTES.md § 13.6).

      T5_swap_discarded  det_check (Seq (Seq e1 e2) e3) = true ->
              denote (Seq (Seq e1 e2) e3) (e_fuel + k) ≈
              denote (Seq (Seq e2 e1) e3) (e_fuel + k), same fuel both sides:
              the accepted-fragment piece of PLAN § 3 item 5 (docs/DESIGN-NOTES.md
              § 13.3).  The Seq arm discards the prefix's value (Semantics.v:218),
              so a swap at a DISCARDED prefix position is Wbisim and the discarded
              values never enter the proof.  The naive suffix swap is refuted
              (T5_top_swap_needs_value), holds exactly under value equality
              (T5_swap_equal_values), and the fold/reassociate half (T5_swap_assoc)
              closes over denE_total_pairwise (after denE_total), whose two-budget
              induction bridges the tail's two fuels (docs/DESIGN-NOTES.md § 13.6).

     T4_eval  det_check e = true -> the evaluator's bag is a singleton:
              for every fuel f, exists nf, cand_bag (norm f e) = nf :: nil.
              Theorem T4_eval, in coq/ChecksEval.v, proves the stronger form, naming the
              witness: `nf` IS `norm fuel e`, the shape the evaluator already computed.
              This leg says ONLY what the evaluator demonstrably delivers.  The
              corpus is why it cannot say more: the evaluator's normal form for
              a slot-independent closed block is a *partial* shape (Group D of
              tests/corpus/m2-det.texpr, docs/DESIGN-NOTES.md § 11.3), so
              "reaches a value" is a sem-leg claim, never an eval-leg claim.
              What the proof tracks is the property the claim needs - no `Choice`
              node is ever minted - because BetaT's `choice_list` is the only row
              in Eval.v's selected head table that can mint one (Eval.v header),
              and G5 rejects exactly the App shapes those beta rows need.

   THE FRAGMENT (PLAN § 8 decision 8a/8b, accepted pending Verse-team revision).
   det_check is a CONSERVATIVE syntactic test - "the conservative checker never
   inspects candidates" (m2 corpus, group E).  A term passes exactly when:

     (G1) well-scoped: every VVar index is bound by an enclosing lambda binder
          or block slot (cutoff arithmetic as recorded in the Syntax.v header,
          mirrored by ws_expr / ws_val / ws_slots);
     (G2) no Choice, Fail, Glob or Iter node anywhere, including inside lambda
          and delay bodies and inside slot values: choice is rejected as a node
          class (wtn_choice_dup_two_entries - br2 idempotence identifies some
          bags, but the checker never inspects candidates); fail has no value
          witness (wtn_fail_root_no_value); Glob is the M4 host layer (the
          Semantics.v Glob arm is SStuck); the Fig. 13 iter family is deferred
          at the head table (Eval.v header) and iter_ifor_absent pins that no
          M2 claim may assume it fires;
     (G3) closed blocks only (decision 8a): every slot `Some`, and every slot
          value is an integer literal or a variable.  Open blocks are the
          admitted Tier-2 M3/T1 completion story (RewPromoteL/RewSubst general
          forms, RULES-AUDIT C1; wtn_open_block_in_seq_stays is the witness).
          Var-valued slots are admissible because (G1) plus the invariant of the
          T4_sem proof (environments are int maps, closeSlots_closed_int)
          resolves every slot to an int literal.  Slots holding tuple/lambda/
          delay values are conservative rejections until T10's type discipline
          runs.
     (G4) every Unify node is a literal pair EqK1 proves equal (is_lit_val on
          both sides and lit_eqb true; Fig. 9 line 432).  Every other unify
          shape is rejected, deliberately: an unequal literal pair is EqK2-fail
          (unify_seq_left_drop_eqk2: "a guaranteed fail is as un-lowerable as a
          guaranteed Div-0", decision 8b); var-vs-var and tuple-vs-tuple pairs
          are exactly the promote / EqTup1-chain territory the Denotation.v
          header defers to M3/T1; a compound side (`(ret 3) = fail`,
          wtn_unify_value_fail_stuck) is not a Fig. 9 pair at all.
     (G5) every App node is a canonical primop application: head `Ret (VPrim p)`
          and the operand in Eval.v's canonical reading (prim_operand_vals: a
          TupE of Ret values, or a bare Ret value), and either
            (a) all operand values are int literals and Syntax.v prim_total
                answers PRes - which rejects literal Div-0 (wtn_div0_after_
                seq_drop) and the gt/isInt/isBool/isUnit literal failures
                (decision 8b's "obvious stuck shapes"), or
            (b) the primop is in the value-insensitive table prim_args_ok and
                its operands are int literals or variables.  The table is
                add/sub/mul/cons2/dotdot at arity 2, neg at arity 1, cons at
                [any , tuple], arrLen at [tuple], with cons/arrLen tuple
                entries also restricted to int-or-var (see ITS comment: that is
                what makes a prim row's *result* syntactically checkable
                without inspecting it).  PPls is absent from the table on
                purpose: Syntax.v gives it a catch-all `PFail` arm at arity 1,
                so `pls[x]` with an unresolved variable is a guaranteed
                evaluator fail - a shape decision 8b rejects, not admits.
          Var operands are needed by the T5 witnesses themselves: Group D's
          amended pins put padd on [var 0, 1] inside a closed block, and the
          corpus records that classification as det=yes.  PDiv with a var
          operand is REJECTED (it is not in the table): a non-zero divisor is a
          semantic fact no syntactic guard can see; the literal case is caught
          by (a) and the var case is an honest M3-side refinement through T8's
          constant folding, not something this cut pretends to know.
          Every other App shape is rejected: lambda-head application is the
          BetaL class (RewSound_BetaL deferred, evolving-heap class C1); tuple-
          head application is BetaT/BetaT0; var/Glob/block-head application has
          no rule at all (Fig. 10 line 463).
     (G6) every TupE node's elements are Ret values.  A bare TupE of compound
          expressions is determinate in the denotation but its evaluation is
          one-pass-rebuild-dependent (tools/corpus/README.md § 3.2, the
          norm4_revisit_partial artifact); deferring it keeps the checker's
          totality proof at the denE_tup_rets lemma and is noted as a
          conservative cut, not a paper claim.

   CONSERVATIVE REJECTIONS, listed rather than hidden (T4 needs soundness, not
   completeness): lambda- and tuple-head application (the BetaL/BetaT class),
   Glob (M4 host layer), every Iter node (Fig. 13 deferred at the head table),
   tuple/lambda/delay-valued block slots, every non-EqK1 Unify shape, PDiv with
   a variable divisor, PPls with a variable operand, and TupE nodes whose
   elements are not values.  Each is pinned as a `det_check = false` Example in
   coq/tests/ChecksTest.v, together with the 29 m2-corpus verdicts (17 accept,
   12 reject) derived from this rule text.

   THE TWO LEGS ARE STATED SEPARATELY, on purpose.  T4_sem proves totality by
   direct evaluation in the denotation (no rewrite rows are invoked; closed
   blocks resolve through closeSlots exactly as the corpus side reads them).
  T4_eval proves bag singletonness by tracking which head rows can fire on a
   checked term and showing none of them mints a Choice node.  No bridge between
   the legs is claimed here: that is T8 at M3 (docs/PLAN.md § 3 item 8; the
   RULES-AUDIT ll. 57/159 correction recorded in decision 8). *)

From Stdlib Require Import ZArith List.
From CTree Require Import CTree Eq.
From CTree.Eq Require Import WBisim.
Import WBisimNotations.
Import EquNotations.
Import ListNotations.

Require Import Timbda.Syntax Timbda.Rewriting Timbda.RewRules Timbda.Semantics Timbda.Eval.
(* T5's peeling idiom reuses Denotation.v's kernel-`sret` bridge bind_sret_l
   (§ 12.2) rather than restating it; one direction, no cycle: Denotation.v
   requires Syntax/Rewriting/Semantics only. *)
Require Import Timbda.Denotation.

(* Nat arithmetic for the fuel and cutoff reasoning.  Note the *explicit* `Nat.le`
   and `Nat.lt` in the statements below: with the ctrees imports in scope the
   overloaded `<=` notation resolves to a CompleteLattice instance, which does not
   exist for nat ("Could not find an instance for ?CompleteLattice : CompleteLattice
   nat"), so bare `x <= y` on nat is not usable in this file. *)
From Stdlib Require Import Lia.

(* `&&` needs the bool scope opened, not Stdlib.Bool imported: Denotation.v and
   KernelTest.v record that a direct Stdlib.Bool import clashes with the ctrees
   chain notation at load time.  Bool itself arrives through Timbda.Syntax. *)
Local Open Scope bool_scope.

(* No CTreeNotations import and no ctree_scope here: the Expr `Ret` constructor
   clashes with the ctrees `Ret` notation (Semantics.v header records the exact
   misresolution) and KernelTest.v records that `[ x ]` misreads as a ctrees
   visible under that import.  `sret` (Semantics.v) is the ctrees return here,
   and one-element bags are written `x :: @nil Expr` for the same reason. *)

(* ---------- andb / forallb plumbing ---------- *)

Lemma andb_and : forall a b, a && b = true -> a = true /\ b = true.
Proof. intros a b H. destruct a, b; auto; discriminate. Qed.

Lemma andb_true2 : forall a b, a = true -> b = true -> a && b = true.
Proof. intros a b Ha Hb. rewrite Ha, Hb. reflexivity. Qed.

Lemma forallb_In : forall (A : Type) (f : A -> bool) (l : list A),
  forallb f l = true -> forall x, In x l -> f x = true.
Proof.
  intros A f l H x Hx. induction l as [| y l' IH]; [contradiction |].
  apply andb_and in H. destruct H as [Hy Hl'].
  simpl in Hx. destruct Hx as [-> | Hx'].
  - exact Hy.
  - apply IH; [exact Hl' | exact Hx'].
Qed.

Lemma In_forallb : forall (A : Type) (f : A -> bool) (l : list A),
  (forall x, In x l -> f x = true) -> forallb f l = true.
Proof.
  intros A f l H. induction l as [| y l' IH]; cbn; auto.
  apply andb_true2; [apply H; left; reflexivity | apply IH; intros x Hx; apply H; right; exact Hx].
Qed.

(* ---------- slot walkers ----------
   Syntax.v records why element<->list mutual Fixpoint blocks are rejected on
   this toolchain ("Cannot guess decreasing argument of fix") and what the
   kernel does instead: element-only mutual blocks, list cases through total
   walkers parameterised by an opaque callback (`walkSlotsV`/`anySlotsV`).  The
   checker follows the same shape, with `allSlotsV` the conjunctive twin of
   `anySlotsV` and the same per-entry cutoff rule (slot j is walked at d0 + j,
   exactly Syntax.v's occurrence/entry-position convention). *)

Fixpoint allSlotsV (cb : Val -> nat -> bool) (d0 : nat)
  (slots : list (Ty * option Val)) : bool :=
  match slots with
  | nil => true
  | (_, Some v) :: rest => cb v d0 && allSlotsV cb (S d0) rest
  | (_, None) :: rest => allSlotsV cb (S d0) rest
  end.

(* ---------- G1: well-scopedness (cutoffs per the Syntax.v header) ---------- *)

Fixpoint ws_val (d : nat) (v : Val) : bool :=
  match v with
  | VVar i => Nat.ltb i d
  | VLam _ e => ws_expr (S d) e
  | VDelay e => ws_expr d e
  | VTup vs => forallb (ws_val d) vs
  | _ => true
  end
with ws_expr (d : nat) (e : Expr) : bool :=
  match e with
  | Ret v => ws_val d v
  | Glob _ => true
  | App e1 e2 => ws_expr d e1 && ws_expr d e2
  | TupE es => forallb (ws_expr d) es
  | Seq e1 e2 => ws_expr d e1 && ws_expr d e2
  | Unify e1 e2 => ws_expr d e1 && ws_expr d e2
  | Choice e1 e2 => ws_expr d e1 && ws_expr d e2
  | Fail => true
  | Iter _ b r => ws_expr d b && ws_expr d r
  | Block slots body =>
      allSlotsV (fun v j => ws_val j v) d slots && ws_expr (length slots + d) body
  end.

Definition ws_slots (d : nat) (slots : list (Ty * option Val)) : bool :=
  allSlotsV (fun v j => ws_val j v) d slots.

(* ---------- G2: banned node classes ---------- *)

Fixpoint bans_okV (v : Val) : bool :=
  match v with
  | VLam _ e => bans_okE e
  | VDelay e => bans_okE e
  | VTup vs => forallb bans_okV vs
  | _ => true
  end
with bans_okE (e : Expr) : bool :=
  match e with
  | Ret v => bans_okV v
  | Glob _ => false
  | App e1 e2 => bans_okE e1 && bans_okE e2
  | TupE es => forallb bans_okE es
  | Seq e1 e2 => bans_okE e1 && bans_okE e2
  | Unify e1 e2 => bans_okE e1 && bans_okE e2
  | Choice _ _ => false
  | Fail => false
  | Iter _ _ _ => false
  | Block slots body => allSlotsV (fun v _ => bans_okV v) 0 slots && bans_okE body
  end.

Definition slots_bans_ok (slots : list (Ty * option Val)) : bool :=
  allSlotsV (fun v _ => bans_okV v) 0 slots.

(* ---------- G3: closed blocks, integer-or-variable slot values ---------- *)

Fixpoint slots_closed_ok (slots : list (Ty * option Val)) : bool :=
  match slots with
  | nil => true
  | (_, Some (VInt _)) :: rest => slots_closed_ok rest
  | (_, Some (VVar _)) :: rest => slots_closed_ok rest
  | _ => false                             (* None, or a richer value kind *)
  end.

Fixpoint blocks_closed_okV (v : Val) : bool :=
  match v with
  | VLam _ e => blocks_closed_okE e
  | VDelay e => blocks_closed_okE e
  | VTup vs => forallb blocks_closed_okV vs
  | _ => true
  end
with blocks_closed_okE (e : Expr) : bool :=
  match e with
  | Ret v => blocks_closed_okV v
  | Glob _ => true
  | App e1 e2 => blocks_closed_okE e1 && blocks_closed_okE e2
  | TupE es => forallb blocks_closed_okE es
  | Seq e1 e2 => blocks_closed_okE e1 && blocks_closed_okE e2
  | Unify e1 e2 => blocks_closed_okE e1 && blocks_closed_okE e2
  | Choice e1 e2 => blocks_closed_okE e1 && blocks_closed_okE e2
  | Fail => true
  | Iter _ b r => blocks_closed_okE b && blocks_closed_okE r
  | Block slots body => slots_closed_ok slots && blocks_closed_okE body
  end.

(* ---------- G4: the EqK1-only unification rule (Fig. 9 line 432) ---------- *)

Definition eq_pair_ok (e1 e2 : Expr) : bool :=
  match e1, e2 with
  | Ret v1, Ret v2 => is_lit_val v1 && is_lit_val v2 && lit_eqb v1 v2
  | _, _ => false
  end.

Fixpoint unify_okE (e : Expr) : bool :=
  match e with
  | Unify e1 e2 => eq_pair_ok e1 e2 && unify_okE e1 && unify_okE e2
  | Ret _ => true
  | Glob _ => true
  | App e1 e2 => unify_okE e1 && unify_okE e2
  | TupE es => forallb unify_okE es
  | Seq e1 e2 => unify_okE e1 && unify_okE e2
  | Choice e1 e2 => unify_okE e1 && unify_okE e2
  | Fail => true
  | Iter _ b r => unify_okE b && unify_okE r
  | Block _ body => unify_okE body
  end.

(* ---------- G5: canonical applications ---------- *)

Definition is_int_or_var (v : Val) : bool :=
  match v with VInt _ | VVar _ => true | _ => false end.

Definition all_int (vs : list Val) : bool := forallb is_int_val vs.

Definition prim_total_res (p : Prim) (vs : list Val) : bool :=
  match prim_total p vs with PRes _ => true | _ => false end.

(* The value-insensitive arms of Syntax.v prim_total, at the arities where the
   arm fires for *every* closing of int-or-var operands:
     add/sub/mul/cons2/dotdot at arity 2, neg at arity 1, cons at [any, tuple],
     arrLen at [tuple].  cons/arrLen also require the tuple's own entries to be
     int-or-var: prim_total's cons result is `cons v0 ⟨v1..vn⟩` and its arrLen
   argument is inspected by shape only, so keeping the entries in the same
   syntactic class is what lets `prim_result_ok` below classify a prim row's
   *result* from the operand list alone - the checker never inspects a value.
   PDiv, the comparisons (gt/lt/geq/leq/neq) and the type tests (isInt/isBool/
   isUnit) are absent on purpose: their PFail/PStuck arms depend on operand
   *values*, so only the all-literals path (a) may accept them.  PPls is absent
   too: `PPls, [_] => PFail` (Syntax.v) makes a variable operand a guaranteed
   fail, and decision 8b rejects guaranteed fails. *)
Definition prim_args_ok (p : Prim) (vs : list Val) : bool :=
  match p, vs with
  | PAdd, [v1; v2] | PSub, [v1; v2] | PMul, [v1; v2] | PCons2, [v1; v2] | PDotDot, [v1; v2] =>
      is_int_or_var v1 && is_int_or_var v2
  | PNeg, v :: nil => is_int_or_var v
  | PCons, v0 :: VTup ws :: nil => is_int_or_var v0 && forallb is_int_or_var ws
  | PArrLen, VTup ws :: nil => forallb is_int_or_var ws
  | _, _ => false
  end.

Definition prim_canon (p : Prim) (vs : list Val) : bool :=
  (all_int vs && prim_total_res p vs) || prim_args_ok p vs.

(* A bare `Ret v` operand (the m0/m2 corpus canonicalises unary prim applications
   that way: `app (ret (primv ppls)) (ret -9)`, KernelTest `prim_app` at arity 1)
   is read by `apply_c` as the value ITSELF: `match arg with VTup vs => prim_total
   p vs | v => prim_total p [v] end`.  A tuple-valued bare operand therefore gets
   UNPACKED into its entries, which is not the syntactic list [v] the guards read.
   So the table path (b) is admitted for a bare operand only at `neg[v]`, where
   unpacking cannot happen for an int-or-var value; the TupE-wrapped form (whose
   unpacking reproduces the entry list, decision 5) keeps the full table.  Path
   (a) is always safe: all-literal operands close to themselves, so the syntactic
   list IS the list apply_c scrutinises.  `arrLen[⟨…⟩]` written bare is thus a
   conservative rejection, noted with the others. *)
Definition prim_bare_ok (p : Prim) (v : Val) : bool :=
  match p with PNeg => is_int_or_var v | _ => false end.

Definition app_node_ok (f a : Expr) : bool :=
  match f with
  | Ret (VPrim p) =>
      match prim_operand_vals a with
      | Some vs =>
          if all_int vs && prim_total_res p vs then true
          else match a with
               | TupE _ => prim_args_ok p vs
               | Ret v => prim_bare_ok p v
               | _ => false
               end
      | None => false
      end
  | _ => false
  end.

Fixpoint apps_okE (e : Expr) : bool :=
  match e with
  | App e1 e2 => app_node_ok e1 e2 && apps_okE e1 && apps_okE e2
  | Ret _ => true
  | Glob _ => true
  | TupE es => forallb apps_okE es
  | Seq e1 e2 => apps_okE e1 && apps_okE e2
  | Unify e1 e2 => apps_okE e1 && apps_okE e2
  | Choice e1 e2 => apps_okE e1 && apps_okE e2
  | Fail => true
  | Iter _ b r => apps_okE b && apps_okE r
  | Block _ body => apps_okE body
  end.

(* ---------- G6: tuple nodes are lists of values ---------- *)

Definition tup_node_ok (es : list Expr) : bool :=
  match rets_of es with Some _ => true | None => false end.

Fixpoint tup_rets_okE (e : Expr) : bool :=
  match e with
  | TupE es => tup_node_ok es && forallb tup_rets_okE es
  | Ret _ => true
  | Glob _ => true
  | App e1 e2 => tup_rets_okE e1 && tup_rets_okE e2
  | Seq e1 e2 => tup_rets_okE e1 && tup_rets_okE e2
  | Unify e1 e2 => tup_rets_okE e1 && tup_rets_okE e2
  | Choice e1 e2 => tup_rets_okE e1 && tup_rets_okE e2
  | Fail => true
  | Iter _ b r => tup_rets_okE b && tup_rets_okE r
  | Block _ body => tup_rets_okE body
  end.

(* ---------- the checker ---------- *)

Definition det_struct (e : Expr) : bool :=
  bans_okE e && (blocks_closed_okE e && (unify_okE e && (apps_okE e && tup_rets_okE e))).

Definition det_check (e : Expr) : bool := ws_expr 0 e && det_struct e.

(* The guards are conjunctive, so their components can be taken apart and put
   back together; every lemma below is one of those two moves. *)

Lemma det_struct_components : forall e,
  det_struct e = true ->
  bans_okE e = true /\ blocks_closed_okE e = true
  /\ unify_okE e = true /\ apps_okE e = true /\ tup_rets_okE e = true.
Proof.
  (* det_struct is written with explicit right-nesting, so each peel exposes
     the leftmost guard. *)
  intros e H. unfold det_struct in H.
  apply andb_and in H. destruct H as [H1 R1].
  apply andb_and in R1. destruct R1 as [H2 R2].
  apply andb_and in R2. destruct R2 as [H3 R3].
  apply andb_and in R3. destruct R3 as [H4 H5].
  split; [exact H1 | split; [exact H2 | split; [exact H3 | split; [exact H4 | exact H5]]]].
Qed.

Lemma det_struct_mk : forall e,
  bans_okE e = true -> blocks_closed_okE e = true -> unify_okE e = true ->
  apps_okE e = true -> tup_rets_okE e = true -> det_struct e = true.
Proof.
  (* det_struct is right-nested: peel left to right. *)
  intros e H1 H2 H3 H4 H5. unfold det_struct.
  apply andb_true2; [exact H1 | apply andb_true2; [exact H2 |
    apply andb_true2; [exact H3 | apply andb_true2; [exact H4 | exact H5]]]].
Qed.

Lemma det_check_components : forall e,
  det_check e = true -> ws_expr 0 e = true /\ det_struct e = true.
Proof. intros e H. apply andb_and in H. tauto. Qed.

Lemma andb3_and : forall a b c, a && b && c = true -> a = true /\ b = true /\ c = true.
Proof.
  (* `a && b && c` parses left-associative: ((a && b) && c). *)
  intros a b c H. apply andb_and in H. destruct H as [Hab Hc].
  apply andb_and in Hab. tauto.
Qed.

Ltac andb2 H := apply andb_and in H; destruct H as [? ?].
Ltac andb3 H := apply andb3_and in H; destruct H as [? [? ?]].

Lemma det_struct_Seq_inv : forall e1 e2,
  det_struct (Seq e1 e2) = true -> det_struct e1 = true /\ det_struct e2 = true.
Proof.
  intros e1 e2 H. apply det_struct_components in H. destruct H as [Hb [Hl [Hu [Ha Ht]]]].
  cbn [bans_okE blocks_closed_okE unify_okE apps_okE tup_rets_okE] in Hb, Hl, Hu, Ha, Ht.
  andb2 Hb. andb2 Hl. andb2 Hu. andb2 Ha. andb2 Ht.
  split; apply det_struct_mk; auto.
Qed.

Lemma det_struct_Unify_inv : forall e1 e2,
  det_struct (Unify e1 e2) = true -> det_struct e1 = true /\ det_struct e2 = true.
Proof.
  intros e1 e2 H. apply det_struct_components in H. destruct H as [Hb [Hl [Hu [Ha Ht]]]].
  cbn [bans_okE blocks_closed_okE unify_okE apps_okE tup_rets_okE] in Hb, Hl, Hu, Ha, Ht.
  andb2 Hb. andb2 Hl. andb3 Hu. andb2 Ha. andb2 Ht.
  split; apply det_struct_mk; auto.
Qed.

Lemma det_struct_App_inv : forall f a,
  det_struct (App f a) = true -> det_struct f = true /\ det_struct a = true.
Proof.
  intros f a H. apply det_struct_components in H. destruct H as [Hb [Hl [Hu [Ha Ht]]]].
  cbn [bans_okE blocks_closed_okE unify_okE apps_okE tup_rets_okE] in Hb, Hl, Hu, Ha, Ht.
  andb2 Hb. andb2 Hl. andb2 Hu. andb3 Ha. andb2 Ht.
  split; apply det_struct_mk; auto.
Qed.

Lemma det_struct_Block_inv : forall sl body,
  det_struct (Block sl body) = true -> det_struct body = true /\ slots_closed_ok sl = true.
Proof.
  intros sl body H. apply det_struct_components in H. destruct H as [Hb [Hl [Hu [Ha Ht]]]].
  cbn [bans_okE blocks_closed_okE unify_okE apps_okE tup_rets_okE] in Hb, Hl, Hu, Ha, Ht.
  andb2 Hb. andb2 Hl.
  split; [apply det_struct_mk; auto | assumption].
Qed.

(* G2 is a node-class test: these four are what "rejected as a class" means. *)
Lemma bans_okE_not_choice : forall e1 e2, bans_okE (Choice e1 e2) = false.
Proof. reflexivity. Qed.
Lemma bans_okE_not_fail : bans_okE Fail = false.
Proof. reflexivity. Qed.
Lemma bans_okE_not_glob : forall g, bans_okE (Glob g) = false.
Proof. reflexivity. Qed.
Lemma bans_okE_not_iter : forall ic b r, bans_okE (Iter ic b r) = false.
Proof. reflexivity. Qed.

(* G4/G5/G3 component extractions. *)
Lemma unify_okE_pair : forall e1 e2,
  unify_okE (Unify e1 e2) = true -> eq_pair_ok e1 e2 = true.
Proof.
  intros e1 e2 H. cbn [unify_okE] in H. apply andb3_and in H. tauto.
Qed.

Lemma eq_pair_ok_shape : forall e1 e2,
  eq_pair_ok e1 e2 = true ->
  exists v1 v2, e1 = Ret v1 /\ e2 = Ret v2
  /\ is_lit_val v1 = true /\ is_lit_val v2 = true /\ lit_eqb v1 v2 = true.
Proof.
  intros e1 e2 H. unfold eq_pair_ok in H.
  destruct e1 as [v1 | gid | e11 e12 | es | e11 e12 | e11 e12 | e11 e12 | | sl body | ic b r];
    cbn [eq_pair_ok] in H; try discriminate H.
  destruct e2 as [v2 | gid | e21 e22 | es | e21 e22 | e21 e22 | e21 e22 | | sl body | ic b r];
    cbn [eq_pair_ok] in H; try discriminate H.
  cbn [is_lit_val] in H.
  apply andb3_and in H.
  eexists; eexists; split; [reflexivity | split; [reflexivity | split; tauto]].
Qed.

Lemma apps_okE_node : forall f a,
  apps_okE (App f a) = true -> app_node_ok f a = true.
Proof. intros f a H. cbn [apps_okE] in H. apply andb3_and in H. tauto. Qed.

Lemma app_node_ok_shape : forall f a,
  app_node_ok f a = true ->
  exists p vs,
    f = Ret (VPrim p) /\ prim_operand_vals a = Some vs /\
    ((all_int vs && prim_total_res p vs = true)
     \/ (exists es, a = TupE es /\ rets_of es = Some vs /\ prim_args_ok p vs = true)
     \/ (exists v, a = Ret v /\ prim_bare_ok p v = true)).
Proof.
  intros f a H. unfold app_node_ok in H.
  destruct f as [v | gid | e1 e2 | es | e1 e2 | e1 e2 | e1 e2 | | sl body | ic b0 r];
    cbn [app_node_ok] in H; try discriminate H.
  destruct v as [| | | | p | | | |]; cbn [app_node_ok] in H; try discriminate H.
  (* option readings are case-split with `remember ... in`, which keeps the
     defining equation (a bare `destruct (term)` consumes the hypothesis). *)
  remember (prim_operand_vals a) as o eqn:E in H. symmetry in E.
  destruct o as [vs |]; [ cbn in H | cbn in H; discriminate H ].
  remember (all_int vs && prim_total_res p vs) as b eqn:Ha in H. symmetry in Ha.
  destruct b; cbn in H.
  - eexists; eexists; split; [reflexivity | split; [exact E | left; exact Ha]].
  - destruct a as [v | gid | e1 e2 | es | e1 e2 | e1 e2 | e1 e2 | | sl body | ic b1 r];
      cbn in H; cbn [prim_operand_vals] in E; try discriminate H.
    + eexists; eexists; split;
        [reflexivity | split; [exact E | right; right;
          exists v; split; [reflexivity | exact H]]].
    + eexists; eexists; split;
        [reflexivity | split; [exact E | right; left;
          exists es; split; [reflexivity | split; [exact E | exact H]]]].
Qed.

Lemma tup_rets_okE_node : forall es,
  tup_rets_okE (TupE es) = true -> tup_node_ok es = true.
Proof. intros es H. cbn [tup_rets_okE] in H. apply andb_and in H. tauto. Qed.

Lemma tup_node_ok_rets : forall es,
  tup_node_ok es = true -> exists vs, rets_of es = Some vs.
Proof.
  intros es H. unfold tup_node_ok in H.
  remember (rets_of es) as o eqn:E in H. symmetry in E.
  destruct o as [vs |]; cbn in H.
  - eexists; exact E.
  - discriminate H.
Qed.

(* G6 says a TupE node is a list of values, and pins *which* values: a `rets_of`
   success forces the list to be exactly `map Ret vs` (Eval.v rets_of). *)
Lemma rets_of_map_rets : forall es vs, rets_of es = Some vs -> es = map Ret vs.
Proof.
  induction es as [| e rest IH]; intros vs H; cbn [rets_of] in H.
  - inversion H. cbn [map]. reflexivity.
  - destruct e as [v | gid | e1 e2 | es0 | e1 e2 | e1 e2 | e1 e2 | | sl body | ic b r];
      cbn [rets_of] in H; try discriminate H.
    remember (rets_of rest) as o eqn:Hrest in H. symmetry in Hrest.
    destruct o as [vs' |]; cbn in H.
    + injection H as Hvs. subst vs. rewrite (IH vs' Hrest). cbn [map]. reflexivity.
    + discriminate H.
Qed.

(* ---------- the denotation leg: fuel budget, environment invariant, totality ---- *)

(* e_fuel is a per-node budget, generous everywhere (an S() per node, a sum of the
   children), and exactly the shape the uniform-fuel evaluator (Semantics.v
   decision 2) consumes:
     * `App`: one unit for the node; head, operand and the apply_c VPrim arm all
       run at the predecessor fuel (apply_c's VPrim arm is itself fuel-free);
     * `TupE`: two units above the sum of the elements - the list arm consumes
       one unit per element position (`denE_tup` evaluates element i at fuel
       F-1-i, exactly the counting Denotation.v's prim_app rows record), and
       every element has budget >= 1, so `sum - i >= e_fuel !!i`;
     * `Block`: one unit; closeSlots is fuel-free and the body runs at the
       predecessor.
   Written with the Syntax.v total-walker idiom (element<->list mutual Fixpoints
   are rejected on this toolchain, Syntax.v header). *)

Fixpoint sumE (cb : Expr -> nat) (es : list Expr) : nat :=
  match es with
  | nil => 0
  | e :: rest => cb e + sumE cb rest
  end.

Fixpoint e_fuel (e : Expr) : nat :=
  match e with
  | Ret _    => 1
  | Glob _   => 1
  | Fail     => 1
  | Choice a b => S (e_fuel a + e_fuel b)
  | App a b  => S (e_fuel a + e_fuel b)
  | Seq a b  => S (e_fuel a + e_fuel b)
  | Unify a b => S (e_fuel a + e_fuel b)
  | Iter _ a b => S (e_fuel a + e_fuel b)
  | TupE es  => S (S (sumE (fun x => e_fuel x) es))
  | Block _ b => S (e_fuel b)
  end.

(* Per-element allowance for `denE_tup` at fuel m: element i runs at fuel
   m-1-i; `allots` hands every position the predecessor budget. *)
Fixpoint allots (es : list Expr) (m : nat) : bool :=
  match es with
  | nil => true
  | e :: rest => Nat.leb (e_fuel e) (Nat.pred m) && allots rest (Nat.pred m)
  end.

Lemma e_fuel_pos : forall e, Nat.le 1 (e_fuel e).
Proof.
  intro e. induction e.
  - auto.
  - auto.
  - cbn [e_fuel]; lia.
  - cbn [e_fuel sumE]; lia.
  - cbn [e_fuel]; lia.
  - cbn [e_fuel]; lia.
  - cbn [e_fuel]; lia.
  - auto.
  - cbn [e_fuel]; lia.
  - cbn [e_fuel]; lia.
Qed.

Lemma allots_bridge : forall es m,
  Nat.le (S (S (sumE (fun x => e_fuel x) es))) (S m) -> allots es m = true.
Proof.
  induction es as [| e rest IH]; intros m H; cbn [allots].
  - reflexivity.
  - cbn [sumE] in H. assert (H1 : Nat.le 1 (e_fuel e)) by apply e_fuel_pos.
    apply andb_true2; [apply Nat.leb_le; lia | apply IH; lia].
Qed.

(* The invariant the T4_sem induction carries about the frame stack: enough frames
   for the de Bruijn cutoff, and every frame an integer.  Checked terms never push
   a lambda frame (G5 admits no lambda head, G2 no iter-for, so beta never runs) -
   frames are block slots, and G3 restricts slot values to VInt and VVar, which
   closeSlots turns into ints under this very invariant.  Int frames are what make
   a prim operand `var[i]` close to an int literal, so prim_total is read at its
   pinned literals-only arms. *)

Definition env_ok (d : nat) (rho : env) : bool :=
  Nat.leb d (length rho) && forallb is_int_val rho.

Lemma env_ok_mk : forall d rho,
  Nat.le d (length rho) -> forallb is_int_val rho = true -> env_ok d rho = true.
Proof.
  intros d rho Hlen Hfb. unfold env_ok.
  apply andb_true2; [apply Nat.leb_le; exact Hlen | exact Hfb].
Qed.

Lemma env_ok_inv : forall d rho,
  env_ok d rho = true -> Nat.le d (length rho) /\ forallb is_int_val rho = true.
Proof.
  intros d rho H. apply andb_and in H. destruct H as [Hlen Hfb].
  split; [apply Nat.leb_le; exact Hlen | exact Hfb].
Qed.

Lemma env_ok_le : forall d d' rho,
  env_ok d rho = true -> Nat.le d' d -> env_ok d' rho = true.
Proof.
  intros d d' rho H Hd. apply env_ok_inv in H. destruct H as [Hlen Hfb].
  apply env_ok_mk; [lia | exact Hfb].
Qed.

Lemma env_ok_cons_int : forall d rho v,
  env_ok d rho = true -> is_int_val v = true -> env_ok (S d) (v :: rho) = true.
Proof.
  intros d rho v He Hi. apply env_ok_inv in He. destruct He as [Hlen Hfb].
  unfold env_ok. apply andb_true2.
  - apply Nat.leb_le. cbn [length]. lia.
  - cbn [forallb]. apply andb_true2; [exact Hi | exact Hfb].
Qed.

(* Membership through `nth_error` (a hand-written version: `apply nth_error_In`
   does not elaborate in this import environment). *)
Lemma forallb_nth : forall (A : Type) (f : A -> bool) (rho : list A) n x,
  forallb f rho = true -> nth_error rho n = Some x -> f x = true.
Proof.
  induction rho as [| y rest IH]; intros n x Hf He.
  - destruct n; simpl in He; discriminate.
  - simpl in Hf. apply andb_and in Hf. destruct Hf as [Hy Hrest].
    destruct n as [| n'].
    + simpl in He. injection He as Heq. subst x. exact Hy.
    (* `eapply`, not `apply`: the induction hypothesis carries `A` as an implicit
       argument, and `apply` fills it with the first explicit argument. *)
    + simpl in He. eapply IH; [exact Hrest | exact He].
Qed.

Lemma ltb_zero_false : forall n, Nat.ltb n 0 = false.
Proof. intro n. destruct n; reflexivity. Qed.

(* A VVar that (G1) says is bound, in an env_ok frame stack, closes to an int. *)
Lemma closeV_var : forall d rho i,
  ws_val d (VVar i) = true -> env_ok d rho = true -> exists a, closeV 0 rho (VVar i) = VInt a.
Proof.
  intros d rho i Hw He.
  cbn [ws_val] in Hw. apply (proj1 (Nat.ltb_lt i d)) in Hw.
  apply env_ok_inv in He. destruct He as [Hlen Hfb].
  (* `cbn` leaves the `i - 0` index unreduced, so it is replaced explicitly. *)
  cbn [closeV]. replace (i - 0) with i by lia.
  destruct (Nat.ltb i 0) eqn:Hltb.
  - exfalso. rewrite (ltb_zero_false i) in Hltb. discriminate Hltb.
  - cbn [closeV]. destruct (nth_error rho i) as [v |] eqn:E.
    + assert (Hiv : is_int_val v = true)
        by (exact (forallb_nth Val is_int_val rho i v Hfb E)).
      destruct v as [| | | a | p | vs | l e0 | e0 | i0]; cbn in Hiv; try discriminate.
      exists a. reflexivity.
    + exfalso. apply (proj1 (nth_error_None rho i)) in E. lia.
Qed.

Lemma closeV_int_or_var_inv : forall d rho v,
  is_int_or_var v = true -> ws_val d v = true -> env_ok d rho = true ->
  exists a, closeV 0 rho v = VInt a.
Proof.
  intros d rho v Hi Hw He.
  destruct v as [| | | a | p | vs | l e0 | e0 | i];
    cbn [is_int_or_var] in Hi; try discriminate Hi.
  - exists a. cbn [closeV]. reflexivity.
  - apply (closeV_var d rho i Hw He).
Qed.

Lemma closeV_lit : forall rho v, is_lit_val v = true -> closeV 0 rho v = v.
Proof.
  intros rho v H. cbn in H. destruct v; cbn in H; try discriminate; cbn [closeV]; reflexivity.
Qed.

Lemma all_int_map_closeV : forall rho vs, all_int vs = true -> map (closeV 0 rho) vs = vs.
Proof.
  intro rho. induction vs as [| v rest IH]; intros H; cbn [all_int] in H; cbn [map].
  - reflexivity.
  - apply andb_and in H. destruct H as [Hv Hrest].
    destruct v; cbn in Hv; try discriminate; cbn [closeV is_int_val];
    rewrite IH; [reflexivity | exact Hrest].
Qed.

(* ---------- slot closing under the invariant ---------- *)

(* G3 is exactly the shape `closeSlots` can complete: every entry `Some v` with v
   an integer or a bound variable.  What such a slot holds: *)

Lemma slots_closed_head : forall t ov rest,
  slots_closed_ok ((t, ov) :: rest) = true ->
  (match ov with Some v => is_int_or_var v | None => false end) = true.
Proof.
  intros t ov rest H.
  destruct ov as [v |].
  - destruct v as [| | | a | q | vs | l e0 | e0 | i0];
      cbn [slots_closed_ok] in H; cbn [is_int_or_var]; try discriminate H; reflexivity.
  - cbn [slots_closed_ok] in H; discriminate H.
Qed.

Lemma closeSlots_int : forall sl rho d,
  slots_closed_ok sl = true -> ws_slots d sl = true -> env_ok d rho = true ->
  exists rho',
    closeSlots rho sl = Some rho' /\ env_ok (length sl + d) rho' = true.
Proof.
  induction sl as [| [t ov] rest IH]; intros rho d Hc Hw He.
  - exists rho. split; [reflexivity | exact He].
  - (* cons: the head slot is valued, its value is VInt or VVar (the only shapes
       slots_closed_ok admits), and it closes to an int frame under env_ok *)
    destruct ov as [v |].
    + destruct v as [| | | a | p | vs | l e0 | e0 | i];
        cbn [slots_closed_ok ws_slots allSlotsV] in Hc, Hw; try discriminate Hc.
      * (* VInt a *)
        apply andb_and in Hw; destruct Hw as [Hwv Hw2].
        destruct (IH (VInt a :: rho) (S d) Hc Hw2
                    (env_ok_cons_int d rho (VInt a) He eq_refl)) as [rho' [HE Hint]].
        apply env_ok_inv in Hint. destruct Hint as [Hle Hfb].
        cbn [closeSlots closeV length]. exists rho'.
        split; [exact HE | apply env_ok_mk; [lia | exact Hfb]].
      * (* VVar i - (G1) plus env_ok resolve it to an int frame *)
        apply andb_and in Hw; destruct Hw as [Hwv Hw2].
        destruct (closeV_var d rho i Hwv He) as [a Hcv].
        assert (He' : env_ok (S d) (closeV 0 rho (VVar i) :: rho) = true)
          by (rewrite Hcv; apply env_ok_cons_int; [exact He | exact eq_refl]).
        destruct (IH (closeV 0 rho (VVar i) :: rho) (S d) Hc Hw2 He') as [rho' [HE Hint]].
        apply env_ok_inv in Hint. destruct Hint as [Hle Hfb].
        cbn [closeSlots length]. exists rho'.
        split; [exact HE | apply env_ok_mk; [simpl in Hle; lia | exact Hfb]].
    + cbn [slots_closed_ok] in Hc; discriminate.
Qed.

(* ---------- computation at checked shapes ----------
   The bridges the totality induction reads: a checked literal pair unifies at
   EqK1, and a `map Ret vs` operand list evaluates to the tuple of its closed
   entries.  Note the `;` chaining used below: a tactic written in its own
   sentence only touches the first goal, so case-by-case closers stay inside the
   chain that produced the goals. *)

Lemma lit_eqb_true : forall v1 v2, lit_eqb v1 v2 = true -> v1 = v2.
Proof.
  intros v1 v2 H. destruct v1, v2; cbn [lit_eqb] in H;
    try discriminate H; first [ apply f_equal; apply Z.eqb_eq; exact H | reflexivity ].
Qed.

(* EqK1 at the fuel the checker's `S _` budget guarantees: fuel 0 is the budget
   artifact arm (SStuck), so a literal pair needs a successor. *)
Lemma unify_top_lit : forall v1 v2 f,
  is_lit_val v1 = true -> is_lit_val v2 = true -> lit_eqb v1 v2 = true ->
  unify_top v1 v2 (S f) = SOk v1.
Proof.
  intros v1 v2 f H1 H2 Heq. apply lit_eqb_true in Heq. subst v2.
  destruct v1; cbn [is_lit_val] in H1; try discriminate H1;
    cbn [unify_top root_of root_eqb no_eq_rule_pair is_lit_val lit_eqb negb andb];
    first [ rewrite Z.eqb_refl; reflexivity | reflexivity ].
Qed.

Lemma closeV_prim : forall rho p, closeV 0 rho (VPrim p) = VPrim p.
Proof. intros rho p. cbn [closeV]. reflexivity. Qed.

Lemma prim_operand_ret : forall v vs,
  prim_operand_vals (Ret v) = Some vs -> vs = v :: nil.
Proof. intros v vs H. cbn [prim_operand_vals] in H. now injection H. Qed.

Lemma sumE_ret_fuel : forall vs,
  Nat.le (length vs) (sumE (fun x => e_fuel x) (map Ret vs)).
Proof. induction vs as [| v rest IH]; cbn [length map sumE e_fuel]; lia. Qed.

(* A TupE node whose elements are values (G6) evaluates element by element:
   `denE_tup` runs element i at fuel F-1-i (Semantics.v), so `S (length vs + k)`
   units leave every Ret arm at least one step, and the tuple that comes out is
   the closed values in list order.  This is the whole TupE half of T4_sem. *)
Lemma denE_tup_rets : forall vs (acc : list Val) rho k,
  denE_tup rho (map Ret vs) acc (S (length vs + k))
    ≅ sret (SOk (VTup (rev acc ++ map (closeV 0 rho) vs))).
Proof.
  induction vs as [| v rest IH]; intros acc rho k.
  - cbn [map length denE_tup]. rewrite app_nil_r. reflexivity.
  (* `Nat.add` in the delta list, spelled out: with the ctrees notations in
     scope a bare `+` inside a tactic argument does not resolve to nat addition. *)
  - cbn [map length Nat.add].
    cbn [denE_tup denE]. setoid_rewrite bind_ret_l. cbn [sret].
    rewrite (IH (closeV 0 rho v :: acc) rho k). cbn [rev].
    (* Coq 9.1 states app_assoc as `l ++ m ++ n = (l ++ m) ++ n`, so the
       re-association this step needs is its right-to-left reading. *)
    rewrite <- app_assoc. cbn [app]. reflexivity.
Qed.

(* ---------- admitted prim rows survive closure ----------
   One lemma per admitted row of Checks.v prim_args_ok (path (b)), plus the
   all-literals bridge (path (a)).  Each row lemma says: at the operand shapes
   that row admits, closing the operands leaves prim_total answering PRes.
   prim_row_PArrLen needs no hypothesis at all, which is exactly what the table
   comment claims - its prim_total row reads the operand's SHAPE, never its
   entries.

   Style note, learned the hard way on this toolchain: a focusing tactic (try,
   first, match goal) placed on the right of `;` only processes the first goal
   it is handed, and the other goals survive silently to Qed; and a `.` sentence
   terminator inside a `; [branch | branch]` list is a syntax error.  So the case
   splits below are written as flat branch lists over the 18 Prim constructors
   of Syntax.v, in declaration order:
     PAdd PSub PMul PDiv PNeg PPls PGt PLt PGEq PLEq PNEq PIsInt PIsBool PIsUnit
     PCons PCons2 PDotDot PArrLen *)

Lemma prim_total_res_sres : forall p vs,
  prim_total_res p vs = true -> exists w, prim_sres (prim_total p vs) = SOk w.
Proof.
  intros p vs H. unfold prim_total_res in H.
  destruct (prim_total p vs); cbn in H;
    [ eexists; cbn [prim_sres]; reflexivity | discriminate H | discriminate H ].
Qed.

(* Path (a): all-literal operands are fixed by closure, so the closed operand
   list IS the list prim_total was checked at. *)
Lemma prim_total_res_map_closed : forall p vs d rho,
  all_int vs = true -> prim_total_res p vs = true -> env_ok d rho = true ->
  exists w, prim_sres (prim_total p (map (closeV 0 rho) vs)) = SOk w.
Proof.
  intros p vs d rho Ha Hres He.
  rewrite (all_int_map_closeV rho vs Ha). apply (prim_total_res_sres p vs). exact Hres.
Qed.

Lemma prim_row_PNeg : forall v d rho,
  is_int_or_var v = true -> ws_val d v = true -> env_ok d rho = true ->
  exists w, prim_sres (prim_total PNeg [closeV 0 rho v]) = SOk w.
Proof.
  intros v d rho Hi Hw He.
  destruct (closeV_int_or_var_inv d rho v Hi Hw He) as [a Hc].
  rewrite Hc. cbn [prim_total prim_sres]. eexists. reflexivity.
Qed.

Lemma prim_row_PArrLen : forall ws rho,
  exists w, prim_sres (prim_total PArrLen [closeV 0 rho (VTup ws)]) = SOk w.
Proof. intros ws rho. cbn [closeV prim_total prim_sres]. eexists. reflexivity. Qed.

Lemma prim_row_PAdd : forall v1 v2 d rho,
  is_int_or_var v1 = true -> is_int_or_var v2 = true ->
  ws_val d v1 = true -> ws_val d v2 = true -> env_ok d rho = true ->
  exists w, prim_sres (prim_total PAdd [closeV 0 rho v1; closeV 0 rho v2]) = SOk w.
Proof.
  intros v1 v2 d rho H1 H2 W1 W2 He.
  destruct (closeV_int_or_var_inv d rho v1 H1 W1 He) as [a1 Hc1].
  destruct (closeV_int_or_var_inv d rho v2 H2 W2 He) as [a2 Hc2].
  rewrite Hc1, Hc2. cbn [prim_total prim_sres]. eexists. reflexivity.
Qed.

Lemma prim_row_PSub : forall v1 v2 d rho,
  is_int_or_var v1 = true -> is_int_or_var v2 = true ->
  ws_val d v1 = true -> ws_val d v2 = true -> env_ok d rho = true ->
  exists w, prim_sres (prim_total PSub [closeV 0 rho v1; closeV 0 rho v2]) = SOk w.
Proof.
  intros v1 v2 d rho H1 H2 W1 W2 He.
  destruct (closeV_int_or_var_inv d rho v1 H1 W1 He) as [a1 Hc1].
  destruct (closeV_int_or_var_inv d rho v2 H2 W2 He) as [a2 Hc2].
  rewrite Hc1, Hc2. cbn [prim_total prim_sres]. eexists. reflexivity.
Qed.

Lemma prim_row_PMul : forall v1 v2 d rho,
  is_int_or_var v1 = true -> is_int_or_var v2 = true ->
  ws_val d v1 = true -> ws_val d v2 = true -> env_ok d rho = true ->
  exists w, prim_sres (prim_total PMul [closeV 0 rho v1; closeV 0 rho v2]) = SOk w.
Proof.
  intros v1 v2 d rho H1 H2 W1 W2 He.
  destruct (closeV_int_or_var_inv d rho v1 H1 W1 He) as [a1 Hc1].
  destruct (closeV_int_or_var_inv d rho v2 H2 W2 He) as [a2 Hc2].
  rewrite Hc1, Hc2. cbn [prim_total prim_sres]. eexists. reflexivity.
Qed.

Lemma prim_row_PCons2 : forall v1 v2 d rho,
  is_int_or_var v1 = true -> is_int_or_var v2 = true ->
  ws_val d v1 = true -> ws_val d v2 = true -> env_ok d rho = true ->
  exists w, prim_sres (prim_total PCons2 [closeV 0 rho v1; closeV 0 rho v2]) = SOk w.
Proof.
  intros v1 v2 d rho H1 H2 W1 W2 He.
  destruct (closeV_int_or_var_inv d rho v1 H1 W1 He) as [a1 Hc1].
  destruct (closeV_int_or_var_inv d rho v2 H2 W2 He) as [a2 Hc2].
  rewrite Hc1, Hc2. cbn [prim_total prim_sres]. eexists. reflexivity.
Qed.

Lemma prim_row_PDotDot : forall v1 v2 d rho,
  is_int_or_var v1 = true -> is_int_or_var v2 = true ->
  ws_val d v1 = true -> ws_val d v2 = true -> env_ok d rho = true ->
  exists w, prim_sres (prim_total PDotDot [closeV 0 rho v1; closeV 0 rho v2]) = SOk w.
Proof.
  intros v1 v2 d rho H1 H2 W1 W2 He.
  destruct (closeV_int_or_var_inv d rho v1 H1 W1 He) as [a1 Hc1].
  destruct (closeV_int_or_var_inv d rho v2 H2 W2 He) as [a2 Hc2].
  rewrite Hc1, Hc2. cbn [prim_total prim_sres]. eexists. reflexivity.
Qed.

Lemma prim_row_PCons : forall v0 ws d rho,
  is_int_or_var v0 = true -> ws_val d v0 = true -> env_ok d rho = true ->
  exists w,
    prim_sres (prim_total PCons [closeV 0 rho v0; closeV 0 rho (VTup ws)]) = SOk w.
Proof.
  intros v0 ws d rho Hi Hw He.
  destruct (closeV_int_or_var_inv d rho v0 Hi Hw He) as [a Hc].
  rewrite Hc. cbn [closeV prim_total prim_sres]. eexists. reflexivity.
Qed.

(* Shapes the table can only match by value shape: arrLen at arity 1 and cons at
   arity 2 admit a tuple operand, and the row is stuck (so Ha stays available)
   until the operand is exposed.  Val's constructors in Syntax.v order:
     VUnit VTrue VFalse VInt VPrim VTup VLam VDelay VVar *)
Lemma prim_args_ok_PArrLen_shape : forall v,
  prim_args_ok PArrLen [v] = true -> exists ws, v = VTup ws.
Proof.
  intros v H. destruct v; cbn [prim_args_ok is_int_or_var forallb] in H;
    [ discriminate H | discriminate H | discriminate H | discriminate H
    | discriminate H | eexists; reflexivity | discriminate H
    | discriminate H | discriminate H ].
Qed.

Lemma prim_args_ok_PCons_shape : forall v1 v2,
  prim_args_ok PCons [v1; v2] = true ->
  exists ws, v2 = VTup ws /\ is_int_or_var v1 = true.
Proof.
  intros v1 v2 H. destruct v2; cbn [prim_args_ok is_int_or_var andb forallb] in H;
    [ discriminate H | discriminate H | discriminate H | discriminate H
    | discriminate H | eexists; split; [reflexivity | apply andb_and in H;
        destruct H as [Hi1 Hrest]; exact Hi1 ]
    | discriminate H | discriminate H | discriminate H ].
Qed.

(* Path (b), arity 1: neg[v] with an int-or-var operand, arrLen[⟨…⟩] with a
   tuple operand, and nothing else at that arity. *)
Lemma prim_args_ok_map_closed1 : forall p v1 d rho,
  prim_args_ok p [v1] = true -> (forall v, In v [v1] -> ws_val d v = true) ->
  env_ok d rho = true ->
  exists w, prim_sres (prim_total p [closeV 0 rho v1]) = SOk w.
Proof.
  intros p v1 d rho Ha Hws He.
  assert (Hw1 : ws_val d v1 = true) by (apply Hws; cbn [In]; left; reflexivity).
  destruct p; cbn [prim_args_ok is_int_or_var forallb] in Ha;
    [ discriminate Ha                                    (* PAdd *)
    | discriminate Ha                                    (* PSub *)
    | discriminate Ha                                    (* PMul *)
    | discriminate Ha                                    (* PDiv *)
    | apply (prim_row_PNeg v1 d rho Ha Hw1 He)           (* PNeg *)
    | discriminate Ha                                    (* PPls *)
    | discriminate Ha                                    (* PGt *)
    | discriminate Ha                                    (* PLt *)
    | discriminate Ha                                    (* PGEq *)
    | discriminate Ha                                    (* PLEq *)
    | discriminate Ha                                    (* PNEq *)
    | discriminate Ha                                    (* PIsInt *)
    | discriminate Ha                                    (* PIsBool *)
    | discriminate Ha                                    (* PIsUnit *)
    | discriminate Ha                                    (* PCons *)
    | discriminate Ha                                    (* PCons2 *)
    | discriminate Ha                                    (* PDotDot *)
    | destruct (prim_args_ok_PArrLen_shape v1 Ha) as [ws Hv];
      rewrite Hv; apply (prim_row_PArrLen ws rho)        (* PArrLen *)
    ].
Qed.

(* Path (b), arity 2: add/sub/mul/cons2/dotdot on int-or-var operands and cons
   on [int-or-var, tuple]. *)
Lemma prim_args_ok_map_closed2 : forall p v1 v2 d rho,
  prim_args_ok p [v1; v2] = true -> (forall v, In v [v1; v2] -> ws_val d v = true) ->
  env_ok d rho = true ->
  exists w, prim_sres (prim_total p [closeV 0 rho v1; closeV 0 rho v2]) = SOk w.
Proof.
  intros p v1 v2 d rho Ha Hws He.
  assert (Hw1 : ws_val d v1 = true) by (apply Hws; cbn [In]; left; reflexivity).
  assert (Hw2 : ws_val d v2 = true)
    by (apply Hws; cbn [In]; right; left; reflexivity).
  destruct p; cbn [prim_args_ok is_int_or_var andb forallb] in Ha;
    [ apply andb_and in Ha; destruct Ha as [Hi1 Hi2];
      apply (prim_row_PAdd v1 v2 d rho Hi1 Hi2 Hw1 Hw2 He)      (* PAdd *)
    | apply andb_and in Ha; destruct Ha as [Hi1 Hi2];
      apply (prim_row_PSub v1 v2 d rho Hi1 Hi2 Hw1 Hw2 He)      (* PSub *)
    | apply andb_and in Ha; destruct Ha as [Hi1 Hi2];
      apply (prim_row_PMul v1 v2 d rho Hi1 Hi2 Hw1 Hw2 He)      (* PMul *)
    | discriminate Ha                                           (* PDiv *)
    | discriminate Ha                                           (* PNeg *)
    | discriminate Ha                                           (* PPls *)
    | discriminate Ha                                           (* PGt *)
    | discriminate Ha                                           (* PLt *)
    | discriminate Ha                                           (* PGEq *)
    | discriminate Ha                                           (* PLEq *)
    | discriminate Ha                                           (* PNEq *)
    | discriminate Ha                                           (* PIsInt *)
    | discriminate Ha                                           (* PIsBool *)
    | discriminate Ha                                           (* PIsUnit *)
    | destruct (prim_args_ok_PCons_shape v1 v2 Ha) as [ws [Hv Hi1]];
      rewrite Hv; apply (prim_row_PCons v1 ws d rho Hi1 Hw1 He) (* PCons *)
    | apply andb_and in Ha; destruct Ha as [Hi1 Hi2];
      apply (prim_row_PCons2 v1 v2 d rho Hi1 Hi2 Hw1 Hw2 He)    (* PCons2 *)
    | apply andb_and in Ha; destruct Ha as [Hi1 Hi2];
      apply (prim_row_PDotDot v1 v2 d rho Hi1 Hi2 Hw1 Hw2 He)   (* PDotDot *)
    | destruct v1; cbn [prim_args_ok] in Ha; discriminate Ha
    ].
Qed.

(* No table row has arity 0 or arity 3 or more.  Note the extra `destruct`s the
   PCons and PArrLen arms need: Coq reduces a `match` only once every pattern it
   still has to try is decided, and `arrLen[⟨…⟩]` inspects the operand HEAD for
   VTup while `cons` inspects the SECOND operand - a variable there keeps the
   whole table lookup stuck rather than taking the `false` fallthrough. *)
Lemma prim_args_ok_map_closed_nil : forall p d rho,
  prim_args_ok p nil = true -> env_ok d rho = true ->
  exists w, prim_sres (prim_total p nil) = SOk w.
Proof. intros p d rho Ha He. destruct p; cbn [prim_args_ok] in Ha; discriminate Ha. Qed.

Lemma prim_args_ok_map_closed_ge3 : forall p v1 v2 v3 rest d rho,
  prim_args_ok p (v1 :: v2 :: v3 :: rest) = true -> env_ok d rho = true ->
  exists w,
    prim_sres (prim_total p (map (closeV 0 rho) (v1 :: v2 :: v3 :: rest))) = SOk w.
Proof.
  intros p v1 v2 v3 rest d rho Ha He.
  destruct p; cbn [prim_args_ok] in Ha;
    [ discriminate Ha                                        (* PAdd *)
    | discriminate Ha                                        (* PSub *)
    | discriminate Ha                                        (* PMul *)
    | discriminate Ha                                        (* PDiv *)
    | discriminate Ha                                        (* PNeg *)
    | discriminate Ha                                        (* PPls *)
    | discriminate Ha                                        (* PGt *)
    | discriminate Ha                                        (* PLt *)
    | discriminate Ha                                        (* PGEq *)
    | discriminate Ha                                        (* PLEq *)
    | discriminate Ha                                        (* PNEq *)
    | discriminate Ha                                        (* PIsInt *)
    | discriminate Ha                                        (* PIsBool *)
    | discriminate Ha                                        (* PIsUnit *)
    | destruct v2; cbn [prim_args_ok] in Ha; discriminate Ha (* PCons *)
    | discriminate Ha                                        (* PCons2 *)
    | discriminate Ha                                        (* PDotDot *)
    | destruct v1; cbn [prim_args_ok] in Ha; discriminate Ha (* PArrLen *)
    ].
Qed.

(* Path (b), any arity: the admitted rows, closed. *)
Lemma prim_args_ok_map_closed : forall p vs d rho,
  prim_args_ok p vs = true -> (forall v, In v vs -> ws_val d v = true) ->
  env_ok d rho = true ->
  exists w, prim_sres (prim_total p (map (closeV 0 rho) vs)) = SOk w.
Proof.
  intros p vs d rho Ha Hws He.
  destruct vs as [ | v1 rest1];
    [ apply (prim_args_ok_map_closed_nil p d rho Ha He)
    | destruct rest1 as [ | v2 rest2];
      [ cbn [map]; apply (prim_args_ok_map_closed1 p v1 d rho Ha Hws He)
      | destruct rest2 as [ | v3 rest3];
        [ cbn [map]; apply (prim_args_ok_map_closed2 p v1 v2 d rho Ha Hws He)
        | apply (prim_args_ok_map_closed_ge3 p v1 v2 v3 rest3 d rho Ha He) ] ] ].
Qed.

(* The bare-operand case: `neg[v]` only, which is exactly where apply_c's
   unpacking cannot change the operand list (Checks.v prim_bare_ok). *)
Lemma prim_bare_res : forall p v d rho,
  prim_bare_ok p v = true -> ws_val d v = true -> env_ok d rho = true ->
  exists w, prim_sres (prim_total p [closeV 0 rho v]) = SOk w.
Proof.
  intros p v d rho Hb Hw He.
  destruct p; cbn [prim_bare_ok] in Hb;
    [ discriminate Hb | discriminate Hb | discriminate Hb | discriminate Hb
    | exact (prim_row_PNeg v d rho Hb Hw He)
    | discriminate Hb | discriminate Hb | discriminate Hb | discriminate Hb
    | discriminate Hb | discriminate Hb | discriminate Hb | discriminate Hb
    | discriminate Hb | discriminate Hb | discriminate Hb | discriminate Hb
    | discriminate Hb ].
Qed.

(* ---------- value-class and budget facts the totality induction reads ----------
   `sumE_e_fuel_map_ret` is the TupE budget identity: a checked TupE is a list of
   `Ret`s (G6) and every `Ret` costs one fuel unit, so the node's own budget
   `S (S (sumE ...))` is two units above `length vs` - exactly what `denE_tup`
   spends (it keeps the predecessor fuel for every element position, Semantics.v
   uniform-fuel block). *)

Lemma is_int_val_is_int_or_var : forall v, is_int_val v = true -> is_int_or_var v = true.
Proof.
  (* Val's constructors in Syntax.v order: VUnit VTrue VFalse VInt VPrim VTup
     VLam VDelay VVar; only VInt is an int. *)
  intros v H. destruct v; cbn [is_int_val is_int_or_var] in H;
    [ discriminate H | discriminate H | discriminate H | reflexivity
    | discriminate H | discriminate H | discriminate H | discriminate H | discriminate H ].
Qed.

Lemma prim_bare_ok_is_int_or_var : forall p v, prim_bare_ok p v = true -> is_int_or_var v = true.
Proof.
  intros p v H. destruct p; cbn [prim_bare_ok] in H;
    [ discriminate H | discriminate H | discriminate H | discriminate H
    | exact H                                          (* PNeg *)
    | discriminate H | discriminate H | discriminate H | discriminate H | discriminate H
    | discriminate H | discriminate H | discriminate H | discriminate H | discriminate H
    | discriminate H | discriminate H | discriminate H ].
Qed.

Lemma sumE_e_fuel_map_ret : forall vs, sumE (fun x => e_fuel x) (map Ret vs) = length vs.
Proof.
  induction vs as [| v rest IH]; cbn [map length sumE e_fuel]; lia.
Qed.

Lemma In_map_ret : forall vs w, In w vs -> In (Ret w) (map Ret vs).
Proof.
  induction vs as [| v rest IH]; intros w Hw; cbn [map In].
  - destruct Hw.
  - destruct Hw as [-> | Hw'].
    + left. reflexivity.
    + right. apply IH. exact Hw'.
Qed.

(* Well-scopedness of the entries of a TupE operand list, read off G1. *)
Lemma ws_val_In_map_ret : forall d vs w,
  ws_expr d (TupE (map Ret vs)) = true -> In w vs -> ws_val d w = true.
Proof.
  intros d vs w H Hw. cbn [ws_expr] in H.
  assert (H1 : forall x, In x (map Ret vs) -> ws_expr d x = true)
    by (apply (forallb_In Expr (ws_expr d) (map Ret vs) H)).
  assert (H2 : ws_expr d (Ret w) = true) by (apply H1; apply In_map_ret; exact Hw).
  cbn [ws_expr] in H2. exact H2.
Qed.

(* Eval.v prim_operand_vals, inverted: the two operand shapes the evaluator reads. *)
Lemma prim_operand_vals_inv : forall a vs, prim_operand_vals a = Some vs ->
  (exists es, a = TupE es /\ rets_of es = Some vs)
  \/ (exists v, a = Ret v /\ vs = v :: nil).
Proof.
  intros a vs H.
  destruct a as [v | gid | e1 e2 | es | e1 e2 | e1 e2 | e1 e2 | | sl body | ic b r];
  cbn [prim_operand_vals] in H.
  - right; exists v; split; [reflexivity | injection H as Hv; symmetry in Hv; exact Hv].
  - discriminate H.                                                 (* Glob *)
  - discriminate H.                                                 (* App  *)
  - left; exists es; split; [reflexivity | exact H].                (* TupE *)
  - discriminate H.                                                 (* Seq *)
  - discriminate H.                                                 (* Unify *)
  - discriminate H.                                                 (* Choice *)
  - discriminate H.                                                 (* Fail *)
  - discriminate H.                                                 (* Block *)
  - discriminate H.                                                 (* Iter *)
Qed.


(* ONE CANONICAL APPLICATION, at the three operand shapes G5 admits
   (app_node_ok_shape).  What apply_c scrutinises is the CLOSED operand value, so
   every bridge here is stated at `map (closeV 0 rho) vs` / `[closeV 0 rho v]`:
     (a) all-literal operands  -> prim_total_res_map_closed   (closing is the identity)
     (b) table operands, TupE  -> prim_args_ok_map_closed
     (b) table operands, bare  -> prim_bare_res               (`neg[v]` only)

   Shape of the proof.  cbn [denE] first unfolds the App node: head evaluation,
   operand evaluation and apply_c all sit under the case-analysis bind, with the
   VTup-nil guard stuck on the head value `closeV 0 rho (VPrim p)`.  A Leibniz
   `rewrite closeV_prim` (plain rewrite reaches into match branches; setoid
   rewriting with a `≅` lemma cannot) exposes the head constructor, and
   `setoid_rewrite bind_ret_l; cbn` then peels the head bind at the root, so the
   operand node surfaces AT ROOT - the only position where `setoid_rewrite` of a
   `≅` lemma is reachable in this library (ctrees registers Proper instances for
   bind but rewriting under a stuck match on a variable never gets there).
   From there each branch is a straight evaluation: denE_tup_rets for the tuple,
   then bind_ret_l again and cbn [apply_c], and the prim bridge rewrites the
   stuck `prim_sres (prim_total ...)` to `SOk w`.

   Fuel: the node budget is `S (1 + e_fuel a)` with `e_fuel a >= 1`, so at node
   fuel `S (S m)` the head, the operand and apply_c all run at `S m`.  For a TupE
   operand `cbn` then leaves `denE_tup ... nil m`, and the budget identity
   sumE_e_fuel_map_ret turns the hypothesis into `m = S (length vs + k)` - exactly
   the shape denE_tup_rets reads. *)
Lemma denE_App_cand : forall rho d p a n,
  env_ok d rho = true -> ws_expr d a = true ->
  app_node_ok (Ret (VPrim p)) a = true ->
  Nat.le (e_fuel (App (Ret (VPrim p)) a)) n ->
  exists v, denE rho (App (Ret (VPrim p)) a) n ≅ sret (SOk v).
Proof.
  intros rho d p a n Henv Hws Hcanon Hfuel.
  apply (app_node_ok_shape (Ret (VPrim p)) a) in Hcanon.
  destruct Hcanon as [q [vs [Hq [Hops Hpath]]]]. inversion Hq. subst q.
  cbn [e_fuel] in Hfuel.
  assert (Hm : exists m, n = S (S m))
    by (exists (n - 2); assert (Hfa := e_fuel_pos a); lia).
  destruct Hm as [m Hm]. rewrite Hm in Hfuel. rewrite Hm. cbn [e_fuel] in Hfuel.
  destruct Hpath as [Hpath | [Hpath | Hpath]].
  - (* ---- (a) every operand is an int literal ---- *)
    apply andb_and in Hpath. destruct Hpath as [Hall Hres].
    apply (prim_operand_vals_inv a vs) in Hops.
    destruct Hops as [Hops | Hops].
    + destruct Hops as [es [Ha Hret]]. subst a.
      assert (Hmap : es = map Ret vs) by (exact (rets_of_map_rets es vs Hret)). subst es.
      cbn [e_fuel sumE] in Hfuel. rewrite sumE_e_fuel_map_ret in Hfuel.
      assert (Hwv : forall v0, In v0 vs -> ws_val d v0 = true)
        by (intros v0 Hv0; apply (ws_val_In_map_ret d vs v0); assumption).
      cbn [denE denE_tup sret].
      assert (Hk : exists k, m = S (length vs + k))
        by (exists (m - S (length vs)); lia).
      destruct Hk as [k Hk]. rewrite Hk.
      rewrite closeV_prim. cbn [sret].
      setoid_rewrite bind_ret_l. cbn [sret].
      setoid_rewrite (denE_tup_rets vs nil rho k).
      cbn [rev app sret].
      setoid_rewrite bind_ret_l. cbn [sret apply_c].
      destruct (prim_total_res_map_closed p vs d rho Hall Hres Henv) as [w Hbr].
      rewrite Hbr. eexists. reflexivity.
    + destruct Hops as [v [Ha Heqvs]]. subst a. subst vs.
      assert (Hwv : ws_val d v = true) by (cbn [ws_expr] in Hws; exact Hws).
      assert (Hiv : is_int_val v = true)
        by (apply (forallb_In Val is_int_val (v :: nil));
              [exact Hall | cbn [In]; left; reflexivity]).
      destruct (closeV_int_or_var_inv d rho v (is_int_val_is_int_or_var v Hiv) Hwv Henv)
        as [a0 Hc].
      cbn [denE denE_tup sret].
      rewrite closeV_prim. rewrite Hc. cbn [sret].
      setoid_rewrite bind_ret_l. cbn [sret].
      setoid_rewrite bind_ret_l. cbn [sret apply_c].
      destruct (prim_total_res_map_closed p (v :: nil) d rho Hall Hres Henv) as [w Hbr].
      cbn [map] in Hbr. rewrite Hc in Hbr. rewrite Hbr. eexists. reflexivity.
  - (* ---- (b) table operands through a TupE operand list ---- *)
    destruct Hpath as [es [Ha [Hret Hargs]]]. subst a.
    assert (Hmap : es = map Ret vs) by (exact (rets_of_map_rets es vs Hret)). subst es.
    cbn [e_fuel sumE] in Hfuel. rewrite sumE_e_fuel_map_ret in Hfuel.
    assert (Hwv : forall v0, In v0 vs -> ws_val d v0 = true)
      by (intros v0 Hv0; apply (ws_val_In_map_ret d vs v0); assumption).
    cbn [denE denE_tup sret].
    assert (Hk : exists k, m = S (length vs + k))
      by (exists (m - S (length vs)); lia).
    destruct Hk as [k Hk]. rewrite Hk.
    rewrite closeV_prim. cbn [sret].
    setoid_rewrite bind_ret_l. cbn [sret].
    setoid_rewrite (denE_tup_rets vs nil rho k).
    cbn [rev app sret].
    setoid_rewrite bind_ret_l. cbn [sret apply_c].
    destruct (prim_args_ok_map_closed p vs d rho Hargs Hwv Henv) as [w Hbr].
    rewrite Hbr. eexists. reflexivity.
  - (* ---- (b) table operands through a bare `Ret v` operand: `neg[v]` ---- *)
    destruct Hpath as [v [Ha Hbare]]. subst a.
    assert (Hwv : ws_val d v = true) by (cbn [ws_expr] in Hws; exact Hws).
    destruct (closeV_int_or_var_inv d rho v (prim_bare_ok_is_int_or_var p v Hbare) Hwv Henv)
      as [a0 Hc].
    cbn [denE denE_tup sret].
    rewrite closeV_prim. rewrite Hc. cbn [sret].
    setoid_rewrite bind_ret_l. cbn [sret].
    setoid_rewrite bind_ret_l. cbn [sret apply_c].
    destruct (prim_bare_res p v d rho Hbare Hwv Henv) as [w Hbr].
    rewrite Hc in Hbr. rewrite Hbr. eexists. reflexivity.
Qed.

(* ---------- T4_sem: the totality leg ----------
   `denE_total` is the fuel induction behind T4_sem: a checked node, evaluated
   in an int environment with at least its own budget, answers a single value.
   The statement generalises over the node (induction on the fuel, everything
   else reverted) so each case can re-instantiate the IH at the children.

   The tactics follow the shape established in denE_App_cand: cbn unfolds the
   node (constructor fuel, constructor node), Leibniz `rewrite` reaches into
   stuck match scrutinees, and `setoid_rewrite` of a `≅` fact is used only once
   the bind whose scrutinee it replaces is at the root - reached by peeling the
   outer binds with bind_ret_l first.  Every `setoid_rewrite bind_ret_l` is
   paired with `cbn [sret]`: the cbn exposes the `go (RetF x)` shape the law
   reads and performs the beta/iota that substitutes the value into the
   continuation, re-exposing the next bind at the root. *)

Lemma denE_total : forall m e d rho,
  ws_expr d e = true -> env_ok d rho = true -> det_struct e = true ->
  Nat.le (e_fuel e) m ->
  exists v, denE rho e m ≅ sret (SOk v).
Proof.
  induction m as [| n IH]; intros e d rho Hw Henv Hds Hfuel.
  - (* no fuel: e_fuel >= 1, contradiction *)
    assert (Hp := e_fuel_pos e). lia.
  - destruct e as [v | gid | f a | es | e1 e2 | u1 u2 | c1 c2 | | sl body | ic b r].
    + (* Ret *)
      exists (closeV 0 rho v). cbn [denE]. reflexivity.
    + (* Glob: G2 *)
      apply det_struct_components in Hds. destruct Hds as [Hban _].
      rewrite (bans_okE_not_glob gid) in Hban. discriminate Hban.
    + (* App: G5 - the operand analysis lives in denE_App_cand *)
      apply det_struct_components in Hds. destruct Hds as [_ [_ [_ [Happs _]]]].
      assert (Hnode := apps_okE_node f a Happs).
      apply (app_node_ok_shape f a) in Hnode.
      destruct Hnode as [p [vs [Hf [Hops Hpath]]]]. subst f.
      cbn [ws_expr] in Hw. apply andb_and in Hw. destruct Hw as [_ Hwa].
      exact (denE_App_cand rho d p a (S n) Henv Hwa (apps_okE_node (Ret (VPrim p)) a Happs) Hfuel).
    + (* TupE: G6 pins the node to `map Ret vs`; sumE_e_fuel_map_ret is the budget *)
      apply det_struct_components in Hds. destruct Hds as [_ [_ [_ [_ Htup]]]].
      apply (tup_rets_okE_node es) in Htup.
      apply (tup_node_ok_rets es) in Htup.
      destruct Htup as [vs Hret].
      assert (Hmap : es = map Ret vs) by (exact (rets_of_map_rets es vs Hret)). subst es.
      exists (VTup (map (closeV 0 rho) vs)).
      cbn [denE].
      cbn [e_fuel sumE] in Hfuel. rewrite sumE_e_fuel_map_ret in Hfuel.
      assert (Hk : exists k, n = S (length vs + k))
        by (exists (n - S (length vs)); lia).
      destruct Hk as [k Hk]. rewrite Hk.
      setoid_rewrite (denE_tup_rets vs nil rho k). cbn [rev app]. reflexivity.
    + (* Seq *)
      apply (det_struct_Seq_inv e1 e2) in Hds. destruct Hds as [Hds1 Hds2].
      cbn [ws_expr] in Hw. apply andb_and in Hw. destruct Hw as [Hw1 Hw2].
      cbn [e_fuel] in Hfuel.
      assert (Hp1 := e_fuel_pos e1). assert (Hp2 := e_fuel_pos e2).
      assert (Hle1 : Nat.le (e_fuel e1) n) by lia.
      assert (Hle2 : Nat.le (e_fuel e2) n) by lia.
      destruct (IH e1 d rho Hw1 Henv Hds1 Hle1) as [v1 He1].
      destruct (IH e2 d rho Hw2 Henv Hds2 Hle2) as [v2 He2].
      exists v2.
      cbn [denE].
      setoid_rewrite He1. cbn [sret].
      setoid_rewrite bind_ret_l. cbn [sret].
      exact He2.
    + (* Unify: G4 pins the EqK1 literal pair *)
      apply det_struct_components in Hds. destruct Hds as [_ [_ [Hu [_ _]]]].
      apply (unify_okE_pair u1 u2) in Hu.
      apply (eq_pair_ok_shape u1 u2) in Hu.
      destruct Hu as [w1 [w2 [Hu1 [Hu2 [Hl1 [Hl2 Heq]]]]]]. subst u1 u2.
      cbn [e_fuel] in Hfuel.
      destruct n as [| f]; [lia |].
      cbn [denE]. cbn [sret].
      setoid_rewrite bind_ret_l. cbn [sret].
      setoid_rewrite bind_ret_l. cbn [sret].
      rewrite (closeV_lit rho w1 Hl1). rewrite (closeV_lit rho w2 Hl2).
      rewrite (unify_top_lit w1 w2 f Hl1 Hl2 Heq).
      exists w1. reflexivity.
    + (* Choice: G2 *)
      apply det_struct_components in Hds. destruct Hds as [Hban _].
      rewrite (bans_okE_not_choice c1 c2) in Hban. discriminate Hban.
    + (* Fail: G2 *)
      apply det_struct_components in Hds. destruct Hds as [Hban _].
      rewrite bans_okE_not_fail in Hban. discriminate Hban.
    + (* Block: G3 - closeSlots_int resolves the closed int-or-var slots *)
      apply (det_struct_Block_inv sl body) in Hds. destruct Hds as [Hdsb Hslots].
      cbn [ws_expr] in Hw. apply andb_and in Hw. destruct Hw as [Hwslo Hwsb].
      cbn [e_fuel] in Hfuel.
      assert (Hle : Nat.le (e_fuel body) n) by lia.
      destruct (closeSlots_int sl rho d Hslots Hwslo Henv) as [rho' [HE Hint]].
      (* `apply IH` leaves the frame-count argument as an evar that Hwsb pins -
         spelling `Datatypes.length sl + d` out in a tactic term instead runs into
         Coq 9.1's overloaded `+` (the CompleteLattice-instance problem again). *)
      assert (Hih : exists v, denE rho' body n ≅ sret (SOk v)).
      { refine (IH body _ rho' Hwsb Hint Hdsb Hle). }
      destruct Hih as [v Hbody].
      exists v.
      cbn [denE].
      rewrite HE. cbn [denE].
      exact Hbody.
    + (* Iter: G2 *)
      apply det_struct_components in Hds. destruct Hds as [Hban _].
      rewrite (bans_okE_not_iter ic b r) in Hban. discriminate Hban.
Qed.

(* ---------- denE_total_pairwise: the § 13.2 recorded item, delivered ----------
   Totality run with BOTH budgets in one induction: for a checked node and any
   two fuels at or above its own budget, the two evaluations are equ-bisimilar.
   Same induction shape as denE_total (induction on the first fuel, everything
   else reverted, the second fuel case-split per arm).  What the arms cost is
   the interesting fact (docs/DESIGN-NOTES.md § 13.6): five arms close because
   the peeled tree is FUEL-FREE - apply_c (Semantics.v:271) consumes its budget
   at the head arm and the VPrim arm returns `sret (prim_sres ...)` with no
   fuel anywhere, so App/TupE/Unify/Ret peel both sides to the literal same
   tree and the bridge is reflexivity (the prim bridge lemmas, which only turn
   that stuck tree into `SOk w`, are not needed - and with them unused, none of
   the prim rows' ws_val side conditions are needed either).  Only Seq and
   Block recurse, bridging the surviving component's two fuels through the IH.
   G2 arms are contradictions, as in denE_total. *)

(* The App arm's two-budget peel.  Both sides run the canonical node through
   the same path analysis of app_node_ok_shape (shared hypotheses, destructed
   once), then peel per side with the per-side k-split; the tails are the same
   stuck prim tree on both sides, modulo the fuels that apply_c already ate. *)
Lemma denE_App_pairwise : forall m1 m2 rho d p a,
  env_ok d rho = true -> ws_expr d a = true ->
  app_node_ok (Ret (VPrim p)) a = true ->
  Nat.le (e_fuel (App (Ret (VPrim p)) a)) m1 ->
  Nat.le (e_fuel (App (Ret (VPrim p)) a)) m2 ->
  denE rho (App (Ret (VPrim p)) a) m1 ≅ denE rho (App (Ret (VPrim p)) a) m2.
Proof.
  intros m1 m2 rho d p a Henv Hws Hcanon Hf1 Hf2.
  apply (app_node_ok_shape (Ret (VPrim p)) a) in Hcanon.
  destruct Hcanon as [q [vs [Hq [Hops Hpath]]]]. inversion Hq. subst q.
  cbn [e_fuel] in Hf1, Hf2.
  assert (Hm1 : exists n, m1 = S (S n))
    by (exists (m1 - 2); assert (Hfa := e_fuel_pos a); lia).
  assert (Hm2 : exists n, m2 = S (S n))
    by (exists (m2 - 2); assert (Hfa := e_fuel_pos a); lia).
  destruct Hm1 as [n1 Hm1]. destruct Hm2 as [n2 Hm2].
  rewrite Hm1, Hm2. cbn [e_fuel] in Hf1, Hf2.
  destruct Hpath as [Hpath | [Hpath | Hpath]].
  - (* (a) all-int operands, both encodings: peel each side to the same prim tree *)
    apply andb_and in Hpath. destruct Hpath as [Hall Hres].
    apply (prim_operand_vals_inv a vs) in Hops.
    destruct Hops as [Hops | Hops].
    + destruct Hops as [es [Ha Hret]]. subst a.
      assert (Hmap : es = map Ret vs) by (exact (rets_of_map_rets es vs Hret)). subst es.
      cbn [e_fuel sumE] in Hf1, Hf2. rewrite sumE_e_fuel_map_ret in Hf1, Hf2.
      assert (Hk1 : exists k, n1 = S (length vs + k))
        by (exists (n1 - S (length vs)); lia).
      assert (Hk2 : exists k, n2 = S (length vs + k))
        by (exists (n2 - S (length vs)); lia).
      destruct Hk1 as [k1 Hk1]. destruct Hk2 as [k2 Hk2].
      rewrite Hk1, Hk2.
      cbn [denE denE_tup sret].
      rewrite closeV_prim. cbn [sret].
      setoid_rewrite bind_ret_l. cbn [sret].
      setoid_rewrite (denE_tup_rets vs nil rho k1).
      setoid_rewrite (denE_tup_rets vs nil rho k2).
      cbn [rev app sret].
      setoid_rewrite bind_ret_l. cbn [sret apply_c].
      reflexivity.
    + destruct Hops as [v [Ha Heqvs]]. subst a. subst vs.
      cbn [denE denE_tup sret].
      rewrite closeV_prim. cbn [sret].
      setoid_rewrite bind_ret_l. cbn [sret].
      setoid_rewrite bind_ret_l. cbn [sret apply_c].
      reflexivity.
  - (* (b) table operands through a TupE operand list *)
    destruct Hpath as [es [Ha [Hret Hargs]]]. subst a.
    assert (Hmap : es = map Ret vs) by (exact (rets_of_map_rets es vs Hret)). subst es.
    cbn [e_fuel sumE] in Hf1, Hf2. rewrite sumE_e_fuel_map_ret in Hf1, Hf2.
    assert (Hk1 : exists k, n1 = S (length vs + k))
      by (exists (n1 - S (length vs)); lia).
    assert (Hk2 : exists k, n2 = S (length vs + k))
      by (exists (n2 - S (length vs)); lia).
    destruct Hk1 as [k1 Hk1]. destruct Hk2 as [k2 Hk2].
    rewrite Hk1, Hk2.
    cbn [denE denE_tup sret].
    rewrite closeV_prim. cbn [sret].
    setoid_rewrite bind_ret_l. cbn [sret].
    setoid_rewrite (denE_tup_rets vs nil rho k1).
    setoid_rewrite (denE_tup_rets vs nil rho k2).
    cbn [rev app sret].
    setoid_rewrite bind_ret_l. cbn [sret apply_c].
    reflexivity.
  - (* (b') table operands through a bare `Ret v` operand *)
    destruct Hpath as [v [Ha Hbare]]. subst a.
    cbn [denE denE_tup sret].
    rewrite closeV_prim. cbn [sret].
    setoid_rewrite bind_ret_l. cbn [sret].
    setoid_rewrite bind_ret_l. cbn [sret apply_c].
    reflexivity.
Qed.

Lemma denE_total_pairwise : forall m1 m2 e d rho,
  ws_expr d e = true -> env_ok d rho = true -> det_struct e = true ->
  Nat.le (e_fuel e) m1 -> Nat.le (e_fuel e) m2 ->
  denE rho e m1 ≅ denE rho e m2.
Proof.
  induction m1 as [| n1 IH]; intros m2 e d rho Hw Henv Hds Hf1 Hf2.
  - assert (Hp := e_fuel_pos e). lia.
  - destruct m2 as [| n2]; [assert (Hp := e_fuel_pos e); lia |].
    destruct e as [v | gid | f a | es | e1 e2 | u1 u2 | c1 c2 | | sl body | ic b r].
    + (* Ret *) cbn [denE]. reflexivity.
    + (* Glob: G2 *)
      apply det_struct_components in Hds. destruct Hds as [Hban _].
      rewrite (bans_okE_not_glob gid) in Hban. discriminate Hban.
    + (* App: G5 - the two-budget peel is denE_App_pairwise *)
      apply det_struct_components in Hds. destruct Hds as [_ [_ [_ [Happs _]]]].
      assert (Hnode := apps_okE_node f a Happs).
      apply (app_node_ok_shape f a) in Hnode.
      destruct Hnode as [p [vs [Hf [Hops Hpath]]]]. subst f.
      cbn [ws_expr] in Hw. apply andb_and in Hw. destruct Hw as [_ Hwa].
      exact (denE_App_pairwise (S n1) (S n2) rho d p a Henv Hwa
               (apps_okE_node (Ret (VPrim p)) a Happs) Hf1 Hf2).
    + (* TupE: G6 pins `map Ret vs`; both sides peel to the same closed tuple *)
      apply det_struct_components in Hds. destruct Hds as [_ [_ [_ [_ Htup]]]].
      apply (tup_rets_okE_node es) in Htup.
      apply (tup_node_ok_rets es) in Htup.
      destruct Htup as [vs Hret].
      assert (Hmap : es = map Ret vs) by (exact (rets_of_map_rets es vs Hret)). subst es.
      cbn [e_fuel sumE] in Hf1, Hf2. rewrite sumE_e_fuel_map_ret in Hf1, Hf2.
      assert (Hk1 : exists k, n1 = S (length vs + k))
        by (exists (n1 - S (length vs)); lia).
      assert (Hk2 : exists k, n2 = S (length vs + k))
        by (exists (n2 - S (length vs)); lia).
      destruct Hk1 as [k1 Hk1]. destruct Hk2 as [k2 Hk2].
      rewrite Hk1, Hk2. cbn [denE].
      setoid_rewrite (denE_tup_rets vs nil rho k1).
      setoid_rewrite (denE_tup_rets vs nil rho k2).
      cbn [rev app]. reflexivity.
    + (* Seq: peel each side to its own fuel of the surviving component, bridge with IH *)
      apply (det_struct_Seq_inv e1 e2) in Hds. destruct Hds as [Hds1 Hds2].
      apply andb_and in Hw. destruct Hw as [Hw1 Hw2].
      cbn [e_fuel] in Hf1, Hf2.
      assert (Hp1 := e_fuel_pos e1). assert (Hp2 := e_fuel_pos e2).
      assert (Hle11 : Nat.le (e_fuel e1) n1) by lia.
      assert (Hle12 : Nat.le (e_fuel e1) n2) by lia.
      assert (Hle21 : Nat.le (e_fuel e2) n1) by lia.
      assert (Hle22 : Nat.le (e_fuel e2) n2) by lia.
      destruct (denE_total n1 e1 d rho Hw1 Henv Hds1 Hle11) as [v1a He1a].
      destruct (denE_total n2 e1 d rho Hw1 Henv Hds1 Hle12) as [v1b He1b].
      assert (P1 : denE rho (Seq e1 e2) (S n1) ≅ denE rho e2 n1).
      { cbn [denE]. setoid_rewrite He1a. rewrite bind_sret_l. cbn [denE].
        reflexivity. }
      assert (P2 : denE rho (Seq e1 e2) (S n2) ≅ denE rho e2 n2).
      { cbn [denE]. setoid_rewrite He1b. rewrite bind_sret_l. cbn [denE].
        reflexivity. }
      rewrite P1, P2.
      refine (IH n2 e2 _ rho Hw2 Henv Hds2 Hle21 Hle22).
    + (* Unify: G4 pins the EqK1 literal pair; both sides peel to `ret w1` *)
      apply det_struct_components in Hds. destruct Hds as [_ [_ [Hu [_ _]]]].
      apply (unify_okE_pair u1 u2) in Hu.
      apply (eq_pair_ok_shape u1 u2) in Hu.
      destruct Hu as [w1 [w2 [Hu1 [Hu2 [Hl1 [Hl2 Heq]]]]]]. subst u1 u2.
      cbn [e_fuel] in Hf1, Hf2.
      destruct n1 as [| f1]; [lia |]. destruct n2 as [| f2]; [lia |].
      transitivity (sret (SOk w1)).
      { cbn [denE]. cbn [sret].
        setoid_rewrite bind_ret_l. cbn [sret].
        setoid_rewrite bind_ret_l. cbn [sret].
        rewrite (closeV_lit rho w1 Hl1). rewrite (closeV_lit rho w2 Hl2).
        rewrite (unify_top_lit w1 w2 f1 Hl1 Hl2 Heq).
        reflexivity. }
      { symmetry. cbn [denE]. cbn [sret].
        setoid_rewrite bind_ret_l. cbn [sret].
        setoid_rewrite bind_ret_l. cbn [sret].
        rewrite (closeV_lit rho w1 Hl1). rewrite (closeV_lit rho w2 Hl2).
        rewrite (unify_top_lit w1 w2 f2 Hl1 Hl2 Heq).
        reflexivity. }
    + (* Choice: G2 *)
      apply det_struct_components in Hds. destruct Hds as [Hban _].
      rewrite (bans_okE_not_choice c1 c2) in Hban. discriminate Hban.
    + (* Fail: G2 *)
      apply det_struct_components in Hds. destruct Hds as [Hban _].
      rewrite bans_okE_not_fail in Hban. discriminate Hban.
    + (* Block: G3 - one closeSlots_int, the two body fuels bridge through IH *)
      apply (det_struct_Block_inv sl body) in Hds. destruct Hds as [Hdsb Hslots].
      apply andb_and in Hw. destruct Hw as [Hwslo Hwsb].
      cbn [e_fuel] in Hf1, Hf2.
      assert (Hle1 : Nat.le (e_fuel body) n1) by lia.
      assert (Hle2 : Nat.le (e_fuel body) n2) by lia.
      destruct (closeSlots_int sl rho d Hslots Hwslo Henv) as [rho' [HE Hint]].
      assert (PB1 : denE rho (Block sl body) (S n1) ≅ denE rho' body n1).
      { cbn [denE]. rewrite HE. cbn [denE]. reflexivity. }
      assert (PB2 : denE rho (Block sl body) (S n2) ≅ denE rho' body n2).
      { cbn [denE]. rewrite HE. cbn [denE]. reflexivity. }
      rewrite PB1, PB2.
      refine (IH n2 body _ rho' Hwsb Hint Hdsb Hle1 Hle2).
    + (* Iter: G2 *)
      apply det_struct_components in Hds. destruct Hds as [Hban _].
      rewrite (bans_okE_not_iter ic b r) in Hban. discriminate Hban.
Qed.

(* T4_sem (docs/PLAN.md § 3 item 4, corpus shape per the header): a checked
   term denotes to exactly one value at every fuel at or above its own budget.
   The empty environment satisfies the int-frame invariant trivially; the
   transport is the same `equ_wbisim_subrelation` step Denotation.v uses for
   every T1 row (WBisim.v:310). *)
Import WBisimNotations.

Theorem T4_sem : forall e k,
  det_check e = true -> exists v, denote e (e_fuel e + k) ≈ sret (SOk v).
Proof.
  intros e k Hc. apply det_check_components in Hc. destruct Hc as [Hw Hds].
  assert (Henv : env_ok 0 nil = true) by (apply env_ok_mk; [lia | reflexivity]).
  assert (Hfuel : Nat.le (e_fuel e) (e_fuel e + k)) by lia.
  destruct (denE_total (e_fuel e + k) e 0 nil Hw Henv Hds Hfuel) as [v He].
  exists v. apply equ_wbisim_subrelation. exact He.
Qed.

(* Fuel-independence corollaries (docs/DESIGN-NOTES.md § 13.2).  Part 1, here:
   at a FIXED fuel the value of an accepted term is unique - two witnesses
   chain through their shared middle node and ctrees' pure inversion
   `equ_ret_inv` (Equ.v:296) splits the resulting pure pair.  Two honest
   boundaries, both learned the hard way:
   - The inversion lives at the EQU level (≅), which is exactly where
     denE_total's witnesses live; the wbisim twin `wbisim_ret_inv`
     (WBisim.v:614) is not applicable to kernel trees, because its class
     constraint `B0 -< C` pins it to ctrees' own base event type B0 and
     instance search fails against the kernel's B2.  The kernel's only route
     from ≅ to ≈ remains the `equ_wbisim_subrelation` transport T4_sem uses.
   - A chain cannot do the CROSS-fuel statement: witnesses `A(j) ≈ sret vj`
     and `A(k) ≈ sret vk` at different fuels share no middle node, so
     "the whole family is pairwise ≈" is not a setoid exercise.  It needs a
     two-fuel strengthening of the totality lemma (denE_total running both
     budgets in one induction), recorded as the `denE_total_pairwise` item
     in § 13.2 - the honest shape of "fuel does not change the value". *)
Theorem T4_value_unique : forall e m v w,
  denote e m ≅ sret (SOk v) -> denote e m ≅ sret (SOk w) -> v = w.
Proof.
  intros e m v w Hj Hw.
  assert (Hpur : sret (SOk v) ≅ sret (SOk w)).
  { transitivity (denote e m). symmetry. exact Hj. exact Hw. }
  (* `sret` is transparently `go (RetF .)`, so equ_ret_inv instantiates at
     the SResult layer and yields `SOk v = SOk w`; constructor injection is
     one step down. *)
  pose proof (equ_ret_inv _ _ Hpur) as Hi.
  now injection Hi.
Qed.

(* T5, accepted-fragment part (docs/PLAN.md § 3 item 5, measured route
   docs/DESIGN-NOTES.md § 13.3).  Three results, one per what the kernel can
   actually say, all set by the Seq arm (Semantics.v:218): `SOk _ => denE rho
   e2 n` - a seq DISCARDS the prefix's value.

   1. T5_swap_discarded: swapping two fragments at a DISCARDED prefix
      position is Wbisim.  Both sides peel to the literal same tail term, so
      there is no cross-fuel step and no coinduction: the fuel induction of
      totality (denE_total) supplies the two component witnesses at exactly
      the fuels the arms query, and § 12.2's peeling idiom (setoid_rewrite
      the witness, rewrite bind_sret_l, cbn) finishes.  The discarded values
      appear nowhere in the conclusion - that is what "discarded" buys.
      Corpus witnesses: e_oo_left vs e_oo_swap in coq/tests/ChecksTest.v
      (prefix swapped, `sub 9 1` tail shared), Group D of
      tests/corpus/m2-det.texpr.
   2. T5_swap_equal_values: a top-position swap holds when both fragments are
      witnessed at the same value - the condition the Seq arm silently
      imposes, stated with the witnesses as hypotheses.
   3. T5_top_swap_needs_value: the naive reading of T5 is REFUTED - swapping
      the surviving suffix changes the value, so seq (ret z1; ret z2) and its
      swap are not even equ-bisimilar for z1 <> z2.  The negation is stated
      at the equ level: at ≈ it would need the wbisim-side inversion § 13.2
      recorded as unavailable to kernel trees (the B0 pin).

   The fold/reassociate half (T5_swap_assoc below) was blocked on exactly one
   thing, which the pairwise lemma right after denE_total now supplies: peeling
   its two sides queries e3 at DIFFERENT fuels (S f vs f under a SHARED budget -
   e_fuel is S over a sum, so both assoc shapes carry the same budget), and
   denE_total_pairwise bridges that gap. *)

Lemma T5_swap_discarded_equ : forall e1 e2 e3 f,
  ws_expr 0 (Seq (Seq e1 e2) e3) = true ->
  env_ok 0 nil = true ->
  det_struct (Seq (Seq e1 e2) e3) = true ->
  Nat.le (e_fuel (Seq (Seq e1 e2) e3)) (S (S f)) ->
  denE nil (Seq (Seq e1 e2) e3) (S (S f))
    ≅ denE nil (Seq (Seq e2 e1) e3) (S (S f)).
Proof.
  intros e1 e2 e3 f Hw Henv Hds Hfuel.
  cbn [e_fuel] in Hfuel.
  assert (Hle1 : Nat.le (e_fuel e1) f) by lia.
  assert (Hle2 : Nat.le (e_fuel e2) f) by lia.
  apply andb_and in Hw. destruct Hw as [Hw12 Hw3].
  apply andb_and in Hw12. destruct Hw12 as [Hw1 Hw2].
  apply det_struct_Seq_inv in Hds. destruct Hds as [Hds12 Hds3].
  apply det_struct_Seq_inv in Hds12. destruct Hds12 as [Hds1 Hds2].
  destruct (denE_total f e1 0 nil Hw1 Henv Hds1 Hle1) as [v1 He1].
  destruct (denE_total f e2 0 nil Hw2 Henv Hds2 Hle2) as [v2 He2].
  transitivity (denE nil e3 (S f)).
  - (* forward order, peeled to the shared tail *)
    cbn [denE].
    setoid_rewrite He1. rewrite bind_sret_l. cbn [denE].
    setoid_rewrite He2. rewrite bind_sret_l. cbn [denE].
    reflexivity.
  - (* swapped order, same tail, witnesses mirrored *)
    cbn [denE].
    setoid_rewrite He2. rewrite bind_sret_l. cbn [denE].
    setoid_rewrite He1. rewrite bind_sret_l. cbn [denE].
    reflexivity.
Qed.

Theorem T5_swap_discarded : forall e1 e2 e3 k,
  det_check (Seq (Seq e1 e2) e3) = true ->
  denote (Seq (Seq e1 e2) e3) (e_fuel (Seq (Seq e1 e2) e3) + k) ≈
  denote (Seq (Seq e2 e1) e3) (e_fuel (Seq (Seq e1 e2) e3) + k).
Proof.
  intros e1 e2 e3 k Hc. apply det_check_components in Hc. destruct Hc as [Hw Hds].
  assert (Henv : env_ok 0 nil = true) by (apply env_ok_mk; [lia | reflexivity]).
  assert (Hfuel : Nat.le (e_fuel (Seq (Seq e1 e2) e3))
                         (e_fuel (Seq (Seq e1 e2) e3) + k)) by lia.
  (* a two-level Seq has e_fuel >= 2, so every sufficient budget is S (S f).
     (pose, not an ex-assert: in this file's notation scope the bare `exists`
     notation resolves to ctrees' indexed-family one - the same loadpath that
     CTree Require Export re-exports - and its witness type is a category
     carrier, not nat.) *)
  pose (f := (e_fuel (Seq (Seq e1 e2) e3) + k - 2)%nat).
  assert (HF : (e_fuel (Seq (Seq e1 e2) e3) + k)%nat = S (S f))
    by (unfold f; cbn [e_fuel]; lia).
  rewrite HF in Hfuel. rewrite HF.
  unfold denote. apply equ_wbisim_subrelation.
  exact (T5_swap_discarded_equ e1 e2 e3 f Hw Henv Hds Hfuel).
Qed.

Lemma T5_swap_equal_values : forall e1 e2 f v,
  denE nil e1 f ≅ sret (SOk v) ->
  denE nil e2 f ≅ sret (SOk v) ->
  denE nil (Seq e1 e2) (S f) ≅ denE nil (Seq e2 e1) (S f).
Proof.
  intros e1 e2 f v He1 He2.
  (* Peel each side to the surviving component FIRST, as separate equations:
     on the combined goal the other component also occurs inside the Seq
     continuation lambda, and a setoid_rewrite reaching into that lambda is
     where ctrees' setoid machinery refuses (the same position-search
     structure § 12.2 measured).  Split, each side has one occurrence. *)
  assert (P1 : denE nil (Seq e1 e2) (S f) ≅ denE nil e2 f).
  { cbn [denE]. setoid_rewrite He1. rewrite bind_sret_l. cbn [denE].
    reflexivity. }
  assert (P2 : denE nil (Seq e2 e1) (S f) ≅ denE nil e1 f).
  { cbn [denE]. setoid_rewrite He2. rewrite bind_sret_l. cbn [denE].
    reflexivity. }
  rewrite P1, P2.
  (* both survivors carry the shared witness - the swap closes *)
  rewrite He2, He1. reflexivity.
Qed.

Lemma T5_top_swap_needs_value : forall z1 z2, z1 <> z2 ->
  ~ (denote (Seq (Ret (VInt z1)) (Ret (VInt z2))) 3
     ≅ denote (Seq (Ret (VInt z2)) (Ret (VInt z1))) 3).
Proof.
  intros z1 z2 Hz H. unfold denote in H. cbn [denE] in H.
  setoid_rewrite bind_sret_l in H. cbn in H.
  pose proof (equ_ret_inv _ _ H) as Hi.
  injection Hi as Zlz.
  exfalso. apply Hz. symmetry. exact Zlz.
Qed.

(* T5's fold/reassociate half, delivered by denE_total_pairwise (the item
   § 13.2 recorded, § 13.4 named its consumer for, § 13.6 closes).  The two
   Seq shapes share e_fuel - `S` over a SUM is associative: both budgets are
   `2 + e_fuel e1 + e_fuel e2 + e_fuel e3` - so the theorem states ONE fuel
   for both.  Peeling at that shared budget: the left side survives as
   `denE nil e3 (S f)`, the right as `denE nil e3 f` - the cross-fuel step
   § 13.4 measured as the blocker, bridged by the pairwise lemma.  Corpus
   witness: e_oo_left vs e_oo_right in coq/tests/ChecksTest.v (Group D's own
   assoc pair over the shared `sub 9 1` tail). *)

Lemma T5_swap_assoc_equ : forall e1 e2 e3 f,
  ws_expr 0 (Seq (Seq e1 e2) e3) = true ->
  env_ok 0 nil = true ->
  det_struct (Seq (Seq e1 e2) e3) = true ->
  Nat.le (e_fuel (Seq (Seq e1 e2) e3)) (S (S f)) ->
  denE nil (Seq (Seq e1 e2) e3) (S (S f))
    ≅ denE nil (Seq e1 (Seq e2 e3)) (S (S f)).
Proof.
  intros e1 e2 e3 f Hw Henv Hds Hfuel.
  cbn [e_fuel] in Hfuel.
  assert (Hp1 := e_fuel_pos e1). assert (Hp2 := e_fuel_pos e2).
  assert (Hp3 := e_fuel_pos e3).
  (* The inner Seq node is witnessed AS A NODE (its ws/det conditions are
     needed whole), so its leaf splits go through pose proof - a plain
     `destruct Hw12 as [Hw1 Hw2]` (the T5_swap_discarded_equ shape) would
     clear Hw12 out of reach of the denE_total call below. *)
  cbn [ws_expr] in Hw.
  apply andb_and in Hw. destruct Hw as [Hw12 Hw3].
  cbn [ws_expr] in Hw12.
  pose proof (andb_and _ _ Hw12) as Hw12c. destruct Hw12c as [Hw1 Hw2].
  apply det_struct_Seq_inv in Hds. destruct Hds as [Hds12 Hds3].
  pose proof (det_struct_Seq_inv e1 e2 Hds12) as Hds12c.
  destruct Hds12c as [Hds1 Hds2].
  assert (Hle12 : Nat.le (e_fuel (Seq e1 e2)) (S f)) by (cbn [e_fuel]; lia).
  assert (Hle1 : Nat.le (e_fuel e1) (S f)) by lia.
  assert (Hle2 : Nat.le (e_fuel e2) f) by lia.
  destruct (denE_total (S f) (Seq e1 e2) 0 nil Hw12 Henv Hds12 Hle12) as [v12 He12].
  destruct (denE_total (S f) e1 0 nil Hw1 Henv Hds1 Hle1) as [v1 He1].
  destruct (denE_total f e2 0 nil Hw2 Henv Hds2 Hle2) as [v2 He2].
  assert (PL : denE nil (Seq (Seq e1 e2) e3) (S (S f)) ≅ denE nil e3 (S f)).
  { cbn [denE]. setoid_rewrite He12. rewrite bind_sret_l. cbn [denE].
    reflexivity. }
  assert (PR : denE nil (Seq e1 (Seq e2 e3)) (S (S f)) ≅ denE nil e3 f).
  { cbn [denE]. setoid_rewrite He1. rewrite bind_sret_l. cbn [denE].
    setoid_rewrite He2. rewrite bind_sret_l. cbn [denE]. reflexivity. }
  assert (Hle3a : Nat.le (e_fuel e3) (S f)) by lia.
  assert (Hle3b : Nat.le (e_fuel e3) f) by lia.
  rewrite PL, PR.
  apply (denE_total_pairwise (S f) f e3 0 nil); assumption.
Qed.

Theorem T5_swap_assoc : forall e1 e2 e3 k,
  det_check (Seq (Seq e1 e2) e3) = true ->
  denote (Seq (Seq e1 e2) e3) (e_fuel (Seq (Seq e1 e2) e3) + k) ≈
  denote (Seq e1 (Seq e2 e3)) (e_fuel (Seq (Seq e1 e2) e3) + k).
Proof.
  intros e1 e2 e3 k Hc. apply det_check_components in Hc. destruct Hc as [Hw Hds].
  assert (Henv : env_ok 0 nil = true) by (apply env_ok_mk; [lia | reflexivity]).
  assert (Hfuel : Nat.le (e_fuel (Seq (Seq e1 e2) e3))
                         (e_fuel (Seq (Seq e1 e2) e3) + k)) by lia.
  pose (f := (e_fuel (Seq (Seq e1 e2) e3) + k - 2)%nat).
  assert (HF : (e_fuel (Seq (Seq e1 e2) e3) + k)%nat = S (S f))
    by (unfold f; cbn [e_fuel]; lia).
  rewrite HF in Hfuel. rewrite HF.
  unfold denote. apply equ_wbisim_subrelation.
  exact (T5_swap_assoc_equ e1 e2 e3 f Hw Henv Hds Hfuel).
Qed.
