(* p519l - localize which node of the p519i proof carries the axiom package *)

From Stdlib Require Import ZArith List.
Require Import compcert.lib.Coqlib compcert.lib.Integers compcert.lib.Maps
  compcert.common.Values compcert.common.AST compcert.common.Memory
  compcert.common.Events compcert.common.Globalenvs
  compcert.cfrontend.Ctypes compcert.cfrontend.Cop compcert.cfrontend.Clight
  compcert.cfrontend.ClightBigstep.
Require Import Timbda.Syntax Timbda.Checks Timbda.Lower.

Print Assumptions Mem.empty.
Print Assumptions sem_binary_operation.
Print Assumptions Clight.eval_Econst_long.
Print Assumptions Clight.eval_Ebinop.
Print Assumptions ClightBigstep.exec_Sset.
Print Assumptions Clight1.exec_stmt.
Print Assumptions Clight.function_entry1.
Print Assumptions Cop.Oadd.

(* the exact vm_compute equality used in p519i *)
Definition Hsem :
  sem_binary_operation
    {| genv_genv := Genv.empty_genv Clight.fundef Ctypes.type nil;
       genv_cenv := PTree.empty composite |}
    Cop.Oadd (Vlong (Int64.repr (Zpos (xO xH)))) Lower.tint64
    (Vlong (Int64.repr (Zpos (xI xH)))) Lower.tint64 Mem.empty
  = Some (Vlong (Int64.repr (Zpos (xI (xO xH))))).
Proof. vm_compute. reflexivity. Qed.
Print Assumptions Hsem.
