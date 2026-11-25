(* =====================================================================
    RuleAst.v - GENERATED FILE (M1 item 1, docs/PLAN.md sec. 5.0): the eval-side
    rule AST surface.  `RuleID` carries one constructor per distinct non-empty
    `kernelTag` field of the ctor rows in dialect/TimbdaRules.td, grouped in
    TimbdaRuleAstOrder order with the group comments the records carry;
    `selected_rows` lists the ctor rows flagged `selected` in `rank` order,
    deduplicated by kernelTag (the two SCHEMA rows share R_Prim / R_PrimFail).
    The hand-glued block this replaces was retired from coq/Eval.v.  Regenerate:
        tblgen-rocq -gen-rocq-ast dialect/Timbda.td -o coq/RuleAst.v
    checks.tblgen-rocq-golden byte-diffs this file against regeneration and
    tools/rules-audit.py section 3 asserts the record provenance; hand edits
    here are a gate failure, not a contribution.
    ===================================================================== *)

From Stdlib Require Import List.
Import ListNotations.

Inductive RuleID : Type :=
| R_Seq | R_Norm1 | R_Norm2 | R_Norm3 | R_Norm4 | R_Norm5        (* fig:12 *)
| R_EqK1 | R_EqK2 | R_EqTup1 | R_EqTup2 | R_EqFail        (* fig:9 *)
| R_BetaL | R_BetaT | R_BetaT0        (* fig:11 *)
| R_Prim | R_PrimFail        (* fig:10 *)
| R_Subst | R_Gc1 | R_PromoteL | R_PromoteR        (* fig:8 *)
| R_IterFail | R_IterChoice | R_IterIf | R_IterAll | R_IterFor
  (* fig:13 *)
| R_HpAlpha | R_LamAlpha.        (* never selected *)

(* selected_rows: the ctor rows flagged `selected` in `rank` order,
   deduplicated by kernelTag *)
Definition selected_rows : list RuleID :=
  [ R_Seq; R_Norm1; R_Norm2; R_Norm3; R_Norm4; R_Norm5; R_EqK1; R_EqK2;
  R_EqTup1; R_EqTup2; R_EqFail; R_BetaL; R_BetaT; R_BetaT0; R_Prim;
  R_PrimFail; R_Subst; R_PromoteL; R_PromoteR].
