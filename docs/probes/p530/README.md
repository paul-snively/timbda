# p530 — the candidate-peek measurements at the BrF seam (2026-11-26/27)

Probe against the landed `coq/Compile.v` (D1+D2), run against the built tree:

    cd coq && <build>; cd _build/default && coqc -Q . Timbda <p530_full.v>   # scratch form

`p530_full.v` is the probe as executed (the compile algebra sections 1-7 +
the probe block appended at the end).  Every line below is a `Compute` output.

Setup: `probe_h e k hint := fold h g (denE nil e k) (mkCS k nil hint)`;
`ch_v_s = Choice (Ret 1) div[1,0]`, `ch_s_v` its flip, `ch_f_v = Choice Fail
(Ret 1)`, `ch_s_s = Choice div0 div0`.

| probe | verdict |
|---|---|
| `ch_v_s`, hint `Some true` | `CDone [] (SOk 1)` — **true = LEFT arm** |
| `ch_v_s`, hint `Some false` | `CDone [] SStuck` — false = right arm |
| `ch_v_s`, hint `None` | `CTrap []` — D1 trap (unchanged) |
| `ch_s_v`, hint `Some false` | `CDone [] (SOk 2)` |
| `ch_f_v`, `Some true` / `Some false` | `CDone [] SFail` / `CDone [] (SOk 1)` — **both arms ANSWER: fail-as-zero IS a candidate (T2)** — the genuine pair decision 15 names |
| `ch_s_s`, `Some true` / `Some false` | `CDone [] SStuck` / `CDone [] SStuck` — **the vacuous site agrees across answers** |
| `ch_v_s` at fuel **1**, `Some true` | `CLoop []` — the main fold too shallow: budget verdict, not a wrong pick |
| `Choice ch_v_s (Ret 2)` (TWO sites), `Some true` | `CDone [] (SOk 1)` — **the same hint answered EVERY BrF: the silent left-priority run** — a single-hint certificate must refuse multi-site programs |
| `Seq ch_v_s Fail`, `Some true` | `CDone [] SFail` — site inside `Seq` resolves; discarded prefix decides the terminal (Semantics.v:219-224) |

Rulings this feeds (landed as decision 17 with increment D3):
1. A bool answer means "left"/"right" outright.
2. The arm test is THREE-valued: `AVVal` (SOk or SFail), `AVStuck` (CDone
   SStuck), `AVUndef` (CLoop/CTrap — undecided, never read as "no candidate").
3. `choice_cert` certifies (Val,Stuck)->left, (Stuck,Val)->right,
   (Stuck,Stuck)->left (vacuous, output-neutral by the agreement row); the
   genuine pair (Val,Val) and any UNDEF side return None -> the trap stands.
4. The certificate runs the SAME `compile` algebra (unhinted) on each arm at
   the program budget — decision 15's kernel-side determinacy analysis, with
   the guard rail intact (bounded fold per arm, no whole-program normalization).
5. Single-hint scope: exactly-one-site programs only (the two-sites row is the
   measured reason); multi-site choice-node materialization is D4.
6. Walker shape (Rocq 9.1.1 trap list): the cross-recursive Expr/list walk is
   rejected ("principal argument equal to e instead of rest") and constructor-
   rebuilt recursive arguments are rejected ("instead of one of the following
   variables") — the accepted shape is a mutual pair indexed on a shared `nat`
   depth, run at `e_fuel p` (exact; shallower only ever refuses).
