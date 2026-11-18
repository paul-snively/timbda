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
tests/corpus/m0.texpr        the spec (49 cases, `defaults fuel 24`)
tools/corpus/corpus.py       reader + Coq-corner generator:  --count | --summary | --emit-coq
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
```

`head none` is a first-class expectation: "the head table selects no redex here" is a
claim about the evaluator, not a missing case.  `--summary` prints which rows fire and
which rows the corpus never touches.

## 2. `head` and `norm` are two different claims

- `head` runs `Timbda.Eval.head_redex` on the **root as written** and compares the row tag.
  `R_Prim` / `R_PrimFail` stand in for the named Fig. 10 rows (`Add`, `Gt1`, `Gt2`, `IsInt1`,
  `IsInt2`, `Cons`, `DotDot`, …), because `head_redex` dispatches them through `prim_total`
  (`coq/Eval.v` header: one match licenses all named rows).
- `norm` runs `Timbda.Eval.norm` with the case's fuel and compares the whole term, by
  structural equality.

In the Coq corner both become `Example … Proof. reflexivity. Qed.`; in the extracted
corner both are OCaml equality against `Timbda_eval.head_redex` / `Timbda_eval.norm`.

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
4. Rows the head table never selects (`R_Subst`, `R_Gc1`, `R_Promote*`, `R_Iter*`, `R_HpAlpha`,
   `R_LamAlpha`) can never appear in a `norm` result; cases about them assert absence.

## 4. Stuck is not fail

The kernel separates three outcomes (`docs/VERSE-RULES.md` § 2.1): a row fires and produces a
value (`R_Prim`), a row fires and produces `Fail` (`R_PrimFail`: `gt2`, `isInt2`, EqK2, EqFail),
or no row fires at all (`head_redex = None`) and the term stays exactly as it is.  `1/0` and
`add(unit, 1)` are the third kind; `x = x`, `lam = lam`, `primhead = primhead` are the
paper's same-root exemption (Fig. 9 lines 441-445, Fig. 10 line 463) and are also third-kind.

## 5. What this corpus does and does not establish

**Does:** pins, for the 49 hand-derived closed terms in the corpus, (a) which row the head table selects at the
root, (b) the normal form under the documented fuel strategy, (c) that a Gallina function and
the OCaml extracted from it behave identically on those cases, and (d) that both readers accept
the same file (the check compares the case counts the two corners see).

**Measured status (2026-11-18, `nix build .#checks.x86_64-linux.corpus-differential`):** Coq corner
`reader_rc=0`, generated corner 315 lines, `rocq_rc=0`, `corner_cases = 49`; extracted corner
`extract_rc=0` (1094 lines of OCaml, `Print Assumptions` = *closed under the global context* for
`norm`, `head_redex` and `selected_rows`), `mli_rc=0`, `ocamlc_rc=0`, `driver_rc=0`,
`corpus corner: 49 cases, all agree with the extracted evaluator`.  The Coq corner is 98
`reflexivity` assertions (one `head` and one `norm` per case, 315 lines of generated `.v`) discharged
by `rocq`, so "the corpus is the spec" has build evidence behind it rather than a claim.

**Does not:** prove `T8` (`Wbisim (denote (norm fuel e) f') (denote e f)`) — the corpus is a
sample, the theorem is `Denotation.v`'s job.  It does not exercise the `Subst`/`Gc1`/`Promote*`
(block-slot completion, Fig. 8) or `Iter*` (Fig. 13) rows: those are deferred by the head table
(`coq/Eval.v` header), and `--summary` lists them as untouched.  It does not cover
unification/`Choice` at the *candidate-set* level (that is `≈`-level reasoning), nor
`Get`/`Put` events, nor open terms under a heap.  The third differential corner — the pinned
`verse-semantics` `tester` running `.versetest` files — is the M3 item in `docs/PLAN.md` § 8;
until it is wired, the oracle is consulted by hand (as in § 6 below), not by the harness.

## 6. Findings this corpus produced (M0)

- **`seq_z` off-by-one (kernel bug, fixed).**  `dotdot[ki1, ki2] ⟶ ki1 (ki1+1) … ki2`
  (Fig. 10 line 459) is inclusive; the pinned oracle agrees
  (`verse-semantics/reduction/Red.hs:1384`, `i <- [l..h]`).  `coq/Syntax.v`'s `seq_z` guarded on
  `Z.ltb lo hi`, so `1..3` materialised as `⟨1,2⟩`: the case `prim_dotdot_range` failed against
  a term the kernel itself computed, and the guard became `Z.leb`.  `KernelTest.v` now pins the
  inclusive range (`dotdot_range_inclusive`, `dotdot_single_element`, `dotdot_descending_empty`)
  so the shape cannot drift back.
- **Division rounding: measured, then pinned.**  `prim_div_negative_floor` asserts
  `(-7)/2 = -4`.  Both corners now confirm it independently: the Coq corner discharges
  `norm … = (ret -4)` (so Coq's `Z.div` floors toward `-infinity`) and the extracted corner runs the
  same case against the extracted evaluator; the pinned oracle uses Haskell `div`, which floors the
  same way (`verse-semantics/reduction/Red.hs:1347`).  Fig. 10 line 452 states `ki1 / ki2` without
  fixing the rounding for negative operands, so the case exists to keep the three-way agreement from
  being broken silently.
- **Which shapes the head table deliberately does not reach.**  `iter_all_shape_matches_but_deferred`
  is a case whose term is exactly `RewIterAll`'s left-hand side, and the corpus asserts `head none`:
  the row exists in `Rewriting.v` but is not selectable by `Eval.v`'s head table (M2/M3 work), which
  is the kind of absence a corpus can only record if it is written from the rules rather than from
  the evaluator.
- **Half-open vs closed normal forms.**  `norm1_then_seq_drops_the_value` and
  `eqtup1_single_element` document § 3's rule 1 vs rule 2 with two adjacent cases.

## 7. Adding a case

1. Derive the answer from `docs/VERSE-RULES.md` (quote the figure and line in `why`), not from
   `rocq`.  If the corner disagrees with your derivation, re-derive against the pinned oracle
   before touching either side — the point of the harness is that a disagreement is evidence.
2. Run `python3 tools/corpus/corpus.py --summary tests/corpus/m0.texpr` to see what the corpus
   already covers; keep names unique (`c_<name>` becomes a Coq identifier in the generated corner).
3. `nix build .#packages.x86_64-linux.timbda-corpus-coq-corner` (Coq side),
   `.#packages.x86_64-linux.timbda-corpus-ocaml-corner` (extracted side, its
   `$out/corpus-run.log` prints the actual term when an expectation misses), and
   `.#checks.x86_64-linux.corpus-differential` for the pair.
4. Nothing in `coq/` changes when a case is added; only `coq/*.v` rebuilds trigger the
   `Admitted`/axiom gate (§ `DESIGN-NOTES` § 6).  If a case exposes a kernel bug, fixing the
   kernel re-runs that gate, which is the point.
