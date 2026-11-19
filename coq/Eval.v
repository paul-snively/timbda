(* Timbda-0 kernel evaluator (coq/Extracted evaluator line of docs/PLAN.md § 5 M0:
   "extracted evaluator + T8 draft").  A pure, axiom-free Gallina function that
   performs head redex selection and fuel-bounded normalization over the
   Rewriting.v rule table; it is the Gallina corner of the differential
   triangle (Gallina evaluator <-> MLIR canonicalizer <-> augustss oracle) and
   will be Extraction'd to OCaml for the shared-corpus harness (M2).

   Selected head rows, in arm order - and the arm order IS the kernel's
   evaluation strategy.  The paper's Fig. 25 group vocabulary is a list of
   strategy *groups*; wiring it to a kernel `StrategyGroup`/`pick_redex`
   priority function is the M2/M3 obligation recorded in docs/VERSE-RULES.md
   sec. 5, and this file implements a fixed arm order instead:
     Seq, Norm1..Norm5            (Fig. 12, groups Seq/Assoc/Norm-star)
     EqK1, EqK2, EqTup1, EqTup2, EqFail   (Fig. 9 taxonomy below)
     BetaL, BetaT, BetaT0         (Fig. 11, groups Bind*, BetaT0 base case)
     R_Prim / R_PrimFail          (Fig. 10 schema rows; they dispatch the
        named ctor rows Add Gt1 Gt2 IsInt1 IsInt2 Cons DotDot through
        prim_total - one match here licenses all named rows for rewriting)
     Subst, PromoteL, PromoteR    (Fig. 8, "slot completion" section below:
        they fill the `x{}` slots beta-l/beta-t declare, which is what turns a
        beta canonical form from decision 3's SStuck into a value)
   Never selected: the identity rows HpAlpha/LamAlpha (renaming is
   representation-trivial under de Bruijn, Rewriting.v), Gc1 (Fig. 8: the
   dropSlot/shrinkE reindexing computation lemma is its own audit row) and the
   iter rows IterFail/IterChoice/IterIf/IterAll/IterFor (Fig. 13; their
   context-hole matchers need the CtxC walk and their soundness is the admitted
   corner - see Denotation.v header).

   The Eq branch uses exactly the root taxonomy of Rewriting.v (root_mismatch /
   no_eq_rule_pair) and the literal equality lit_eqb of Semantics.v, so the
   head table and the denotation agree on every term: where the head table
   returns None, unify_top in the denotation is SStuck; where it returns a
   Fail rhs, the denotation is SFail.  The Subst/promote arms are the recorded
   exception, and they go the other way: their lhs is a block with a `None`
   slot, which decision 3 reads as SStuck, while their rhs is a valued-slot
   block that evaluates.  That is exactly the C1 divergence docs/RULES-AUDIT.md
   sec. 1/3 records as the reason their `RewSound_*` lemmas are deferred (M3/T1
   evolving-heap semantics) - and it is why `norm` now reaches a value where it
   used to end stuck.

   BetaT0 relies on the Semantics.v decision-5 short-circuit (fail without
   forcing e).  BetaL/BetaT create `x{}` declared slots, and the promote rows
   are what close the `x = e` unification against them; before the promote arms
   a beta canonical form was stuck precisely at that unification.

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

(* ---------- slot completion at a Block root (Fig. 8: Subst, PromoteL, PromoteR)
   A Fig. 8 redex lives *inside* a block's body, so `body_walk` searches that body
   through exactly the two binder-free context grammars the constructors quantify
   over: `k : CtxS` for RewSubst, `k : CtxC` for RewPromoteL/R (Syntax.v).  Adding
   the parent node back on the way up is plugging with the composed context - a
   redex under `e ; C` is `fillS (HS_SeqR k e2) redex`, `Unify redex' e2` is the
   same term - so what `head_redex` returns is the constructor's right-hand side,
   not a hand-rolled variant of it (KernelTest.v section D proves the coincidence
   for all three rows).

   Barriers, inherited from the ctors and NOT widened here: no context hole through
   `TupE`, `Choice`, `Iter` or a nested `Block`, and no descent into a `VLam` /
   `VDelay` value.  That is the recorded narrowing relative to the pinned oracle's
   deep substitution (verse-semantics `Red.hs:1059`), and it is what the audit
   records `Subst-Deep` and the deferred `IterChoice` context-hole matcher are
   about (docs/RULES-AUDIT.md sec. 2, 3.4).

   Slot index rule (Rewriting.v slot conventions): a body-position index i names the
   block's slot p = slot_of_body_idx n i = n - 1 - i exactly when i < n; i >= n is an
   enclosing binder and no Fig. 8 row applies to it.

   Guards, taken verbatim from the ctors: Subst needs `slot_value_at slots p = Some v`
   (the paper's `x v`, a *valued* heap entry, line 412); the promote rows need p to be
   declared-only (`exists X,x{hp}`), `promote_ok` (the value mentions no slot of its own
   block, so it survives the move to slot position) and `promote_hp_ok` (`hp[v/x]`
   restricted to the identity - the Tier-2 evolving-heap obligation, M3/T1).

   Strategy inside one block body - a kernel decision, recorded as one, not a paper
   claim: these rows are searched before that body's Fig. 9-12 rows; each position is
   tried PromoteL, then PromoteR, then Subst-at-node, then the descent.  A Subst and a
   promote can never compete for the same slot (a slot is valued or declared-only, not
   both), so only their *positions* matter: when a promote redex matches a node but its
   guard fails, the walk still descends through that node's children, which is how
   `x{hp, x v}. C[x = v']` becomes a Subst redex instead. *)

Definition slot_of_body_idx (n i : nat) : nat := n - 1 - i.

Definition promote_guard (n : nat) (slots : list (Ty * option Val)) (p : nat)
    (v : Val) : bool :=
  match slot_value_at slots p with
  | Some _ => false              (* RewPromoteL/R quantify over `exists X,x{hp}` *)
  | None   => promote_ok n v && promote_hp_ok slots p
  end.

Definition mk_promote (r : RuleID) (n : nat) (slots : list (Ty * option Val))
    (i : nat) (v : Val) : option (RuleID * list (Ty * option Val) * Expr) :=
  if Nat.ltb i n && promote_guard n slots (slot_of_body_idx n i) v
  then let p := slot_of_body_idx n i in
       Some (r, fillSlot p (bodyToSlotV n p v) slots, Ret v)
  else None.

(* The two directions are tested as two patterns, not as two match arms: a term
   `x = y` whose left side is out of slot range must still be able to fire
   promote-r with the value on the left (paper line 417), which arm shadowing
   would silently lose.  Order within the same unification: PromoteL then
   PromoteR, i.e. constructor order. *)
Definition promote_dir (r : RuleID) (n : nat) (slots : list (Ty * option Val))
    (e1 e2 : Expr) : option (RuleID * list (Ty * option Val) * Expr) :=
  match r with
  | R_PromoteL => match e1, e2 with
                  | Ret (VVar i), Ret v => mk_promote R_PromoteL n slots i v
                  | _, _ => None
                  end
  | R_PromoteR => match e1, e2 with
                  | Ret v, Ret (VVar i) => mk_promote R_PromoteR n slots i v
                  | _, _ => None
                  end
  | _ => None
  end.

Definition promote_here (n : nat) (slots : list (Ty * option Val)) (body : Expr)
  : option (RuleID * list (Ty * option Val) * Expr) :=
  match body with
  | Unify e1 e2 =>
      match promote_dir R_PromoteL n slots e1 e2 with
      | Some st => Some st
      | None => promote_dir R_PromoteR n slots e1 e2
      end
  | _ => None
  end.

Definition subst_here (n : nat) (slots : list (Ty * option Val)) (body : Expr)
  : option (RuleID * list (Ty * option Val) * Expr) :=
  match body with
  | Ret (VVar i) =>
      if Nat.ltb i n then
        let p := slot_of_body_idx n i in
        match slot_value_at slots p with
        | Some v => Some (R_Subst, slots, Ret (slotValueFromBody n p v))
        | None   => None                    (* `x{}` is declared, not `x v` *)
        end
      else None                             (* index escapes this block's slots *)
  | _ => None
  end.

Fixpoint body_walk (n : nat) (slots : list (Ty * option Val)) (body : Expr)
  : option (RuleID * list (Ty * option Val) * Expr) :=
  match promote_here n slots body with
  | Some st => Some st
  | None => match subst_here n slots body with
            | Some st => Some st
            | None => match body with
                      | Unify e1 e2 =>
                          match body_walk n slots e1 with
                          | Some (r, sl, e1') => Some (r, sl, Unify e1' e2)
                          | None => match body_walk n slots e2 with
                                    | Some (r, sl, e2') => Some (r, sl, Unify e1 e2')
                                    | None => None
                                    end
                          end
                      | Seq e1 e2 =>
                          match body_walk n slots e1 with
                          | Some (r, sl, e1') => Some (r, sl, Seq e1' e2)
                          | None => match body_walk n slots e2 with
                                    | Some (r, sl, e2') => Some (r, sl, Seq e1 e2')
                                    | None => None
                                    end
                          end
                      | App e1 e2 =>
                          match body_walk n slots e1 with
                          | Some (r, sl, e1') => Some (r, sl, App e1' e2)
                          | None => match body_walk n slots e2 with
                                    | Some (r, sl, e2') => Some (r, sl, App e1 e2')
                                    | None => None
                                    end
                          end
                      | _ => None           (* Tuple/Choice/Iter/Block/VLam: no hole *)
                      end
            end
  end.

Definition block_redex (slots : list (Ty * option Val)) (body : Expr)
  : option (RuleID * Expr) :=
  match body_walk (length slots) slots body with
  | Some (r, slots', body') => Some (r, Block slots' body')
  | None => None
  end.

(* Head redex table.  Arm order: Fig. 12 structural rows first (they de-clutter
   before any value matching), then the Fig. 9 taxonomy, then Fig. 11 beta, then
   Fig. 10 delta, then the Fig. 8 slot-completion walk at a Block root.  Returns
   the selected rule tag and the rewritten term. *)

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
  (* ---- Fig. 8: slot completion *inside* a block body (Subst / PromoteL / R) ---- *)
  | Block slots body => block_redex slots body
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

(* ---------- candidate bag of a normal form (choice = the denotation's br2) ----
   `Choice` has no rewrite row in Figs. 9-12: candidate bags are a denotation-side
   object (T2: kernel `Choice` extracts to `br2`, Denotation.v).  What the evaluator
   CAN expose honestly is which alternatives a normal form actually offers:

     * a `Choice` node splits, recursively - the outermost alternatives;
     * a block whose slots are all valued is read through, exactly as `closeSlots`
       reads it in the denotation (Semantics.v decision 3), and each alternative is
       handed back under the same slot list - a candidate carries the heap it was
       produced under;
     * a block with a `None` slot is a leaf (decision 3's SStuck), as is anything
       else - including a choice sitting under a `Seq`, an `=` or an `Iter`.

   Not splitting under Seq/= is not an oversight: moving a choice across a bind *is*
   the interchange law IterChoice's ctrees-side content stands for, and that law is
   deferred (docs/RULES-AUDIT.md sec. 3.4).  So `cand_bag` claims only what the
   kernel has rules for, and the corpus asserts it case by case. *)

Fixpoint all_slots_valued (slots : list (Ty * option Val)) : bool :=
  match slots with
  | nil => true
  | (_, Some _) :: rest => all_slots_valued rest
  | (_, None) :: _ => false
  end.

Fixpoint cand_bag (e : Expr) : list Expr :=
  match e with
  | Choice e1 e2 => cand_bag e1 ++ cand_bag e2
  | Block slots body =>
      if all_slots_valued slots
      then map (fun b => Block slots b) (cand_bag body)
      else [Block slots body]
  | _ => [e]
  end.

(* The strategy table for the M1 audit docs: which ctor rows the head table
   actually selects (R_Prim/R_PrimFail stand in for the named Fig. 10 rows;
   R_HpAlpha/R_LamAlpha/Gc1 never fire; the iter rows wait for the M3 CtxC matcher
   machinery).  Selection is not proof: R_BetaL/R_BetaT/R_Subst/R_PromoteL/
   R_PromoteR are selected while their RewSound_* lemmas stay deferred, which the
   audit table records row by row (docs/RULES-AUDIT.md sec. 1 `sel` column). *)

Definition selected_rows : list RuleID :=
  [R_Seq; R_Norm1; R_Norm2; R_Norm3; R_Norm4; R_Norm5;
   R_EqK1; R_EqK2; R_EqTup1; R_EqTup2; R_EqFail;
   R_BetaL; R_BetaT; R_BetaT0; R_Prim; R_PrimFail;
   R_Subst; R_PromoteL; R_PromoteR].
