(* Timbda-0 soundness:  T1 (`RewSound_*`) per docs/PLAN.md §3 item 1:
   "Rew_r e e' -> Wbisim (sem e) (sem e')", one statement per `Rew` constructor
   in coq/Rewriting.v.  The relation here is ctrees weak bisimilarity `≈`
   (CTree.Eq.WBisim), which is exactly the strategy-insensitive equality the
   candidate-set model uses (VERSE-RULES §6).

   Statement conventions (recorded in docs/RULES-AUDIT.md § 5):

   * Fuel transfer.  The denotation is uniform-fuel (Semantics.v decision 2);
     a rule that deletes/adds an evaluation node changes the budget by exactly
     one per node.  Each lemma therefore quantifies a residual `f` and picks
     the LHS/RHS fuel so that *every sub-evaluation below the rewritten node
     sits at the same fuel on both sides*.  E.g. Seq (Ret v) e -> e needs
     S(S f) on the left (node + value arm) and S f on the right.  Counting the
     `denE`/`denE_tup` nodes of a primitive application: the head `Ret (VPrim p)`
     arm, the `TupE` list arm and one unit per list element, so a k-argument
     primop row uses `S^4 f` (k = 1) and `S^5 f` (k = 2).  A short budget shows
     up as an unreduced `(fix denE ...)` in the goal, never as an error message.
     In the unbounded-fuel limit both sides coincide.

   * Closed-value hypotheses (convention G1).  The paper's rule meta-variables
     range over heap normal forms; the denotation closes values against the
     environment when evaluating them.  Where the rule's own hypothesis is
     sensitive to that closing (IsInt2: `isInt[x]` when x has a value; the
     Prim schema), the RewSound hypothesis is stated on the closed instance,
     mirroring the audit strategy order (Subst rewrites valued slots to their
     values before IsInt fires).  The named Fig. 10 rows (Add/Gt1/Gt2/IsInt1/
     IsInt2/Cons/DotDot) carry the constructor hypotheses verbatim, up to G1.

   * Beta-t0 relies on the fail-short-circuit in the App arm (Semantics.v
     decision 5): the rule discards `e`, so its fuel `S(S f)` only covers the
     function arm.

   Discharged here (15 named ctors + the two schema ctors at the arities the kernel
   uses, plus the T2 choice/branch algebra):
     EqK1 EqK2 EqTup2 EqFail Add Gt1 Gt2 IsInt1 IsInt2 Cons DotDot
     Prim1 Prim2 PrimFail1 PrimFail2 Seq BetaT0 HpAlpha LamAlpha
     Denote_Choice, Br2_{Commut,Assoc,Idem,StuckL}_W
   Deferred to M3/T1 (18 ctors + the 2 schema generalizations), recorded per ctor in
   docs/RULES-AUDIT.md sections 1-3, with the reason class:
     evolving-heap (kernel decision 3 makes a `None`-slot block SStuck, so the
     LHS/RHS denotations genuinely differ until block-slot semantics exists):
       BetaL BetaT Subst Gc1 PromoteL PromoteR Float
     schema/chain induction (needs a unify_seq/eq_seq computation lemma; the
     Prim schema at a *variable-length* argument list likewise needs the
     length-indexed fuel accounting over denE_tup):
       EqTup1, Prim_n-ary, PrimFail_n-ary
     fuel rebudgeting (needs a fuel-monotonicity lemma):  Norm1 Norm2 Norm3
       Norm4 Norm5
     iter/choice corner (needs closeSlots composition + the bind/br2
     interchange at ≈):  IterFail IterChoice IterIf IterAll IterFor

   No axioms are introduced by this file: every Lemma below is proved.  The
   deferred rows carry no statement yet (a false statement would be worse than
   none - under decision 3 their LHS/RHS denotations differ on open `None`-slot
   terms).  `Print Assumptions` at the bottom shows the only axiom any row
   inherits: `Eqdep.Eq_rect_eq`, which ctrees' own coinduction/Program layer is
   built on (deps/ctrees/theories/Eq, built with Program), not anything Timbda adds.
 *)

From Stdlib Require Import ZArith List.
(* Stdlib.Bool is deliberately NOT imported here: its exported `&&&` notation
   at level 40 clashes hard with the ctrees chain's level-59 requirement (a
   load-time clash in either import order).  Bool arrives transitively
   through Timbda.Syntax without its notation table. *)
From CTree Require Import CTree Eq.
From CTree.Eq Require Import WBisim.
Import WBisimNotations.
Import EquNotations.
Import CTreeNotations.
Import ListNotations.
Local Open Scope ctree_scope.

Require Import Timbda.Syntax Timbda.Rewriting Timbda.Semantics.

(* ---------- shared cbn vocabulary ----------
   `bind` is a cofixpoint (CTree.subst) and does NOT reduce definitionally:
   `bind (sret x) k = k x` is unprovable by `cbv`/`reflexivity`.  Every
   computation lemma therefore (a) transports the goal to ctrees' structural
   equality `≅` (equ), where the monad law `bind_ret_l` is provable and
   admissible under `≈` through the global Proper instances, (b) rewrites with
   it, and (c) normalizes with a *fixed delta list*.  Fixpoints such as `negb`,
   `andb`, `rev` only reduce when they are in that list; `Z.eqb`/`Z.ltb` are
   deliberately kept out so that rule hypotheses can be matched against them. *)

(* Coq 9 delta lists are space-separated: `cbn [a, b]` is a syntax error. *)
Ltac kernel_cbn :=
  cbn [denE denE_tup apply_c iter_step closeSlots closeV closeE
       prim_app prim_total prim_sres unify_top unify_seq sret
       root_of root_eqb no_eq_rule_pair is_lit_val is_int_val lit_eqb
       walkSlotsV anySlotsV negb andb rev app length].

Ltac kernel_cbn_foldprim :=
  cbn [denE denE_tup apply_c iter_step closeSlots closeV closeE
       prim_app prim_sres unify_top unify_seq sret
       root_of root_eqb no_eq_rule_pair is_lit_val is_int_val lit_eqb
       walkSlotsV anySlotsV negb andb rev app length].

(* Full normalization: prim_total is unfolded as well. *)
Ltac t1_norm := apply equ_wbisim_subrelation;
  repeat (setoid_rewrite bind_ret_l; kernel_cbn).

(* Normalization that keeps `prim_total p [...]` folded, for rows whose
   hypothesis is an equation about it (the Fig. 10 schema rows). *)
Ltac t1_fold := apply equ_wbisim_subrelation;
  repeat (setoid_rewrite bind_ret_l; kernel_cbn_foldprim).

(* ---------- helpers ---------- *)

Lemma closeV_lit (rho : env) (v : Val) :
  is_lit_val v = true -> closeV 0 rho v = v.
Proof. destruct v; simpl; auto; discriminate. Qed.

Lemma closeV_map_VInt (rho : env) (l : list Z) :
  map (closeV 0 rho) (map VInt l) = map VInt l.
Proof.
  (* `simpl` closes the base goal itself in some builds, so the proof below is
     written as a goal-count-independent sequence rather than a 2-branch focus. *)
  induction l; simpl; try reflexivity; rewrite IHl; reflexivity.
Qed.

Lemma zeqb_self_true : forall x : Z, Z.eqb x x = true.
Proof. intros x. apply (proj2 (Z.eqb_eq x x)); reflexivity. Qed.

(* Fig. 10 reflection facts: each named primop's kernel computation, expressed
   as an equation that the rows can rewrite with. *)
Lemma prim_total_PGt_true : forall (a b : Z),
  Z.ltb b a = true -> prim_total PGt [VInt a; VInt b] = PRes (VInt a).
Proof. intros a b H. cbn [prim_total]. rewrite H. reflexivity. Qed.

Lemma prim_total_PGt_false : forall (a b : Z),
  Z.ltb b a = false -> prim_total PGt [VInt a; VInt b] = PFail.
Proof. intros a b H. cbn [prim_total]. rewrite H. reflexivity. Qed.

Lemma prim_total_PIsInt_fail : forall u : Val,
  is_int_val u = false -> prim_total PIsInt [u] = PFail.
Proof.
  intros u H. destruct u; cbn in H; try discriminate; cbn; reflexivity.
Qed.

Lemma denE_ret_S (rho : env) (v : Val) (f : nat) :
  denE rho (Ret v) (S f) = sret (SOk (closeV 0 rho v)).
Proof. reflexivity. Qed.

(* ---------- Fig. 9 : unification rows ---------- *)

Lemma RewSound_EqK1 : forall (v : Val) (rho : env) (f : nat),
  is_lit_val v = true ->
  denE rho (Unify (Ret v) (Ret v)) (S (S f))
    ≈ denE rho (Ret v) (S (S f)).
Proof.
  (* The whole per-case discharge lives in one `;` chain: after a `;`-branch
     tactical Ltac1 shelves the sibling goals, so a `.`-terminated step would
     only run in one of them. *)
  intros v rho f H; cbn in H;
  destruct v; cbn in H; try discriminate;
  t1_norm; try (rewrite zeqb_self_true); kernel_cbn; reflexivity.
Qed.

Lemma RewSound_EqK2 : forall (v1 v2 : Val) (rho : env) (f : nat),
  is_lit_val v1 = true -> is_lit_val v2 = true -> v1 <> v2 ->
  denE rho (Unify (Ret v1) (Ret v2)) (S (S f))
    ≈ denE rho Fail (S (S f)).
Proof.
  (* One `;` chain for the same shelving reason as in RewSound_EqK1. *)
  intros v1 v2 rho f H1 H2 Hne; cbn in H1, H2;
  destruct v1, v2; cbn in H1, H2; try discriminate;
  try (exfalso; apply Hne; reflexivity);
  t1_norm; try reflexivity;
  match goal with
  | Hdiff : VInt ?a <> VInt ?b |- context[ Z.eqb ?a ?b ] =>
      destruct (Z.eqb a b) eqn:E;
      [ exfalso; apply Hdiff; f_equal; apply (proj1 (Z.eqb_eq a b)); exact E
      | try (rewrite E); kernel_cbn; reflexivity ]
  end;
  reflexivity.
Qed.

Lemma RewSound_EqTup2 : forall (vs ws : list Val) (rho : env) (f : nat),
  length vs <> length ws ->
  denE rho (Unify (Ret (VTup vs)) (Ret (VTup ws))) (S (S f))
    ≈ denE rho Fail (S (S f)).
Proof.
  intros vs ws rho f Hlen; t1_norm;
  match goal with
  | Hlen : length ?vs <> length ?ws
    |- context[ Nat.eqb (length (map (closeV 0 ?rho) ?vs))
                (length (map (closeV 0 ?rho) ?ws)) ] =>
      destruct (Nat.eqb (length (map (closeV 0 rho) vs))
                           (length (map (closeV 0 rho) ws))) eqn:E;
      [ exfalso; apply Hlen;
        pose proof (proj1 (Nat.eqb_eq _ _) E) as H2;
        rewrite !length_map in H2; exact H2
      | try (rewrite E); kernel_cbn; reflexivity ]
  end.
Qed.

Lemma RewSound_EqFail : forall (v1 v2 : Val) (rho : env) (f : nat),
  root_mismatch v1 v2 = true ->
  denE rho (Unify (Ret v1) (Ret v2)) (S (S f))
    ≈ denE rho Fail (S (S f)).
Proof.
  intros v1 v2 rho f Hm. cbn in Hm.
  destruct v1, v2; cbn in Hm; try discriminate; t1_norm; reflexivity.
Qed.

(* ---------- Fig. 10 : primitive-operation rows ---------- *)

Lemma RewSound_Add : forall (a b : Z) (rho : env) (f : nat),
  denE rho (prim_app PAdd [Ret (VInt a); Ret (VInt b)]) (S (S (S (S (S f)))))
    ≈ denE rho (Ret (VInt (a + b))) (S (S (S (S (S f))))).
Proof. intros. t1_norm; reflexivity. Qed.

Lemma RewSound_Gt1 : forall (a b : Z) (rho : env) (f : nat),
  Z.ltb b a = true ->
  denE rho (prim_app PGt [Ret (VInt a); Ret (VInt b)]) (S (S (S (S (S f)))))
    ≈ denE rho (Ret (VInt a)) (S (S (S (S (S f))))).
Proof.
  intros a b rho f H. t1_fold.
  rewrite (prim_total_PGt_true a b H). kernel_cbn. reflexivity.
Qed.

Lemma RewSound_Gt2 : forall (a b : Z) (rho : env) (f : nat),
  Z.ltb b a = false ->
  denE rho (prim_app PGt [Ret (VInt a); Ret (VInt b)]) (S (S (S (S (S f)))))
    ≈ denE rho Fail (S (S (S (S (S f))))).
Proof.
  intros a b rho f H. t1_fold.
  rewrite (prim_total_PGt_false a b H). kernel_cbn. reflexivity. Qed.

Lemma RewSound_IsInt1 : forall (a : Z) (rho : env) (f : nat),
  denE rho (prim_app PIsInt [Ret (VInt a)]) (S (S (S (S f))))
    ≈ denE rho (Ret (VInt a)) (S (S (S (S f)))).
Proof. intros. t1_norm; reflexivity. Qed.

(* G1: the hypothesis is about the closed instance of the argument (convention
   above).  `prim_total_PIsInt_fail` is stated for an arbitrary value term, so
   it applies to the closed argument without inspecting how it was closed. *)
Lemma RewSound_IsInt2 : forall (v : Val) (rho : env) (f : nat),
  is_int_val (closeV 0 rho v) = false ->
  denE rho (prim_app PIsInt [Ret v]) (S (S (S (S f))))
    ≈ denE rho Fail (S (S (S (S f)))).
Proof.
  intros v rho f H. t1_fold.
  rewrite (prim_total_PIsInt_fail (closeV 0 rho v) H). kernel_cbn. reflexivity.
Qed.

Lemma RewSound_Cons : forall (v0 : Val) (vs : list Val) (rho : env) (f : nat),
  denE rho (prim_app PCons [Ret v0; Ret (VTup vs)]) (S (S (S (S (S f)))))
    ≈ denE rho (Ret (VTup (v0 :: vs))) (S (S (S (S (S f))))).
Proof. intros. t1_norm; reflexivity. Qed.

Lemma RewSound_DotDot : forall (a b : Z) (rho : env) (f : nat),
  denE rho (prim_app PDotDot [Ret (VInt a); Ret (VInt b)]) (S (S (S (S (S f)))))
    ≈ denE rho (Ret (VTup (map VInt (seq_z a b)))) (S (S (S (S (S f))))).
Proof. intros. t1_norm; rewrite closeV_map_VInt; kernel_cbn; reflexivity. Qed.

(* PrimSchema rows, at the arities the kernel prim_total table actually uses
   (1 and 2).  The hypothesis is the closed instance (G1); the general
   variable-length form is deferred - see the header list. *)

Lemma RewSound_Prim1 : forall (p : Prim) (v0 v : Val) (rho : env) (f : nat),
  prim_total p [closeV 0 rho v0] = PRes (closeV 0 rho v) ->
  denE rho (prim_app p [Ret v0]) (S (S (S (S f))))
    ≈ denE rho (Ret v) (S (S (S (S f)))).
Proof.
  intros p v0 v rho f Hprim. t1_fold.
  rewrite Hprim. kernel_cbn. reflexivity.
Qed.

Lemma RewSound_Prim2 : forall (p : Prim) (v1 v2 v : Val) (rho : env) (f : nat),
  prim_total p [closeV 0 rho v1; closeV 0 rho v2] = PRes (closeV 0 rho v) ->
  denE rho (prim_app p [Ret v1; Ret v2]) (S (S (S (S (S f)))))
    ≈ denE rho (Ret v) (S (S (S (S (S f))))).
Proof.
  intros p v1 v2 v rho f Hprim. t1_fold.
  rewrite Hprim. kernel_cbn. reflexivity.
Qed.

Lemma RewSound_PrimFail1 : forall (p : Prim) (v0 : Val) (rho : env) (f : nat),
  prim_total p [closeV 0 rho v0] = PFail ->
  denE rho (prim_app p [Ret v0]) (S (S (S (S f))))
    ≈ denE rho Fail (S (S (S (S f)))).
Proof.
  intros p v0 rho f Hprim. t1_fold.
  rewrite Hprim. kernel_cbn. reflexivity.
Qed.

Lemma RewSound_PrimFail2 : forall (p : Prim) (v1 v2 : Val) (rho : env) (f : nat),
  prim_total p [closeV 0 rho v1; closeV 0 rho v2] = PFail ->
  denE rho (prim_app p [Ret v1; Ret v2]) (S (S (S (S (S f)))))
    ≈ denE rho Fail (S (S (S (S (S f))))).
Proof.
  intros p v1 v2 rho f Hprim. t1_fold.
  rewrite Hprim. kernel_cbn. reflexivity.
Qed.

(* ---------- Fig. 11 / Fig. 12 : structural rows ---------- *)

Lemma RewSound_BetaT0 : forall (e : Expr) (rho : env) (f : nat),
  denE rho (App (Ret (VTup (@nil Val))) e) (S (S f))
    ≈ denE rho Fail (S (S f)).
Proof. intros. t1_norm; reflexivity. Qed.

Lemma RewSound_Seq : forall (v : Val) (e : Expr) (rho : env) (f : nat),
  denE rho (Seq (Ret v) e) (S (S f)) ≈ denE rho e (S f).
Proof. intros. t1_norm; reflexivity. Qed.

(* HpAlpha / LamAlpha are the renaming rules: under the de Bruijn representation
   a renaming *is* the identity, so the constructor witnesses the trivial
   rewrite and soundness is `≈`-reflexivity (RULES-AUDIT note). *)
Lemma RewSound_HpAlpha :
  forall (slots : list (Ty * option Val)) (body : Expr) (rho : env) (f : nat),
  denE rho (Block slots body) f ≈ denE rho (Block slots body) f.
Proof. intros. reflexivity. Qed.

Lemma RewSound_LamAlpha : forall (t : Ty) (e : Expr) (rho : env) (f : nat),
  denE rho (Ret (VLam t e)) f ≈ denE rho (Ret (VLam t e)) f.
Proof. intros. reflexivity. Qed.

(* ---------- Fig. 6 line 336 / §6 : choice and its branch algebra ----------
   The kernel maps `b1 b2` to `br2` (Semantics.v decision 4); the candidate-set
   reading of §6 is the branch algebra below, transported from ctrees' sbisim
   laws (`~`) to `≈` through `sbisim_wbisim_subrelation`.  Applying a law to an
   sbisim lemma directly fails - `sbisim` and `wbisim` are different greatest
   fixed points - hence the explicit transport in each row. *)

Lemma Denote_Choice : forall (e1 e2 : Expr) (rho : env) (f : nat),
  denE rho (Choice e1 e2) (S f) ≈ br2 (denE rho e1 f) (denE rho e2 f).
Proof. intros. kernel_cbn; reflexivity. Qed.

Lemma Br2_Commut_W : forall (t u : ctree void1 B2 SResult),
  br2 t u ≈ br2 u t.
Proof. intros. apply sbisim_wbisim_subrelation. apply br2_commut. Qed.

Lemma Br2_Idem_W : forall (t : ctree void1 B2 SResult),
  br2 t t ≈ t.
Proof. intros. apply sbisim_wbisim_subrelation. apply br2_idem. Qed.

Lemma Br2_Assoc_W : forall (t u v : ctree void1 B2 SResult),
  br2 (br2 t u) v ≈ br2 t (br2 u v).
Proof. intros. apply sbisim_wbisim_subrelation. apply br2_assoc. Qed.

Lemma Br2_StuckL_W : forall (t : ctree void1 B2 SResult),
  br2 Stuck t ≈ t.
Proof. intros. apply sbisim_wbisim_subrelation. apply br2_stuck_l. Qed.

(* Deferred corner (IterChoice's "the ctrees-side soundness of this rule IS the
   bind/br2 interchange", Rewriting.v line 455):  at the `equ` level the two
   sides normalize to `br branch2 (fun b => bind (if b then p else q) k)` and
   `br branch2 (fun b => if b then bind p k else bind q k)`, whose lambda bodies
   are extensionally but not syntactically equal, so `reflexivity` cannot close
   them and the ≈-level route needs ctrees' up-to-bind coinduction
   (`bind_chain_gen`, WBisim.v line 574).  Recorded as the iter/choice corner in
   docs/RULES-AUDIT.md; no statement is claimed here. *)

(* ---------- axiom audit ---------- *)

Print Assumptions RewSound_Seq.
Print Assumptions RewSound_EqK2.
Print Assumptions RewSound_Prim2.
