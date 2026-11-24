(* LowerTest.v — the test lane for Lower.v (T7, docs/PLAN.md § 3 item 7).

   Positive smoke: a checked straight-line term lowers with no context calls, and
   `Compute` shows the actual Clight emission (the Sset/Ssequence/assign-int64
   shapes the T6 refinement will later have to reason about).
   Negative smoke: the general case genuinely emits context calls (the guards'
   ban on Choice/Iter is exactly what T7 says never happens on checked terms).

   Two kernel-file idioms this lane must keep (both learned the hard way):
   - `Import ListNotations` here: `Import` statements inside compiled modules
     (Syntax.v's own, line 19) are not re-exported, so each file re-opens them.
   - the kernel-side terms are DEFINED BEFORE `Require Import Timbda.Lower`:
     Lower drags in CompCert, whose scope window rebinds bare numerals toward
     BinNums.Z (Check VInt prints `BinNums.Z -> Val` there) and shadows the
     list notation, so `[..]`-with-numerals terms must be parsed before that
     window opens.  Lower itself then sees only the named definitions.

   Print Assumptions T7_no_switch lands in the kernel's strict axiom gate
   (flake.nix timbda-kernel buildPhase: the build.log's axiom lines are exactly
   {Eqdep.Eq_rect_eq.eq_rect_eq}).  Measured beforehand with the p502 probe: the
   Clight SYNTAX cone is `Closed under the global context` — T7 mentions only
   statement/expr constructors, never the Clight step relation — so this file
   must print nothing or eq_rect_eq alone; anything else means the kernel's
   compiled cone leaked past the § 13.7 audit boundary. *)

From Stdlib Require Import ZArith List.
Import ListNotations.

Require Import Timbda.Syntax Timbda.Rewriting Timbda.Semantics Timbda.Checks.

Definition t_add : Expr :=
  App (Ret (VPrim PAdd)) (TupE [Ret (VInt 2); Ret (VInt 3)]).
Definition t_seq : Expr := Seq t_add (Ret (VInt 5)).
Definition t_block : Expr :=
  Block [(TInt, Some (VInt 7))]
        (App (Ret (VPrim PSub)) (TupE [Ret (VInt 7); Ret (VInt 2)])).
Definition t_choice : Expr := Choice (Ret VTrue) (Ret VFalse).
Definition t_iter : Expr := Iter IFor (Ret VUnit) (Ret VUnit).
Definition t_seq_fail : Expr :=
  Seq (App (Ret (VPrim PMul)) (TupE [Ret (VInt 6); Ret (VInt 7)])) Fail.

Require Import Timbda.Lower.

Example lower_add_checked : det_check t_seq = true.
Proof. reflexivity. Qed.

Example lower_seq_no_switch : no_switch_l (lower t_seq) = true.
Proof. reflexivity. Qed.

Example lower_block_no_switch : no_switch_l (lower t_block) = true.
Proof. reflexivity. Qed.

Example lower_choice_switches : no_switch_l (lower t_choice) = false.
Proof. reflexivity. Qed.

Example lower_iter_switches : no_switch_l (lower t_iter) = false.
Proof. reflexivity. Qed.

Compute lower t_seq_fail.

Print Assumptions T7_no_switch.
