# p531 — the context-carried genuine pair (2026-11-27, lands with increment D4a)

Probe against the D4a tree BEFORE the root-scope ruling, run against the built tree:

    cd coq && <build>; cd _build/default && coqc -Q . Timbda p531_full.v

`p531_full.v` is the probe as executed (kernel terms pre-window, Compile window
after — the CompileTest idiom).  Every line below is a `Compute` output.

| program | pre-ruling output | verdict |
|---|---|---|
| `Seq (Choice (Ret 1) (Ret 2)) Fail` | `CDone [node] (SOk 1)` | **MIS-EMIT** — the `Seq`-prefix terminal rule says `SFail`; the whole-program `Pair` dispatch dropped it |
| `Seq (Choice (Ret 1) (Ret 2)) (Ret 7)` | `CDone [node] (SOk 1)` | **MIS-EMIT** — the kernel value is `SOk 7` (prefix discarded); the site's leftmost is not the program's value |
| `Seq (Choice (Ret 1) div0) Fail`, hint `Some true` | `CDone [Sskip] SFail` | the CERTIFIED path handles the context correctly (the hint travels with the fold) — unchanged by the ruling, re-pinned |
| `Block nil (Choice (Ret 1) (Ret 2))` | `CDone [node] (SOk 1)` | carrier-blind mis-emit risk; trapped by the ruling |
| `TupE [Choice (Ret 1) (Ret 2); Ret 3]` | `CDone [node] (SOk 1)` | **MIS-EMIT** — the tuple-building disappears entirely |

Ruling this feeds (landed in `coq/Compile.v` sec. 3/9, decision 18): the `Pair`
dispatch is a WHOLE-PROGRAM replacement outside the fold — it sees the SITE but
not the CONTEXT.  `peek_result` therefore splits by carrier: root site
(`p = Choice _ _`) certifies `Pair`; a non-root genuine pair returns `Trap`.
Measured AFTER the ruling, all four context carriers answer `CTrap SResult []`
(pinned: `c_pair_in_seq_refused`, `c_pair_in_seq_val_refused`,
`c_pair_in_tup_refused`, `c_pair_in_block_refused`); the forced/vacuous rulings
keep their D3 scope (context carried, fold-decided terminal).  Named obligation:
node emission INSIDE the fold (three-valued hint, continuation decides the
terminal) — D4-follow-up/M3, same drawer as the multi-site hint queue.
