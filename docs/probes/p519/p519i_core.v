(* p519i - T6 core validation probe (rebuild of p519f) + range-lemma inventory.

   Compiles against the gate-built timbda-kernel .vo tree + installed CompCert. *)

From Stdlib Require Import ZArith List.
Require Import compcert.lib.Coqlib compcert.lib.Integers compcert.lib.Maps
  compcert.common.Values compcert.common.AST compcert.common.Memory
  compcert.common.Events compcert.common.Globalenvs compcert.common.Smallstep
  compcert.cfrontend.Ctypes compcert.cfrontend.Cop compcert.cfrontend.Clight
  compcert.cfrontend.ClightBigstep.
Require Import Timbda.Syntax Timbda.Checks Timbda.Lower.

(* candidate clight_of: flatten a no-switch lstmt to a Clight.statement *)
Fixpoint clight_of (l : Lower.lstmt) : Clight.statement :=
  match l with
  | Lower.Lclight s => s
  | Lower.Lswitch _ => Clight.Sskip
  | Lower.Lseq l1 l2 => Clight.Ssequence (clight_of l1) (clight_of l2)
  end.

(* empty global environment: no symbols, no composites *)
Definition ge0 : Clight.genv :=
  {| genv_genv := Genv.empty_genv Clight.fundef Ctypes.type nil;
     genv_cenv := PTree.empty composite |}.

(* kernel add[2,3]; lower emits Sset lower_res (Ebinop Oadd (repr 2) (repr 3)) *)
Definition e_add : Expr :=
  App (Ret (VPrim PAdd))
      (TupE (Ret (VInt (Zpos (xO xH))) :: Ret (VInt (Zpos (xI xH))) :: nil)).

Compute Checks.det_check e_add.                      (* expected true *)
Compute Lower.lower e_add.

(* the Clight-side realization: one exec_Sset over eval_Ebinop of two constants *)
Definition probe_exec_add :
  Clight1.exec_stmt ge0 Clight.empty_env (PTree.empty val) Mem.empty
    (clight_of (Lower.lower e_add))
    Events.E0
    (PTree.set Lower.lower_res (Vlong (Int64.repr (Zpos (xI (xO xH)))))
               (PTree.empty val))
    Mem.empty ClightBigstep.Out_normal.
Proof.
  cbn [Clight1.exec_stmt clight_of Lower.lower].
  apply ClightBigstep.exec_Sset.
  eapply Clight.eval_Ebinop.
  - apply Clight.eval_Econst_long.
  - apply Clight.eval_Econst_long.
  - vm_compute. reflexivity.
Qed.

Print Assumptions probe_exec_add.
Print Assumptions clight_of.
Print Assumptions ge0.

(* range story: the Int64 spec lemmas T6's range hypothesis will cite *)
Search Int64.intval Int64.repr.
