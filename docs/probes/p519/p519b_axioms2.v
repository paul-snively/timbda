(* p519b - continuation of the axiom battery: memory/global cone, Clight
   semantics cone, big-step cone, plus API spellings for ge0 construction. *)

Require Import compcert.lib.Coqlib compcert.lib.Integers compcert.lib.Maps
  compcert.common.Values compcert.common.AST compcert.common.Memory
  compcert.common.Events compcert.common.Globalenvs compcert.common.Smallstep
  compcert.cfrontend.Ctypes compcert.cfrontend.Cop compcert.cfrontend.Clight
  compcert.cfrontend.ClightBigstep.

(* ---------- memory/global cone ---------- *)
Print Assumptions Mem.empty.
Print Assumptions Mem.loadv.
Print Assumptions Mem.storev.
Print Assumptions Genv.empty_genv.
Print Assumptions Genv.init_mem.
Print Assumptions Genv.globalenv.
Print Assumptions PTree.get.
Print Assumptions PTree.set.

(* ---------- Clight semantics cone ---------- *)
Print Assumptions Clight.eval_expr.
Print Assumptions Clight.eval_lvalue.
Print Assumptions Clight.step.
Print Assumptions Clight.initial_state.
Print Assumptions Clight.semantics1.
Print Assumptions Smallstep.star.
Print Assumptions Smallstep.forward_simulation.

(* ---------- big-step cone (candidate T6 reference) ---------- *)
Print Assumptions ClightBigstep.Clight1.exec_stmt.
Print Assumptions ClightBigstep.Clight1.eval_funcall.
Print Assumptions ClightBigstep.Clight1.bigstep_program_terminates.
Print Assumptions ClightBigstep.Clight1.bigstep_semantics_sound.

(* ---------- API spellings for a hand-built empty genv / program ---------- *)
Search composite_env.
Search Composite_Env.
Search empty_genv.
Search prog_comp_env.
