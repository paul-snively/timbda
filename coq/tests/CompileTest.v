(* CompileTest.v - the test lane for Compile.v (docs/PLAN.md M2 increment D1,
   docs/COMPILE-STRATEGY.md sec. 8's landing sequence: "smallest corner first
   (Ret/Fail/Seq - already proven as b_ret/b_fail/b_seq)").

   Positive smoke: the three D1 corners compile to EXACTLY the pinned fragments
   (the terminal write at the landed Lower.v spelling), the two stucks stay
   permanently distinct (p529 law 2: a kernel fuel exhaustion is a `CDone`
   result carrying SStuck; a compile fuel exhaustion is the `CLoop` verdict
   itself), and `Compute` shows the actual Clight terminal write.
   Negative smoke: an uncertified Choice TRAPS - decision 15's
   candidate-existence certificate (the choice corner) is what replaces this
   trap, so a silent left-priority here would be the FoldCTree horn smuggled
   in as a compiler.

   Same kernel-file idioms as LowerTest.v (both learned the hard way there):
   the kernel-side Expr terms are DEFINED BEFORE `Require Import
   Timbda.Compile` - the CompCert import window Compile.v drags in rebinds
   bare numerals toward BinNums.Z and shadows list notation - and every
   compile-side nat literal carries `%nat` (the trap Compile.v documents at
   its iterF: a bare nat literal there parses as BinNums.Z0, "a constructor
   of inductive type Z where nat is expected").

   AUDIT boundary: `Print Assumptions` here is allowed ONLY on computation-
   only pins.  c_ret's proof is pure conversion over closed terms, so it
   prints nothing (or eq_rect_eq alone, already the kernel's single audit
   axiom); `c_terminal_exec` mentions the Clight step relation and would
   print the FULL 13-axiom CompCert cone into build.log, breaking the
   kernel's strict single-axiom gate (flake.nix timbda-kernel buildPhase).
   The Compile family's cone is audited instead by that sweep's axiom block:
   measured this increment, `rocq check Timbda.Compile` prints exactly the 13
   axioms already pinned there - the fold path adds none. *)

From Stdlib Require Import ZArith List.
Import ListNotations.

Require Import Timbda.Syntax Timbda.Semantics.

(* Parsed before the CompCert window opens (LowerTest idiom). *)
Definition c_ret_prog : Expr := Ret (VInt 3).
Definition c_seq_prog : Expr := Seq (Ret (VInt 1)) (Ret (VInt 2)).
Definition c_fail_prog : Expr := Fail.
Definition c_choice_prog : Expr := Choice (Ret (VInt 1)) Fail.
Definition c_nest4 : Expr :=
  Seq (Seq (Seq (Ret (VInt 1)) (Ret (VInt 2))) (Ret (VInt 3))) (Ret (VInt 4)).

(* Corner 2 (D2) corner spellings: decision 5's `op[..]` shape, same as
   RealizeCorners' prim_corner and Compile.v's local cprim. *)
Definition c_prim_add_prog : Expr :=
  App (Ret (VPrim PAdd)) (TupE (map Ret [VInt 2; VInt 3])).
Definition c_prim_gt_prog : Expr :=
  App (Ret (VPrim PGt)) (TupE (map Ret [VInt 3; VInt 2])).
Definition c_prim_div_neg_prog : Expr :=
  App (Ret (VPrim PDiv)) (TupE (map Ret [VInt 7; VInt (-2)])).
Definition c_prim_div0_prog : Expr :=
  App (Ret (VPrim PDiv)) (TupE (map Ret [VInt 1; VInt 0])).

(* Coq re-exports a module's OWN definitions but not the libraries it
   `Require Import`ed, so the Clight statement constructors and the landed
   Lower spellings are named explicitly here (Compile.v itself imports both
   windows; this is the same fact Realize.v's header states for the fan-in). *)
Require Import compcert.cfrontend.Clight Timbda.Lower Timbda.Compile.

(* Corner 1, strategy sec. 8, at Leibniz `=`. *)
Example compile_ret_pin :
  compile c_ret_prog 1%nat
  = CDone SResult [Sset lower_res (vconst (VInt 3))] (SOk (VInt 3)).
Proof. reflexivity. Qed.

Example compile_fail_pin : compile c_fail_prog 1%nat = CDone SResult [Sskip] SFail.
Proof. reflexivity. Qed.

Example compile_seq_pin :
  compile c_seq_prog 2%nat
  = CDone SResult [Sset lower_res (vconst (VInt 2))] (SOk (VInt 2)).
Proof. reflexivity. Qed.

(* The two stucks, distinct by construction (p529 law 2): kernel fuel
   exhaustion is DATA in a `CDone` verdict - no `CLoop`, nothing loop-shaped. *)
Example compile_kernel_stuck_pin : compile c_nest4 3%nat = CDone SResult [Sskip] SStuck.
Proof. reflexivity. Qed.

(* ... while compile fuel exhaustion IS the `CLoop` verdict: the resumption
   boundary as the verdict itself (strategy sec. 2), with an empty fragment
   because the algebra never appends during unrolling. *)
Example compile_budget_verdict_pin : compile c_ret_prog 0%nat = CLoop SResult nil.
Proof. reflexivity. Qed.

(* The D1 negative corner: a choice the determinacy analysis has not certified
   has NO defined emitted C (the trap `g`; corner D3/D4's candidate peek
   replaces it, measured as a delta from this pin). *)
Example compile_choice_traps_pin : compile c_choice_prog 2%nat = CTrap SResult nil.
Proof. reflexivity. Qed.

Compute compile c_seq_prog 2%nat.

Print Assumptions c_ret.

(* Corner 2 (D1 seq. 7's pins at the test lane): fuel 4 exhibits the prim
   spine's stuck specimen and fuel 5 completes it - the kernel budget for the
   spine is 5, measured.  Guard success writes the LEFT operand (Fig. 10 test
   shape); guard failure is fail-as-zero; the floor-`Z.div` value lands as a
   constant (the emitted C contains no division - the truncation-fork tension
   is T6's binop spelling's, not this algebra's); the zero divisor is the
   prim-guard stuck: same observable shape as the fuel stuck, different
   provenance (p529 law 2). *)
Example compile_prim_fuel4_pin : compile c_prim_add_prog 4%nat = CDone SResult [Sskip] SStuck.
Proof. reflexivity. Qed.

Example compile_prim_add_pin :
  compile c_prim_add_prog 5%nat
  = CDone SResult [Sset lower_res (vconst (VInt 5))] (SOk (VInt 5)).
Proof. reflexivity. Qed.

Example compile_prim_gt_left_pin :
  compile c_prim_gt_prog 5%nat
  = CDone SResult [Sset lower_res (vconst (VInt 3))] (SOk (VInt 3)).
Proof. reflexivity. Qed.

Example compile_prim_div_floor_pin :
  compile c_prim_div_neg_prog 5%nat
  = CDone SResult [Sset lower_res (vconst (VInt (-4)))] (SOk (VInt (-4))).
Proof. reflexivity. Qed.

Example compile_prim_div0_stuck_pin : compile c_prim_div0_prog 5%nat = CDone SResult [Sskip] SStuck.
Proof. reflexivity. Qed.

Compute compile c_prim_div_neg_prog 5%nat.
