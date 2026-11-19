# Corpus harness (M0 tail)

One spec file, read twice, executed twice.  This is the smallest thing in the repo
that makes the differential claim of `docs/PLAN.md` § 6 checkable instead of asserted:

| corner | reader | evaluator it runs | build |
|---|---|---|---|
| Coq | `tools/corpus/corpus.py` (Python) → generated `.v` of `reflexivity` assertions | Gallina `Timbda.Eval.norm` / `head_redex`, compiled by `rocq` | `nix build .#packages.x86_64-linux.timbda-corpus-coq-corner` |
| extracted | `tools/corpus/driver.ml` (its own reader, written against the surface syntax) | the OCaml that `Extraction` produced from `Timbda.Eval.norm` | `nix build .#packages.x86_64-linux.timbda-corpus-ocaml-corner` |

`nix build .#checks.x86_64-linux.corpus-differential` builds both, fails if either
corner fails or if the two case counts differ, and writes `$out/report.txt`.

```
tests/corpus/m0.texpr        the spec (64 cases, `defaults fuel 24`)
tools/corpus/corpus.py       reader + Coq-corner generator:  --count | --count-cands | --summary | --emit-coq
tools/corpus/driver.ml       reader + extracted-evaluator driver (compiled with the extracted module)
tools/extract/extract.v      the `Extraction` driver (not part of the Timbda theory)
```

The corpus expectations were derived **by hand from the paper rules** (`docs/VERSE-RULES.md`,
SPJ "Supporting Figures" Figs. 9-13) before looking at what the evaluator produces.
When a corner disagreed, the case was re-derived against the paper text plus the pinned
`verse-semantics` oracle and the resolution recorded in the case's `why` field - one of
those re-derivations turned out to be a kernel bug (§ 6).

## 1. Surface grammar

Canonical form, no sugar.  `expr` maps 1:1 onto the kernel constructors in `coq/Syntax.v`:

| corpus | kernel | note |
|---|---|---|
| `(ret v)` | `Ret v` | |
| `(glob POS)` | `Glob pos` | `ident := positive`, so `(glob 1)` is `xH` |
| `(app e a)` | `App e a` | |
| `(tup e ...)` | `TupE [e; ...]` | primop operand tuple |
| `(seq e1 e2)` | `Seq e1 e2` | |
| `(unify e1 e2)` | `Unify e1 e2` | the paper's `e1 = e2` |
| `(choice e1 e2)` | `Choice e1 e2` | candidate bag (`br2` in the denotation) |
| `fail` | `Fail` | |
| `(block (slot ...) e)` | `Block [(ty, option Val); ...] e` | slot `(ty)` = declared only (`@None Val`), `(ty v)` = filled |
| `(iter comb e1 e2)` | `Iter comb e1 e2` | `iall` `iif` `ifor` |
| `unit` `true` `false` | `VUnit` `VTrue` `VFalse` | |
| `INT` (may be negative) | `VInt z` | Z literal, negatives via `Z.opp` in the generated corner |
| `(primv padd)` … | `VPrim PAdd …` | the 18 names of `Inductive Prim` |
| `(tupv v ...)` | `VTup [v; ...]` | a *value* tuple (`(tupv)` is the empty one) |
| `(lam ty e)` | `VLam ty e` | |
| `(delay e)` | `VDelay e` | |
| `(var n)` | `VVar n` | de Bruijn index |
| `tunit tbool tint (arr ty ty) tany` | `TUnit` `TBool` `TInt` `TArr` `TAny` | |

Case blocks:

```
defaults fuel 24            # applies to every later `case` unless the case says `fuel N`
case some_name            # [a-z][A-Za-z0-9_]* ; used as the suffix of c_<name> in the Coq corner
  head r_seq              # which head-table row the ROOT must select, or `none` (no row fires)
  expr (unify (ret 3) fail)
  norm (unify (ret 3) fail)
  why "…why that is the right answer, with the paper rule and figure line…"
  cands (expr ...)          # optional, repeatable: one expected `cand_bag` element
  cands_why "…why that bag has that shape…"
```

`head none` is a first-class expectation: "the head table selects no redex here" is a
claim about the evaluator, not a missing case.  `--summary` prints which rows fire, how
often, and which rows the corpus never touches.  `cands` is likewise optional but
counted separately by the harness (`--count-cands`, `corner_cands`, `cands corner:`), so a
corner that silently dropped the candidate-bag assertions cannot pass by satisfying the
case count alone.

## 2. `head` and `norm` are two different claims

- `head` runs `Timbda.Eval.head_redex` on the **root as written** and compares the row tag.
  `R_Prim` / `R_PrimFail` stand in for the named Fig. 10 rows (`Add`, `Gt1`, `Gt2`, `IsInt1`,
  `IsInt2`, `Cons`, `DotDot`, …), because `head_redex` dispatches them through `prim_total`
  (`coq/Eval.v` header: one match licenses all named rows).
- `norm` runs `Timbda.Eval.norm` with the case's fuel and compares the whole term, by
  structural equality.
- `cands` (when present) runs `Timbda.Eval.cand_bag` on the case's `norm` expectation and compares
  the resulting **list**, in order: it is a claim about the evaluator's candidate bag, not about
  `≈`-level candidate sets (`docs/DESIGN-NOTES.md` § 9 states what `cand_bag` is allowed to claim).

In the Coq corner all three become `Example … Proof. reflexivity. Qed.`; in the extracted
corner they are OCaml equality against `Timbda_eval.head_redex` / `Timbda_eval.norm` /
`Timbda_eval.cand_bag`.

## 3. What `norm` actually does (read this before believing an expectation)

`coq/Eval.v`'s normalizer is a *fuel-bounded one-pass* strategy:

```coq
Fixpoint norm fuel e :=
  match fuel with
  | 0 => e
  | S n => match head_redex e with
           | Some (_, e') => norm n e'                       (* head step: fuel - 1, re-visit *)
           | None => <rebuild: each child gets norm n, root left as it is>
         end
  end.
```

Consequences that expectations must respect:

1. **Head steps repeat.**  After a redex fires, the result is at the head position again and
   is re-tried with one less fuel.  `unify 3 (seq unit fail)` → Norm1 → `seq unit (unify 3
   fail)` → the Seq-of-a-value row fires immediately → `unify 3 fail`, which is stuck.  So the
   normal form is `(unify (ret 3) fail)`, not the intermediate `seq`.
2. **A rebuilt root is not re-visited.**  If no row fires, the term is rebuilt bottom-up with
   the *same* remaining fuel, and the rebuild itself is never handed back to `head_redex`.
   `unify (ret unit) (ret (tupv unit))` rewrites by EqTup1 to
   `seq (ret unit) (ret (tupv unit))` and *stays* that way: the inner parts normalized, the
   new root did not get another look.  `seq (ret unit) (ret (tupv unit))` is the normal form
   at any fuel.
3. Fuel is not "steps needed": it is the depth of normalization passes.  A term whose head
   row keeps firing consumes fuel per step; a stuck head with normalizing children converges.
4. Rows the head table never selects (`R_Gc1`, `R_Iter*`, `R_HpAlpha`, `R_LamAlpha`) can never appear
   in a `norm` result; cases about them assert absence.  `R_Subst` and `R_PromoteL/R` are selected now
   (M0 close-out, `docs/DESIGN-NOTES.md` § 9) and 8 corpus cases exercise them.

## 4. Stuck is not fail

The kernel separates three outcomes (`docs/VERSE-RULES.md` § 2.1): a row fires and produces a
value (`R_Prim`), a row fires and produces `Fail` (`R_PrimFail`: `gt2`, `isInt2`, EqK2, EqFail),
or no row fires at all (`head_redex = None`) and the term stays exactly as it is.  `1/0` and
`add(unit, 1)` are the third kind; `x = x`, `lam = lam`, `primhead = primhead` are the
paper's same-root exemption (Fig. 9 lines 441-445, Fig. 10 line 463) and are also third-kind.

## 5. What this corpus does and does not establish

**Does:** pins, for the 64 hand-derived closed terms in the corpus, (a) which row the head table
selects at the root, (b) the normal form under the documented fuel strategy, (c) the candidate bag
`Timbda.Eval.cand_bag` returns for 7 of those terms, (d) that a Gallina function and the OCaml
extracted from it behave identically on those cases, and (e) that both readers accept the same file
(the check compares the case counts *and* the candidate-bag counts the two corners see).

**Measured status, attested 2026-11-19 11:46:33-11:59:39 through `tools/build/nix-gate.sh`**
(`.#checks.x86_64-linux.corpus-differential`, 764 s — the check drags the 12 min 43 s `timbda-kernel`
build along with it).  What its output
`/nix/store/xdsy2v844zfnixkqjdw0qz8cdw0bbcwj-timbda-corpus-differential` contained, read from the
files themselves:

- `coq-corner-status.txt`: `reader_rc=0`, `cands_rc=0`, `reader_cases=64`, `reader_cands=7`,
  `corner_lines=421`, `rocq_rc=0`, `marker=corner_cases = 64`, `cands_marker=corner_cands = 7`;
- `ocaml-corner-status.txt`: `extract_rc=0`, `extracted_lines=1465`, `mli_rc=0`, `ocamlc_rc=0`,
  `driver_rc=0`, `summary=corpus corner: 64 cases, all agree with the extracted evaluator`,
  `cands_summary=cands corner: 7 groups, all agree with cand_bag`;
- `report.txt`: `Coq corner: 64 cases / 7 cand_bag claims, generated by corpus.py, all discharged by
  rocq`, `generated corner: 421 lines of .v`, and under `axiom footprint of the extracted evaluator:`
  four `Closed under the global context` lines.

The Coq corner is 135 `Example` obligations — 64 `head`, 64 `norm`, 7 `cands` — each closed by
`Proof. reflexivity. Qed.`; `corpus.py --emit-coq` emits them in 421 lines and the corner derivation
closes all 135 under `rocq`.  That is what turns "the corpus is the spec" from an assertion
into a build fact.  Re-running the check costs 764 s plus whatever headroom the kernel compile needs,
so run it through `tools/build/nix-gate.sh` (exit 0 green, 1 a nix failure, 2 refused by preflight,
124 stopped by its host watchdog) rather than a bare `nix build`: `tools/build/README.md`.  Store paths
quoted here are dated records of one run — the collector deleted the *previous* run's corner and check
outputs at 10:50:10-10:50:11, and both corners re-derive whenever `docs/` changes — so the attestation
is the run and the status files it wrote, not the paths.  Sequence and journal timestamps:
`docs/DESIGN-NOTES.md` § 4.3.

**Does not:** prove `T8` (`Wbisim (denote (norm fuel e) f') (denote e f)`) — the corpus is a sample,
the theorem is `Denotation.v`'s job, and `cands` claims are about the *evaluator's* candidate list,
not about `≈`-level candidate sets.  It does exercise the `Subst`/`PromoteL`/`PromoteR` rows now
(§ 9 of `docs/DESIGN-NOTES.md`), but not `Gc1` (deliberately unselected) nor the `Iter*` rows (Fig.
13), both of which `--summary` lists as untouched.  It does not cover `Get`/`Put` events, nor open
terms under a heap, nor division against the C++ runtime (only against the pinned Haskell oracle: the
truncating-`/` claim has no citation, `docs/VERSE-RULES.md` § 3 DEV-5).  The third differential
corner — the pinned `verse-semantics` `tester` running `.versetest` files — is the M3 item in
`docs/PLAN.md` § 8; until it is wired, the oracle is consulted by hand (as in § 6 below), not by the
harness.

## 6. Findings this corpus produced (M0)

- **`seq_z` off-by-one (kernel bug, fixed).**  `dotdot[ki1, ki2] ⟶ ki1 (ki1+1) … ki2`
  (Fig. 10 line 459) is inclusive; the pinned oracle agrees
  (`verse-semantics/reduction/Red.hs:1384`, `i <- [l..h]`).  `coq/Syntax.v`'s `seq_z` guarded on
  `Z.ltb lo hi`, so `1..3` materialised as `⟨1,2⟩`: the case `prim_dotdot_range` failed against
  a term the kernel itself computed, and the guard became `Z.leb`.  `KernelTest.v` now pins the
  inclusive range (`dotdot_range_inclusive`, `dotdot_single_element`, `dotdot_descending_empty`)
  so the shape cannot drift back.
- **Division rounding: measured against the oracle, and only against the oracle.**
  `prim_div_negative_floor` asserts `(-7)/2 = -4`.  Both corners confirm it independently (the Coq
  corner discharges `norm … = (ret -4)`, so Coq's `Z.div` floors toward `-infinity`; the extracted
  corner computes the same `-4`), and the pinned oracle floors the same way (`Red.hs:1346-1347`:
  `j /= 0` then `i \`div\` j`, with `Core/Expr.hs:623` + `645-647` making "divisor is not 0" a
  *precondition* while `primOpCanFail Div = False`).  What is **not** verified is the C++ side: the
  claim that the runtime evaluates `/` with truncation toward zero has no citable source in this
  repo, so the case pins a two-way agreement (kernel, Haskell oracle) and the C++ lowering is an
  open obligation (`docs/VERSE-RULES.md` § 3 DEV-5, `docs/PLAN.md` § 4 T3).  A zero divisor is
  `PStuck` in the kernel (`coq/Syntax.v:349`), which is the reading that matches the oracle's
  precondition rather than its `primOpCanFail` flag - that tension is an open question for the
  upstream team, not something the corpus decides.
- **Fig. 8 slot completion is reachable now, and 8 cases pin it.**  `Eval.v`'s `Block` arm
  (`body_walk`) selects `R_PromoteL`, `R_PromoteR`, `R_Subst`, which changes what `norm` produces
  for a block with a declared slot: `promotel_binds_declared_slot`
  (`(block ((tany)) (unify (ret (var 0)) (ret 7)))` → `(block ((tany 7)) (ret 7))` - PromoteL fills
  the slot and the unification node is *replaced by the value*) versus `subst_declared_slot_needs_a_value`
  (`(block ((tany)) (ret (var 0)))`, `head none`: `x{}` is declared, not `x v`) are the two ends of
  that behavior, and `promote_blocked_by_another_slot` / `promote_blocked_by_an_existing_heap_ref` /
  `guard_blocked_promote_still_descends` pin where the rows are *not* allowed to fire.  The four beta
  expectations in `KernelTest.v` and the corpus had to be re-derived for it: beta now lands on a value
  under a complete heap instead of stopping at `x = v`.
- **`cand_bag` is the one claim here that is a reading, not a transcription - and it is confirmed
  as a reading.**  The 7 `cands` groups (10 expected candidate elements) assert the evaluator's
  candidate list exactly as `Eval.v` computes it: recursive split under `Choice`; an all-valued block
  read through with its slot list kept; a block with a `None` slot treated as one leaf; a choice under
  `Seq`/`=`/`Iter` treated as one leaf.  No `R_Choice` row exists, and not splitting under a bind is
  the deferred bind/`br2` interchange, so these assertions *pin* a decision rather than derive one.
  The reading was put to the project owner on 2026-11-19 and confirmed as written; what it is still
  *not* is the set of normal forms reachable by `norm` (`norm` does not fire inside a branch point),
  and what `cand_bag_declared_block_is_a_leaf` and `cand_bag_choice_under_a_bind_is_one_candidate`
  record is that decision.  See `docs/DESIGN-NOTES.md` § 9.
- **Which shapes the head table deliberately does not reach.**  `iter_all_shape_matches_but_deferred`
  is a case whose term is exactly `RewIterAll`'s left-hand side, and the corpus asserts `head none`:
  the row exists in `Rewriting.v` but is not selectable by `Eval.v`'s head table (M2/M3 work), which
  is the kind of absence a corpus can only record if it is written from the rules rather than from
  the evaluator.  `Gc1` is likewise not selected on purpose (no `dropSlot`/`shrinkE` reindexing lemma
  exists to check it against).
- **Half-open vs closed normal forms.**  `norm1_then_seq_drops_the_value` and
  `eqtup1_single_element` document § 3's rule 1 vs rule 2 with two adjacent cases.


## 7. Adding a case

1. Derive the answer from `docs/VERSE-RULES.md` (quote the figure and line in `why`), not from
   `rocq`.  If the corner disagrees with your derivation, re-derive against the pinned oracle
   before touching either side — the point of the harness is that a disagreement is evidence.
2. Run `python3 tools/corpus/corpus.py --summary tests/corpus/m0.texpr` to see what the corpus
   already covers; keep names unique (`c_<name>` becomes a Coq identifier in the generated corner).
3. Build the pair with `tools/build/nix-gate.sh .#checks.x86_64-linux.corpus-differential` — the
   two corners and the differential are one bill of work (§ 5), and on this box the gate is the safe
   way to pay it (§ 5's exit codes).  Building one corner on its own (`nix build
   .#packages.x86_64-linux.timbda-corpus-coq-corner`, or the ocaml corner, whose build log shows the
   actual `norm`/`cand_bag` output when a case reports `FAIL` rather than `ok`) still drags
`packages.timbda-kernel` in through `buildInputs`, so prefer the gate.
4. Nothing in `coq/` changes when a case is added; only `coq/*.v` rebuilds trigger the
   `Admitted`/axiom gate (§ `DESIGN-NOTES` § 6).  If a case exposes a kernel bug, fixing the
   kernel re-runs that gate, which is the point.
