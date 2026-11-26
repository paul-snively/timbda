# Probe p528 - T6 increment C: the div floor fold and the T4/T6 composition (2026-11-26)

The proof text of T6 increment C, proven against the increment-B store tree
(`timbda-kernel` 0.1.0, the gate-attested output of `767ed2fd`) before the
`coq/` edits.  Decision record: docs/PLAN.md decision 12; narrative:
docs/DESIGN-NOTES.md § 13.15 (and the retraction of the § 13.14
"`Z.div` truncates" line).

Parts (concatenated as `p528_all.v`, which compiles green in one pass against
the increment-B tree):

| part | content |
| --- | --- |
| `p528_part1.v` | imports header + the Int64<->Z bridge layer: repr-level arith (`bridge_add/sub/mul/neg`, unconditional via `Int64.eqm_samerepr` + `eqm_unsigned_repr`), signed-level cmp (`bridge_cmp_Cgt/Clt/Cge/Cle/Cne`, `zlt` destructed and the `Z.ltb` side pinned via `Z.ltb_lt/Z.ltb_ge`), the equality machinery (`signed_eq_of_eqm`, `signed_eq_of_mod_eq`, `int64_eq_signed`), `leb_as_or_lt_eq` / `leb_as_neg_lt`, and the local `vint_z` + `vint_z_VInt` |
| `p528_part2.v` | the div fork: five rungs (`divZ_exact`, `divZ_same_pos`, `divZ_same_neg`, `divZ_mixed_pos_neg`, `divZ_mixed_neg_pos` - the mixed-sign inexact quadrants overshoot by exactly 1), `bridge_divs_quot`, the measured gap literals (`divs_floor_gap_neg/pos = -3`, `floor_literal_neg/pos = -4`), and the dialect-ladder mirror `divZ_ladder` + `divZ_ladder_div` (four-quadrant `Z_lt_ge_dec` split, `Z.div_unique` routing, `set ... in *` shields) |
| `p528_part3.v` | the correspondence: arith map `prim_match_add/sub/mul/neg`, the pre-fold div arm (`prim_clight_old_divs`, truncation side) and the probe-side fold mirrors `prim_clight_new`/`prim_expr_new` with `prim_match_PDiv`/`prim_expr_new_eval_PDiv`/`prim_expr_new_PDiv_literal`; guard map `prim_guard_match_PGt/PLt/PGEq/PLEq/PNEq` (kernel guard success `<->` observed `Vint (Int.repr 1)`); the exact corner denotation (`prim_corner`, `rets_of_map_ret`, `e_fuel_prim_corner2 = 6%nat`, `denorm` = cbv over the evaluator constants, `denote_prim_corner_P*`); the composition `T6_T4_match_add` / `T6_T4_match_PGt` (denote-witness glued to `T6_exec_ws`'s exec-and-pin witness) and `T6_T4_match_PDiv_fold` (the T4 half at the kernel floor) |

Landing deltas (measured against the real tree during the `coq/Realize.v`
assembly, each recorded in decision 12d):

- `prim_clight_old_divs` and the probe mirrors do not land - the fold is the
  arm now; `prim_clight_floor_div` (the post-fold snapshot) is stated **with
  `int64_range` hypotheses**: without them it is false, because the fold reads
  operands through `vint_z = Int64.signed . z64`, and `Int64.signed (Int64.repr z) = z`
  holds only inside the signed window.
- `cbn [vint_z z64]` unfolds `z64` but silently refuses `vint_z` (an applied
  constant under `Z.div`) - bare `cbn` too, and with `vint_z` in the delta
  list; `unfold vint_z` fires.  The landed proofs use `unfold`.
- `prim_expr_eval`'s PDiv arm closes all four vs-cases via `eval_const64`;
  `odiv_ready` stays as a measured bridge the dispatch never reaches.
- `Realize.v` imports no `ListNotations` and does not see bare `eqmod`
  (`Zbits`'s): the increment-C section opens `Import Zbits ListNotations`
  locally.
- The probe's `prim_corner`-denotation and composition half of the PDiv
  theorem compile store-independently (the kernel `prim_total` floor is the
  same in both trees); the full `T6_T4_match_PDiv` (exec half through the
  folded lowering) exists only in the landed text.

Reproduce (the kernel `.vo` tree is the gate-attested `timbda-kernel` package
output; its store path rotates with rebuilds - read it from
`nix build .#packages.x86_64-linux.timbda-kernel --no-link --print-out-paths`):

    cd docs/probes/p528
    K=$(nix build ../../.#packages.x86_64-linux.timbda-kernel --no-link --print-out-paths)/lib/coq/9.1/user-contrib
    nix develop ../../.#rocq --command bash -c \
      "export ROCQPATH=\$K; rocq c p528_all.v"

Landing structure (post-split): the landed increment-C text is not a section
of `coq/Realize.v` anymore - the build-unit policy (decision 12e,
docs/DESIGN-NOTES.md § 4.2 and § 13.15) moved it verbatim into the fan-in
leaves `coq/RealizeBridges.v` / `coq/RealizeDiv.v` / `coq/RealizeCorners.v` /
`coq/RealizeCompose.v`, with `coq/Realize.v` the CompCert-side hub and
`coq/dune-workspace` at `(jobs 1)`.  The `prim_match_*` / guard maps and the
composition theorems sit in `RealizeCompose.v`; the corner denotations in
`RealizeCorners.v`; the div rungs/ladder in `RealizeDiv.v`; the bridges and
the signed window (with `int64_range`) in `RealizeBridges.v`.

Toolchain traps measured during authoring (full list in decision 12d): `Z`
destructs to 3 constructors - decide against 0 (`Z.eq_dec`) or split with
`Z_lt_ge_dec` (9.1's `Z_lt_dec` is a 3-way sumbool); `lia` refuses div/quot
identities head-on ("Cannot find witness") - route `Z.div_unique` with
`set (q := Z.quot x y) in *.` shields; a hypothesis-bearing `rewrite` puts the
MAIN goal first in the bullet sequence (`apply` puts it last); `e_fuel` of a
two-operand corner is 6 (`Checks.v`'s TupE arm `S (S (sumE ..))`) and fuel is
`nat` (`6%nat`); full `cbn` after a delta-listed `cbn` finishes the nat `+`
lia refuses; `cbv` (not `cbn` - by-name in 9.1) is what fires the monadic
beta-redexes of the denotation.

Split-era traps (measured during the fan-in landing, each cost one compile
round): a literal `*)` inside a header comment CLOSES the comment - regex-style
globs like `(foo_*, bar_*)` in a file header give "illegal begin of vernac";
`coqc` writes its `.vo` next to the SOURCE file, not to the cwd - a driver
that compiles `coq/X.v` with `-R _build/default Timbda` must relocate the
artifacts (vo/vok/vos/glob/aux) or the next unit fails with "Unable to locate
library Timbda.X (while searching for a .vos file)"; and a file whose proofs
use `rets_of` (Eval.v), `andb_and` (Checks.v), or bare `VInt` (Syntax.v) must
Require that module directly - `Require Import` chains do not re-export.

Corner-denotation restatement (the second half of increment C, same day;
probes `p528_part4_corner_equ.v` / `p528_part5_hrg.v` / `p528_part6_hds.v`):
the corner statements are pinned at ctrees' structural equality `≅`, NOT at
Leibniz `=` - `>>=` desugars to ctrees' CoFixpoint `subst`, a cofix can only
be unstuck under `observe`, so no delta list of any size can fire a bind
chain and `denote corner = sret v` is simply FALSE as a statement (ctrees'
own monad laws exist only at `equ`/`wbisim`).  The fuel-6 `denorm` cbv of the
first fan-in draft (superseded spelling in `p528_part3.v`) was the 61 GiB
rocqworker earlyoom shot: cbv on a fuel-6 corner duplicates the stuck cofix
tower per fuel layer - measured ladder on the add corner with
`kernel_cbn`: 1 s at fuel 4, 18 s at fuel 5, stall at fuel 6; `cbn [denE]` on
the TupE arm alone expands ~200k lines; `vm_compute` and `native_compute`
stall on the same terms; fuel 2 normalizes instantly.  The green route
touches ONE arm per rewrite: each `denE`/`denE_tup`/`apply_c` arm as a
`reflexivity`-level equation rewritten at the head, binds fired by
Denotation.v's `bind_sret_l`, closure by a negative-delta pass
(`cbn -[...]`) that DELTA-BLOCKS every fixpoint so re-opening the fuel tower
is impossible by construction (`p528_part4_corner_equ.v`, ~2 s end to end).

Corner-landing traps (each cost one compile round): Coq 9.1 rejects `cbn []`
and `cbn [a, b]` - delta lists are SPACE-separated and the all-blocked
spelling is the negative one `cbn -[a b]`; `cbn` with a delta list does not
unfold a constant whose subtree is stuck and then REVERTS the whole cascade
(`cbn [det_struct ... app_node_ok ...]` on the PGt corner returns the goal
unchanged), so guard-bearing claims route through one-line lemmas like
`prim_total_res_PGt_true` and an explicit `unfold` prologue instead;
`prim_args_ok` is the structural-prim arity check (false for PGt/PDiv), which
makes `det_struct` of a failed-guard corner genuinely FALSE - the guard
hypothesis is substance, not decoration; `Z.eqb`/`Z.ltb`/`orb` must stay
delta-blocked in the corner machine or the guard hypotheses lose their match;
`Local Open Scope Z_scope` retypes bare numerals, so fuel arguments need
`0%nat`/`6%nat` even where the fuel is syntactically obvious; `WBisimNotations`
clashes with compcert Coqlib (`&&&` registered at level 59 vs 40) so the
CompCert-facing leaf imports `EquNotations` only; the conjunction notation
`/\'` rejects a binder term on either side (`exists x, P` needs plain `/\`
with parentheses); and `unfold a b` space-separated is a syntax error.
