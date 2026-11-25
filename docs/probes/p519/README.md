# Probe p519 - T6 design measurements against the installed CompCert 3.17 (2026-11-25)

These probes settle the three design obligations PLAN § 3 item 6 / `coq/Lower.v`'s
header pinned before T6's first proof line.  Decision record: docs/PLAN.md
decision 10; narrative: docs/DESIGN-NOTES.md § 13.14.

Reproduce (the kernel `.vo` tree path is the gate-attested `timbda-kernel`
package output; it rotates with rebuilds - read the path from a
`nix build .#packages.x86_64-linux.timbda-kernel` result):

    cd docs/probes/p519
    K=$(realpath ../../result)/lib/coq/9.1/user-contrib   # or the store path
    nix develop ../../.#rocq --command bash -c \
      "export ROCQPATH=\$ROCQPATH:$K; rocq c p519i_core.v"

Spellings that took measurements of their own: Rocq 9.1 renamed `rocq v` ->
`rocq c`; the rocq devShell already carries CompCert on `COQPATH` (deprecated
name - forward it as `ROCQPATH`); `rocq c` defaults to `.vos` search, so the
`-Q` flag needs a built-with-`vos` tree while `ROCQPATH` finds the package's
`.vo` set fine.

Results (all against `coqPackages_9_1` CompCert 3.17 + the gate kernel build):

| probe | question | measured answer |
| --- | --- | --- |
| `p519a_axioms.v` | kernel calibration | `T7_no_switch` closed; `T4_sem` eq_rect_eq-only |
| `p519a_axioms.v` | value-arithmetic cone | `sem_binary_operation`/`sem_unary_operation` carry the 4-axiom Flocq/Classical package - the whole `Fixpoint` bodies (float branches -> Flocq classical rounding), not just the evaluated branch; re-measured: `sem_cast` is closed |
| `p519b_axioms2.v` | memory/global cone | `Mem.empty/storev`, `PTree.get/set`, `Genv` pieces closed; `Mem.loadv` carries the package (its `val`-construction chain reaches Flocq rounding) |
| `p519b_axioms2.v` | semantics cone | the `Clight.eval_expr`/`eval_lvalue` inductives carry the package (the axioms sit in the premise types - `sem_binary_operation` and co.); `Clight.step`, `star`, big-step `eval_funcall`/`bigstep_program_terminates`: the same package |
| `p519i_core.v` | is a statement-level `exec_stmt` derivation for the kernel `add[2,3]` real? | yes - one `exec_Sset` over `eapply eval_Ebinop` + two `eval_Econst_long` + a `vm_compute` closed equality; `Print Assumptions` = the 6-axiom package |
| `p519l_localize.v` | where do the axioms enter? | `sem_binary_operation` alone: 4-axiom package; `eval_Ebinop`/`exec_Sset`: adds `inline_assembly_sem` + `external_functions_sem`; `Mem.empty`, `Clight.function_entry1`, `ge0`, `clight_of`: closed |

`exec_Sset` is a one-premise rule in 3.17 (`eval_expr` only); sequences split
into `exec_Sseq_1`/`exec_Sseq_2`; `Clight1.exec_stmt` is the transparent
specialization `exec_stmt function_entry1`, so generic constructor spellings
apply after `cbn [Clight1.exec_stmt]`.  `apply Clight.eval_Ebinop` leaves
`v1/v2` without instances (they occur only in premises) - `eapply` fixes it.
