# p532 — the pinned oracle, re-measured (2026-11-27, issue #1 follow-up)

Probe against `augustss/verse-semantics` at the flake.lock pin
`d0eababfb7a5662f40bc7de45a596cb925445b8d` ("Tidy up mc_verify", 2026-06-26):
fresh clone, built with the pinned nixpkgs toolchain (`nix shell nixpkgs#ghc
nixpkgs#cabal-install` \u2192 GHC 9.10.3, `cabal build exe:tester -j2`; the `-j2`
cap follows the decision-20 host discipline \u2014 ran alongside the resident
workload, nothing evicted).

**Official suite, reproduced.** `tester tests/tests.versetest` bare (the issue
reporter's invocation): 238 tests \u2014 **219 expected, 3 unexpected (`Splice6`
unexpected failure, `fundom2` unexpected success, `for-wrap1` unexpected
failure), 16 skipped** \u2014 matching the issue #1 comment exactly.  With the
Makefile flags (`--evaluator=essential --assume-verified`): 208 expected, 30
skipped, 0 unexpected.  Both numbers recorded; the bare run is the comparison
basis.

**Probe file: `p532.versetest`, 19 claims, expectations derived BY HAND from
the printed rules first** (Fig. 10 line 459 and Fig. 13 re-read 2026-11-27 from
`SPJ_Verse-figures.pdf` renders), the oracle consulted second.  **19/19 PASSED
with expected results.**

| claim family | pins (each = expected value, `{wrong}` = stuck) | result |
|---|---|---|
| order observable via `all{}` | `all{1\|2}`\u2192`array{1,2}`; `all{2\|1}`\u2192`array{2,1}`; `all{3\|3}`\u2192`array{3,3}` | \u2713 \u2014 the distinct pins make non-commutativity AND non-idempotence explicit |
| leftmost split (Fig. 13 as printed) | `all{(1\|2)+(10\|20)}`\u2192`array{11,21,12,22}`; `all{(10\|20)+(1\|2)}`\u2192`array{11,12,21,22}` | \u2713 \u2014 witness pair: distinct tuples |
| `one`/`if` first candidate | `one{2\|1}`\u2192`2`; `if(x := 2\|1){x}else{0}`\u2192`2` | \u2713 |
| commutativity witness with NO collector | `one{1\|(1/0)}`\u2192`1`; `one{(1/0)\|1}`\u2192stuck | \u2713 \u2014 inexpressible in a bag model |
| dotdot = flat choice enumeration (line 459 bars) | `all{1..3}`\u2192`array{1,2,3}` (kernel's tuple reading would answer `array{array{1,2,3}}`); `one{1..3}`\u2192`1`; `all{3..1}`\u2192`array{}`; `all{x := 1..3; x*2}`\u2192`array{2,4,6}` | \u2713 |
| DEV-5 rows asked of the oracle | `7/(0-2)`\u2192`-4`; `(0-7)/(0-2)`\u2192`3`; `(0-6)/(0-4)`\u2192`1`; `32/4`\u2192`8` (surface `/` is integer div); `1/0`\u2192stuck; `if(x := 1/0){x}else{2}`\u2192stuck | \u2713 \u2014 floor confirmed; zero-divisor stuck NOT catchable (opposite of the VM probes) |

**What this feeds** (same commit): VERSE-RULES \u00a7 3 (line-459 row amended to the
printed bars; \u00a7 3.4 IterChoice amended to the printed juxtaposition; range-note
correction; new **DEV-21**; DEV-5 half-2 addendum), RULES-AUDIT \u00a7 4 follow-up
(two-operator finding; the `\u2248`-collapse observation), PLAN \u00a7 3 (T2 evidence
note), \u00a7 5.0 (M3 DoD: the two owed rulings), \u00a7 9 (anchor status + the
`www.cs.uoregon.edu` fact).

**Doctrine lines.**  The oracle is evidence for ledger rows, not a gate lane:
session-green \u2260 gate-green; the pinned chain remains the sole attestation
authority (the gate itself is untouched \u2014 docs-only increment, no coq/ or
dialect/ file changed, golden programs contain no `Iter` or `dotdot` syntax,
checked at `coq/tests/GoldenCompile.v` the same day, so M2's byte-pinned
evidence stands under either M3 ruling).  M2-era record untouched: everything
here is dated amendment, no silent edit.
