# Probe p524 - T6 increment B: the general statement-level induction (2026-11-25)

The proof text of T6 increment B, proven against the increment-A store tree before
it was appended to `coq/Realize.v`.  Decision record: docs/PLAN.md decision 11;
narrative: docs/DESIGN-NOTES.md § 13.14 (increment B paragraph).

Parts (concatenated as `p524_all.v`, which compiles green in one pass):

| part | content |
| --- | --- |
| `p524_part1.v` | imports header + the Int64 mirror layer: `z64`, `clight_of_val`, `prim_clight`, `last_val`, the monadic `lower_final`, `vconst_z64` |
| `p524_part2.v` | `sem_*_long`: CompCert's own `sem_binary_operation`/`sem_unary_operation` specialized at `Int64.int` (add/sub/mul/div/lt/gt/le/ge/ne/neg) |
| `p524_part3.v` | Int64 range facts (`int64_range_signed`, `signed_repr_min`, `int64_eq_zero_ne`, `int64_mone_guard` via `Z.div_unique`), `prim_total_res_PDiv_ne`, `eval_const64`, `eval_vconst_val` |
| `p524_part4.v` | `eval_bin64_OXX` / `eval_un64_Oneg`: whole-expression eval lemmas over `Int64` constants (the Odiv one carries the zero-divisor and min_signed/-1 guards) |
| `p524_part5.v` | statement plumbing: `exec_seq_close`, `lower_res_ne_slot` (slot i is `Z.to_pos (i+2)`, lower_res is `xH`), `get_slot_neutral`, `last_val_ne_none`, `exec_rets_sets` (TupE "last ret wins"), `exec_slots_prelude` (Block prelude writes slot tempvars only) |
| `p524_part6.v` | `prim_guard_ok` + `prim_guard_ok_canon` (guards discharged from `app_node_ok_shape`'s three paths), `odiv_ready`, `prim_expr_eval` (explicit 18-arm per-prim dispatch - multi-goal `match goal`/`solve` under-covers in Rocq 9.1, see decision 11c) |
| `p524_part7.v` | `T6_exec_ws` (depth-indexed induction mirroring `T7_no_switch_ws`'s arm skeleton) and `T6_exec` at `le0` |

Reproduce (the kernel `.vo` tree is the gate-attested `timbda-kernel` package
output; its store path rotates with rebuilds - read it from
`nix build .#packages.x86_64-linux.timbda-kernel`):

    cd docs/probes/p524
    K=$(realpath ../../result)/lib/coq/9.1/user-contrib   # or the store path
    nix develop ../../.#rocq --command bash -c \
      "export ROCQPATH=\$K; rocq c p524_all.v"

Toolchain traps measured during authoring (full list in decision 11c): `rocq c`
compiles `.vos` first so the probe loads the kernel package via `ROCQPATH` (which
carries `.vo`); multi-goal `match goal`/`solve` dispatch silently leaves goals
open after nested `destruct`s; `destruct ... eqn:E` rewrites hypotheses that
contain the destructed term; `discriminate` is syntactic and misses
conversion-equal hypotheses that differ in hidden implicit args; `+` on
`Datatypes.length` needs `%nat` pinning in this file's scopes.
