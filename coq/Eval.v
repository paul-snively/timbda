(* Timbda-0 kernel evaluator (coq/Extracted evaluator line of docs/PLAN.md § 5 M0:
   "extracted evaluator + T8 draft").  A pure, axiom-free Gallina function that
   performs head redex selection and fuel-bounded normalization over the
   Rewriting.v rule table; it is the Gallina corner of the differential
   triangle (Gallina evaluator <-> MLIR canonicalizer <-> augustss oracle) and
   will be Extraction'd to OCaml for the shared-corpus harness (M2).

   Head table (audit order; mirrors the § 5 strategy groups restricted to Core
   Verse):
     Seq, Norm1..Norm5            (Fig. 12, groups Seq/Assoc/Norm-star)
     EqK1, EqK2, EqTup1, EqTup2, EqFail   (Fig. 9 taxonomy below)
     BetaL, BetaT, BetaT0         (Fig. 11, groups Bind*, BetaT0 base case)
     R_Prim / R_PrimFail          (Fig. 10 schema rows; they dispatch the
        named ctor rows Add Gt1 Gt2 IsInt1 IsInt2 Cons DotDot through
        prim_total - one match here licenses all named rows for rewriting)
   Never selected: the identity rows HpAlpha/LamAlpha (renaming is
   representation-trivial under de Bruijn, Rewriting.v), the evolving-heap rows
   Subst/Gc1/PromoteL/PromoteR (Fig. 8; block-slot completion is the M2
   Get/Put semantic version), and the iter rows IterFail/IterChoice/IterIf/
   IterAll/IterFor (Fig. 13; their context-hole matchers need the CtxC walk and
   their soundness is the admitted corner - see Denotation.v header).

   The Eq branch uses exactly the root taxonomy of Rewriting.v (root_mismatch /
   no_eq_rule_pair) and the literal equality lit_eqb of Semantics.v, so the
   head table and the denotation agree on every term: where the head table
   returns None, unify_top in the denotation is SStuck; where it returns a
   Fail rhs, the denotation is SFail.

   BetaT0 relies on the Semantics.v decision-5 short-circuit (fail without
   forcing e).  BetaL/BetaT create `x{}` declared slots; their bodies
   normalize further, but the unification `x = e` against a declared slot only
   closes via the Fig. 8 promote rows (M2) - the same boundary as decision 3
   in the denotation.

   T8 draft (adequacy, to be discharged as a Lemma in M3):
     for every closed e and fuel >= the normalizing budget,
        denote (norm fuel e) fuel  ~=  denote e fuel
   - i.e. the strategy terminates to the same candidate tree.  It follows
   compositionally from the RewSound_* lemma family (15 discharged now, 20
   deferred) plus a fuel-transfer side condition; the alpha rows never fire so
   they need no soundness input at all. *)

From Stdlib Require Import ZArith Bool List.
Require Import Timbda.Syntax Timbda.Rewriting Timbda.Semantics.
Import ListNotations.

(* ---------- audit-aligned rule tags ---------- *)

Inductive RuleID : Type :=
| R_Seq | R_Norm1 | R_Norm2 | R_Norm3 | R_Norm4 | R_Norm5        (* fig:12 *)
| R_EqK1 | R_EqK2 | R_EqTup1 | R_EqTup2 | R_EqFail               (* fig:9  *)
| R_BetaL | R_BetaT | R_BetaT0                                   (* fig:11 *)
| R_Prim | R_PrimFail                                            (* fig:10 *)
| R_Subst | R_Gc1 | R_PromoteL | R_PromoteR                      (* fig:8  *)
| R_IterFail | R_IterChoice | R_IterIf | R_IterAll | R_IterFor   (* fig:13 *)
| R_HpAlpha | R_LamAlpha.                                        (* never selected *)

(* ---------- redex recognisers for the selected head groups ---------- *)

(* Collect the value arguments of a canonical primop operand `TupE [Ret v1; ..]`
   (Semantics.v decision 5: a bare `Ret v` operand is the one-element list [v],
   matching the apply_c unpacking in the denotation). *)
Fixpoint rets_of (es : list Expr) : option (list Val) :=
  match es with
  | nil => Some (@nil Val)
  | Ret v :: rest => match rets_of rest with
                     | Some vs => Some (v :: vs)
                     | None => None
                     end
  | _ :: _ => None
  end.

Definition prim_operand_vals (arg : Expr) : option (list Val) :=
  match arg with
  | TupE es => rets_of es
  | Ret v => Some [v]
  | _ => None
  end.

(* Head redex table.  Ordering: Fig. 12 structural rows first (they de-clutter
   before any value matching), then the Fig. 9 taxonomy, then Fig. 11 beta,
   then Fig. 10 delta.  Returns the selected rule tag and the rewritten term. *)

Definition head_redex (e : Expr) : option (RuleID * Expr) :=
  match e with
  (* ---- Fig. 12: structural / normalization rows ---- *)
  | Seq (Ret v) e2 => Some (R_Seq, e2)
  | Seq (Seq e1 e2) e3 => Some (R_Norm5, Seq e1 (Seq e2 e3))
  | Unify (Ret v) (Seq e1 e2) => Some (R_Norm1, Seq e1 (Unify (Ret v) e2))
  | Unify (Ret v) (Unify e1 e2) =>
      Some (R_Norm2, Seq (Unify (Ret v) e1) (Unify (Ret v) e2))
  | Unify (Seq e1 e2) e3 => Some (R_Norm3, Seq e1 (Unify e2 e3))
  | Unify (Unify (Ret v) e1) e2 =>
      Some (R_Norm4, Seq (Unify (Ret v) e1) (Unify (Ret v) e2))
  (* ---- Fig. 9: unification taxonomy ---- *)
  | Unify (Ret v1) (Ret v2) =>
      if is_lit_val v1 && is_lit_val v2 then
        if lit_eqb v1 v2 then Some (R_EqK1, Ret v1) else Some (R_EqK2, Fail)
      else match v1, v2 with
           | VTup vs, VTup ws =>
               if Nat.eqb (length vs) (length ws)
               then Some (R_EqTup1, eq_seq vs ws (Ret (VTup vs)))
               else Some (R_EqTup2, Fail)
           | _, _ =>
               if root_mismatch v1 v2
               then Some (R_EqFail, Fail) else None
           end
  (* ---- Fig. 11: beta rows ---- *)
  | App (Ret (VLam t b)) e2 =>
      Some (R_BetaL, Block [(t, @None Val)]
                      (Seq (Unify (Ret (VVar 0)) (liftE 1 0 e2)) b))
  | App (Ret (VTup (v0 :: vs))) e2 =>
      Some (R_BetaT, Block [(@TAny, @None Val)]
                      (Seq (Unify (Ret (VVar 0)) (liftE 1 0 e2))
                           (choice_list (beta_t_cands 0 (v0 :: vs)))))
  | App (Ret (VTup nil)) _ => Some (R_BetaT0, Fail)
  (* ---- Fig. 10: delta via the schema rows (dispatches the named rows) ---- *)
  | App (Ret (VPrim p)) arg =>
      match prim_operand_vals arg with
      | Some vs => match prim_total p vs with
                   | PRes v => Some (R_Prim, Ret v)
                   | PFail => Some (R_PrimFail, Fail)
                   | PStuck => None
                   end
      | None => None
      end
  | _ => None
  end.

(* ---------- fuel-bounded normalization (uniform-fuel idiom) ---------- *)

Fixpoint norm (fuel : nat) (e : Expr) : Expr :=
  match fuel with
  | 0 => e
  | S n =>
      match head_redex e with
      | Some (_ , e') => norm n e'
      | None =>
          match e with
          | Glob g => Glob g
          | Ret v => Ret v
          | App e1 e2 => App (norm n e1) (norm n e2)
          | TupE es => TupE (map (norm n) es)
          | Seq e1 e2 => Seq (norm n e1) (norm n e2)
          | Unify e1 e2 => Unify (norm n e1) (norm n e2)
          | Choice e1 e2 => Choice (norm n e1) (norm n e2)
          | Block slots body => Block slots (norm n body)
          | Iter ic b r => Iter ic (norm n b) (norm n r)
          | Fail => Fail
          end
      end
  end.

(* The strategy table for the M1 audit docs: which ctor rows the head table
   actually selects (R_Prim/R_PrimFail stand in for the named Fig. 10 rows;
   R_HpAlpha/R_LamAlpha never fire; the rest wait for M2/M3 machinery). *)

Definition selected_rows : list RuleID :=
  [R_Seq; R_Norm1; R_Norm2; R_Norm3; R_Norm4; R_Norm5;
   R_EqK1; R_EqK2; R_EqTup1; R_EqTup2; R_EqFail;
   R_BetaL; R_BetaT; R_BetaT0; R_Prim; R_PrimFail].
