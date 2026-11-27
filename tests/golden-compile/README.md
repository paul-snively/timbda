# golden-compile — the M2 golden test (D4b)

What this lane pins (COMPILE-STRATEGY sec. 8's closing line: "The golden test
then pins the fragments, including their named choice nodes"):

1. **Fragment pins (primary).** For each golden program, `compile p fuel` equals
   the hand-derived `CRes SResult` — every one mirrors a `coq/Compile.v` corner
   lemma (the golden test re-reads the corners, it does not invent expectations).
2. **Rendered source (mechanical).** `coq/tests/GoldenCompile.v` renders every
   compilable program's fragment through the C printer (`render_frag`) into a
   single source `golden_source`.  The check computes it and diffs it against
   the checked-in `golden.c.expected` — byte-for-byte.
3. **Executed stdout (terminal).** clang compiles `golden.c.expected` and the
   pinned `golden.stdout` is the run's output.  The C program is the emitted
   structure plus the HARNESS contract below; the arbiter body is the spec's
   M2 reading (leftmost candidate present).

Harness contract (the only hand-written C, and it is pinned):
- globals `long timbda_res, timbda_cand0, timbda_cand1;` — `xH`/`xO xH`/`xI xH`
  (Compile.v sec. 3), initialized to the sentinel `TIMBDA_NOTSET` before each
  program body runs.
- `SOk v` ends with `timbda_res = <v>L;`; `SFail`/`SStuck` end with `;` —
  `terminal_stmt` writes NOTHING for both (Compile.v:213-218 measured; the
  Coq-side verdicts distinguish them, the C observes an unset global — the
  golden stdout prints `NOTSET`).
- the arbiter `timbda_arbiter(c0, c1)` = `timbda_res = c0;` — the decision-18
  spec (leftmost-present IS the observed value); its M4/M5 implementation
  (re-enterable control) replaces the body, not the call sites.

Refusals are part of the golden record but NOT C programs: `Choice Fail (Ret 1)`
(genuine pair, Fail arm not seatable), the two-site program, and the four
context-carried genuine pairs (p531) stay Coq-side `CTrap` pins.

## The golden programs

| # | program | fuel | verdict | C body (rendered) | stdout |
|---|---|---|---|---|---|
| G1 | `Ret 3` | 1 | `SOk 3` | `timbda_res = 3L;` | `3` |
| G2 | `Fail` | 1 | `SFail` | `;` | `NOTSET` |
| G3 | `Seq (Ret 1) (Ret 2)` | 2 | `SOk 2` | `timbda_res = 2L;` | `2` |
| G4 | prim add `7 + -2` | 5 | `SOk 5` | `timbda_res = 5L;` | `5` |
| G5 | prim div floor `7 / -2` | 5 | `SOk -4` | `timbda_res = -4L;` | `-4` |
| G6 | prim div `1 / 0` | 5 | `SStuck` | `;` | `NOTSET` |
| G7 | `Choice (Ret 1) div0` | 5 | `SOk 1` | `timbda_res = 1L;` | `1` |
| G8 | `Choice div0 (Ret 2)` | 5 | `SOk 2` | `timbda_res = 2L;` | `2` |
| G9 | `Choice div0 div0'` | 5 | `SStuck` | `;` | `NOTSET` |
| G10 | `Seq (Choice (Ret 1) div0) Fail` | 5 | `SFail` | `;` | `NOTSET` |
| G11 | `Choice (Ret 1) (Ret 2)` — TRUE multi-candidate (Amendment B's added program) | 5 | `SOk 1` | `; arbiter(cand0, cand1);` with cand writes | `1` |
| G12 | `Choice (Ret 2) (Ret 1)` — its flip | 5 | `SOk 2` | candidate constants swapped | `2` |
| G13 | G11 at fuel 1 (budget honesty: the node materializes complete) | 1 | `SOk 1` | same as G11 | `1` |

G7–G9 are the determinate programs the certificate proves straight-line: **zero
choice nodes** — the strategy's "nondeterminism either proved away or printed in
the C", proved-away half.  G11–G13 are the printed half: the named arbiter
`Scall` exercised by real two-candidate programs (Amendment B's obligation —
the m2-det corpus's single genuine two-candidate program is eval-side; the
golden corpus ADDS these compile-side ones).
