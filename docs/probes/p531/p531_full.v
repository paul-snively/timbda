Require Import Timbda.Syntax Timbda.Semantics.
From Stdlib Require Import ZArith List.
Import ListNotations.

(* kernel terms BEFORE the Compile/CompCert window (CompileTest idiom) *)
Definition sp_seq_fail : Expr := Seq (Choice (Ret (VInt 1)) (Ret (VInt 2))) Fail.
Definition sp_seq_val : Expr := Seq (Choice (Ret (VInt 1)) (Ret (VInt 2))) (Ret (VInt 7)).
Definition sp_cert_ctrl : Expr :=
  Seq (Choice (Ret (VInt 1)) (App (Ret (VPrim PDiv)) (TupE (map Ret [VInt 1; VInt 0])))) Fail.
Definition sp_block : Expr := Block nil (Choice (Ret (VInt 1)) (Ret (VInt 2))).
Definition sp_tup : Expr := TupE [Choice (Ret (VInt 1)) (Ret (VInt 2)); Ret (VInt 3)].

Require Import Timbda.Compile.

(* (1) Pair site under a Seq prefix whose terminal rule says SFail *)
Compute compile sp_seq_fail 5%nat.
(* (2) Pair site under a Seq prefix that itself completes *)
Compute compile sp_seq_val 5%nat.
(* (3) Control: the CERTIFIED (hinted) path on the same shape *)
Compute compile_h sp_cert_ctrl 5%nat (Some true).
(* (4) Pair under Block / inside TupE *)
Compute compile sp_block 5%nat.
Compute compile sp_tup 5%nat.
