(* GoldenCompile.v — the M2 golden-compile record (D4b; docs/PLAN.md M2 sec. 5,
   docs/COMPILE-STRATEGY.md sec. 8's closing obligation, Amendment B's added
   multi-candidate programs).  Spec + rationale: tests/golden-compile/README.md.

   Three records in one file:
   (1) the golden PROGRAMS (kernel terms pre-window per the CompileTest idiom,
       G1..G12 of the README table) and their fuel-pinned compile verdicts —
       each mirrors a landed coq/Compile.v corner lemma: the golden test
       re-reads the corners, it never invents expectations;
   (2) the C RENDERER (render_stmt/render_body): the emitted CompCert
       statements as source lines against the harness contract (globals
       timbda_res/timbda_cand0/timbda_cand1 = the binary-positive idents
       xH / xO xH / xI xH of Compile.v sec. 3; arbiter = xO (xO xH)); every
       body pinned by computation;
   (3) golden_lines — the WHOLE translation unit as a list of lines.  The
       checks.golden-compile lane computes it, assembles golden.c.actual,
       DIFFS it byte-for-byte against the checked-in golden.c.expected, compiles
       with clang -std=c11 -Wall -Werror, and diffs the run against the pinned
       golden.stdout.

   Idioms inherited (see CompileTest.v header): kernel terms before the
   CompCert window; every compile-side nat literal carries %nat; string
   literals need `Open Scope string_scope` (measured Rocq 9.1.1: without it,
   "No interpretation for string").

   AUDIT boundary: Print Assumptions never runs here (CompileTest.v's rule);
   the Compile-family cone is audited by the kernel lane's rocqchk sweep. *)

From Stdlib Require Import String ZArith List.
Import ListNotations.
Open Scope string_scope.

Require Import Timbda.Syntax Timbda.Semantics.

(* ---- the golden programs (pre-window; README table G1..G12) ---- *)
Definition g1  : Expr := Ret (VInt 3).
Definition g2  : Expr := Fail.
Definition g3  : Expr := Seq (Ret (VInt 1)) (Ret (VInt 2)).
Definition g4  : Expr := App (Ret (VPrim PAdd)) (TupE [Ret (VInt 7); Ret (VInt (-2))]).
Definition g5  : Expr := App (Ret (VPrim PDiv)) (TupE [Ret (VInt 7); Ret (VInt (-2))]).
Definition g6  : Expr := App (Ret (VPrim PDiv)) (TupE [Ret (VInt 1); Ret (VInt 0)]).
Definition g7  : Expr := Choice (Ret (VInt 1)) g6.                       (* certified left *)
Definition g8  : Expr := Choice g6 (Ret (VInt 2)).                       (* certified right *)
Definition g9  : Expr := Choice g6
               (App (Ret (VPrim PDiv)) (TupE [Ret (VInt 2); Ret (VInt 0)])). (* vacuous *)
Definition g10 : Expr := Seq g7 Fail.                                   (* cert under Seq *)
Definition g11 : Expr := Choice (Ret (VInt 1)) (Ret (VInt 2)).          (* TRUE multi-cand *)
Definition g12 : Expr := Choice (Ret (VInt 2)) (Ret (VInt 1)).          (* its flip *)
Definition g14 : Expr := Choice g7 (Ret (VInt 2)).                      (* two sites *)

Require Import compcert.lib.Integers compcert.common.AST compcert.cfrontend.Clight Timbda.Lower Timbda.Compile.

(* ---- record (1): fuel-pinned verdicts (mirrors of the corner lemmas) ---- *)
Definition compile_at (p : Expr) (fuel : nat) : CRes SResult := compile p fuel.

Example golden_g1_verdict  : compile_at g1 1%nat  = CDone SResult [Sset lower_res (vconst (VInt 3))] (SOk (VInt 3)).
Proof. reflexivity. Qed.
Example golden_g2_verdict  : compile_at g2 1%nat  = CDone SResult [Sskip] SFail.
Proof. reflexivity. Qed.
Example golden_g3_verdict  : compile_at g3 2%nat  = CDone SResult [Sset lower_res (vconst (VInt 2))] (SOk (VInt 2)).
Proof. reflexivity. Qed.
Example golden_g4_verdict  : compile_at g4 5%nat  = CDone SResult [Sset lower_res (vconst (VInt 5))] (SOk (VInt 5)).
Proof. reflexivity. Qed.
Example golden_g5_verdict  : compile_at g5 5%nat  = CDone SResult [Sset lower_res (vconst (VInt (-4)))] (SOk (VInt (-4))).
Proof. reflexivity. Qed.
Example golden_g6_verdict  : compile_at g6 5%nat  = CDone SResult [Sskip] SStuck.
Proof. reflexivity. Qed.
Example golden_g7_verdict  : compile_at g7 5%nat  = CDone SResult [Sset lower_res (vconst (VInt 1))] (SOk (VInt 1)).
Proof. reflexivity. Qed.
Example golden_g8_verdict  : compile_at g8 5%nat  = CDone SResult [Sset lower_res (vconst (VInt 2))] (SOk (VInt 2)).
Proof. reflexivity. Qed.
Example golden_g9_verdict  : compile_at g9 5%nat  = CDone SResult [Sskip] SStuck.
Proof. reflexivity. Qed.
Example golden_g10_verdict : compile_at g10 5%nat = CDone SResult [Sskip] SFail.
Proof. reflexivity. Qed.
Example golden_g11_verdict : compile_at g11 5%nat = CDone SResult
  [Sset choice_cand0 (vconst (VInt 1));
   Sset choice_cand1 (vconst (VInt 2));
   Scall None (Evar choice_arbiter arbiter_signature)
     [Evar choice_cand0 tint64; Evar choice_cand1 tint64]] (SOk (VInt 1)).
Proof. reflexivity. Qed.
Example golden_g12_verdict : compile_at g12 5%nat = CDone SResult
  [Sset choice_cand0 (vconst (VInt 2));
   Sset choice_cand1 (vconst (VInt 1));
   Scall None (Evar choice_arbiter arbiter_signature)
     [Evar choice_cand0 tint64; Evar choice_cand1 tint64]] (SOk (VInt 2)).
Proof. reflexivity. Qed.
Example golden_g13_verdict : compile_at g11 1%nat = CDone SResult
  [Sset choice_cand0 (vconst (VInt 1));
   Sset choice_cand1 (vconst (VInt 2));
   Scall None (Evar choice_arbiter arbiter_signature)
     [Evar choice_cand0 tint64; Evar choice_cand1 tint64]] (SOk (VInt 1)).
Proof. reflexivity. Qed.

(* Refusals are golden RECORD entries but not C programs (decision 18). *)
Example golden_refuse_fail_pair :
  compile_at (Choice Fail (Ret (VInt 1))) 5%nat = CTrap SResult nil.
Proof. reflexivity. Qed.
Example golden_refuse_two_sites :
  compile_at g14 5%nat = CTrap SResult nil.
Proof. reflexivity. Qed.
Example golden_refuse_pair_in_seq :
  compile_at (Seq g11 Fail) 5%nat = CTrap SResult nil.
Proof. reflexivity. Qed.

(* ---- record (2): the C renderer (harness contract in the README) ---- *)
Fixpoint str_app (a b : string) : string :=
  match a with
  | String s t => String s (str_app t b)
  | EmptyString => b
  end.

Definition render_ident (id : AST.ident) : string :=
  match id with
  | xH => "timbda_res"
  | xO xH => "timbda_cand0"
  | xI xH => "timbda_cand1"
  | xO (xO xH) => "timbda_arbiter"
  | _ => "TIMBDA_UNEXPECTED_IDENT"
  end.

(* Decimal rendering of a BinNums.Z (measured Rocq 9.1.1: `Z.to_string` and
   `Nat.to_string` are NOT in this environment), and the signed read of an
   emitted Int64 constant: `Int64.signed` (Lower.v's vint_z idiom — the raw
   `Int64.intval` is the UNSIGNED residue: measured, -4 displays as
   18446744073709551612 through it). *)
(* Fuel-bounded BINARY decimal rendering of a BinNums.Z.  Three measured
   Rocq 9.1.1 traps shaped this: `Z.to_string`/`Nat.to_string` do not exist
   in the window; `n / 10` is not structurally decreasing ("principal
   argument equal to n / 10 instead of a subterm of n"); and converting a
   64-bit value through `Z.to_nat` materializes a unary nat (measured: the
   probe for 2^64-4 was OOM-killed at a 5 GiB scope).  Z.leb/Z.div/
   Z.modulo/Z.eqb on the binary Z are exact and cheap; 20 fuel covers every
   int64 (max 19 digits).  Triangulation, not trust: a wrong rendering fails
   the clang build or the pinned golden.stdout. *)
Definition z_digit (d : BinNums.Z) : string :=
  if Z.eqb d 0 then "0" else
  if Z.eqb d 1 then "1" else
  if Z.eqb d 2 then "2" else
  if Z.eqb d 3 then "3" else
  if Z.eqb d 4 then "4" else
  if Z.eqb d 5 then "5" else
  if Z.eqb d 6 then "6" else
  if Z.eqb d 7 then "7" else
  if Z.eqb d 8 then "8" else
  if Z.eqb d 9 then "9" else "?".

Fixpoint z_dec_fuel (k : nat) (z : BinNums.Z) : string :=  (* z >= 0 *)
  match k with
  | 0 => ""
  | S k' => if Z.leb z 9 then z_digit z
            else str_app (z_dec_fuel k' (Z.div z 10)) (z_digit (Z.modulo z 10))
  end.

Definition z_dec (z : BinNums.Z) : string :=
  match z with
  | Z0 => "0"
  | Zpos p => z_dec_fuel 20 (Zpos p)
  | Zneg p => str_app "-" (z_dec_fuel 20 (Zpos p))
  end.   (* measured: this BinNums (Corelib.Numbers.BinNums) has exactly these
            three constructors - no Znegp. *)

Definition render_expr (e : Clight.expr) : string :=
  match e with
  | Clight.Econst_long n _ => str_app (z_dec (Int64.signed n)) "L"
  | Clight.Evar id _ => render_ident id
  | _ => "TIMBDA_UNEXPECTED_EXPR"
  end.

Fixpoint render_args (args : list Clight.expr) : string :=
  match args with
  | nil => ""
  | e :: nil => render_expr e
  | e :: rest => str_app (str_app (render_expr e) ", ") (render_args rest)
  end.

Definition render_stmt (s : Clight.statement) : string :=
  match s with
  | Clight.Sset id e =>
      str_app (render_ident id) (str_app " = " (str_app (render_expr e) ";"))
  | Clight.Sskip => ";"
  | Clight.Scall None (Clight.Evar f _) args =>
      str_app (render_ident f) (str_app "(" (str_app (render_args args) ");"))
  | _ => "TIMBDA_UNEXPECTED_STMT;"
  end.

Definition render_body (frag : list Clight.statement) : list string :=
  map (str_app "    ") (map render_stmt frag).

Definition frag_of (c : CRes SResult) : list Clight.statement :=
  match c with
  | @CDone _ f _ => f
  | _ => @nil Clight.statement
  end.

Definition golden_body (p : Expr) (fuel : nat) : list string :=
  render_body (frag_of (compile p fuel)).

(* body pins: the rendered TEXT, pinned by computation — these lines are the
   fragments the README table promises.  `vm_compute` where a full evaluation
   is needed (strings through Fixpoints are conversion-visible either way). *)
Example golden_g1_body  : golden_body g1 1%nat  = ["    timbda_res = 3L;"].
Proof. vm_compute; reflexivity. Qed.
Example golden_g2_body  : golden_body g2 1%nat  = ["    ;"].
Proof. vm_compute; reflexivity. Qed.
Example golden_g3_body  : golden_body g3 2%nat  = ["    timbda_res = 2L;"].
Proof. vm_compute; reflexivity. Qed.
Example golden_g4_body  : golden_body g4 5%nat  = ["    timbda_res = 5L;"].
Proof. vm_compute; reflexivity. Qed.
Example golden_g5_body  : golden_body g5 5%nat  = ["    timbda_res = -4L;"].
Proof. vm_compute; reflexivity. Qed.
Example golden_g6_body  : golden_body g6 5%nat  = ["    ;"].
Proof. vm_compute; reflexivity. Qed.
Example golden_g7_body  : golden_body g7 5%nat  = ["    timbda_res = 1L;"].
Proof. vm_compute; reflexivity. Qed.
Example golden_g8_body  : golden_body g8 5%nat  = ["    timbda_res = 2L;"].
Proof. vm_compute; reflexivity. Qed.
Example golden_g9_body  : golden_body g9 5%nat  = ["    ;"].
Proof. vm_compute; reflexivity. Qed.
Example golden_g10_body : golden_body g10 5%nat = ["    ;"].
Proof. vm_compute; reflexivity. Qed.
Example golden_g11_body : golden_body g11 5%nat
  = ["    timbda_cand0 = 1L;"; "    timbda_cand1 = 2L;";
     "    timbda_arbiter(timbda_cand0, timbda_cand1);"].
Proof. vm_compute; reflexivity. Qed.
Example golden_g12_body : golden_body g12 5%nat
  = ["    timbda_cand0 = 2L;"; "    timbda_cand1 = 1L;";
     "    timbda_arbiter(timbda_cand0, timbda_cand1);"].
Proof. vm_compute; reflexivity. Qed.
Example golden_g13_body : golden_body g11 1%nat = golden_body g11 5%nat.
Proof. reflexivity. Qed.

(* ---- record (3): the whole translation unit ---- *)
Definition prog_block (body : list string) : list string :=
  ("  reset();" :: "  {" :: body) ++ ("  }" :: "  report();" :: nil).

Definition golden_lines : list string :=
  [ "#include <stdio.h>";
    "#define TIMBDA_NOTSET (0x7FFFFFFFFFFFFFFFL)";
    "static long timbda_res   = TIMBDA_NOTSET;";
    "static long timbda_cand0 = TIMBDA_NOTSET;";
    "static long timbda_cand1 = TIMBDA_NOTSET;";
    (* the arbiter body IS the decision-18 SPEC (leftmost candidate present is
       the observed value, written to lower_res).  M4/M5 replaces this body
       with re-enterable control; the call sites never change. *)
    "static void timbda_arbiter(long c0, long c1) { timbda_res = c0; }";
    "static void reset(void) { timbda_res = TIMBDA_NOTSET; timbda_cand0 = TIMBDA_NOTSET; timbda_cand1 = TIMBDA_NOTSET; }";
    "static void report(void) { if (timbda_res == TIMBDA_NOTSET) puts(""NOTSET""); else printf(""%ld\n"", timbda_res); }";
    "int main(void) {"
  ]
  ++ prog_block (golden_body g1 1%nat)
  ++ prog_block (golden_body g2 1%nat)
  ++ prog_block (golden_body g3 2%nat)
  ++ prog_block (golden_body g4 5%nat)
  ++ prog_block (golden_body g5 5%nat)
  ++ prog_block (golden_body g6 5%nat)
  ++ prog_block (golden_body g7 5%nat)
  ++ prog_block (golden_body g8 5%nat)
  ++ prog_block (golden_body g9 5%nat)
  ++ prog_block (golden_body g10 5%nat)
  ++ prog_block (golden_body g11 5%nat)
  ++ prog_block (golden_body g12 5%nat)
  ++ prog_block (golden_body g11 1%nat)
  ++ [ "  return 0;"; "}" ].
