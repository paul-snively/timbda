(* GoldenCompile.v — the M2 golden-compile record (D4b; docs/PLAN.md M2,
   docs/COMPILE-STRATEGY.md sec. 8's closing obligation, Amendment B's
   added multi-candidate programs).  Spec: tests/golden-compile/README.md.

   Three layers, one file:
   (1) the golden PROGRAMS (kernel terms, pre-window per the CompileTest idiom)
       and their compile verdicts — each one mirrors a landed coq/Compile.v
       corner lemma (the golden test re-reads the corners; it never invents);
   (2) the C RENDERER (render_stmt/render_frag_lines): the emitted CompCert
       statements as source lines against the harness contract (globals
       timbda_res/cand0/cand1 = the binary-positive idents xH / xO xH / xI xH,
       arbiter = x0 (x0 xH)); every body is pinned by `reflexivity`;
   (3) golden_lines: the WHOLE translation unit as a list of lines — the gate
       check computes it, assembles golden.c.actual, diffs it against the
       checked-in golden.c.expected, compiles it with clang, and diffs the run
       against golden.stdout.

   AUDIT boundary (same as CompileTest.v): Print Assumptions never runs here;
   the Compile-family cone is audited by the kernel lane's rocqchk sweep. *)

From Stdlib Require Import ZArith List.
Import ListNotations.

Require Import Timbda.Syntax Timbda.Semantics.

(* ---- the golden programs (pre-window; README table G1..G12) ---- *)
Definition g1  : Expr := Ret (VInt 3).
Definition g2  : Expr := Fail.
Definition g3  : Expr := Seq (Ret (VInt 1)) (Ret (VInt 2)).
Definition g4  : Expr := App (Ret (VPrim PAdd)) (TupE [Ret (VInt 7); Ret (VInt (-2))]).
Definition g5  : Expr := App (Ret (VPrim PDiv)) (TupE [Ret (VInt 7); Ret (VInt (-2))]).
Definition g6  : Expr := App (Ret (VPrim PDiv)) (TupE [Ret (VInt 1); Ret (VInt 0)]).
Definition g7  : Expr := Choice (Ret (VInt 1)) g6.                    (* certified left *)
Definition g8  : Expr := Choice g6 (Ret (VInt 2)).                    (* certified right *)
Definition g9  : Expr := Choice g6
               (App (Ret (VPrim PDiv)) (TupE [Ret (VInt 2); Ret (VInt 0)])). (* vacuous *)
Definition g10 : Expr := Seq g7 Fail.                                 (* cert in Seq *)
Definition g11 : Expr := Choice (Ret (VInt 1)) (Ret (VInt 2)).        (* TRUE multi-cand *)
Definition g12 : Expr := Choice (Ret (VInt 2)) (Ret (VInt 1)).        (* its flip *)

Require Import Timbda.Compile.

(* ---- (1) verdict record: fuel-pinned mirrors of the corner lemmas ---- *)
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

(* The refusals stay golden RECORD entries but not C programs (decision 18): *)
Example golden_refuse_fail_pair :
  compile_at (Choice Fail (Ret (VInt 1))) 5%nat = CTrap SResult nil.
Proof. reflexivity. Qed.
Example golden_refuse_two_sites :
  compile_at (Choice (Choice (Ret (VInt 1)) (cprim PDiv [VInt 1; VInt 0])) (Ret (VInt 2))) 5%nat
  = CTrap SResult nil.
Proof. reflexivity. Qed.
Example golden_refuse_pair_in_seq :
  compile_at (Seq g11 Fail) 5%nat = CTrap SResult nil.
Proof. reflexivity. Qed.

(* ---- (2) the C renderer (harness contract, README) ---- *)
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

Definition render_expr (e : Clight.expr) : string :=
  match e with
  | Clight.Econst_long n _ => str_app (Z.to_string (Int64.intval n)) "L"
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

(* body pins: the RENDERED text, pinned (reflexivity over closed terms) —
   these lines are the fragments the README table promises. *)
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

(* ---- (3) the whole translation unit ---- *)
Definition prog_block (body : list string) : list string :=
  ("  reset();" :: "  {" :: body) ++ ("  }" :: "  report();" :: nil).

Definition golden_lines : list string :=
  [ "#include <stdio.h>";
    "#define TIMBDA_NOTSET (0x7FFFFFFFFFFFFFFFL)";
    "static long timbda_res   = TIMBDA_NOTSET;";
    "static long timbda_cand0 = TIMBDA_NOTSET;";
    "static long timbda_cand1 = TIMBDA_NOTSET;";
    (* the arbiter body is the decision-18 SPEC: leftmost candidate present IS
       the observed value.  M4/M5 replaces this body (re-enterable control);
       the call sites never change. *)
    "static void timbda_arbiter(long c0, long c1) { timbda_res = c0; }";
    "static void reset(void) { timbda_res = TIMBDA_NOTSET; timbda_cand0 = TIMBDA_NOTSET; timbda_cand1 = TIMBDA_NOTSET; }";
    "static void report(void) { if (timbda_res == TIMBDA_NOTSET) puts(\"NOTSET\"); else printf(\"%ld\\n\", timbda_res); }";
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
  ++ [ "  return 0;", "}" ].
