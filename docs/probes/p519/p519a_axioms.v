(* p519a - T6 design probe, part A: axiom-surface battery against the
   INSTALLED CompCert 3.17 tree (nixpkgs coqPackages_9_1.compcert) plus the
   gate-built timbda-kernel .vo set.  Purpose (docs/PLAN.md sec. 3 item 6,
   docs/DESIGN-NOTES.md sec. 13.7): decide the Flocq audit-lane question
   BEFORE the first T6 proof line - which constants in the candidate T6
   cone are closed, and where the ClassicalDedekindReals pair enters. *)

Require Import compcert.lib.Coqlib compcert.lib.Integers compcert.lib.Maps
  compcert.common.Values compcert.common.AST compcert.common.Memory
  compcert.common.Events compcert.common.Globalenvs compcert.common.Smallstep
  compcert.cfrontend.Ctypes compcert.cfrontend.Cop compcert.cfrontend.Clight
  compcert.cfrontend.ClightBigstep.

Require Import Timbda.Syntax Timbda.Checks Timbda.Lower.

(* ---------- calibration lines (expected: closed / eq_rect_eq) ---------- *)
Print Assumptions Lower.T7_no_switch.
Print Assumptions Checks.T4_sem.

(* ---------- the value/arithmetic function cone (expected: closed?) ---------- *)
Print Assumptions sem_binary_operation.
Print Assumptions sem_unary_operation.
Print Assumptions sem_cast.
Print Assumptions bool_val.
Print Assumptions Int64.add.
Print Assumptions Int64.repr.
Print Assumptions Int64.signed.
Print Assumptions Int64.intval.

(* ---------- the memory/global cone (expected: closed?) ---------- *)
Print Assumptions Mem.initial_memory.
Print Assumptions Mem.loadv.
Print Assumptions Mem.storev.
Print Assumptions Genv.empty_genv.
Print Assumptions Genv.init_mem.
Print Assumptions Genv.globalenv.
Print Assumptions PTree.get.
Print Assumptions PTree.set.

(* ---------- the Clight semantics cone (expected: pair; re-measure) ---------- *)
Print Assumptions Clight.eval_expr.
Print Assumptions Clight.eval_lvalue.
Print Assumptions Clight.step.
Print Assumptions Clight.initial_state.
Print Assumptions Clight.semantics1.
Print Assumptions Smallstep.star.
Print Assumptions Smallstep.forward_simulation.

(* ---------- the big-step cone (the candidate T6 reference) ---------- *)
Print Assumptions ClightBigstep.Clight1.exec_stmt.
Print Assumptions ClightBigstep.Clight1.eval_funcall.
Print Assumptions ClightBigstep.Clight1.bigstep_program_terminates.
Print Assumptions ClightBigstep.Clight1.bigstep_semantics_sound.

(* ---------- API surface searches for the formulation ---------- *)
Search composite_env empty.
Search Genv.empty_genv.
Search Int64.add Int64.signed.
