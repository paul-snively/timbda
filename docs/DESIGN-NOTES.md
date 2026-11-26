# Timbda-0 kernel design notes

Working notes for the M0 Gallina spike (`coq/`).  These record *why* the kernel
is shaped the way it is, and the toolchain facts that the shape depends on.
Rule provenance itself lives in `docs/VERSE-RULES.md`; milestone scope in
`docs/PLAN.md`.

## 1. Locally-nameless / de Bruijn conventions

- Locals are de Bruijn **indices**, innermost binder = `0` (Weirich autosubst
  idiom: raw AST + a disciplined `lift`/`shrink`; PLAN § 5.2 "well-scoped ASTs").
- A block `block{∃X{hp}. e}` stores its slot list `X` **outermost-first**:
  slot `i` may refer to the `i` slots listed before it, so at slot `i`'s entry
  position the cutoff is `i + d` (where `d` counts binders already crossed
  *outside* the block); the body position has cutoff `|X| + d`.
- Slot values are `option Val`: `None` = declared-but-unvalued, the domain of
  the promote/Gc rules (VERSE-RULES § 2, Fig. 8).  Non-recursive slots only;
  recursive heaps are the Gc-Rec/Def-Rec Tier-2 rows.  What that boundary is, in
  the published record (cited 2026-11-21): the machine-side twin of the carve-out
  VC's own confluence theorem stands on — VC proves confluence (Thm 4.1) only for
  "well-behaved" terms, and its unrestricted recursion question is open by the
  paper's own admission (skew confluence, Ariola & Blom, APPL 2002; VC: "the proof
  of skew confluence is not yet complete"); full lineage in PLAN § 11 "The Ariola
  chain inside VC", incl. VC's rule u-occurs, which fails the cyclic unification
  x = ⟨1, x, 3⟩; e outright.  The kernel stands on the well-behaved side of that
  fork: the promote/GC occurs guards (Rewriting.v ll. 78-83, 226, 232-236) carry
  "Exact for the non-recursive M0 fragment", and VC's even/odd term is queued as a
  candidate out-of-corpus test for the M2/M3 flex obligations.  The Tier-2
  recursive rows, when built, inherit the choice VC faces — carve-out vs. skew
  confluence — as a decision to measure and cite, not inherit.
- `liftE k e` inserts `k` binders *outside* `e`; `shrinkE e` (cutoff `d`) removes
  the binder at index `d` and reindexes above it.  Under the GC1 side condition
  (`occurs` says the dropped binder is unused) the `Var d -> Var 0` clause is
  unreachable junk.

## 2. Coq 9.1 recursive-function constraints (measured, not theorised)

Probe files: `/tmp/opencode/synprobe/p1..p15.v` (rocq 9.1.0, switch
`RP.2026.02.0~9.1~2026.01`).  Findings that shaped `coq/Syntax.v`:

| Idiom | Result on 9.1 |
|---|---|
| Mutual `Fixpoint {fV, fE}` recursing on Val/Expr structure only | accepted |
| Same block plus a **list-typed** member (`fVs : list Val -> list Val`) | **rejected** — "Cannot guess decreasing argument of fix" / "Recursive call to fa2 has principal argument equal to "v" instead of "rest"" |
| Element↔list cycles written with the accumulator idiom (`with fGo : nat -> list A -> list A := fix go ... end 0`) | **rejected** (same messages) |
| Eta self-calls inside a mutual block: `map (liftV k d) vs`, `existsb (occursE i) es` | accepted, computes correctly |
| Total walker taking an **opaque callback** (`walkSlotsV (cb : Val -> nat -> Val)`), fed `fun v i => liftV k (i + d) v` from the element block | accepted, computes correctly |
| Uniform-`nat`-fuel mutual block (fuel at argument position 1 of every member) | accepted (kept as the fallback if eta-calls ever meet a proof wall) |
| Cutoff threaded through the *returned* function (`match v return (nat -> Val) with ...`) | accepted, but list cases must then be stubbed or supplied separately |
| `Inductive PrimResult := PRes Val \| ...` (anonymous constructor parameter) | **rejected**: "Cannot infer the type of Val" — write `PRes : Val -> PrimResult` |
| `From Coq Require Import ...` | deprecated warning → use `From Stdlib` |

Chosen design (p14a, now in `coq/Syntax.v`): two total walkers defined *before*
the element blocks —

```coq
Fixpoint walkSlotsV (cb : Val -> nat -> Val) (d0 : nat)
  (slots : list (Ty * option Val)) : list (Ty * option Val) := ...
Fixpoint anySlotsV (cb : Val -> nat -> bool) (p0 : nat)
  (slots : list (Ty * option Val)) : bool := ...
```

and element-only mutual blocks `{liftV,liftE}`, `{shrinkV,shrinkE}`,
`{occursV,occursE}` whose Block cases read

```coq
Block (walkSlotsV (fun v i => liftV k (i + d) v) d slots)
      (liftE k (length slots + d) body)
```

This keeps every recursive call structurally decreasing on a Val/Expr, so no
fuel is needed anywhere in the kernel — which matters because the M0 soundness
lemmas are proved by `coinduction`/`play` over the ctrees layer, not by
induction over syntax.

## 3. ctrees / itree layer

- Pinned as `github:vellvm/ctrees@cabcf9bf24b0f459204a7da19ac01b7697ff04e3` (branch `dev`,
  pins.toml `[formal.ctrees]`).  Upstream package name is `rocq-ctree` (version `2.0-dev`),
  Coq logical path `CTree`; the flake builds it from that input (`nix build
  .#packages.x86_64-linux.timbda-ctrees`) with **no local patches**.  The same revision can be
  materialised as a read-only working copy under `deps/ctrees` via `tools/ctrees-sync.sh`, which
  is what the `deps/ctrees/theories/...` line citations below point into.
- Import ladder used by the kernel (mirrors `deps/ctrees/examples/ImpBr/ImpBr.v`):
  `From CTree Require Import CTree Eq.` pulls `Equ`/`Trans`/`SBisim`/`SSim`/
  `CSSim` and the up-to coinduction tactics (`coinduction`, `step`, `play`,
  `upto_bind`, `upto_bind_eq`).  `Import CTreeNotations` + `Open Scope ctree_scope`.
- Pure effect signature is itree's `void1`, written directly: `ctree void1 B2 R`.
  There is no `Empty` in ctrees, and `ctree (fun _ => void1)` is the wrong shape.
- Choice is the binary-branch bifunctor `B2` (`Br`/`BrS` visible; `spin` is the
  divergent branch).  The laws the kernel's `Choice` depends on
  (`theories/Eq/SBisim.v:1315-1372`): `br2_assoc`, `br2_commut`, `br2_idem`,
  `br2_merge`, `br2_is_stuck`, `br2_stuck_l`, `br2_stuck_r`, `br2_spin_l`
  (`coq/Probe.v` exercises four of them).  `~` is SBisim; `sbisim_wbisim`
  (`theories/Eq/WBisim.v:227`) is the bridge to weak bisimilarity used by the
  strategy-freedom statements.  Stay off `brS2`.
- State handling: `interp_state` + a `E ~> Monads.stateT env (ctree void1 B2)`
  handler, and an `is_simple` instance on the effect signature so that
  `interp_state_sbisim` can transport SBisim through the interpreter.

## 4. Build / dev-shell workflow

Toolchain contract (docs/PLAN.md § 6 "Formalization side": *Nix-native Rocq; opam
secondary*): the host provides **nix only**.  Rocq, Python 3, GHC, Bazel/bazelisk, git —
everything else — arrives from the flake; nothing else on the host is load-bearing.
Canonical loop:

```sh
python3 tools/pins/pins.py check                          # pins.toml == MODULE.bazel == flake.lock
tools/build/nix-gate.sh                                   # the default eight-lane chain, --max-jobs 1, and
                                                        # a refusal to start if the host has no headroom
   # (nix builds cannot be cgroup-capped from here: see sec. 4.3).  Individually they are:
nix build .#checks.x86_64-linux.version-consistency       # nixpkgs tool versions == pin table
nix build .#checks.x86_64-linux.coq-load-chain            # every kernel logical dep resolves on nix
nix build .#packages.x86_64-linux.timbda-kernel           # M0 kernel + its Print Assumptions audit
nix build .#checks.x86_64-linux.corpus-differential       # two-corner differential corpus (tools/corpus/README.md)
nix develop .#rocq                                        # or .#all: Rocq + GHC + bazelisk, all flake-provided
cd coq && dune build                                      # the in-shell kernel build
nix develop .#devShells.x86_64-linux.rocq -c tools/build/coq-build.sh   # the same build, guarded: envelope
                                                        # + peak + watchdog + artifact check (sec. 4.2)
```

**DEV-3 closed (2026-11-18).**  `flake.nix`'s `coqStack` builds the libraries nixpkgs does not
ship — `coq-ext-lib`, `paco`, `rocq-coinduction` (tag `v1.21`), `coq-itree`, `rocq-ctree` —
from the locked flake inputs (pins.toml `[formal.*]`; each also exposed as
`nix build .#packages.x86_64-linux.timbda-{extlib,paco,coinduction,itrees,ctrees}`), and
relation-algebra / equations / Stdlib come from nixpkgs.  So `cd coq && dune build` runs inside
`nix develop .#rocq` with **nix only** on the host; the transitional switch is retired (it held
rocq-coinduction 1.21, coq-ext-lib 0.13.0, coq-itree dev@284d4224, coq-paco dev@d0561bf,
rocq-ctree 2.0-dev, dune 3.21.0 — all now reproduced by the flake from the pin table).
Verified 2026-11-18 on the pinned toolchain: kernel build clean (8 `.vo` modules, 12m58s),
load-chain clean, version-consistency clean, golden-test clean.

The kernel build *is* the axiom gate: `timbda-kernel`'s `buildPhase` fails if `Admitted`
appears in dune's output, or if the `Print Assumptions` blocks (§ 6, RULES-AUDIT § 6) name
anything other than exactly one axiom, `Eqdep.Eq_rect_eq.eq_rect_eq`.

`tools/ctrees-sync.sh` survives only as a way to read the pinned ctrees source locally (the
notes above quote `deps/ctrees/theories/...` line anchors); its opam-switch pinning mode is
removed, and CTree reaches the build through the flake input instead.

Dune facts learned the hard way (all recorded in `coq/dune-project`):

- `(lang dune 3.21)` must be the **first** line of `dune-project`.
- `(using coq 0.7)` is load-bearing, not taste.  coq lang ≥ 0.8 makes dune compile with
  `coqc -boot`, and `-boot` switches off rocq 9.1's implicit loadpath: because nixpkgs ships
  the Stdlib as a *package* (`rocqPackages.stdlib` → `user-contrib/Stdlib`) rather than as
  rocq-core theories, `From Stdlib Require …` and bare `ZArith`/`BinPos` then fail — that was
  every 0.8-mode failure measured in extlib/ctrees on 2026-11-18.  coq lang 0.7 is dune's
  "implicit bootstrap": no `-boot`, rocq keeps its loadpath.  `(using rocq 0.11)` (the new RBL)
  is not an option yet: dune's rocq mode needs the RBL-era package layout nixpkgs' 9.1 doesn't ship.
- coq lang 0.7 also **rejects** installed theories in `(theories CTree …)` ("Theory CTree not
  found in the current scope. Upgrade to coq lang 0.8"), which is why `coq/dune` carries no
  `(theories …)`/`(deps …)`: logical deps resolve through rocq's loadpath.  nixpkgs' rocq hook
  exports ROCQPATH only, dune 3.21's coq-mode theory DB scans COQPATH only, so the flake mirrors
  one into the other (its own `setupHook` + `export COQPATH="$ROCQPATH…"` in each buildPhase).
- dune's coq mode calls `coqc`/`coqdep`/`coqdoc`; nixpkgs' rocq 9.1 ships only `rocq`, so
  `flake.nix` provides `rocq-shims` (`rocq c` / `rocq dep` / `rocq doc`).
- silence the deprecated-coq-lang lint with `(warnings (deprecated_coq_lang disabled))`.
- The project name and the package name must match (`timbda-kernel`), and
  `(coq.theory (name Timbda) (package timbda-kernel))` has **no** `(deps …)`
  field: logical dependencies come from the installed libraries.
- List patterns (`[VInt a; VInt b]`) need `Import ListNotations`.

### 4.1 Reading a build result honestly (a mistake measured on 2026-11-18)

**A build's verdict is its exit status, not its output.**  Recording a kernel run as

```sh
dune build 2>&1 | grep -v 'Warning' | tail -40      # never do this to decide pass/fail
```

reads "nothing printed" as "nothing failed", and it is wrong twice over: the pipeline's
exit status is `tail`'s, so dune's non-zero status is gone, and the filter chain removes
exactly the lines that carry a failure - rocq reports an error as a
`File "./tests/KernelTest.v", line 383, characters 21-24:` header followed by an `Error:`
line, and filtering either of those leaves an empty stream.  A "compilation produced no
output" claim made that way hid two real failures (`rw_here` applied to a constructor with
the wrong arity, and a `:= by vm_compute` definition that rocq's grammar rejects - use
`Proof. vm_compute. Qed.`); the build was red while the terminal looked quiet.

The rule to keep: redirect the whole build, check the status, then read the *file*.

```sh
cd coq && dune build > /tmp/opencode/dune-build.log 2>&1; echo "dune exit=$?"
grep -c -e Error -e Admitted /tmp/opencode/dune-build.log    # a report, not the verdict
```

`flake.nix` already encodes this: `timbda-kernel`'s `buildPhase` runs `set -o pipefail` and
greps `build.log` (a file, not a stream), and every corpus corner records its own `*_rc`
into `status.txt` *and* gates on it (sec. 4.2).  That is why a `nix build` verdict is trustworthy
and an ad-hoc filtered shell one-liner is not.  Counting (`grep -c`) is reporting: it says how big
the problem is, never whether there is one - which is why § 8.2 requires a status code per step.

### 4.2 Keeping the kernel build inside a memory envelope (measured 2026-11-19)

This machine also hosts the model server, so "the build is red" and "the build was killed" are
different failures and need different answers.  Both were measured.

**The host facts, from `journalctl -u earlyoom` (2026-11-19, verbatim).**  `earlyoom` fires only
when *both* memory and swap are at/below 10%, and this box has 3.8 GiB of swap total, so the swap
half of that condition is usually near-false and occasionally near-true:

```
01:50-03:50  mem avail 82.45%, swap free 0 of 3907 MiB (0.00%)      -> no kill (mem term false)
04:26:04     low memory! at or below SIGTERM limits: mem 10.00%, swap 10.00%
             sending SIGTERM to "strata-host": badness 1238, VmRSS 42651 MiB
04:37:31     mem avail: 951 of 63916 MiB (1.49%), swap free: 364 of 3907 MiB (9.32%)
             sending SIGTERM to "rocqworker": badness 1556, VmRSS 55022 MiB
05:06:11     mem avail: 1171 of 63916 MiB (1.83%), swap free: 327 of 3907 MiB (8.38%)
             sending SIGTERM to "strata-host": badness 1243, VmRSS 44542 MiB
```

The 04:37:31 line is the interesting one: the process earlyoom chose was a **55 GiB `rocqworker`**,
i.e. this project's own build, and the two `strata-host` kills either side of it happened while the
model server held **43.5 GiB RSS**, of which **43.4 GiB is private anonymous dirty** - one `rw-p`
region of 41,909,476 kB backed by a **1.5 GiB** pack on disk (`Mapped:` host-wide is only 1.0 GiB, so
none of it is page cache).  Swap free here is never comfortable: 0% during the quiet hours, 9.32-9.45%
during the kills, 47% later in the day.  A machine whose swap is 3.8 GiB against a resident 43 GiB
model server and a build that can want 55 GiB is a machine where the OOM decision is *which* big
process to shoot, not *whether* one is coming.

**What a killed build looks like.**  The signature is the same whether the killer is `earlyoom` or a
harness timeout that outlived its own command: `coq/_build/log` ending `[got signal TERM]`, dune exit
1 with **no `Error:` line anywhere**, `tests/KernelTest.vo` absent, and `tests/KernelTest.glob` sitting
at exactly 131072 bytes with nothing compiled from it.  Both kinds happened here today: the journal
records the OOM kills quoted above, and at least one `[got signal TERM]` came from this agent's own
command timeout rather than from earlyoom.  That is why the wrapper separates its three verdicts -
*this cgroup* OOM-killed a worker (`memory.events: oom_kill > 0`), killed externally (journal evidence
in the build window), or something else entirely (no cgroup kill, no journal kill, and a log with no
error) - instead of concluding "OOM" from a silent log.

**Coq's own demand, measured.**  `dune build -j 1` over the whole kernel peaked at **56,588,736 kB
maxrss (53.9 GiB)** in one `coqc`, 685 s CPU.  That is not a property of the kernel or of the fuel
(`norm` is called at 10-24 here): a bounded probe (`tools/build/coq-probe.sh`, which refuses to run
if `memory.max=max`) isolated it to one `Example` of mine, `denote_norm_beta_is_value`, which asked
the bytecode machine to decide `denote e 24 = denote (norm 24 e) 24`.  Under a 1.6 GiB cap that
probe ran 300 s without finishing, accumulating 540,907 `memory.high` throttle events; at fuel 4
the same claim left an open goal (`Attempt to save an incomplete proof`); with `reflexivity` it
failed as `Unable to unify`.  The claim was itself wrong (§ 3.1, `RULES-AUDIT` § 3 class C1:
adequacy is a `Wbisim` statement with fuel transfer, not an `=` between two fuel-equal ctrees
terms), so it is gone from `KernelTest.v`, which now records the measurements instead.  After
removing it, the guarded kernel build reports **dune exit 0, scope-cgroup peak 647 MiB, 52 s**,
with all 8 expected `.vo` files present, and `nix build .#packages.x86_64-linux.timbda-kernel`
reports `axioms referenced (1): Eqdep.Eq_rect_eq.eq_rect_eq`.

**The repo-side guard** (`tools/build/coq-build.sh`, run from the dev shell):

1. *preflight* - refuse to start unless `MemAvailable` covers the envelope plus headroom;
2. *containment* - re-exec inside `systemd-run --user --scope -p MemoryHigh=… -p MemoryMax=…
   -p MemorySwapMax=0`, so an over-growing worker is killed inside its own cgroup instead of pushing
   the host into a swap storm;
3. *verified containment* - the wrapper reads back `$CG/memory.max` and **fails if it is not the
   requested byte count**.  Not paranoia: an early version of the wrapper dropped the `-p`
   properties across its own `exec systemd-run` and silently created an *uncapped* scope
   (`memory.max=max`), which made a 54 GiB compile look protected - and while it ran it displaced
   the model server, which is exactly what it was supposed to prevent.  Caps in user scopes do work
   (`memory.max=1073741824` measured inside one); they only work when actually passed;
4. *designated victim* - raise `oom_score_adj=500` on `coqc`/`rocqworker` (raising is allowed
   unprivileged; lowering needs `CAP_SYS_RESOURCE`), so that when the kernel's own OOM killer or this
   scope's own `MemoryMax` decides who dies, it takes the restartable build rather than the database,
   the model server, or the login shell.  The claim has a measured limit, in sec. 4.3: it does not apply
   to `earlyoom`, whose badness is built from RSS, so a build capped at a few GiB never outscores a
   43-49 GiB model server;
5. *host watchdog* - host `MemAvailable` and swap headroom are sampled while the build runs, the
   low-water marks are printed, and the build's own process group is aborted when either falls under
   `TIMBDA_COQ_MIN_AVAIL` (1 GiB) or `TIMBDA_COQ_MIN_SWAPFREE` (700 MiB), with a verdict line that names
   itself.  Why it is needed is in sec. 4.3: the envelope is committed host memory, so when the build
   fills it the kernel pays by swapping *other* processes' pages - here, the model server's;
6. *honest verdict* - dune's own exit code, the unfiltered log, the scope's `memory.peak` and
   `memory.events` counters, and the expected `.vo` set.  "No `Error:` line" is never success: a run
   that consumed its whole envelope and left no artifacts is a *kill*, and the wrapper says whose
   kill it was (`oom_kill > 0` = the envelope `MemoryMax` was too small for that unit;
   `oom_kill = 0` with missing artifacts = an external kill, with the journal window quoted;
   `memory.high` counts in the hundred-thousands = throttled to a stall, which looks the same in
   dune's output).

**Concurrency is baked into the project**, not auto-detected: `coq/dune-workspace` sets `(jobs 1)`
as of 2026-11-26 (it read `(jobs 2)` until then).
(dune requires `(lang dune 3.21)` as the first line of that file, and `(jobs 1)` is a top-level
field - writing `(dune (jobs 1))` gives `Invalid first line` / `Unknown field "dune"`.)  dune's
auto-detection picked 20-way concurrency on this 20-core box, which is a self-inflicted OOM before
Strata is even considered.  The 2026-11-26 drop to serial is measured, not cautious: at the time the T6 hub
unit appeared to cost a ~15 GiB coqc (`strata-host` measured 41.5-50 GiB resident the same evening,
`(jobs 2)` producing two silent deaths - dune RC=1 / coqc RC=143, no Coq error line, no `.vo`, the
exact failure signature sec. 4.1 warns about).  Re-measured the same day AFTER the `≅` restatement
(sec. 13.16): a clean full-lane `dune build` sampled at 0.3 s peaks at 655 MiB overall (`Realize.v`
499 MiB, `tests/KernelTest.v` 655 MiB, `Lower.v` 422 MiB) and the flake's `rocq check` cone sweep at
515 MiB - the 15 GiB peak was the grinding Leibniz-`=` corner WIP, not the hub's cost.  Serial stays
the ruling: the two silent deaths were concurrency-driven, and the lane still must not run twice at
once next to a ~54 GiB model server.  The realization side was split fan-in the same day
(sec. 13.15) so no unit re-checks the accumulated history.  Override on a quiet machine with
`dune build -j 8`.

**Deliberately not done:** taking headroom from Strata.  Its engine *is* this session's model host,
and a `MemoryHigh` far below its 43.4 GiB of dirty anon would OOM-kill it rather than throttle it.  The
fixes that would change the host picture all need root, and all of them are recorded rather than
applied: (i) swap with real headroom - 3.8 GiB of swap against a 43-49 GiB model server and a build that
once reached 55 GiB is what makes `earlyoom`'s AND-condition reachable; (ii) telling `earlyoom` which
processes it may not shoot, which on this box (earlyoom 1.7, matching process *names*, no `--ignore`
flag) means `--avoid '(^|/)(init|systemd|sshd|dbus|gala|dune|coqc|rocq|rocqworker|nix|gcc|ld|as)$'` plus
`--prefer '(^|/)(strata|strata-host|llama|redpanda)$'`; (iii) a `MemoryMax` drop-in on
`nix-daemon.service`, which is the only way to cap the build sandbox that sec. 4.3 shows is otherwise
uncapped.  Exact commands, the trade-off, and the fact that none of it has been run are in
`tools/build/README.md`.

**One more vacuity hole found while building this guard** (§ 8.2's rule, in a place I had not
guarded): `nix build .#packages.x86_64-linux.timbda-corpus-ocaml-corner` exited **0** while its own
status said `ocamlc_rc=2  driver_rc=127` - the phases wrote status files that nothing read, so a
corner that neither compiled nor ran was still a successful derivation.  Both corner packages now
assert their own `rc` values and their minimum generated/extraction sizes; `checks.corpus-differential`
keeps its independent gate.  The compile error behind it was a missing `;` in `tools/corpus/driver.ml`:
`(match … end)` followed by `false` on the next line parses as an application - `This expression has
type unit; this is not a function`.


### 4.3 Cold builds, and the half of the gate that cannot be contained (measured 2026-11-19)

The 647 MiB of § 4.2 is a **warm** number: `coq/_build` already held the `.vo` files, so the heaviest
units were not recompiled.  A cold tree - what a fresh clone, a `git clean -xdf`, or my own
`rm -rf coq/_build` gives you - costs more, and the envelope defaults have to be sized against the
cold number, not the warm one.

**A cap set below a unit's working set is a stall, not a protection.**  Four capped attempts at the
same cold build, judged by `memory.events` and by the `.vo` set rather than by the log:

| envelope | concurrency | what happened | counters |
|---|---|---|---|
| `HIGH=2G MAX=3G`, +1G headroom | workspace `(jobs 2)` | ~2 h, never finished; I stopped it | `high` 251,745 events, `oom_kill` 0, a `rocqworker` in `D` state at 2858516 kB |
| `HIGH=3G MAX=4G`, +512M | `-j 1` | 522 s, then the caller's own timeout killed the scope | peak 3107 MiB, `high` 849,937 events, `max` 0, `oom_kill` 0, `Denotation.vo` absent |
| `HIGH=3400M MAX=3600M`, +1G | `-j 1` | 39 min, stopped by me | peak 3450 MiB, pinned against `memory.high=3400M`; `high` **4,041,348** events, `max` 0, `oom_kill` 0, `Denotation.vo` absent |
| `HIGH=4400M MAX=4800M`, +1G, `SWAPMAX=1G`, host floors 900M/1200M | `-j 1` | 186 s, **aborted by the host watchdog** | peak 4433 MiB and still rising, `high` 154,707, `max` 0, `oom_kill` 0; host `SwapFree` 2517 -> 1106 MiB, `MemAvailable` min 1884 MiB; `verdict: STOPPED BY THE HOST WATCHDOG`, wrapper exit 124 |

All four rows have the same outward signature - no Coq error, no `oom_kill`, no `Denotation.vo` - and
row 4 is the one that makes the case for reading counters: `high` 154,707 in 186 s with `max` and
`oom_kill` at 0 is a cgroup fighting its own soft limit, which is indistinguishable in dune's output
from a build that was limited cleanly.  What stopped it was the host floor, not the envelope: host
`SwapFree` fell to 1106 MiB, above the 700 MiB floor this run demanded and far from the ~390 MiB
(10% of 3907 MiB) at which earlyoom's swap term would have become true.

Put the four rows next to the host numbers and the shape of the problem is unambiguous.  A
`Denotation.v` compile wants **more than 4.4 GiB of private anonymous memory** (row 4 peaked at 4433
MiB inside a 4800 MiB envelope and had not finished); this box has ~6 GiB of `MemAvailable` while the
model server holds 43-50 GiB; and its swap is 3.9 GiB, 1.4 GiB of which was already in use before the
build started.  A capped build then cannot finish (rows 1-3), and an uncapped one pays for itself out
of the model server, which is the storm measured above.  Those two facts - not a preference - are what
`tools/build/coq-build.sh` and `tools/build/nix-gate.sh` are built on.

**A self-inflicted measurement from the same afternoon.**  While row 3 was still running I edited
`tools/build/coq-build.sh`, and bash - which reads a script lazily, by byte offset - misparsed the
half-changed file: the wrapper printed `line 212: syntax error near unexpected token` and
`line 260: [0: command not found`, and produced no verdict block at all.  The file is syntactically
clean *now*, which is the lesson: a script that misparsed only while it was being read leaves nothing
for a later `bash -n` to find.  Two rules follow.  (1) Do not edit a helper while an instance of it
is running - a helper changed under a live process yields a corrupted run, not a clean one.  (2) Do
not treat a wrapper's own report as the record: what survives is what the kernel kept.  For row 3 the
scope was read while the build was still alive - `memory.peak=3617779712` (3450 MiB) against
`memory.high=3565158400` and `memory.max=3774873600`, `memory.events: high 4041348 max 0 oom_kill 0`
- and those numbers outlived the wrapper that broke.

**Which unit, and why.**  The missing artifact in every attempt is `_build/default/Denotation.vo`, and
the worker that survives longest is compiling it: 2858516 kB in the 2G/3G run, a 3107 MiB peak in the
3G/4G-at-`-j 1` run, 3450 MiB pinned to its cap in the 3400M/3600M run, 4433 MiB and climbing in the
4800 MiB run the watchdog stopped.  The hot spot is named rather than guessed at: `Denotation.v`'s T1
tactic `t1_norm := apply equ_wbisim_subrelation; repeat (setoid_rewrite bind_ret_l; kernel_cbn)`
(`coq/Denotation.v:100`), with `t1_fold` (line 105) and the `T1_*` lemmas that use them -
`setoid_rewrite` inside a `repeat` re-searches morphisms over a term `kernel_cbn` has already
unfolded, so each round re-normalizes a bigger term than the last.  That is a measurement about M0's
T1 proofs and an M1-side optimisation candidate: re-tactoring coinductive proofs to make a build
cheaper is not something an M0 close-out does blind, so it is recorded here as the thing to do rather
than done.  `Denotation.v` is also the file that carries the T1 theorem body this milestone is about,
which is why the cost is not simply moved elsewhere: `tests/KernelTest.v` compiles in minutes, and the
corpus corner compiles in under a minute (`nix log` for `…-corpus-coq-corner` shows the whole Coq
corner at 59 s), so the cost is in the proofs, not in the evaluator or the harness.

*Status 2026-11-23: done.*  § 12.2's retactor - bridge lemma `bind_sret_l` plus a root-peeling
`rewrite` loop in `t1_norm`/`t1_fold`, every lemma statement untouched - took the cold
`coqc Denotation.v` from 708 s and 11.2 GiB maxrss to 181 s and 1.9 GiB.

**The nix half of the gate cannot be capped from inside the repo, and that is a measured property of
this machine, not an opinion.**

- nix here is daemon-managed: `nix-daemon.service` runs as root (Determinate Nix 3.24.2, nix 2.35.3),
  `Slice=system.slice`, `MemoryHigh=infinity`, `MemoryMax=infinity`; `/nix/store` is not writable by
  the calling user.  So `systemd-run --user --scope -p MemoryMax=…` wrapped around a `nix build`
  caps only the *client* process: the sandboxed `nixbld*` worker that actually runs `coqc` lives in
  the daemon's cgroup tree, where `memory.max = max`.  Wrapping a nix build in the same scope that
  contains `dune build` would be a placebo, and a build that *looks* contained while uncapped is the
  exact failure mode § 4.2 exists to prevent.  (2026-11-19 measurement; the two `infinity` values and
  `memory.max = max` were superseded by the root-side override - re-read 2026-11-26 in § 4.3.1.  The
  conclusion holds: the cap that exists is root's, not the caller's.)
- `nix show-config` here: `max-jobs = 20`, `sandbox = true`.  `coq/dune-workspace`'s `(jobs 2)` limits
  dune inside **one** derivation; it says nothing about how many derivations nix builds at once, and
  `nix build` with several targets on a 20-core box defaults to 20.  (Re-read 2026-11-26:
  `max-jobs = 1`, `cores = 0` - capped on both sides since 2026-11-19, § 4.3.1.  The point stands and is
  why the gate passes `--max-jobs 1` itself rather than trusting a config file.)

What the uncontrolled version of that looks like on this box, from `journalctl -u earlyoom -b -1`
for 08:24:41-08:33:56 (previous boot, during a `nix build` gate chain that started at 08:23:24 and
never finished):

```
30 SIGTERM decisions in 10 minutes
28 of them the model server: "strata" / "strata-host", VmRSS 41094-47169 MiB, badness 1195-1264
 2 of them a Brave renderer process (164 MiB, 90 MiB - after the model server had already been shot)
mem avail 2.44-9.03%, swap free 0-8.91% of 3907 MiB       the machine rebooted at 08:34
```

Not one Coq process was a victim in that window, and that is the point: earlyoom ranks by its own
badness built from RSS, so a build capped at a few GiB never outscores a model server holding 43-49
GiB.  A capped build is the *marginal* allocation and the model server is what dies.  (When the Coq
worker was uncapped and huge, earlyoom did pick it: `"rocqworker"`, badness 1556, VmRSS 55022 MiB.)
So the `oom_score_adj=500` designation of § 4.2 protects the machine's other services from the
*kernel's* OOM choice and from this scope's own `MemoryMax`; it does **not** make the build the
sacrifice earlyoom picks, and the docs should not claim otherwise.

**What re-verifying the gate costs, and what it actually bought today.**  `nix build --dry-run` names
what is unrealised for a working tree, and its hashes are only valid for the tree state they were read
from: the two corners have `src = ./.` and the check re-reads `docs/PLAN.md` and
`docs/DESIGN-NOTES.md`, so every tracked edit to these notes re-derives them, while `timbda-kernel`'s
`src = ./coq` is untouched by them.  Three runs of that one command today - 09:43, ~10:53, 11:43 -
printed three different corner/check sets (`f67pim6xayay09l1zdq8akzvvdj3mibj` /
`mfc0q1vz1rq9cmvpw3w51zfc44hx665q` / `cp6m4p1zk38dphwmj2qngv85n5sc2dsp`, then `acawqy7wv8zsiknlvid4ma5fyr2p16nj`
/ `ysp5gdf27jzlgi1k8k2lnjhpnjapc8lp` / `hrbvx5pfilrydwnqcsw77imgq3qjascb`, then
`piavm8vld1fl518fr4x9g79pj6nmp3rb` / `hb953zvqs4wnlk9pry69y4hqhmg0d98v` /
`51rfp1h4w6hwb1imwady71knrjm3pz8i`) and the same kernel drv `4p62q17fq2yfczbwl73nm05m9g4bkb4q` each
time.  Quoting a corner drv hash in a doc is therefore quoting a timestamp.

That bill was paid at 11:46:33-11:59:39 through `tools/build/nix-gate.sh` (4 targets, `--max-jobs 1`),
and all four targets came back green against today's tree:

| target | rc | elapsed | what the run did |
|---|---|---|---|
| `checks.version-consistency` | 0 | 0 s | 11 pinned tool versions matched |
| `checks.corpus-differential` | 0 | 764 s | built `4p62q17…` (the kernel) locally, then both corners, then the check |
| `packages.timbda-kernel` | 0 | 0 s | already realised by the row above: `/nix/store/sn9hfhilnjiqhc8w705f0pj07zi6ism7-timbda-kernel-0.1.0` |
| `checks.golden-test` | 0 | 21 s | fetched 14 paths (415.4 MiB down, 3.3 GiB unpacked), `ghc-9.12.3` among them |

The kernel's build log says `buildPhase completed in 12 minutes 43 seconds` and ends on the axiom audit
(`axioms referenced (1): Eqdep.Eq_rect_eq.eq_rect_eq :` / `OK kernel builds, single axiom eq_rect_eq`);
the output is 1,047,784 B holding all eight `.vo` files, `Denotation.vo` and `KernelTest.vo` included,
built from source tree `6fs895yaa68lk976z4r8zxv0qp31j07a-coq`.

Two claims written an hour earlier were wrong, and are worth keeping as claims:

- `checks.golden-test` is not blocked on a missing GHC.  At 11:59 it greened in 21 s with GHC 9.12.3
  substituted.  What was measured at 09:37-10:24 was a substituter state - narinfo queries to
  `cache.nixos.org` and `install.determinate.systems` timing out at 15 s, that path 404ing - and it got
  written down as a property of the dependency.  Cache reachability is a variable on this box; a drv
  listing GHC as "to be built" with `--offline --option substitute false` says what happens *without* a
  substituter, not what this box does.
- `checks.version-consistency` has no build artifact to inspect: its output is a 112-byte file
  (`runCommand` ends in `touch $out`, `nix path-info` reports `ultimate: true`), so attesting it means
  reading a log line - `timbda version-consistency ok (11 pinned tool versions match)`.

And the cost of the green run, measured in the same window instead of inferred: 24 s after it started,
`journalctl -u earlyoom` recorded `mem avail: 6379 of 63916 MiB ( 9.98%), swap free: 110 of 3907 MiB (
2.82%)`, `low memory! at or below SIGTERM limits: mem 10.00%, swap 10.00%`, and `sending SIGTERM to
process 5473 uid 1000 "strata-host": badness 1238, VmRSS 42653 MiB`.  The model server was killed and
reloaded while the gate was going green.  The guard's preflight had passed 24 s earlier on `MemAvailable
8236 MiB` (12.9% of 63916 MiB) with swap free already at 116 MiB (2.97%): a 6 GiB floor on a 62 GiB box
is 9.6% of RAM, i.e. *below* earlyoom's own 10% trigger, so the guard admitted the run while earlyoom
was one allocation from firing - and earlyoom ranks by RSS, so the 4 GiB build was never going to be the
victim.  What the guard checks now is stated in `tools/build/README.md`; the point for these notes is
that "the gate greened" and "the host paid for it" are facts about the same run.

**What was read off realised store outputs, and how long they stayed realised.**  Between 10:44 and
10:49 the kernel, both corners and the differential check were realised from an earlier build of this
same tree, and their contents were read directly - `.vo` sets listed, `status.txt`/`report.txt` quoted,
sources compared byte-for-byte against the working tree:

- `z2bh66b7dl8izxpqlwmssshsvvrm9ry4-timbda-kernel-0.1.0` held all eight `.vo` files including
  `Timbda/Denotation.vo` and `TimbdaTests/KernelTest.vo`.  Its `.drv` source is
  `k0vbgca354871nias6vmsv2l38lr9z7j-coq`, and `Eval.v`, `Denotation.v` and `tests/KernelTest.v` in
  that source are **byte-identical to the working tree** - so the `Block`-row selection and
  `cand_bag` now in `Eval.v` have been through the nix kernel gate, and the only kernel-side change
  since that build is a comment rewrite in `coq/dune-workspace` (its `(jobs 2)` is unchanged).
- `nix log` for that output ends `--- axiom audit (Print Assumptions, coq/tests/KernelTest.v) ---
  axioms referenced (1): Eqdep.Eq_rect_eq.eq_rect_eq : / OK kernel builds, single axiom
  eq_rect_eq`, with `buildPhase completed in 12 minutes 48 seconds` - the uncapped cold cost of the
  kernel theory on this box, measured as a wall time that a throttled build cannot reproduce.
- `783h7rakq85bx8f9ldwx7lf3rzwvcpyq-timbda-corpus-coq-corner-0.1.0/status.txt`:
  `reader_rc=0  cands_rc=0  reader_cases=64  reader_cands=7  corner_lines=421  rocq_rc=0
  marker=corner_cases = 64  cands_marker=corner_cands = 7`; the `corner-generated.v` inside it is
  **byte-identical** to what `python3 tools/corpus/corpus.py --emit-coq tests/corpus/m0.texpr`
  produces today (421 lines, 135 `Example`s).
- `zr3lw60ma4jrgjqmikhdb1ik186d31yp-timbda-corpus-ocaml-corner-0.1.0/status.txt`:
  `extract_rc=0  extracted_lines=1465  mli_rc=0  ocamlc_rc=0  driver_rc=0`,
  `summary=corpus corner: 64 cases, all agree with the extracted evaluator`,
  `cands_summary=cands corner: 7 groups, all agree with cand_bag`; its `driver.ml` is byte-identical
  to `tools/corpus/driver.ml`, and its `.drv` carries the `FAIL: the corpus driver exited` gate text
  - i.e. this is the corner *after* the vacuity fix of sec. 8.2.  The pre-fix generation was realised
  at that reading too, `fgqpnm06kfz651qjpbdfi3070c56zpx6-timbda-corpus-ocaml-corner-0.1.0`, whose status
  reads `ocamlc_rc=2  driver_rc=127  summary=  cands_summary=`: the derivation that succeeded while
  running nothing.
- `4ad7nky40jibbh89d141n795n332c1df-timbda-corpus-differential/report.txt`: `Coq corner: 64 cases / 7
  cand_bag claims, generated by corpus.py` / `extracted corner: 64 cases / 7 cand_bag claims, against
  timbda_eval.ml (1465 lines, Extraction'd from the same Gallina evaluator)` / `generated corner: 421
  lines of .v`, plus four `Closed under the global context` lines for the extracted functions.

None of that is in the store any more, and the interval was six minutes.  Determinate Nix's collector
ran seven times today (`journalctl -u nix-daemon` records 1733 ` deleting ` lines: 1236 at 04:19, 7 at
06:19, 165 at 08:19, 1 at 08:49 with 3 more at 08:50, 1 at 10:49 and 320 at 10:50), 63 of them naming a
`timbda-*` path.  The ones quoted above went at the end of the last cycle - `4ad7nky…`/`zr3lw60…`/
`fgqpnm06…`/`783h7rakq…` at 10:50:10, `z2bh66b7…` and its source tree `k0vbgca3…-coq` at 10:50:11 -
and 56 minutes later the 11:46 chain built the corner and check derivations again under new hashes.  What survives
a session on this box is the `src = ./coq` kernel derivation and whatever the collector has not
collected yet, which is not a thing to build an argument on.  A store path quoted in these notes is a dated
record of a read, not a standing artifact, and the attestation that matters is the run that produced it
(§ 4.3's 11:46 table) plus the `status.txt` that run wrote into its own output.

What is *not* established by any of this: that the corpus spec is correct because a store output says
so.  The gate establishes that the two readers, the Gallina evaluator and the extracted one agree on
64 cases and 7 candidate bags, and that the kernel's `Print Assumptions` footprint is one axiom - the
same claims `docs/RULES-AUDIT.md` § 6 makes about the Coq side.  Re-running it costs 764 s and, today,
one model-server restart.

**Therefore: two guards, one per build path.**  `tools/build/coq-build.sh` contains the dev-shell
build (contained, verified, watchdog-guarded) and adds host floors to its watchdog - aborting the
build when host `MemAvailable` falls under `TIMBDA_COQ_MIN_AVAIL` (default 1 GiB) or swap headroom
under `TIMBDA_COQ_MIN_SWAPFREE` (default 700 MiB), printing `verdict: STOPPED BY THE HOST WATCHDOG:
<which floor, at what value>` and the run's low-water marks.  Tested by demanding the impossible
(`TIMBDA_COQ_MIN_AVAIL=55G`): exit 124 after 3 s, the named watchdog verdict, and no orphaned
`dune`/`rocqworker`.  `tools/build/nix-gate.sh` covers the gate chain, where containment is
impossible, and it is now written around the fact that a preflight is not a guard for the duration of a
13-minute build:

- two floors, not one: `MemAvailable >= max(TIMBDA_NIX_GATE_MIN, 12% of MemTotal)` **and**
  `swap free >= max(TIMBDA_NIX_GATE_SWAPMIN, 12% of SwapTotal)`, because earlyoom's own trigger is 10%
  mem AND 10% swap free - a floor at or under 10% admits a run that earlyoom is ready to start killing
  things for, which is exactly what happened at 11:46:33.
- a watchdog during each target (2 s polls) that kills *our own* `nix build` when a floor is crossed,
  reports which floor, and then states plainly whether the root-side build survived our kill
  (`nix-daemon.service` had `MemoryMax=infinity` when this line was written; re-read 2026-11-26 it is
  `MemoryHigh=4G MemoryMax=5G MemorySwapMax=infinity`, § 4.3.1 - and the honest answer is still "it may
  well have", because what stops a daemon worker is root's cgroup, never our `kill`).  Measured
  today: `TIMBDA_NIX_GATE_ALLOW=yes … .#checks.x86_64-linux.corpus-differential` on a host with 6706 MiB
  free and a 8192 MiB floor → the watchdog fired on its first poll, the target got
  `rc=124 … STOPPED … (target not attested)`, and no `nixbld`/`rocq`/`dune` worker was alive 20 s later.
- the same exit-code discipline as `coq-build.sh`: 0 green, 1 a nix failure, 2 refused by preflight,
  124 stopped by the host watchdog - and a target stopped by the watchdog is listed as *not attested*
  rather than as failed-or-passed.
- `--max-jobs 1` (nix's default is 20), per-target rc capture, and the earlyoom / kernel-OOM journal
  windows printed after the verdict, so "the gate is green" and "the host was healthy" stay two
  separately reported facts even when both are true.

#### 4.3.1 The cold-lane ordering ruling, and three host facts that had gone stale (re-measured 2026-11-26)

The gate's Coq-side failure mode on a cold store is not a heavy unit; it is an **ordering** artifact.
`checks.corpus-differential` does not build the kernel *and then* its corners: the two corpus corners
take `timbda-kernel` in `buildInputs` (`flake.nix`, `mkCorpusCoqCorner`), so the cheap-first chain made
the corpus target compile the entire Coq kernel inside its own poll window.  Measured on this box (63.9
GiB RAM, `strata-host`/llama-swap - this agent's own model server - resident at 54.5 GiB RSS): the cold
corpus target ran 85 s, dipped `MemAvailable` from 6918 MiB to 5021 MiB, crossed the script's own 5120
MiB floor, and was recorded `rc=124 … STOPPED BY THE HOST WATCHDOG (target not attested)` while its log
was still in `timbda-kernel>` output.  The identical target, with the kernel derivation already in the
store, returned `rc=0` and never went below 5799 MiB; and `.#packages.x86_64-linux.timbda-kernel` run on
its own (270 s wall, `buildPhase` 4 min 30 s) moved `MemAvailable` 7362 → 7393 MiB, i.e. not at all.
The chain therefore puts the Coq package lane **before** the check lanes that drag it.  With one
derivation at a time this does not reduce the peak - it decides which target's watchdog window the
kernel's allocation lands in, so a kill and its evidence belong to the lane that costs the memory.  The
reordered chain re-attested 8/8 the same day (`nix failures: 0`, `watchdog kills: 0`, 32 s on a warm
store).

Three facts this section had been asserting from 2026-11-19 that the machine no longer reports:

1. `nix-daemon.service` is **not** `MemoryMax=infinity` any more.  `systemctl show -p MemoryMax -p
   MemoryHigh -p MemorySwapMax -p Slice nix-daemon.service`: `MemoryHigh=4294967296`,
   `MemoryMax=5368709120`, `MemorySwapMax=infinity`, `Slice=system.slice`, with
   `/sys/fs/cgroup/system.slice/nix-daemon.service/memory.max` reading back `5368709120` - the root-side
   override recorded in `tools/build/README.md` § "Root-side options".  The gate's conclusion survives
   the correction but its premise changes: the sandboxed workers *are* capped, by a 4 GiB throttle and a
   5 GiB hard limit that root chose and this caller cannot see, touch, or tighten; `MemorySwapMax`
   unlimited is why an oversized build spills into swap (the 11:46:33 storm shape) instead of dying in
   its cgroup.  A user `systemd-run` scope around `nix build` remains a placebo.
2. `nix show-config` answers `max-jobs = 1` (root-side `/etc/nix/nix.custom.conf` and this account's
   `~/.config/nix/nix.conf`, both from the 2026-11-19 hygiene pass), `cores = 0`, `sandbox = true`.  The
   gate still passes `--max-jobs 1` explicitly: a guard that depends on somebody else's config file is
   not a guard.
3. earlyoom's thresholds are the program's defaults, and they are 10 %/10 %: `earlyoom -h` on the
   running v1.7 says `-m` default 10 %, `-s` default 10 %, SIGKILL at half the SIGTERM threshold, and
   "both memory and swap must be below minimum for earlyoom to act"; the unit runs
   `/usr/bin/earlyoom -r 3600` with no `-m`/`-s` (`EARLYOOM_ARGS` in `/etc/default/earlyoom`).  That is
   why the gate's `GUARD=12` default sits above the trigger, and why today's runs - swap 16.5 GiB of 20
   free - produced earlyoom *reports* (e.g. "mem avail: 6273 of 63916 MiB ( 9.82 %)") with no kill: mem
   dipped near the trigger while swap was nowhere near it.

And the reason the ordering question is cheap to answer now: the Coq lane's real cost.  A clean
full-lane `dune build` of `coq/` at `(jobs 1)`, sampled at 0.3 s, peaks at **655 MiB** (`Realize.v` 499
MiB, `tests/KernelTest.v` 655 MiB, `Lower.v` 422 MiB), and the flake's cone sweep `rocq check -silent -o
-Q _build/default Timbda Timbda.Realize Timbda.RealizeCompose` peaks at **515 MiB**.  The older records
- "peaking over 4.4 GiB" here, "~15 GiB coqc" in § 4.2 - describe the pre-`≅` work-in-progress trying to
normalize false Leibniz-`=` corner goals (§ 13.16), not the kernel's cost.

**The two remaining gate costs were store churn, not proofs, and both are now closed.**

*The collector was eating the Coq lane.*  Determinate Nix auto-GCs after builds, and nothing rooted the
gate's outputs: the kernel output that this morning's 8/8 chain built (`…-timbda-kernel-0.1.0`) answered
`error: path … is not valid` when the 15:02 chain wanted it, so the afternoon run paid the full 4 min 30 s
`buildPhase` again - and rebuilt to the *same* output path, the determinism check these notes keep
insisting on.  The fix is a GC root, and the measured part is which rooting a non-root user is actually
allowed to create: `nix build … --profile /nix/var/nix/profiles/…` fails with `creating symlink …:
Permission denied`, while `nix-store --realise --add-root <link> --indirect <out-path>` works for a
`trusted-users` account - it writes the symlink somewhere we own (`~/.local/state/timbda-gcroots/`) and
registers it under `/nix/var/nix/gcroots/auto`.  `nix-gate.sh` now does exactly that for the lanes named
in `TIMBDA_NIX_GATE_KEEP` (default: the Coq package lane and `corpus-differential`, 3.3 MiB and the two
corners; deliberately *not* `golden-test`, whose ghc would pin 3.3 GiB for no benefit).  The lane build
itself also switched to `nix build --no-link`, because a `result` symlink left in the repo is an
untracked path that a flake `src = ./.` would happily copy.

*Documentation edits were rehashing the Coq corners.*  Both corpus corners had `src = ./.` - the whole
repository - while what they read is three files and a corpus spec: `tools/corpus/corpus.py`,
`tools/corpus/driver.ml`, `tools/extract/extract.v`, and `tests/corpus/*.texpr` (the kernel's `.vo` trees
arrive through `timbda-kernel` in `buildInputs`, not from the source tree).  They now take a narrowed
`cornerSrc`.  Verified: `.#checks.corpus-differential.outPath` is unchanged by a `docs/` edit, and the
lane still prints `ok: 64 corpus cases (incl. 7 candidate bags) agree across corners`.  The trap in
implementing it is worth recording because it looks like it works when read: nix 2.35.3 hands a
`cleanSourceWith` filter **the store path it is copying** (`/nix/store/<hash>-source/tools/corpus/corpus.py`),
not a path relative to `src`; a filter written as `path == "tools/corpus/corpus.py"` kept every directory
and **no file at all**, which surfaced as `cp: cannot stat '…/source/tools/extract/extract.v'` inside the
corner.  Suffix/infix matching (`hasSuffix "/tools/corpus/corpus.py"`, `hasInfix "/tests/corpus/"`) is the
spelling that works, with `cleanSourceFilter` applied first for `.git`/`.jj`/`_build`.


## 5. Toolchain probe results (pinned nixpkgs)

At the pinned nixpkgs
(`b349185bb79c7cf7ad8ea8c097931730bf473c71`, nixos-26.05):

- `rocqPackages.rocq-core` = `9.1.1`, `rocqPackages.stdpp` = `1.13.0`,
  `rocqPackages.relation-algebra` = `1.8.0`;
  `rocqPackages` has **no** ctrees / coinduction / coq-ext-lib / coq-itree / paco, so
  `flake.nix`'s `coqStack` builds them from the locked inputs (all built clean 2026-11-18:
  `coq-ext-lib` 0.13.0-dev, `coq-paco` 4.4-dev, `rocq-coinduction` 1.21, `coq-itree`
  5.2.1-dev, `rocq-ctree` 2.0-dev).  Two pins moved to get there: coinduction master needs
  rocq ≥ 9.2 (retargeted to tag `v1.21`), and interaction-trees needs `Paco.paco`
  (`[formal.paco]` added) — see the pins.toml notes.
- Two upstream build quirks needed patching: extlib's `dune-project` says `using coq 0.8`
  (retargeted to 0.7 by `postPatch`), and paco's `src/Makefile` still invokes the retired
  `coq_makefile` binary (`rocq makefile -f`).
- Only the legacy `coqPackages` namespace provides `equations` (`1.3.1+9.1`).
- Coinduction ships a findlib plugin (`lib/ocaml/4.14.4/site-lib/rocq-coinduction/plugin.cmxs`),
  loaded by `From Coinduction Require Import all`; findlib's hook puts it on OCAMLPATH.  Outside a
  derivation (`nix shell`) no setup hooks run, so ROCQPATH/COQPATH/OCAMLPATH have to be set by hand.
- No ghc/cabal on PATH: the Haskell golden tests run through nix only
  (`tests/golden/run.sh`, `haskell.compiler.ghc912` = 9.12.3).

## 6. T1 proof machinery (M0, measured)

Batch probes under `/tmp/opencode` (`probes8/9/10.py`, `p11*.v`, `p12_axioms.v`); the
per-rule status table is `docs/RULES-AUDIT.md` § 1.  The findings that shaped
`coq/Denotation.v`:

- Applying a ctrees `~` (sbisim) lemma to an `≈` goal fails outright - sbisim and
  wbisim are different greatest fixed points ("gfp (sb eq) … vs gfp wb …").  Bridge
  with `sbisim_wbisim_subrelation` / `equ_wbisim_subrelation`.
- `bind` is a cofixpoint (`CTree.subst`): `bind (sret x) k = k x` is *not* provable by
  `cbv`/`reflexivity`.  Every computation lemma transports the goal to `≅` (equ),
  rewrites `bind_ret_l` there (`setoid_rewrite`), and closes with `reflexivity`.
- cbn on rocq 9: fixpoints like `negb`/`andb`/`rev`/`app`/`length` reduce **only when
  they are in the delta list**; `Z.eqb`/`Z.ltb` must stay OUT of it, otherwise the
  hypothesis-driven rewrites lose their match.  Two vocabularies: `t1_norm` (unfold
  `prim_total`) and `t1_fold` (keep `prim_total p [...]` folded for rows whose
  hypothesis is an equation about it).  Boolean hypotheses go through reflection
  lemmas (`zeqb_self_true`, `prim_total_PGt_true/_false`, `prim_total_PIsInt_fail`),
  never goal-side `inversion`.
- Ltac `;` semantics: a tactic chain terminated by `.` leaves only one live goal -
  the siblings are shelved - producing "Attempt to save an incomplete proof" / "No
  such goal".  Each row's full per-case discharge lives in ONE `;` chain (see
  `RewSound_EqK1/EqK2/EqTup2`).  Identifiers are resolved at Ltac *definition* time:
  `apply Hne` inside an Ltac body is "The reference Hne was not found"; match the
  hypothesis pattern instead.  `Show` is likewise unavailable inside Ltac bodies.
- `Print Assumptions` (build-time): every discharged `≈`-level lemma - and ctrees'
  own lemmas, e.g. `Probe.v`'s `ex_br2_commut` - prints exactly one axiom,
  `Eqdep.Eq_rect_eq.eq_rect_eq`, inherited from ctrees' Program-generated definitions;
  `closeV_lit`/`closeV_map_VInt` print "Closed under the global context".  Audit:
  `docs/RULES-AUDIT.md` § 6.
- The lazy-and notation is owned twice: `Stdlib/Bool/Bool.v:919-920` declares
  `a &&& b` (left assoc) at **level 40** in `lazy_bool_scope`, and
  `RelationAlgebra/common.v:28` declares `a &&& b` (right assoc) at **level 59**.
  Loading both in one compilation unit is a hard load-time error in either order; the
  ctrees side arrives through `CTree/Eq/WBisim.v:55-56`
  (`From RelationAlgebra Require Export rel srel monoid kat kat_tac rewriting
  normalisation`) → `monoid.v:6` `Require Export lattice` → `lattice.v` imports
  `common`.  Rule and probes: § 7.3.
- Comment hazard: a substring like `…/Eq/*` inside a `(* … *)` header terminates the
  comment early ("illegal begin of vernac").

## 7. Candidate sets: br2/`≈`, not stdpp `gset` (measured 2026-11-18)

`docs/PLAN.md` § 5 once said candidate sets would be "stdpp `gset`s".  Measured against
the pinned toolchain (rocq-core 9.1.1, stdpp 1.13.0, Stdlib 9.0.0, relation-algebra
1.8.0, ctrees 2.0-dev) that carrier is not available at the cost PLAN implied.  The 2026-11-18
kernel build those probes ran against was `/nix/store/llqcq9lhppbnkdm4xmxlkap02xsfwn8v-timbda-kernel-0.1.0`
(the name the daemon journal records for it, deleted since), and the 2026-11-19 rebuild of the same
sources, `z2bh66b7dl8izxpqlwmssshsvvrm9ry4`, was collected at 10:50:11 - § 4.3 has that sequence, and
today's live kernel output is `sn9hfhilnjiqhc8w705f0pj07zi6ism7`.  The probe *outputs* (a `probe-*`
package set, reports at `$out/gX-report.txt`, sources under `/tmp/opencode/stdpp-probe`) no longer
exist on this box - `/tmp/opencode` was wiped by the 08:34 reboot and the probe derivations were
collected - so tables 7.1 and 7.3 are a record of runs, not something to re-open.  What *can* be
re-checked on 2026-11-19 is the load-bearing mechanism those tables rest on, the two-level `&&&`
collision, against the store paths this tree evaluates to:

```
$ grep -n '"a &&& b"' …/94xvhnj8l70ni7f3jarhg8sqsbf5jnqj-rocq-core9.1-stdlib-9.0.0/…/Stdlib/Bool/Bool.v
919: Notation "a &&& b" := (if a then b else false)
920: (at level 40, left associativity) : lazy_bool_scope.
$ grep -n '"a &&& b"' …/ry6s3wsfiq151p1pfay8xpa81jkpw6s6-rocq-core9.1-relation-algebra-1.8.0/…/RelationAlgebra/common.v
28: Notation "a &&& b" := (if (a:bool) then (b:bool) else false) (right associativity, at level 59).
$ count greps run over the pinned ctrees source - its store name is copied out of the
  `ctrees` symlink inside …/v24v7rhqmijml7hvqckq7yvq15qgnmxc-timbda-pin-sources, which resolves to
  …/c2877sxnmbdaw3a10ww3wr06b26fsfid-source:
  files 62, .v files 41, bytes of .v 650,343
  files mentioning "stdpp": 0,   files containing "&&&": 0,
  theories/Eq/WBisim.v lines 55-56 read: From RelationAlgebra Require Export /
      rel srel monoid kat kat_tac rewriting normalisation.
```

That last grep is § 7.2's claim restated in the present tense: the kernel's ctrees dependency does not
itself use stdpp or define `&&&`; it inherits the level-59 one from `RelationAlgebra.common` through
`WBisim.v`'s import chain, and that is what collides with `Stdlib.Bool`'s level-40 lazy-and.

### 7.1 What a `gset` carrier would need

| Probe | Configuration | Measured result |
|---|---|---|
| gA1 | `From stdpp Require Import base sets gmap countable.`; carrier `gset nat` (`list_to_set [1; 2; 2]`); AC/unit laws stated up to `≡`, closed by `set_solver` | 5/5 closed |
| gA2 | same carrier, AC laws stated as Leibniz equalities (`=`) over `gset nat` - the shape a `T8`-style candidate-bag lemma wants; closed via `gset_leibniz` (`gmap.v:639`) / `set_eq` (`sets.v:571`) + `elem_of_union`, or `set_solver` | 4/4 closed.  So Leibniz *is* available for `gset` - the gate is `Countable`, not the equality |
| gB1 | `coq/Syntax.v`'s AST pasted verbatim (`ident := positive`, mutual `Val`/`Expr`, `SResult`), then `Goal Countable SResult. Proof. apply _. Qed.` | **`Error: Could not find an instance for "EqDecision SResult"`** – `gset K = mapset (gmap K)` (`gmap.v:599`) requires `Countable K`, and `Countable` carries `EqDecision` (`countable.v:12-16`).  `SResult`/`Val`/`Expr` are mutually recursive with `Z`, `positive`, `list` and binder-bearing ctors (`VLam Ty Expr`), so both `EqDecision` and `Countable` must be hand-written; there is no stock instance |
| gB2 | same AST, carrier `listset SResult` (`Listset [SOk (VInt 1); SFail; SStuck]`) - no `Countable` needed | 5/5 closed up to `≡` – but see gC2 |
| gC | `listset Outcome` (`Record Outcome := MkOutcome { outcome_of : option (option Z) }`); AC laws via the `IdemP`/`Comm`/`Assoc` `SemiSet` instances `listset.v` provides | 4/4 closed |
| gC2 | `listset Outcome` Leibniz attempt: `x ∪ y = y ∪ x` via `unfold_leibniz; apply (comm _)` | **fails**: `Error: Could not find an instance for "Comm eq union"`.  `listset` (`listset.v:6`, a `Record` over `list` with `SemiSet` instances only, `base.v:1536`/`1546`) has no `LeibnizEquiv` instance, so the Leibniz-gated `union_*_L` laws (`sets.v:590-598`) do not apply: `listset` only speaks up to `≡` (setoid), not up to `=` |
| gD | `From stdpp Require Import base sets listset.` + `Require Import Timbda.Syntax` (kernel package) | 5/5 closed - no clash: stdpp re-exports the *same* `Stdlib.Bool` notation, and `Timbda.Syntax` does not pull `CTree.Eq.WBisim` |
| gE | stdpp first, then `CTree`/`Eq`/`WBisim` + `Timbda.Syntax Rewriting Semantics Denotation` | **fails**: `Notation "_ &&& _" is already defined at level 40 … while it is now required to be at level 59` |
| gE2 | same stack, stdpp last | **fails**, mirrored error: `… already defined at level 59 … now required to be at level 40` |
| gE5 | `From Stdlib Require Import ZArith Bool List.` + `CTree`/`Eq`/`WBisim`, **no stdpp** | **fails** with the level-40 error - the collision is kernel-side and stdpp-independent |
| gE3 (control) | `CTree`/`Eq`/`WBisim` + the four kernel modules, no stdpp, no Bool import; `Print Assumptions` | compiles; `denote` closed, `Br2_Commut_W`/`Br2_Assoc_W` print exactly `Eqdep.Eq_rect_eq.eq_rect_eq` |
| gF (control) | `From Stdlib Require Import ZArith List.` + `CTree`/`Eq`/`WBisim` (no Bool) | clean |

### 7.2 Decision

**Candidate sets stay ctrees `br2` branchings read up to weak bisimilarity (`≈`)** -
`denote : Expr -> fuel -> ctree void1 B2 SResult`, `T1`/`T2`/`T8` stated at the `≈`
level (`docs/PLAN.md` § 3, § 5).  Consequences measured above:

- A `gset` carrier is *possible*: Leibniz-level AC reasoning works out of the box once the
  key type is `Countable` (gA1/gA2).  The cost is the instance work - hand-written
  `EqDecision` + `Countable` for the mutually-recursive `Val`/`Expr`/`SResult` domain (gB1) -
  and the `listset` shortcut around that domain only reaches `≡`, not `=` (gC2).
- `listset` would make candidate equality setoid-level (`≡`), which weakens `T8`'s
  statement (the trace-equality claim needs `≈` on ctrees anyway).
- The notation collision (7.3) makes any single file that wants *both* stdpp's set
  layer and ctrees' `WBisim` layer a build breaker, in either import order (gE/gE2), so a
  stdpp candidate-bag layer would have to live in its own compilation units behind a
  hand-managed import boundary.  That collision is not stdpp's fault: `Stdlib.Bool` +
  `CTree.Eq.WBisim` alone trips it (gE5), which is why `coq/Denotation.v` already avoids a
  direct Bool import.
- Therefore: `br2`/`≈` is the carrier for M0-M1.  stdpp stays pinned
  (`tools/pins/pins.toml [formal.stdpp]`, note added) for a possible M2/M3
  candidate-bag/ownership layer, and is deliberately **not** in `flake.nix`'s
  `rocqDeps` because nothing in `coq/` imports it.  Pinned ctrees sources contain no
  `&&&` and no stdpp reference (checked against
  `/nix/store/v24v7rhqmijml7hvqckq7yvq15qgnmxc-timbda-pin-sources`).

### 7.3 Notation-attribution probes (gG1-gG9, gH1-gH2)

`rocq compile` + `Locate "&&&"`, one layer per compilation unit.  (Every probe that loads
ctrees also prints the upstream `_ ° _` / `_ ~ 1` `notation-incompatible-prefix` warnings and
the `COQPATH` deprecation notice; both are noise from the pinned deps, not from Timbda.)

| Probe | Loaded | `Locate "&&&"` / error |
|---|---|---|
| gG1 | nothing | `Unknown notation` |
| gG2 | `From Stdlib Require Import Bool.` | `(from Stdlib.Bool.Bool)` – level 40, left assoc, `lazy_bool_scope` |
| gG8 | `From stdpp Require Import base sets listset.` | the **same** entry, `(from Stdlib.Bool.Bool)` – stdpp re-exports, does not define its own |
| gG7 | `From CTree Require Import CTree Eq.` | `Unknown notation` (core+Eq alone does not put level 59 in scope) |
| gG4 | `From CTree Require Import CTree Eq.` + `From CTree.Eq Require Import WBisim.` | `(from RelationAlgebra.common)` – level 59, right assoc |
| gG6 | `From RelationAlgebra Require Import common.` then `From Stdlib Require Import Bool.` | level 59 entry, then **`Error: Notation "_ &&& _" is already defined at level 59 … while it is now required to be at level 40`** - the minimal repro, no ctrees and no stdpp involved |
| gG5 | kernel chain (`CTree` + `Eq` + `WBisim`) then `From Stdlib Require Import ZArith Bool List.` | same clash, roles swapped |
| gH2 | `From Stdlib Require Import ZArith Bool List.` + `From CTree Require Import CTree Eq.` (no `WBisim`) | level 40 entry only - this is today's `Timbda.Semantics` configuration, clean |
| gG9 | `From stdpp Require Import base sets listset.` + `From CTree Require Import CTree Eq.` | compiles; level 40 entry only - stdpp coexists with ctrees core/Eq, not with `WBisim` |
| gH1 | `Timbda.Syntax Rewriting Semantics Denotation` in one unit | `Unknown notation` - notation tables of transitively-loaded modules are not replayed |

**Rule to keep the kernel buildable:** a compilation unit may directly import the ctrees
`Eq`/`WBisim` layer *or* `Stdlib.Bool`/stdpp, never both.  `coq/Denotation.v` takes the
ctrees side (no Bool import); `coq/Semantics.v`, `coq/Eval.v`, `coq/Syntax.v` take the
Bool side and never import `WBisim`; `coq/tests/KernelTest.v` omits Bool deliberately.
Bool reaches `Denotation.v` transitively through `Timbda.Syntax` (gH1 shows that does not
replay the level-40 table).

## 8. Extraction + the corpus corner (measured 2026-11-18)

The M0 tail is PLAN § 5's "extracted evaluator" plus the differential-corpus half of
PLAN § 6.  Layout and the claims it backs are in `tools/corpus/README.md`; the numbers
below are from the pinned toolchain (rocq-core 9.1.1, OCaml 4.14.4, pins `[toolchain.extraction]`).

### 8.1 Extraction on rocq 9.1 (measured)

- `Extraction` is a **plugin**: the bare keyword is a syntax error (`Error: Syntax error:
  illegal begin of vernac.`) until the theories file that carries
  `Declare ML Module "rocq-runtime.plugins.extraction"` is Required.  On 9.1 that file is
  `lib/coq/theories/extraction/Extraction.v` and its glob reads `FCorelib.extraction.Extraction`,
  so the import is `From Corelib.extraction Require Import Extraction.`.
- `Set Extraction Output Directory "."` + `Extraction "timbda_eval.ml" …` writes beside the
  compilation unit.  Without it rocq 9.1 warns and defaults to the compilation dir; in a nix
  build that *is* the build dir (nix mounts it at `/build`), which is why the first probe's
  output was found in `$PWD`.
- Extracted from `Timbda.Eval.norm`, `Timbda.Eval.head_redex`, `Timbda.Eval.selected_rows` and
  `Timbda.Eval.cand_bag` (the four things the corpus corner asserts about): one self-contained
  **1465-line** `.ml` (no external findlib dependency), `Print Assumptions Timbda.Eval.norm` prints
  **`Closed under the global context`** - four such lines, one per extracted name, all four axiom-free -
  and the extracted type shapes the driver must construct are: `nat = O | S`, `positive = XI | XO | XH`,
  `z = Z0 | Zpos | Zneg`, `'a list = Nil | Cons`, `'a option = Some | None`,
  `('a,'b) prod = Pair`, `iterComb = IAll | IIf | IFor`, `val0`/`expr` (with `Fail` as a
  nullary constructor of `expr`), `primResult = PRes | PFail | PStuck`, and `ruleID` with all
  **27** row constructors, of which `selected_rows` exposes **19** as selectable by the head table
  (`corpus.py --summary` prints which of those 19 actually fired, and names the 8 never exercised).
- `Extraction "timbda_eval.ml"` also emits `timbda_eval.mli`, so the build compiles the interface
  first (`ocamlc -c timbda_eval.mli`) and then `ocamlc -o corpus-run timbda_eval.ml driver.ml`.  That
  is not ceremony: the driver is then type-checked against the extracted signature, so a kernel change
  that changes the extracted shape breaks the build instead of silently changing what gets compared.
- `rocq compile` (no dune) resolves `Require Import Timbda.*` only if the kernel package's
  `lib/coq/9.1/user-contrib` is on `ROCQPATH`.  nixpkgs' setup hooks add the *library* packages, not
  our own kernel derivation, so both corner build phases export it explicitly.
- Harness wiring in `flake.nix`: packages `timbda-corpus-coq-corner` (corpus → generated
  `corner.v` → `rocq compile`) and `timbda-corpus-ocaml-corner` (extract → compile → run), plus
  the check `checks.corpus-differential`, which builds both corners, requires both to accept
  every case and the case counts each corner sees to be equal, and writes `$out/report.txt`.
  All of it lives in `tools/` + `tests/`, so `dune build` over `coq/` and the § 6 axiom gate
  are untouched by harness work.

### 8.2 Corners write a status file, and the check reads it (measured)

The first version of these corners "passed" while running nothing.  Two causes, both worth
remembering: (i) the corpus and driver files were untracked, and a flake whose `src = ./.` sits in a
git repo exposes only tracked files, so the corner build dirs were missing their inputs; (ii) `rocq c`
on an *empty* `corner.v` exits 0, so "the Coq corner compiled" was vacuously true.  Each corner now
writes a `status.txt` and the check reads it:

```
coq corner:      reader_rc=0  cands_rc=0  reader_cases=64  reader_cands=7  corner_lines=421
                 rocq_rc=0  marker=corner_cases = 64  cands_marker=corner_cands = 7
extracted corner: extract_rc=0  extracted_lines=1465  mli_rc=0  ocamlc_rc=0  driver_rc=0
                  corpus corner: 64 cases, all agree with the extracted evaluator
                  cands corner: 7 groups, all agree with cand_bag
```

The check fails on any non-zero status, on `reader_cases = 0`, on `reader_cands = 0`, on a generated
corner of `<= 100` lines, on an extraction of `<= 200` lines, on a case-count or candidate-bag-count
disagreement between the corners, and on either corner's summary line failing to say "all agree".  The
candidate-bag count is gated **separately** on purpose: a corner that silently dropped its `cands`
assertions would still satisfy the case count.
Rule to keep: **a differential corner must fail on vacuity, not only on mismatch** — the cheap failure
mode of a generated-test harness is generating nothing.

A *third* vacuity of exactly that kind appeared on 2026-11-19, in a place this rule had not reached:
`nix build .#packages.x86_64-linux.timbda-corpus-ocaml-corner` exited 0 while its own status file said
`ocamlc_rc=2  driver_rc=127`, because reading status files was the check's job and nothing inside the
corner looked at what it had written.  Both corner packages now assert their own `rc` values and their
minimum generated/extraction sizes, and § 4.2 records the compile error that was hiding behind it.

### 8.3 Corpus findings (64 cases; 45 fire a row, 19 assert `head none`)

- **`seq_z` was off by one (kernel fix).**  Fig. 10 line 459 (`dotdot[ki1, ki2] ⟶
  ki1 (ki1+1) … ki2`) is inclusive, and the pinned oracle agrees with it
  (`verse-semantics/reduction/Red.hs:1384`: `[Res (IntE i) | i <- [l..h]]`; its own tests,
  e.g. `for(x:=1..3){x}` → `(1,2,3)`).  `coq/Syntax.v` gated the range on `Z.ltb lo hi`, so
  `1..3` materialised as `⟨1,2⟩`: the corpus case `prim_dotdot_range` disagreed with what the
  kernel itself computed, and the guard is now `Z.leb lo hi` (whose fuel
  `|hi-lo|+1` is then exactly the inclusive length, and `lo > hi` gives `nil`, matching
  Haskell's `[l..h] = []`).  `KernelTest.v` pins the boundary cases (`dotdot_range_inclusive`,
  `dotdot_single_element`, `dotdot_descending_empty`) so it cannot drift back.
  Consequence for the proofs: none of them reduced `seq_z` concretely - `RewSound_DotDot`
  rewrites with `closeV_map_VInt` and keeps `map VInt (seq_z a b)` symbolic on both sides -
  so the definition change needed no proof edit; the kernel rebuild re-ran the § 6 gate.
- **Division rounding is pinned against the oracle, and only against the oracle.**  Fig. 10 line 452
  states `ki1 / ki2` without giving the rounding for negative operands.  The kernel uses `Z.div`
  (floors: `(-7)/2 = -4`) and the pinned Haskell oracle uses `div` (`Core/Expr.hs:623`,
  `reduction/Red.hs:1346-1347`, `j /= 0` then Haskell `div` - also floors), and the corpus case
  `prim_div_negative_floor` records that agreement; both corners confirm it independently (the Coq
  corner discharges `norm … = (Ret (VInt (-4)))`, the extracted corner computes the same `-4`), so a
  change on either side shows up as a corner failure rather than as a drift in a comment.  What is
  **not** verified is the third party in that comparison: the claim that the C++ runtime evaluates `/`
  with C++ truncation (`(-7)/2 = -3`) has no citation any more - no `Value.h` exists in this repo, in
  its bazel externals, or on this machine's `~/verse-*/` trees - so that half is recorded as an open
  lowering obligation (PLAN § 4 T3, `VERSE-RULES` § 3 record DEV-5) instead of as a measured fact.
- **`norm`'s two behaviours are separate claims.**  Head steps repeat (fuel decrements per
  step: `unify 3 (seq unit fail)` → Norm1 → `seq unit (unify 3 fail)` → `Seq`-of-a-value →
  `unify 3 fail`), while a stuck head rebuilds its children bottom-up with the same fuel and
  is **not** re-tried (`eqtup1_single_element`'s normal form is the half-rebuilt
  `seq (ret unit) (ret (tupv unit))` at any fuel).  Expectations that mixed these up were the
  two initial corner failures; both were resolved on the corpus side, not on the kernel side.
- Coverage note: 8 of the 27 `RuleID`s are never exercised (`R_Gc1`, `R_IterFail`, `R_IterChoice`,
  `R_IterIf`, `R_IterAll`, `R_IterFor`, `R_HpAlpha`, `R_LamAlpha`) - the `Iter` rows and the
  alpha-conversion rows are not selectable by `Eval.v`'s head table at all (M2/M3 items), and `Gc1`
  is deliberately not selected (§ 9).  `corpus.py --summary` prints that list rather than hiding it,
  and it also prints which of the 19 selectable rows fired and how often.

## 9. The Fig. 8 block rows and `cand_bag` (M0 close-out, measured 2026-11-19)

M0's last gap was the Fig. 8 section: `Subst`, `PromoteL`, `PromoteR` were listed in the audit
table but *unselected*, so `Eval.v` had no way to rewrite inside a `Block`, and a block with a
declared (`None`) slot just stayed stuck forever.  Selecting those rows is what makes the
divergence from Core Verse observable at all (`RULES-AUDIT` § 3 class C1), so they are now selected
at `Block` roots.  The corpus pins that with 12 cases: 8 of them select one of the three rows at the
root - `R_Subst` 5 (`subst_valued_slot`, `subst_inside_seq`, `subst_then_eqfail`,
`subst_then_eqfail_from_the_right_side`, `guard_blocked_promote_still_descends`), `R_PromoteL` 2
(`promotel_binds_declared_slot`, `promote_then_subst_two_slots`), `R_PromoteR` 1 (`promoter_var_on_right`,
which is `promote_blocked_by_an_existing_heap_ref`'s neighbour case) - and 4 assert `head none` at the
shapes where the rows must **not** fire: `subst_declared_slot_needs_a_value` (a declared slot is `x{}`,
not `x v`), `promote_blocked_by_another_slot`, `promote_blocked_by_an_existing_heap_ref`, and
`subst_no_hole_through_a_nested_block` (the walk stops at a nested `Block` instead of passing through it).

**How the walk is built** (`coq/Eval.v`, in the order the code commits to):

1. `promote_dir` tests the two directions as two *patterns*, not two arms of one match: a
   unification `x = y` whose left side is out of slot range must still be able to fire `PromoteR`
   with the value on the left (paper line 417), and arm shadowing would silently lose that.  Within
   one `Unify`, `promote_here` tries `PromoteL` then `PromoteR` - constructor order.
2. `subst_here` fires on `Ret (VVar i)` only when `i < length slots` *and* that slot already holds
   a value; a declared slot gives `None` ("`x{}` is declared, not `x v`" - the same reading as
   `RULES-AUDIT` § 3 for the stuck/fail distinction).
3. `body_walk` tries the two slot-completion rows at the body's own root first, and only then
   descends structurally through `Unify`, `Seq`, `App` (left component before right).
4. `body_walk` does **not** descend through `Tuple`, `Choice`, `Iter`, a nested `Block`, or `VLam`.
   Those are the barriers, and they are deliberate: a rewrite under a `Choice` would move an
   alternative across a branch point, which is the bind/`br2` interchange content that `RULES-AUDIT`
   § 4 tracks as its own corner and `docs/VERSE-RULES.md` § 3.4 states as a paper claim - and the
   `R_Iter*` rows that the head table does not select.  The corpus pins each barrier:
   `subst_no_hole_through_a_nested_block`, `guard_blocked_promote_still_descends`,
   `promote_blocked_by_another_slot`, `promote_blocked_by_an_existing_heap_ref`.

**`cand_bag`: what the candidate-bag claim is allowed to say.**  Fig. 8's blocks are the first
place where the kernel can produce more than one normal form, so M0 needs a candidate-bag reading
that is not invented whole-cloth.  `Eval.v`'s `cand_bag` claims exactly four things:

- a `Choice` splits recursively: `cand_bag (Choice e1 e2) = cand_bag e1 ++ cand_bag e2`;
- a `Block` whose slots are **all** valued is read *through*, keeping the slot list on every
  candidate (`map (Block slots) (cand_bag body)`) - a candidate carries the heap it was produced
  under, matching how `Semantics.v` decision 3 reads such a block in the denotation;
- a `Block` with a `None` slot is a single leaf candidate (decision 3's `SStuck`);
- everything else - including a `Choice` under a `Seq`, an `=`, or an `Iter` - is a single leaf.

The last two are the substantive reading, and it is **not** an oversight: splitting a choice across
a bind *is* the interchange law whose ctrees-side content is deferred (`RULES-AUDIT` § 4's tracked
bind/`br2` corner), so
`cand_bag` claims only what the kernel has rules for.  Consequence worth stating plainly: with this
reading `cand_bag` is *not* a "set of reachable normal forms" function - `norm` would have to fire
inside a branch point to produce a candidate that `cand_bag` refuses to produce.  It is the bag of
normal forms reachable **by the rows the head table selects**, which is what M0 can actually audit.
Both corners of the corpus assert it as written (`beta_choice_two_candidates`,
`cand_bag_choice_under_a_bind_is_one_candidate`, `cand_bag_declared_block_is_a_leaf`), 7 candidate
groups in total.

**Selected is not discharged.**  `RULES-AUDIT` § 3 C1 lists seven rows (`BetaL, BetaT, Subst, Gc1,
PromoteL, PromoteR, Float`); the head table can now reach five of them (all but `Gc1` and `Float`), and
**none of the seven has a discharged `RewSound_*`** - `RewSound_Subst`, `RewSound_PromoteL`,
`RewSound_PromoteR` join `RewSound_BetaL`/`RewSound_BetaT` as T1 obligations, i.e. firing 8 corpus
cases (`R_Subst` 5, `R_PromoteL` 2, `R_PromoteR` 1) proves the rows are *reachable*, not sound.  The
audit table says this row by row (`sel` column plus the "selected vs discharged" note), and `Gc1` is
deliberately *not* selected: heap growth (`Block {} e ⇝ Block {⟨τ, v⟩} e`) belongs to the evolving-heap
semantics, and selecting it here would invent an allocation order the paper does not fix.

**Confirmed, with the limits of the claim spelled out.**  `R_Choice` does not exist as a rewriting
row, so the candidate bag above is a *reading* of choice - built from `Semantics.v` decision 3 plus
the deferred interchange laws - and it is the one part of the M0 close-out that is a reading rather
than a transcription.  It was put to the project owner on 2026-11-19 and **confirmed as written**:
split at `Choice`; an all-valued `Block` read through with its slot list kept on every candidate; a
`Block` with a `None` slot as a single leaf; no splitting under `Seq`, `=` or `Iter`.  What that
confirmation does not do, and what therefore stays in these notes rather than only in `Eval.v`:

- `cand_bag` is **not** the set of normal forms reachable by `norm`.  `norm` never fires inside a
  branch point, so a `Choice` stays a candidate *as a choice*; its branches become candidates only
  where `norm` produced them top-down.  Reading `cand_bag` as the reachable-normal-form set would be
  a claim the corpus does not support.
- it is not a transcription of a Fig. 8 or Fig. 13 row, and the 7 `cands` groups (10 expected
  candidate elements, including the two single-leaf cases `cand_bag_declared_block_is_a_leaf` and
  `cand_bag_choice_under_a_bind_is_one_candidate`) *pin* the decision rather than justify it.  If a
  later reading of Figs. 8/13 argues for splitting under a bind, that is the bind/`br2` interchange
  (`RULES-AUDIT` § 4) becoming available - and then `cand_bag` and those cases change together, as a
  corner failure rather than as a silent drift.

**And what a `cands` assertion is not.**  It compares `Eval.v`'s candidate *list*, ordered: a claim
about the evaluator's bag, not about `≈`-level candidate sets, and not `T8`.

## 10. Dialect encoding decisions (DEV-6, DEV-16, DEV-18, DEV-20; written 2026-11-21)

DEV-1..5 are kernel-side records: deviations from, or readings of, the paper
(`VERSE-RULES` § 3, PLAN § 4 T3/§ 6).  The dialect code cites four further ids -
DEV-6, DEV-16, DEV-18, DEV-20 - that had no entry anywhere in docs: the comments in
`dialect/TimbdaCanonicalization.{h,cpp}` and `dialect/Timbda.td` point at ledger entries that did not
exist.  This section writes them down under exactly the ids the code cites, so the cross-references
resolve as written.  Unlike DEV-1..5 these are *dialect encoding decisions* - choices about how the
kernel's machinery is spelled in MLIR - and each record says what its decision does **not** yet
carry: their machine-checkable form is M2 work, not M1 evidence.

**DEV-6 - SSA substitution is an encoding invariant.**  The kernel's substitution machinery (the
`liftV`/`liftE` de Bruijn arithmetic) has no dialect counterpart.  Capture is carried by the SSA
structure instead: valued block slots are operands captured directly by the body region, declared-only
slots are block arguments, and the Fig. 8 promotion rows are what rewrite arguments into operands
(`dialect/Timbda.td`, `Block` op summary - that row pair *is* the substitution).  A `Glob` channel is
read through op operands too: the kernel's `Glob` is an `Expr`, and its dialect form is the op's value
channel (`isValOperand`'s glob case).  Cloning maps captured references through unchanged through a
single `IRMapping` per pass - the kernel `liftV` pass-through, with the `IRMapping` playing the role
the kernel's indices play.  Limits of the claim: the dialect verifier checks the *shape* of regions
(one block, one yield, binder arity); the invariant "no rewrite can produce an uncaptured reference"
is currently exercised on the kernel side only (the corpus pins substitution behaviour for `Eval.v`'s
head table), and on the dialect side nothing exercises it at all: no bazel target builds the
canonicalizer - `//dialect:timbda_dialect_test` links only the ops/verifier library, and
`bazel build //dialect:TimbdaCanonicalization` is the canonicalizer TU's only compile check today.
A canonicalization test target and a checkable form of the invariant (verifier obligation or proof)
are deferred to M2.

**DEV-16 - the region value convention.**  A region op's value is its single block's `timbda.yield`
operand.  A `timbda.bind` region is one block with one argument - the arm binder - that the arm never
references: Fig. 12's rows only match when the kernel arm binder is unused, so the dialect binder
exists structurally and is never read.  The init operand carries the bound expression's value channel;
the arm's final statement carries the arm's value channel; the kernel's `;` sequencing is the arm's
statement sequence.  Arm-tail extension (`extendArmTail`, `spliceStatementsIntoTerminated`,
`spliceBlockIntoArm`) preserves all of this, and the `Block` op's declared-only slots - which *are*
referenceable block arguments, the point DEV-6's promote direction turns into operands - are the one
place a region argument is allowed to appear live.

**DEV-18 - region edits are record-only and root-anchored.**  Stock DRR cannot emit ops with regions
(probe F, `dialect/TimbdaPatterns.td` header), so every region-shaped RHS - Seq arms, `Block` binders,
`Unify` chains, the beta choice trees - is rebuilt in the C++ helpers instead of generated, through
rewriter-recorded APIs only (`matchRewrite`'s `match` phase never edits IR), and always anchored
immediately before the matched root op.  Consequence the audit depends on: the 23 generated rewriter
structs decide *which* row fires; the helper half decides *how* its region RHS is built; the
generated-body/helper bijection (`tools/rules-audit.py`) is what keeps the two halves naming the same
rows.

**DEV-20 - the 128-bit Z mirror, and why it is neither `arith` nor a bignum library.**  The kernel
computes over Coq's Z: unbounded addition/multiplication, floor `Z.div`, `Z.modulo` signed like the
divisor (the floor half is measured, not asserted - § 8's `norm` corners pin `(-7) / 2` at `-4` in
both engines).  The dialect mirrors that by evaluating closed literal prim operands on `APInt` at the
mirror width (`kZBits`; `divZ` corrects `sdiv`'s truncating quotient to `Z.div`'s floor; `seq_z`
reproduces the inclusive `DotDot` range), and materialising results with the grow-don't-truncate
ladder: keep the row's own literal width, else 64-bit, else the mirror.  `arith` is not used, and
`grep -rn "arith::" dialect/` is empty today; the reasons are recorded here rather than left to code
comments:

- Fig. 9-10 rows are *prim rows over Z-valued values*, decided from attribute facts at match time
  (literalness, widths, `Z.ltb` residue).  `arith` ops are fixed-width SSA arithmetic with their own
  overflow semantics, and a rewrite would have to emit them as SSA arithmetic *before* knowing the
  row's answer - the guards would then re-derive from values what they currently read from attributes.
- Fixed width *with truncation* is exactly the choice DEV-5 left open as a lowering obligation (the C
  `/`-truncates claim, unverified here by design).  Choosing it inside canonicalization would bake the
  unverified half into the middle of the pipeline, where a flip on the obligation becomes silent; the
  mirror instead widens (seed width -> 64-bit -> mirror) and leaves the commitment where M2's T5
  certified-lowering leg can be asked to prove it.
- `PStuck` rows (open operands) have no `arith` counterpart: on `arith` an open operand is still
  foldable IR arithmetic, while the kernel rows stay stuck.
- APInt is already arbitrary precision for attributes and pinned with the toolchain; a third-party
  GMP would extend the pin for no correctness gain.

What the mirror is **not**, said plainly: a 128-bit guarantee.  Plain APInt `+ - *` wrap at `2^128`,
`zOf`'s zext asserts on inputs wider than the mirror, and nothing in the verifier today bounds a
literal's width against the mirror - so a wider-than-mirror literal in external IR reaches that
assertion, not an error.  Fuel bounds kernel steps, not magnitudes (§ 5), and `DotDot` materialises
its inclusive span eagerly as a VTup, so materialisation - not folding - is where a magnitude bound
has to bite.  Recording it as an obligation: M2 owes a literal-width/materialisation bound (fuel or
size) before the canonicalizer consumes IR the corpus did not generate.  Mechanism accepted
2026-11-21, pending Verse-team revision (PLAN § 8 decision 8c): verifier-side - external
literals wider than the mirror are rejected at verification, plus a span bound on eager
`DotDot` materialisation; not fuel.

## 11. The m2 corpus gate executed (measured 2026-11-22)

`tests/corpus/m2-det.texpr` - 29 claims written by hand on 2026-11-21 per decision 6's ritual - has
now been run through both corners.  What the run taught is bigger than the pass: 27 of the 29
claims executed exactly as derived, and the two that did not were wrong on the *claim* side, in a
way the two engines agreed about.

### 11.1 Getting the bill past the host floor

The bill ran 2026-11-22 06:20 as four gate targets: the two m2 corners, `checks.corpus-m2-differential`
and the m0 `checks.corpus-differential` (the last to re-attest the unchanged m0 pair against the
parameterised flake).  Two earlier attempts the same morning never built anything: at the stock
floors (`TIMBDA_NIX_GATE_MIN=8G`, `TIMBDA_NIX_GATE_GUARD=12`, so a mem floor of 8192 MiB - the knob,
since 12% of MemTotal 63916 MiB is 7670 MiB) the box had **10.0-10.9% MemAvailable** - 6362-6940
MiB, `strata-host` measured 42.1-49.5 GiB resident across those attempts - so the script printed
`refusing to build` and exited 2 with every target `not attested` (exit-code discipline, § 4.3).
`journalctl` windows for those attempts contain no OOM kill: earlyoom's trigger is *both* mem and
swap free under 10%, and swap free was 15.2-15.3 GiB of 20.3 GiB (73-75%), so it never had a chance
to fire; the honest failure here is "no work started", not "the host was unhealthy".

The bill was paid with `TIMBDA_NIX_GATE_MIN=5G TIMBDA_NIX_GATE_GUARD=8`, which preflight renders as
`mem floor: MemAvailable >= 5120 MiB (8.0% of total) [knob 5G, guard 8%]` - the knob, since 8% of
63916 MiB is 5113 MiB - and `swap floor: swap free >= 1623 MiB [knob 700M, guard 8%]`.  That mem
floor is *below* earlyoom's 10%-of-mem trigger (5120 MiB = 8.0% of this box), which is exactly the
case § 4.3's "a floor at or under 10% is not a guard" warns about; the reason it was acceptable here
is the second half of that note - earlyoom needs *both* thresholds, and swap free stayed at
15.1-15.3 GiB (73-75% free, 13 GiB above its trigger) in every bill of the day - plus the 2 s
during-run watchdog, which is what would have stopped a build that started under the floor.  Nothing
crossed it: the same journal windows record no OOM kill, and the low-water `MemAvailable` readings
for the four targets were 6820-7375 MiB (10.7-11.5%).

### 11.2 What the executed pair says, in each corner's own words

From the outputs' own `status.txt` (all five still in the store when these lines were read):

- `xv9qr24869s3pblfq2jypm4nldqvb7fk-timbda-corpus-coq-corner-m2-0.1.0`: `reader_rc=0 cands_rc=0
  reader_cases=29 reader_cands=7 corner_lines=211 rocq_rc=0 marker=corner_cases = 29
  cands_marker=corner_cands = 7`, plus `corner-generated.v` = 211 lines / 46 `Example`s, all proved.
- `m9gcaybb7jfqhldfgchhnsm4vxhh3m2x-timbda-corpus-ocaml-corner-m2-0.1.0`: `extract_rc=0
  extracted_lines=1465 mli_rc=0 ocamlc_rc=0 driver_rc=0`,
  `summary=corpus corner: 29 cases, all agree with the extracted evaluator`,
  `cands_summary=cands corner: 7 groups, all agree with cand_bag`; its `corpus-run.log` has 29 `ok`
  lines and 0 `FAIL` lines.
- `3b4wzs2agyizpr5igi9sv3j4haisxxfj-timbda-corpus-m2-differential`: `corpus:
  tests/corpus/m2-det.texpr (29 cases, 7 with a candidate bag)`, `generated corner: 211 lines of
  .v`, `extracted corner: 29 cases / 7 cand_bag claims against timbda_eval.ml (1465 lines)`, four
  `Closed under the global context` lines for the extracted names, and the driver line
  `ok: 29 corpus cases (incl. 7 candidate bags) agree across corners (Gallina native vs extracted
  OCaml)`.
- `dc4r0y70q2j51106277ybcns2hqq7ixb-timbda-corpus-differential` re-ran the m0 pair green: `64
  cases / 7 with a candidate bag`, `generated corner: 421 lines`, `timbda_eval.ml (1465 lines)` -
  identical counts to § 8.2-8.3's record, which is the point of re-running it after the wiring change.
  Worth recording: the m0 corner derivations got *new hashes* even though m0's spec file is
  untouched, because both corners copy the whole flake source (`$src/tools/corpus/corpus.py`,
  `$src/tests/...`) - editing `m2-det.texpr` moves the m0 corners' `$src` too.  A T4/T5-era cache
  expectation that "m0 corners are content-addressed by m0.texpr alone" is simply false on this
  flake.

### 11.3 The two claims the engines rejected, and what re-deriving from rule text found

On the first run the two engines agreed with each other and disagreed with the file: the Coq corner
could not prove the generated `Example` asserting the draft's normal form, and the OCaml driver
printed `FAIL` for the same two cases and their candidate-bag claims - Group D's
`oo_indep_blocks_fwd`/`oo_indep_blocks_rev`, where draft 1 claimed the first block of the fwd pin -
`(block ((tint 5)) (app (ret (primv padd)) (tup (ret (var 0)) (ret 1))))`, a closed single-slot
block whose body is an application whose *argument tuple* mentions the block's own slot - collapses
to `(ret 6)` under `R_Subst`.  Both engines returned the partial shape instead: block 1 stays exactly
as written (no row fires at a block head whose body is an application, and `R_Subst` cannot reach a
term position inside an argument tuple), and block 2 - `(block ((tint 7) (tint 9)) (ret (var 0)))`,
whose body *is* the `R_Subst` pattern with the hole context empty - resolves to `(ret 9)`.  So the
normal form both corners agreed on is `seq <block 1 unchanged> <block 2 → (ret 9)>`, with a
one-candidate bag holding that whole node (the `cand_bag` law m0 already pins), and the differential
reported "2 of 29 do not agree" - naming the claim side.

Decision 6's ritual then applied in the direction the *first* run could not test: the engines do not
adjudicate which claim is correct, the rule text does.  Re-derivation, recorded verbatim in the two
`why` fields (`tests/corpus/m2-det.texpr` ll. 155, 163) and summarised in the commit message: at a
block head only the selected Fig. 8 rows apply (`Eval.v`'s `body_walk`); `R_Subst`'s rule form
(`coq/Rewriting.v` ll. 398-403) matches bodies of shape `fillS k (Ret (Var i))` with `k` in the
recorded S grammar (`coq/Syntax.v` ll. 116-131: `S ::= hole | e=S | S=e | e[S] | S[e] | e;S | S;e`),
and *a position inside an application's argument tuple is not in that grammar* - the
value-context/block-inside variants are `Subst-Deep`, the Tier-2 row this kernel deliberately does
not select and which `coq/Rewriting.v` ll. 480-483 records as deferred to M3.  Two m0 pins already
say the same thing from the other side (`subst_then_eqfail`: `R_Subst` reaches unify-argument `S`
positions; `betal_body_is_slot_variable`: host-position blocks never collapse in m0's pinned
shapes).  So the kernel's non-collapse was right, the draft's collapse was a derivation error, and
the amendment moved the claims - not the engine - to the rule-text reading.  No kernel file changed
in that commit (`git show --stat` for `802e9ad` touches only `tests/corpus/m2-det.texpr`), which is
why § 11.2's kernel-side numbers (1465 extracted lines, the four closed axiom footprints) are
comparable across the amendment.

Generalisation worth keeping for T4-T7-era claims: a cross-corner differential is a disagreement
detector, not an oracle.  When both corners agree and the file does not, the file is the suspect,
and the fix is a fresh derivation from `docs/VERSE-RULES.md` / kernel rule text plus the existing
pinned precedents - never "what the driver printed" (that is the direction decision 6 exists to
forbid).  Recording the rejected claim in the file's header note (`m2-det.texpr` ll. 16-23) rather
than erasing it is part of the same discipline: the amended pins say `det=yes (amended 2026-11-22)`
and keep the draft's error visible.

Two consequences for M2's machinery, both now corpus facts rather than rulings:

- Decision 8a's closed-blocks restriction is unchanged, but its *witness* is now precise: T4's
  fair-sem side still resolves that block to the value 6 (paper-side slot lookup in evaluation -
  the kernel has no `Get` row, tools/corpus/README.md § 5), while the *evaluator* produces a partial
  shape.  So T4's `sem e ≈ eval e` leg has to be stated for a `sem` that does the resolving, and the
  corpus pins the evaluator's half separately.
- T5's corpus witnesses for order-agnostic straight-line lowering are now the amended *mirrored
  pair* (each permutation reaches its own partial normal form, identical candidate count), together
  with the three unchanged Group D permutation pins (`oo_left_assoc`, `oo_assoc_right`,
  `oo_swap_prefix`).  What they do *not* provide is a collapse claim the M0 row set cannot make.
- Group G's four `promote-freshness` probes - the measurement side of the flex-scope question
  queued in PLAN § 10 - came back as claimed, `head -> no row` in both corners, which pins the
  kernel's stricter `promote_ok` as behaviour with cases attached.

Store paths here are dated readings, per § 4.3's rule: the corner and check outputs listed above
were present when read, and the durable record is the amendment commit and this entry.

### 11.4 Today's box is not the box § 10 measured

Re-measuring for the re-bill (2026-11-22 07:08, `tools/build/nix-gate.sh` preflight and
`systemctl show nix-daemon`):

- The nix daemon cgroup is **`MemoryHigh=4.0G` / `MemoryMax=5.0G`**
  (`/etc/systemd/system/nix-daemon.service.d/override.conf` lines 2-3; re-read 2026-11-22
  as `MemoryAccounting=yes`, `MemoryHigh=4294967296`, `MemoryMax=5368709120`,
  `StartupMemoryMax=infinity`, `MemorySwapMax=infinity`, `Delegate=no`).  § 10 recorded
  5.4G/7.4G on 2026-11-19, so that envelope is a dated reading, not the live setting.  Two
  consequences worth having straight: `Delegate=no` means the envelope applies to the daemon's
  own subtree (a build it spawns lands in that cgroup, so 5G is its hard ceiling today), and at
  5G a kernel-scale derivation - § 4.3 measured 20.2 GiB peak, 53.9 GiB max-rss on one `coqc` -
  does not fit there at all.  That is why § 4.3's division of labour (coq-build.sh runs
  kernel-scale work inside its own envelope-checked cgroup, 4096M high / 5120M max; the gate
  runs the small corner and check derivations) is load-bearing rather than tidy.  What I have
  *not* done today is re-run a kernel build through the daemon at this envelope, so the claim
  above is a capacity inference from recorded peaks, not a fresh measurement.
- Swap is 20.3 GiB total; during the re-bill `swap free 15156 of 20291 MiB (74.71%)`, MemTotal
  63916 MiB (62.4 GiB).  § 4.3's 2026-11-19 records measured 3,907 MiB of swap on an earlier
  incarnation of this box, so the swap headroom described here (15 GiB free of 20) is a property of
  today's configuration, not of those older runs.  `earlyoom` v1.7 is `enabled`, running as
  `/usr/bin/earlyoom -r 3600` from `EnvironmentFile=-/etc/default/earlyoom` (which sets nothing but
  `EARLYOOM_ARGS="-r 3600"`), `MemoryMax=50M`, `DynamicUser=yes`, `Restart=always`.  So its
  trigger is the upstream default - mem avail <= 10% AND swap free <= 10% - and there is no
  `--avoid`/`--prefer` configuration on this box, exactly as § 4.2 records as "deliberately not
  applied".  The re-bill's journal window shows no OOM kill.
- Target readings for the re-bill, as the gate printed them: at the m0 target, `start: MemAvailable
  7027 of 63916 MiB (10.99%)  swap free 15156 of 20291 MiB (74.71%)`, low-water 7015 MiB; held
  floors 5120 MiB mem / 1623 MiB swap at `TIMBDA_NIX_GATE_MIN=5G TIMBDA_NIX_GATE_GUARD=8`.  Both
  targets rc=0 in single-digit seconds (the m0 line reads `elapsed 3s`), re-attesting 29 cases / 7
  candidate bags for m2 and 64 / 7 for m0 - the same counts § 11.2 records.
- A cache fact the re-bill makes visible rather than inferable: the check outputs have *new* store
  paths (`rc4g2jacvi0bvixwm0lqa0gp108md6b5-timbda-corpus-m2-differential`,
  `95ch4c3y81q67pbc92g04i4zyswrsjh2-timbda-corpus-differential`) purely because this file changed -
  both corner derivations consume the whole flake source.  Treat "the check rebuilt" as "the source
  hash moved", never as "the kernel moved", and cross-check the kernel-side numbers (1465 extracted
  lines, the four `Closed under the global context` footprints) before drawing a semantic
  conclusion from a rebuild.

## 12. T4's two soundness legs, proved (M2, 2026-11-23)

`coq/Checks.v` now carries both legs whose shapes § 11's corpus pinned, over the checker
`det_check e = ws_expr 0 e && det_struct e` (`coq/Checks.v` l. 395; the six guards G1-G6 are
documented at the head of the file):

```
Theorem T4_sem   : forall e k, det_check e = true -> exists v, denote e (e_fuel e + k) ≈ sret (SOk v)
Theorem T4_eval  : forall e fuel, det_check e = true -> cand_bag (norm fuel e) = norm fuel e :: nil
```

`T4_sem` (l. 1404) is the PLAN § 3 claim, witnessed through `denE_total` and transported from ctrees
structural equality to `≈` by `equ_wbisim_subrelation` - the same idiom every T1 row in Denotation.v
uses, and the reason the pure layer's witness is `sret (SOk v)`: the Get/Put signature is the M4 host
layer (Semantics.v header decision), so there is no state leg to name.

`T4_eval` (l. 2644) says only what the evaluator demonstrably delivers, and § 11.3 is why it cannot
say more: for the amended Group D pins the evaluator's normal form of a *closed* block with an
app-body is a partial shape, so "reaches a value" is a sem-leg claim and never an eval-leg claim.  The
leg is assembled from three lemmas, each one the honest version of a step:

  * `head_redex_det` (l. 2406): if `head_redex e = Some (r, c)` and `det_struct e`, then
    `det_struct c`.  This is where the guards do their work as *pinning*, not as filtering: G5's
    `app_node_ok` (l. 341) forces the head to `Ret (VPrim p)`, which shadows the `R_BetaL`/`R_BetaT`
    arms - the only rows in `Eval.v`'s selected table that can mint a `Choice` - so the "no choice is
    ever minted" invariant is a G5 fact about shapes, not a bookkeeping claim; G4's `eq_pair_ok`
    (l. 272, two literal values plus `lit_eqb`) leaves `EqK1` as the only live `Unify` row and its
    contractum is a literal; G3's `slots_closed_ok` kills the promote rows inside `body_walk`
    (`promote_guard_dead`), leaving `R_Subst`, whose conclusion is that the slots list is *unchanged*
    (`body_walk_det`, l. 2171) and the body stays `det_struct`.
  * `norm_det` (l. 2561): induction on fuel; at a stuck root the reconstruction re-reads G4/G5/G6 on
    children that `det_struct` already pinned to stuck syntax, so the node is reassembled from the
    hypothesis rather than re-derived.
  * `cand_bag_single` (l. 2616): structural induction on `e`; a G3-closed block reads through its
    valued slots (`slots_closed_all_valued`, l. 2309) and the IH collapses the mapped singleton.

Measured facts about the toolchain, recorded because each one cost probes and the next Gallina leg
will meet them again (rocq 9.1.1, this file's own build):

  * `cbn` refuses to unfold `block_redex`: its unfolding is stuck on the `body_walk` call, so cbn
    treats the delta step as unproductive and stops at `block_redex sl body`.  `unfold block_redex in Hh`
    is what exposes the walk call as the scrutinee that `destruct ... eqn:Hw` can then rewrite
    (`Eval.v` l. 222-227).  Whitelisted `cbn [f]` behaves the same way for a *productive* constant,
    which is what keeps `prim_total p vs` visible where the rewrite has to land.
  * `destruct (t) as [...] eqn:H` eliminates `t`'s occurrences **in place** wherever `t` is a match
    scrutinee: `Hh : head_redex ... = Some (r, cont)` comes back as `Some (R_Prim, Ret w) = Some (r, cont)`
    already agreeing with `Hp`, so a later `rewrite Hp in Hh` is not merely useless, it errors with
    `Found no subterm matching`.  Read such hypotheses directly; the `first [rewrite H | idtac]` hedge in
    `norm_det` exists for the cases where Coq generalises instead.
  * `Ltac` bodies resolve bare identifiers against the *parameter list at definition time*
    (`Ltac tr := subst zz.` fails "Hypothesis zz was not found"), so every hypothesis a tactic touches
    must be passed as a parameter.
  * `induction e` interleaves constructor arguments with their induction hypotheses in `as [...]`
    patterns - a pattern that names only the arguments silently binds an argument name to an IH.  The
    `cand_bag_single` proof reads its two live roots out of the goal with `match goal` instead, which
    keeps it independent of `Expr`'s argument names.

`coq/tests/ChecksTest.v` (324 lines, 45 `Example`s) is the Gallina-side mirror of § 11's corpus: the
same 29 expressions, each with its `det_check` verdict as decision 8 derives it - **17 accept, 12
reject, exactly the corpus's own tally**, with no pin adjusted to engine output: the file was written
from the corpus's `det=` readings, and the only objection the first build raised was a misspelled
`Definition` name of mine, never a verdict.  It also mirrors the nine
`norm` pins the accepted cases carry and all seven candidate bags: the five accepted bags are
discharged *through* `T4_eval` (the theorem, not a computation of `cand_bag`), and the two rejected
ones (`Choice`, the open block under a `;`) are plain `cand_bag` evaluations, which is what the corpus
means by "the evaluator's bag" there.

Build-time evidence, as § 8.2 requires it to be: `Print Assumptions T4_eval` prints
`Closed under the global context` - the eval leg is pure Gallina, no ctrees dependency - while
`Print Assumptions T4_sem` prints the single stdlib axiom `Eqdep.Eq_rect_eq.eq_rect_eq`, the same one
the vendored ctrees machinery contributes to every audited T1 row.  `tools/build/coq-build.sh`
`EXPECTED_VO` now names `Checks` and `tests/ChecksTest` and the flake's kernel gate checks both `.vo`
files alongside `tests/KernelTest.vo`; the axiom audit itself (exactly one unique axiom line, no
`Admitted`) is unchanged, as are the m0 corpus corners.

What M2 still owes is unchanged by this: T5 (the Wbisim between permuted fragments, whose witnesses
§ 11.3 amended to the mirrored partial-shape pair), `Lower.v`'s T6/T7 for determinate fragments, and
the golden test with zero switch sites.

### 12.1 Why the eval leg lives in its own module (`coq/ChecksEval.v`, measured 2026-11-23)

With `T4_eval`'s chunk inside `Checks.v`, the checker became the kernel's heaviest compilation unit
(2653 lines) and the kernel build stopped fitting in any envelope this box can host.  What was
measured, in the order it happened:

- the gate bill (`TIMBDA_NIX_GATE_MIN=5G TIMBDA_NIX_GATE_GUARD=8`, `--max-jobs 1`, pinned `coq/
  dune-workspace` `jobs 2`): the `timbda-kernel` derivation ran 1636 s and took the host from
  `MemAvailable 9959 MiB` to `4955 MiB`, with swap free falling 17875 → 11882 MiB, before the gate's
  watchdog killed our own nix client.  All three Coq-side targets (`timbda-kernel`,
  `corpus-differential`, `corpus-m2-differential`) ended `rc=124 ... target not attested`;
  `version-consistency` and `golden-test` stayed green; `journalctl -u earlyoom` for the window is
  empty, so the refusal worked as designed and nothing on the host was harmed.
- the contained path refused as well: `tools/build/coq-build.sh` at its pinned 2G/3G envelope ended
  `Active: failed (Result: oom-kill)` on its own transient user scope - `Duration: 2h 43min`,
  `CPU: 1min 4.7s`, i.e. the build spent its wall clock throttled against `MemoryHigh` - and left
  `coq/_build/default` holding 8 of the expected `.vo` files.  That is the wrapper doing its job (a
  worker OOM-killed inside its own cgroup, no Coq error, `got signal` evidence rather than a
  verdict), and it says the *envelope* was too small for the unit, not that the proof is expensive
  to check.
- freeing host memory was tried and is not available: stopping Red Panda (4.0 GiB resident, 2.9 GiB
  of swap) moved MemAvailable 8.5 → 10.2 GiB, which is not enough for a ~5 GiB working set above a
  5120 MiB floor; the 42 GiB resident neighbour (strata-host) stays.

The split is therefore a build-infra decision, not a theory decision: `coq/ChecksEval.v`
(`Require Import Timbda.Checks`) carries `head_redex_det`, `norm_det`, `cand_bag_single` and
`T4_eval`; `coq/Checks.v` keeps the guards, the checker and `T4_sem`.  Nothing about the claims
moves - same statements, same proofs, same `Print Assumptions` results - and one consequence is
visible in the imports: `ChecksEval.v` needs no `CTree`/`WBisim` import at all, which is exactly the
fact `Print Assumptions T4_eval` reports as `Closed under the global context`.  The gate and the
artifact list name all three files (`flake.nix` kernel gate, `tools/build/coq-build.sh EXPECTED_VO`).

### 12.2 Retactoring `Denotation.v`'s `t1_norm`/`t1_fold`: § 4.3's TODO, closed (measured 2026-11-23)

§ 12.1 made the M2 units cheap; the kernel build still did not fit, because § 4.3's recorded - and
deliberately not-yet-done - hot spot is `Denotation.v`, an M0 file: `nix build` of the kernel was
re-invalidated by M2's kernel edits, so re-billing the corpus pairs required a cold `coqc Denotation.v`
at 11.2 GiB private memory.  With the resident 42 GiB neighbour (strata-host) and Red Panda already
stopped, that number fits nowhere on this box: the gate watchdog refused the nix bill, a 4.6 GiB
envelope OOM-killed a worker inside its own cgroup, and the contained wrapper stalled at `memory.high`
(`Result: oom-kill`, `Duration: 2h 43min`, `CPU: 1min 4.7s`).  So the TODO got done.

**Localization by cumulative prefix compiles.**  Rocq 9.1.1 has no `Set Timing`, no `Set Time` and no
`Set Ltac Profiling` - each prints `Warning: There is no flag or option with this name` - so per-lemma
cost was measured by compiling the file truncated at lemma boundaries (single `coqc`, `/usr/bin/time -v`):

| prefix ends at | wall | maxrss |
|---|---|---|
| l.196 (all Fig. 9 unify rows) | 1.03 s | 458 MiB |
| l.205 (`RewSound_EqFail`) | 2.35 s | 458 MiB |
| l.212 (`RewSound_Add`) | 97 s | 7.5 GiB |
| l.251 (`RewSound_Cons` + rest of Fig. 10) | 6:41 | 10.4 GiB |
| whole file | 11:48 | 11.2 GiB |

One lemma - `RewSound_Add`, a two-line `Proof. intros. t1_norm; reflexivity. Qed.` at fuel 5 - carries
7.5 GiB of that.  The raw dumps (`Set Printing All.`, obtained from real tactic failures - a `Fail
reflexivity` swallows its own error text) show why: after `kernel_cbn` the `App`/`TupE` rows are nested
`@CTree.bind (@sret …) (fun r => …)` chains under lambdas, and `setoid_rewrite` inside `repeat` runs a
full position search through the `Chain`/`Proper` instances ctrees registers globally, once per layer.

**The alias that hid it.**  The kernel's pure head is its own constant, `Semantics.v:50`
`Definition sret x := go (RetF x)`; the library law is headed by ctrees' notation
(`CTreeDefinitions.v:102`) `Ret x := (go (RetF x))` - same body, different name.  `setoid_rewrite`
matches up to conversion, so it paid the search cost without ever exposing this; plain `rewrite`
matches syntactically and reported `Found no subterm matching @CTree.bind … @go … @RetF …`.  A
`t1_norm` without the setoid search therefore did not even type-check until the law was restated at
the kernel head.

**The retactor** (statements untouched; only the two Ltacs and one new bridge lemma):

```coq
Lemma bind_sret_l {X Y : Type} (x : X) (k : X -> ctree void1 B2 Y) :
  sret x >>= k ≅ k x.
Proof. unfold sret. apply bind_ret_l. Qed.

Ltac t1_norm := apply equ_wbisim_subrelation; kernel_cbn;
  repeat (first [ rewrite bind_sret_l | progress kernel_cbn ]).
```

Normalize, then peel the exposed head binds with plain `rewrite` - the same idiom ctrees' own proofs
use (`Misc/Head.v`, `Interp/FoldCTree.v`: `rewrite bind_ret_l; reflexivity`).  Two toolchain facts
learned writing it: the bridge must stand *before* the tactics (Ltac resolves bare identifiers at
definition time; the first cut failed "The reference bind_sret_l was not found"), and it must be
stated with the `>>=` notation, not the constant `bind`, which is not in scope unqualified.

**Measured result.**  Cold `coqc Denotation.v` alone: 708 s and 11,202,248 kB maxrss before; **181 s
and 1,937,748 kB** after - 6x less memory, 4x faster, and the three `Print Assumptions` audits it ends
with print the same single `Eqdep.Eq_rect_eq.eq_rect_eq` fingerprint as before, so the kernel gate's
axiom audit is unaffected.  The § 4.3 table's cap-attempts (2G/3G … 4800M) all died on this unit.

**Whole-tree result (same day).**  A cold `tools/build/coq-build.sh` (pinned `jobs 2`, envelope back at
its documented `HIGH=2G MAX=3G`, the setting every § 4.3 attempt died against) finished with scope-cgroup
peak **1936 MiB**, `memory.events` counters `high 0 max 0 oom_kill 0` - the build never touched the soft
cap - `ok: all 11 expected .vo artifacts present, dune exit 0`, zero `Error:`/`Admitted` lines, and host
MemAvailable low-water 10.9 GiB.  The retactor did not move the cost elsewhere: it removed it.

## 13. Fuel is on the term side; coinduction is on the relation side (written 2026-11-24)

M2's theorems quantify over fuel - `T4_sem` reads `denote e (e_fuel e + k) ≈ sret (SOk v)` - and that
invites a wrong worry: that kernel claims are verified "only up to some size" and that fixing that
means rebuilding the semantics coinductively.  Both halves of the worry are false, and § 13.1 is why.
§ 13.2 is the corollary that pins what fuel actually buys; § 13.3 records where coinduction was
expected to enter, and § 13.4 - the measured T5 draft - records where it actually does, which is not
where § 13.3 predicted.

### 13.1 Fuel is a syntactic budget, and accepted fragments terminate by construction

- `e_fuel` (`Checks.v:594`) computes a node budget from the `Expr` itself - it is a structural bound,
  not a numeric constant or an empirical cap - and `denE` (`Semantics.v:210`) is a total `Fixpoint`
  decreasing in it.  Totality of checked terms is exactly the fuel induction of `denE_total`
  (`Checks.v:1316`).
- The accepted fragment has no recursion on the term side.  The `det_struct` ban arm (G2) excludes
  Choice, Fail, Glob and Iter - the `Glob` and `Iter` arms of `denE_total` close by
  `bans_okE_not_glob` / `bans_okE_not_iter` - and `apps_okE` (G5) forces every application head to be
  `Ret (VPrim p)` (`app_node_ok_shape`, used in `denE_total`'s App arm).  There is no self-applying
  lambda and no loop, so the denotation tree of an accepted term is finite in shape, with its bound
  supplied by the syntax.  That is why every kernel claim about an accepted term is `forall k` (or
  `forall fuel` on the eval leg) rather than a claim at a fixed size, and why the fixed fuels in
  tests/corpus are witnesses of a quantified statement, not limits on it.  The checker's own verdict
  is fuel-free: `det_check` takes no fuel argument.

### 13.2 The stability lemma: `T4_value_unique`

With § 13.1 in hand, the missing half of "what the fuel index buys" is uniqueness, and that is the
corollary `coq/Checks.v` carries after `T4_sem`:

```coq
Theorem T4_value_unique : forall e m v w,
  denote e m ≅ sret (SOk v) -> denote e m ≅ sret (SOk w) -> v = w.
```

With `T4_sem` (existence at every fuel `>= e_fuel e`): at each such fuel an accepted term denotes
*exactly* one value.  The proof chains the two witnesses through their shared middle node
(`transitivity` at `≅`) and ctrees' pure inversion `equ_ret_inv` (`Equ.v:296`) splits the resulting
`sret (SOk v) ≅ sret (SOk w)` into `SOk v = SOk w`; the § 12.2 `sret`/`Ret` alias crosses through
transparently, because `equ_ret_inv` matches up to conversion, and the inversion lands one layer up
at the `SResult` peak, where plain `injection` finishes at `Val`.

Two honest boundaries, both learned from failed attempts and worth recording exactly:

- **A chain cannot cross fuel.**  Witnesses `A(j) ≈ sret vj` and `A(k) ≈ sret vk` at *different*
  fuels share no middle node, so "the whole family `denote e (e_fuel e + k)` is pairwise `≈`" is not
  a setoid exercise at all.  What it needs is a two-fuel strengthening of the totality lemma -
  `denE_total` run with both budgets in one induction, producing related witnesses - recorded as the
  **`denE_total_pairwise`** item; § 13.4 named its first consumer (the
  fold/reassociate half of T5), and § 13.6 records the item landing the same day -
  deferred honestly, then discharged.
  That is the honest shape of "fuel does not change the value": a lemma about the induction, not
  about the setoid, exactly as § 13.1 predicts.
- **The wbisim-side inversion is not available to kernel trees.**  ctrees' `wbisim_ret_inv`
  (WBisim.v:614) looks like the one-step twin of `equ_ret_inv`, but its statement carries the class
  constraint `B0 -< C` for ctrees' own base event type `B0`; instance search against the kernel's
  `B2` fails - `apply (wbisim_ret_inv _ _ H)` on `sret v ≈ sret w` in `ctree void1 B2 SResult`
  errors `Could not find an instance for "B0 -< B2"`.  The inversion therefore lives at the equ
  level, which is where `denE_total`'s witnesses live anyway, and the kernel's only route from `≅`
  to `≈` remains the `equ_wbisim_subrelation` transport every T1 row and `T4_sem` already use.

**Measured.**  `Print Assumptions T4_value_unique` - added to `coq/tests/ChecksTest.v` alongside the
two existing ones - prints the same single `Eqdep.Eq_rect_eq.eq_rect_eq` fingerprint `T4_sem` prints:
the `dependent induction` inside ctrees' `equ_ret_inv` is the machinery that fingerprint already
documents, and `JMeq`-shaped axioms appear nowhere in the log.  The build ends `ok: all 11 expected
.vo artifacts present, dune exit 0` with zero `Error:`/`Admitted` lines, so the kernel gate's axiom
audit is again unchanged by M2 work.

### 13.3 Coinduction is on the relation side; T5 was expected to be the kernel's first explicit coinductive proof

A grep audit of `coq/*.v` shows zero tactic-position use of coinduction machinery (`coinduction`
tactic, `paco*`, `pfold` - every occurrence of those strings in kernel files is prose in a comment):
the kernel consumes the coinductively defined relations (`≅`, `≈`) only through
ctrees' proved interface - `equ_wbisim_subrelation` (WBisim.v:310), the monad laws, the
`Equivalence_wbisim` setoid (WBisim.v:423).  That is enough for T1-T4, whose obligations close by the
fuel induction of § 13.1.  T5 was expected to be the first kernel item where it is not:

> T5 (PLAN.md § 3 item 5): for independent fragments, Wbisim (sem (seq e1 e2)) (sem (seq e2 e1)).

The pre-draft reading of that item - the two denotations are `bind` chains, the proof must relate
them up to permuted layers, so the obligation is coinductive by shape - was measured against the
kernel's actual `Seq` arm on 2026-11-24 and found partly wrong; § 13.4 is the measurement.  What
survives of this section is the route, kept for the claims § 13.4 defers:

1. **The machinery is already vendored.**  coq-coinduction 1.21 and paco 4.4 sit on the build's
   loadpath, and ctrees' own bind proofs use exactly the tactic shape a coinductive proof needs -
   `coinduction S CIH` (`Equ.v`: `bind_ret_r`, `bind_bind`) - so the kernel's first genuinely
   coinductive proof will start from working local idioms, not new dependencies.
2. **Up-to-bind is the right shape.**  ctrees' `bind_chain_gen` (WBisim.v:574) lets a coinductive
   proof step over `bind` chains as a whole instead of unfolding them layer by layer - the shape
   the divergent-component era (M3's Iter) will need.
3. **The witnesses already exist.**  § 11.3's amended mirrored partial-shape pair is the pair of
   trees T5 relates; the corpus pins the statement before the proof machinery is built.

The coinductive debt ledger, as corrected by § 13.4's measurement, has three entries: the
greatest-fixed-point characterization of `iter_step`'s chain that M3's Iter opens (a
`bind_chain_gen`-style argument), M4's Glob/host interaction, and whatever `≈`-level inversion the
kernel will need when a claim must refute a `≈` rather than a `≅` (§ 13.2's B0 boundary again).
Nothing on the term side needs coinduction as long as G2 and G5 hold; coinduction enters precisely
where the language gains recursion.  "Unbounded permutation", which this section listed as a
coinduction entry point, turned out not to need it - § 13.4.  That is the whole content of "fuel
vs coinduction", with the ledger corrected by measurement.

### 13.4 What the T5 draft measured (2026-11-24)

The draft is in the kernel: `T5_swap_discarded_equ` / `T5_swap_discarded` / `T5_swap_equal_values` /
`T5_top_swap_needs_value` (`coq/Checks.v`, after `T4_value_unique`) and the mirror examples
`oo_swap_prefix_sem` and `oo_naive_suffix_swap_refuted` (`coq/tests/ChecksTest.v`).  Four findings,
in order of how much they move the plan:

- **Naive T5 is false, and a two-line kernel refutation pins that.**  The `Seq` arm
  (`Semantics.v:218`) is `SOk _ => denE rho e2 n`: a seq DISCARDS the prefix's value and returns
  the suffix's.  So `sem (seq e1 e2) ≈ sem (seq e2 e1)` fails whenever the two fragments carry
  different values, and `T5_top_swap_needs_value` refutes it at the kernel's own literals
  (`seq (ret z1; ret z2)` denotes to `ret z2`, the swap to `ret z1`), by `equ_ret_inv` plus
  `injection`.  It is stated at `≅` because at `≈` the refutation would need exactly the inversion
  § 13.2 recorded as unavailable to kernel trees (the `B0` pin) - the boundary showing up as a
  proof-shape fact, not a comment.  The corpus had already said this the only way a corpus can:
  the amended Group D block pins leave different final components, `9` fwd and `6` rev, and
  `oo_naive_suffix_swap_refuted` pins that pair as values.
- **The true claim is the swap at a DISCARDED prefix position, and it closes without coinduction.**
  `T5_swap_discarded`: for a checked term, `denote (Seq (Seq e1 e2) e3) (e_fuel + k) ≈
  denote (Seq (Seq e2 e1) e3) (e_fuel + k)`, the same fuel both sides.  The proof is totality (the
  fuel induction of § 13.1) producing the component witnesses at exactly the fuels the arms query,
  then § 12.2's peeling idiom bringing BOTH sides to the literal same tail term `denE nil e3 (S f)`
  - one `transitivity` at that shared term, then `equ_wbisim_subrelation` transport in exactly
  `T4_sem`'s shape.  The discarded values never appear in the proof; that is what "discarded" buys,
  and it is why the kernel's first T5 attempt never asks for coinduction: `bind` chains of accepted
  fragments are peelable because G2 and G5 make them finite.  Corpus witness: `oo_swap_prefix_sem`,
  which discharges `e_oo_left` vs `e_oo_swap` - Group D's own swapped prefix over the shared
  `sub 9 1` tail - through the theorem, using the corpus verdict pin as the hypothesis.
- **A top-position swap holds exactly under a shared value witness.**  `T5_swap_equal_values` states
  it with both fragments witnessed at the same value; peeling leaves `sret (SOk v)` both sides.
  This is the condition the `Seq` arm silently imposes, now a kernel lemma instead of a footnote.
- **The fold/reassociate half is blocked, and its blocker is § 13.2's recorded item.**  Peeling
  `Seq (Seq e1 e2) e3 ≈ Seq e1 (Seq e2 e3)` reaches `denE nil e3` at DIFFERENT fuels on the two
  sides - a cross-fuel statement, exactly the `denE_total_pairwise` shape.  The item got its first
  named consumer the same day, and § 13.6 records it landing: `T5_swap_assoc` is that fold half.

Four toolchain facts were measured on the way in, all silent until they bit - the first three bite
only after `Checks.v`'s `Import WBisimNotations` (l.1410), which is why the same `exists` idiom
works earlier in the same file:

- a bare `exists` in an `assert` type resolves to ctrees' indexed-family quantifier, not Coq's
  `ex` (the witness type comes back as `car (?ops ?n ?m)`);
- `+` in a type whose expected type is not pinned (`x + k = S (S f)`) parses as ctrees' indexed
  sum - `%nat` or a type-pinned context like `Nat.le _ (_ + _)` decides it;
- `setoid_rewrite` reaching the other component's occurrence INSIDE a `Seq` continuation lambda is
  refused by ctrees' setoid machinery - peel each side as its own `assert` equation, one
  occurrence each, then `rewrite` the two equations into the goal;
- `intros` auto-substitutes a `v1 = v2` introduced from the same `forall`'s binders and fuses the
  two witness hypotheses - the lemma reads better with one shared witness.

`Print Assumptions T5_swap_discarded` prints the same single `Eqdep.Eq_rect_eq.eq_rect_eq`, the
coq-build audit stays at zero `Error:`/`Admitted` with all 11 `.vo`, and - the headline - the grep
audit of § 13.3 still holds after the T5 draft: zero tactic-position use of coinduction machinery,
every occurrence of those strings in kernel files being prose in a comment, the T5 block's own
included.  The kernel's first explicit coinductive proof is still ahead of it, and § 13.3 now
records honestly that it belongs to M3's Iter, not to T5.

### 13.5 The fuel idiom is also the lowering strategy (recorded 2026-11-24 as a design constraint)

The question that opened this subsection, recorded as asked: *cofix closures cannot be lowered to
CertiRocq for performance reasons - they must become induction over fuel so CertiRocq emits plain
`while` loops - is that something to tackle now?*  The measured answer is that the kernel already
made this transformation everywhere it concerns CODE, so there is nothing to tackle today; what the
question produces is a rule, and rules are cheap to record before the unit that must obey them
(`Lower.v`, T6/T9) is written.  What was checked:

- **Zero cofix in kernel Gallina.**  `grep -e CoFixpoint -e cofix` over `coq/*.v` hits exactly one
  comment - Denotation.v:77 - and that comment is itself the exposure statement: ctrees' own
  `bind`/`subst` are cofixpoints and do not reduce definitionally.  They live on the spec side,
  where sem-side proofs construct `ctree` trees for `≅`/`≈` claims; they are not in extracted code.
- **The compiled cone is named, and it is fuel-indexed.**  `tools/extract/extract.v` extracts
  "exactly the head-table cone of coq/Eval.v: the fuel-bounded normalizer, the head-redex selector,
  the candidate-bag reader" (its own header) - the four names whose `Print Assumptions` is
  `Closed under the global context` (§ 12): pure Gallina, no ctrees import.  That cone is what the
  T9 CertiRocq composition feeds.
- **The kernel's fuel idiom was born as exactly this transformation.**  `Semantics.v` header item
  (2): the Fig. 13 iter-choice distribution "rebuilds a term as large as its input, so it is not
  structurally recursive" - the kernel answered with the uniform-fuel `Fixpoint`, with the honesty
  note already attached: "Fuel exhaustion yields SStuck - an artifact of the depth budget, not a
  semantic rule."  A fuel-indexed `Fixpoint` is the shape CertiRocq turns into a `while` loop, and
  § 13's theorem stack is what makes that lowering semantics-preserving rather than a semantic
  change: `T4_sem` proves the checked term denotes its value at every fuel `e_fuel e + k`, and
  `e_fuel` is the structural bound of § 13.1 - so for checked inputs the loop's fuel guard can
  never fire, the `while` computes the same value as the unbounded idealization, and the guard
  doubles as a totality guarantee for the compiled artifact.  (The artifact's failure mode is total by
  construction: guard false means `SStuck`, a value, never undefined behavior.)

The rule, recorded in PLAN § 3 item 6 and § 4: Gallina that enters the CertiRocq cone -
`lower_det`, the M3 certified runtime, the future Iter-era evaluator - is structurally recursive or
fuel-indexed `Fixpoint` only; no `CoFixpoint`, no ctrees cofix construction in the compiled cone.
When M3's Iter arrives the shape is already pinned: `iter_step` (Semantics.v:286) decrements fuel
on the sem side, the eval side handles the Fig. 13 rows through the same uniform-fuel idiom, and
T8's uniform-fuel accounting is already a corpus fact.  Fuel, in other words, is not only the
kernel's proof device (§ 13.1) - it is also the kernel's loop discipline, and coinduction stays
where § 13.3 put it: in the proofs, erased before extraction.

### 13.6 `denE_total_pairwise`: the cross-fuel bridge, and T5's fold half (2026-11-24)

§ 13.2 recorded that a fixed-fuel uniqueness chain cannot cross fuels: witnesses
`denote e m1 ≅ sret (SOk v1)` and `denote e m2 ≅ sret (SOk v2)` share no middle node, and "the whole
family is pairwise related" needs totality run with both budgets in one induction.  That item is now
a kernel lemma: `denE_total_pairwise` (`coq/Checks.v`, right after `denE_total`): for a checked node
and any two fuels at or above `e_fuel e`, `denE rho e m1 ≅ denE rho e m2`.  The proof is
`denE_total`'s induction run twice at once (induction on the first fuel, everything else reverted,
the second fuel case-split per arm), and what the arms cost is the interesting fact:

- **Five arms close for free: the peeled tree is fuel-free.**  Ret, TupE, Unify and App (via the
  helper `denE_App_pairwise`) peel both sides to the literal same tree - `apply_c` (Semantics.v:271)
  consumes its budget at the head arm, and the `VPrim` arm returns `sret (prim_sres ...)` with no
  fuel anywhere - so the cross-fuel bridge is `reflexivity`.  Notably the prim bridge lemmas (which
  only rewrite that stuck tree into `SOk w`) are not needed at all, and with them unused, none of
  the prim rows' `ws_val` side conditions are needed either: the two-budget statement is provable
  with strictly less machinery than the totality statement it bridges.
- **Only two arms recurse.**  Seq peels each side to its own fuel of the surviving component (the
  `denE_total` witnesses at exactly the arm fuels, § 12.2's peeling idiom) and bridges with the IH;
  Block does one `closeSlots_int` and bridges the body's two fuels with the IH.
- **Three arms are G2 contradictions**, exactly as in `denE_total` - the pairwise lemma inherits the
  fragment's shape, not just its induction.

With the bridge in place, T5's deferred fold/reassociate half is a peel-peel-bridge theorem:
`T5_swap_assoc` - for checked terms, `denote (Seq (Seq e1 e2) e3) (e_fuel + k) ≈
denote (Seq e1 (Seq e2 e3)) (e_fuel + k)`.  Two structural facts make it cheap: `e_fuel`'s `Seq`
arm is `S` over a SUM, so the two assoc shapes carry literally the same budget
(`2 + e_fuel e1 + e_fuel e2 + e_fuel e3`); and peeling at that shared budget leaves the tail `e3`
at `S f` on the left and `f` on the right - the exact gap the pairwise lemma closes.  Corpus
witness: `oo_assoc_sem` discharges `e_oo_left` vs `e_oo_right` - Group D's own left- and
right-associated pair over the shared `sub 9 1` tail - through the theorem, and
`Print Assumptions T5_swap_assoc` lands on the usual single `Eqdep.Eq_rect_eq.eq_rect_eq`.

Two toolchain facts from the draft, both now recorded in the kernel's own comments: `apply` on an
IH whose frame-count parameter does not appear in its conclusion leaves an unsolvable evar (the
Checks.v Block-arm note) - `refine` with `_` is the fix, and `denE_total_pairwise` needs it in both
of its recursing arms; and a `destruct` on a node-level conjunct CLEARS the node-level hypothesis
(the `T5_swap_discarded_equ` shape is fine there because that proof never re-uses it) - T5's fold
proof cannot afford that, because it witnesses the inner Seq node as a node, so its leaf splits go
through `pose proof`.

Ledger: § 13.3's coinduction ledger is unchanged by this - the cross-fuel bridge is a plain
two-budget induction, and the grep audit (zero tactic-position `coinduction`/`paco`/`pfold` in
kernel files) still holds after the landing.  With `T5_swap_assoc` in, T5 is fully discharged for
the accepted fragment: swap (`T5_swap_discarded`), value condition (`T5_swap_equal_values`),
refutation (`T5_top_swap_needs_value`), fold (`T5_swap_assoc`).

### 13.7 CompCert 3.17 as a build-time dependency: the namespace trap, the license gate, and T6's axiom surface (measured 2026-11-25)

T6 (`lower_det e = c -> Wbisim (sem e) (ClightSem c)`, PLAN § 3 item 6) needs CompCert's
Gallina library, and `pins.toml` has pinned `compcert 3.17` with the version-consistency gate
asserting it for weeks.  Consuming it is where the facts were:

- **Top-level `pkgs.compcert` is a prover-9.0 build.**  At the pinned nixpkgs, all-packages
  wiring is `inherit (coqPackages_9_0) compcert`; the drv's own `configurePhase` says
  `-coqdevdir $lib/lib/coq/9.0/user-contrib/compcert/`.  `.vo` files are prover-version-locked,
  so those cannot load under this flake's rocq 9.1.1 — and building that variant starts a
  from-scratch stdlib 9.0 rebuild: the first gate bill died 51 seconds in when the parallel
  rebuild crossed the memory floor.  The usable attribute is **`pkgs.coqPackages_9_1.compcert`**:
  same pinned 3.17, nixpkgs-applied Coq 9.1.1 compat patch, `coqdevdir lib/coq/9.1/user-contrib`,
  142 `.vo` across `lib/common/backend/cfrontend/cparser/driver/export/x86/x86_64`.
  pins.toml's `nixpkgs_attr` moved to the 9.1 attribute so the gate asserts the package this
  flake actually consumes.
- **cache.nixos.org carries the 9.1-series closure** (compcert, flocq 4.2.2, MenhirLib
  20260203 all substituted; measured 384 s end to end with `cores = 2`, host low-water
  6499 MiB — the 5 GiB `MemoryMax` nix-daemon containment did its job).  The 9.0 variant
  is *not* substituted, consistent with hydra building only the supported series.
- **License plumbing is scoped, not global.**  The nixpkgs import in `flake.nix` carries an
  `allowUnfreePredicate` admitting exactly `compcert` (INRIA non-commercial license); any
  future unfree package trips evaluation.  The dep is build-time Coq-library use only —
  ccomp as a compiler stays the separate license-gated CI lane of PLAN § 4, and nothing in
  `coq/` imports CompCert yet, so the shipped kernel `.vo` cone is unchanged.
- **Loadpath plumbing needed no special casing** (measured, not assumed): CompCert compiles
  each source dir with `-R <dir> compcert.<dir>`, so its `.vo` record fully-qualified internal
  dependencies even though the sources write bare `Require Import AST`; a consumer needs only
  the parent `user-contrib` on the loadpath.  Verified on a miniature tree built with that
  mapping, then against the real one: `ROCQPATH` and `COQPATH` both carry `compcert` in
  `nix develop .#rocq`, and `Require Import compcert.cfrontend.Clight.` just works.  One
  rocq 9.1 quirk: `Print Assumptions` resolves *references*, not deep module paths under a
  recursive `-R` — audit constants, not modules.
- **T6's axiom surface — the most valuable measurement.**  In the installed tree:
  `Smallstep.star` and `Smallstep.forward_simulation` (the generic closure and simulation
  machinery any refinement statement must meet) print `Closed under the global context`;
  `Clight.step`, `Csem.lred`, `Csem.rred` and `ClightBigstep.bigstep_program_terminates` each
  carry Flocq's classical pair `ClassicalDedekindReals.sig_not_dec` + `sig_forall_dec`, pulled
  in through `Clight.val -> Float -> R` in the step type itself.  Any T6 statement mentioning
  Clight values drags those two axioms into `Print Assumptions` transitively, while the kernel
  gate hard-pins `Eqdep.Eq_rect_eq.eq_rect_eq` as the sole axiom.  The audit decision —
  allowlist, separate audit scope, or float-avoiding formulations for int-only fragments —
  belongs in the Lower.v design, made before the first proof line.
- **Surface facts** from the probe (`Check`-verified against the tree): `Clight.v` carries
  Clight syntax *and* its small-step semantics (`Inductive state`/`step`; constructors
  `Sskip`, `State`, `Callstate`; `step` is parameterized by the builtin-call semantics);
  `Csem.v` is the CompCert C semantics as a file-level module; `export.Clightdefs` is the
  Clight<->Csyntax bridge clightgen and CertiRocq both use.

Ledger: the coinduction ledger (§ 13.3) is untouched; the kernel's own `.vo` set is unchanged
(11 modules, `eq_rect_eq` sole axiom); the probe itself lives outside `coq/` on purpose —
Lower.v will get its own probe-first draft like T5 did, with the axiom question settled first.

### 13.8 T7 landed: `Lower.v` as a fuel-free structural `Fixpoint`, the syntax-cone audit lane, and CompCert's notation window (measured 2026-11-25)

T7 (`det_check e = true -> no_switch (lower e)`, PLAN § 3 item 7) landed in `coq/Lower.v`,
faithful to the PLAN wording and probe-first (p501–p511) like T5 was.  What the increment
measured:

- **Shape.**  `lstmt` is the kernel-side statement type: Clight statements wrapped as
  `Lclight`, sequenced as `Lseq`, and — the point of T7 — an explicit `Lswitch e` marker
  carrying the *kernel* `Expr` wherever `lower` declines to translate (Fail, Choice, Iter,
  context-call shapes).  `lower : Expr -> lstmt` is a **total, fuel-free structural
  `Fixpoint`** — legal under the CertiRocq-cone rule (§ 13.5) as the structurally-recursive
  alternative to the fuel-bounded sketch in PLAN item 6.  `no_switch_l : lstmt -> bool`
  decides absence of `Lswitch`; `T7_no_switch` is stated for `det_check` and proved through
  `T7_no_switch_ws`, the depth-general form: the `ws_expr` guard is depth-indexed (a Block
  body is checked at `Datatypes.length sl + d`, Checks.v's own convention), so the induction
  carries the depth universally and the Block arm re-instantiates it.
- **The measured fragment is purely straight-line.**  `app_node_ok_shape` (Checks.v:537) pins
  what `det_check` admits at an `App`: only `App (Ret (VPrim p))` heads with literal
  (`rets_of`) operands — no beta, no loops.  `Glob`/`Choice`/`Fail`/`Iter` are banned by
  `bans_okE`, so their induction arms close by `discriminate` on the peeled guard; `Unify`
  closes through `eq_pair_ok`'s `Sskip` arm; `TupE` through `tup_node_ok_rets`; only `Seq`
  and `Block` recurse.  Arithmetic constants emit 64-bit: `Clight.Econst_long (Int64.repr n)
  (Ctypes.Tlong Signed noattr)` (`Econst_int` is 32-bit `int` — p504).  Documented
  placeholder arms (prims outside the arithmetic map, `TupE` layouts, `Some (VVar _)` slots,
  `VLam`) are structurally present but semantically vacuous until T6 refines them.
- **The § 13.7 audit question resolves for the half T7 touches.**  `Print Assumptions
  T7_no_switch` — run *inside* the build via `coq/tests/LowerTest.v` — prints `Closed under
  the global context`: T7 mentions only Clight *syntax* constructors (p502 had measured the
  syntax cone axiom-free), never the step relations, so Flocq's `sig_not_dec`/`sig_forall_dec`
  pair never enters and the kernel gate's `eq_rect_eq`-only pin is untouched.  The fresh-build
  log audit was re-run with the flake's own grep before billing: exactly one axiom line, and
  the new `Compute` emission dump (record fields like `Integers.Int64.intval := 6;`) does not
  match the axiom-line pattern `^[A-Za-z][A-Za-z0-9_.]* :`.  The Flocq decision stays a T6
  obligation, scoped to the *semantics* cone (`Clight.step`, `Csem.lred/rred`,
  `ClightBigstep`).
- **CompCert's notation window — the costliest ergonomic fact.**  `Require Import
  Timbda.Lower` (hence CompCert) rebinds *parsing* for the rest of a file: `[..]` list
  literals and `x :: l` stop resolving to stdlib lists ("Unknown interpretation for notation
  _ :: _"), and bare numerals stop elaborating against the kernel's `Z` — `Check VInt` then
  prints `BinNums.Z -> Val` and `VInt 2` fails with "2 has type nat while it is expected to
  have type BinNums.Z" (CompCert 3.17 wraps stdlib `Z` in `BinNums.Z`; numeral overloading
  does not see through the wrapper).  The test lane is written around it: kernel-side terms
  are `Definition`s *before* the `Timbda.Lower` require, and every test file re-opens
  `Import ListNotations` — a module's own `Import`s (Syntax.v:19) are not re-exported to
  consumers.  Inside `Lower.v` itself only cons patterns (`(PAdd, a :: b :: nil)`) and
  `Datatypes` spellings appear.
- **Proof assembly idiom.**  The final T7 proof shares only the induction and the `intros`;
  every bullet re-peels `det_struct_components` + `andb_and`/`andb3_and` because the guards'
  `cbn` shapes are constructor-specific (Block's unify/apps/tup arms are already body-single
  after `cbn`; bans/blocks/ws peel conjunctively).  A shared pre-bullet peel verified fine
  on every single-branch probe (p511-style isolation) yet failed in the 10-bullet assembly —
  per-branch self-containment is the idiom for this guard bundle.  9.1 Ltac1 detail that
  bit once: intro-pattern names cannot be passed as Ltac1 variables ("cannot be coerced to a
  variable"), which is why Checks.v destructs inline and Lower.v does too.
- **Consumption fact for the distribution.**  `Lower.vo` is the first kernel artifact whose
  import cone reaches CompCert: downstream users of `timbda-kernel`'s installed `.vo` set need
  `compcert` on the loadpath (already true in the flake, `rocqDeps ⊂ buildInputs`), and the
  kernel `.vo` set grows 11 → 13 (`Lower.vo`, `tests/LowerTest.vo`), mirrored in
  `tools/build/coq-build.sh` `EXPECTED_VO` and the `flake.nix` buildPhase vacuity check.

Ledger: coinduction ledger (§ 13.3) untouched (Lower.v adds no cofix or ctrees machinery);
kernel axiom set unchanged (`eq_rect_eq` sole, T7's own cone prints *closed*); M2 debt now
T6 + golden test.

### 13.9 The M1 attestation lanes: bazel evidence that is content-bound, and the flake visibility rule (measured 2026-11-25)

Decision 9's two cheap M1 lanes landed as flake checks (`checks.rules-audit`,
`checks.bazel-native-tests`), both in `tools/build/nix-gate.sh`'s default chain (now six
lanes).  What was measured:

- **The bazel graph is buildable on this host today**: `bazel --batch test //dialect:...`
  completed with 2141 action-cache hits, dialect test PASSED in 7.6 s — the hermetic-llvm
  0.8.27 / LLVM-MLIR 23.1.2 closure is fully cached (~7.6 GiB `~/.cache/bazel`).  So the
  "bazel builds, nix checks consume as prebuilt" contract (§ 6) needs no new infra: it just
  had to be *attested*.
- **Evidence shape.**  `tools/build/bazel-lane.sh` (bazel side, run via `nix develop .#cpp`)
  writes `tools/build/bazel-lane-status.txt`: the target set, the `Build completed` line, the
  per-test PASSED summary, the recorded `bazel --version`, and a `sha256sum` block over every
  bazel-graph input (`dialect/*` + `MODULE.bazel` + `MODULE.bazel.lock` + `.bazelversion` +
  `pins.toml`).  The nix check refuses the status unless it records rc=0 + PASSED + the pinned
  bazel version, and re-runs `sha256sum -c` against *its own* copy of the tree.  No timestamp:
  the content hashes are the freshness signal, so a status can only ever vouch for the exact
  dialect/pin content it was generated from — a changed dialect silently unbinds the evidence
  and the gate goes red.  (First run of the check *was* the negative-path test: it correctly
  refused before the status file existed.)
- **The flake visibility rule — an operational trap worth remembering.**  A path literal
  `./.` inside `flake.nix` copies only git-**tracked** content (HEAD tree plus dirty changes to
  tracked files); brand-new untracked files are invisible to derivations — even though
  `getFlake(...).outPath` (the flake's `self`) shows them.  A new lane's artifact
  (`bazel-lane-status.txt`) therefore stays invisible until it is committed; the correct order
  for anything introducing new files is: jj commit → gate bill (attests the committed tree,
  which is what the lanes can see) → move `main` → push.  `nix flake archive-tarball` no
  longer exists in nix 2.35; diagnose store-visible content with
  `nix eval --impure --raw --expr '(builtins.getFlake ".").outPath'` plus `ls`, or
  `nix show-derivation`'s `env.srcs`.

### 13.10 The tblgen-rocq toolchain resolution: the Nix side builds the generator (probes p512/p513, measured 2026-11-25)

M1 item 1's load-bearing question was *where the tblgen-rocq binary comes from*.  PLAN sec. 6
answers the split - "-gen-rocq output on the Nix side ... do not make one graph build the other's
artifacts" - but the question was whether nixpkgs can actually build a TableGen backend at the
pinned vintage.  It can, and the shape of the job is now measured:

- **nixpkgs llvmPackages_23 = 23.1.0** (vs the hermetic-llvm/bazel pin 23.1.2: same 23.1 series;
  the pair is now pinned as `[formal.mlir_gen]` and asserted by the version-consistency lane).
  It substitutes from cache in seconds - no MLIR-from-source build needed on the Nix side.
- **What nixpkgs ships**: `llvmPackages_23.llvm.lib` = `libLLVMTableGen.a`, `libLLVMSupport.a`,
  `libLLVMDemangle.a` (plus the rest); `llvm.dev` carries the full classic TableGen C++ API
  (`llvm/TableGen/Record.h` with `RecordKeeper::getDefs`, `Record::getValueAsString/Int/ListInit`,
  `isSubClassOf`; `llvm/TableGen/Parser.h` = `TableGenParseFile(SourceMgr&, RecordKeeper&)`);
  `mlir` main output carries `libMLIRTableGen.a`/`libMLIRTblgenLib.a`/PDLL libs.  **What it does
  not ship**: the `mlir/TableGen/Record.h`+`RecordKeeper.h` wrappers (nixpkgs' header install set
  omits exactly those - the other 23 `mlir/TableGen/*.h` are present and internally reference the
  missing one), nor the `mlir-tblgen`/`mlir-pdll` *binaries* (`FileCheck` and `llvm-tblgen` are in
  llvm's bin).  On the bazel side, `@llvm-project//llvm:FileCheck` exists but there is no `lit`
  target - lit comes from nixpkgs (`lit` 18.1.8).
- **Probe p513 (the decision-maker)**: a C++17 main against `llvmPackages_23` compiled, linked
  (`-lLLVMTableGen -lLLVMSupport -lLLVMDemangle -lz -lpthread -ldl`) and ran *inside a nix
  derivation*, parsed the real `dialect/Timbda.td` - full ODS + dialect + the 72 rule records -
  via `TableGenParseFile`, and walked `isSubClassOf("TimbdaRuleRecord")`: **72 defs, 26
  selected**, field reads (`ctor`, `status`, `ops`, `selected`) all resolving - the audit's own
  counts, from an independent code path.  So the Nix-side backend needs no MLIR wrapper headers
  at all: the classic llvm::RecordKeeper surface is sufficient (the mlir wrappers are convenience
  over the same parser).
- **Two API gotchas measured, worth encoding in the backend**: (a) llvm-TABLEGen resolves
  `include "X"` against CWD + explicit paths, *not* the includer's directory - that resolution is
  an MLIR wrapper feature - so the generator job must arrange the search tree (probe: run from
  the dialect dir with symlinks `mlir -> $(mlir.dev)/include/mlir`, `llvm -> $(llvm.dev)/include/llvm`,
  `dialect -> .`); (b) `.td` `int` fields are IntInit - `Record::getValueAsBit` *fataled* on
  `selected` (LLVM 23 also spells it `isSubClassOf`, not `isSubclassOf`).
- **Binary prebuilt consumption is rejected for this stack** (probe, same day): a bazel-built
  binary imported via `nix store add-file` registers in the store but the daemon silently drops
  it from a drv's `inputSrcs` (CA-imported paths are not referenceable as derivation inputs under
  this nix config) - a sandboxed check cannot consume bazel binaries.  This hardens sec. 6's
  "they meet only at generated artifacts" from a design preference into an enforced fact for the
  rule-record family: *text* is the interface, not executables.
- **Consequence for generated-file placement**: the kernel lane compiles the whole `coq/` dune
  unit and its gate scans the build log for `Admitted`, so a generated *soundness-skeleton* file
  cannot join that unit until its proofs exist (M2).  Generation lands in a `coq/` subtree outside
  the dune unit first; the hand-glued `Rew`/AST retire only when the generated definitions are
  proof-compatible.  Reproducing the hand-glued ctor signatures byte-exactly needs the record
  schema to carry the Coq-side fields (binders/hyps/lhs/rhs per ctor are currently bespoke in
  `coq/Rewriting.v`, prose-only in the `.td`) - the schema step precedes the emitter step.

### 13.11 M1 item 1, rules half: the ctor surface moves into the records, and `RewRules.v` becomes a generated file (landed 2026-11-25, probes p514/p515)

The one-way move § 13.10's closing paragraph demanded, executed as one increment:

- **Schema step**: `tools/rules-coqctor.py` transcribes the 35 hand-glued `Rew`
  ctor signatures out of `coq/Rewriting.v` into structured record fields -
  `coqTag`/`coqForall`/`coqHyps`/`coqLhs`/`coqRhs`/`papForm` on
  `TimbdaRuleRecord` - plus six `TimbdaRuleGroup` defs and a
  `TimbdaRuleGenOrder` carrying the emission order (the file's actual group
  order: Fig 9, 10, 11, 12, 8, 13).  The tool self-checks by re-rendering every
  ctor from its fields (whitespace-normalized, 35/35 exact, audit comments
  included) before touching the `.td`; the transcription is lossless and
  mechanical, and the hand-glued ctor block is then cut from `Rewriting.v`
  (helpers + a pointer note stay; the file's header now says so).  `coqTag`
  exists because the audit tag may differ from the ctor suffix (`RewPrim`
  carries tag `PrimSchema`) - the audit already knew that from the Coq side,
  now the records do too.
- **Emitter step**: `dialect/tblgen-rocq/TimbdaRocqGen.cpp` - the PLAN sec. 2
  backend - built on `[formal.mlir_gen]` (llvmPackages_23) exactly as 13.10's
  recipe.  Modes: `-gen-rocq-rules` implemented; `-gen-rocq-ast` and
  `-gen-rocq-checker` registered but refuse with rc=2 (an unimplemented mode
  must refuse, never emit a skeleton - the golden lane's byte claim only means
  something for what is actually generated).  Output is a pure function of the
  `.td` content: hand-tracked word wrapping at fixed columns, no timestamps,
  the `rw_step`/`rewrites` context closure carried as fixed backend text (it
  is paper machinery, not record-derived; the dcont extern surface remains
  `-gen-rocq-externs` at M4).
- **Measured facts** (p515): generated `coq/RewRules.v` ctor-for-ctor equals
  the retired hand-glued block after whitespace flattening, 35/35 including
  audit-comment text, emission order preserved; all 11 bazel `TdGenerate`
  actions re-run on the rewritten `.td` and stay green (bazel's action cache
  is content-keyed - `TimbdaRules.td` demonstrably an input); the `.#rocq`
  dune unit compiles the generated inductive with every existing proof intact
  (Denotation's 35 `RewSound_*` lemmas, KernelTest unchanged).
- **13.10's placement prediction refined by measurement**: the "outside the
  dune unit" reservation was about generated *soundness skeletons* (proofs).
  A generated *statement* file - inductives and definitions only - joins the
  dune unit immediately: proofs against the same ctor surface recompile
  untouched.  `EXPECTED_VO` and the kernel buildPhase gained `RewRules` as
  anti-vacuity witnesses.
- **Two toolchain teeth learned the hard way, now encoded**: (a) `StringMap`
  keys must outlive the values they index - indexing ctor names by
  `StringRef`s into moved `std::string` members compiled but found nothing at
  lookup; the backend keys a `std::unordered_map` instead; (b) LLVM 23.1
  `raw_fd_ostream` dropped the `(path, string&)` ctor - it is `(path,
  std::error_code&, sys::fs::OF_None)` now.  Also C++17, not 20: no
  `map::contains`.
- **Gate shape**: `checks.tblgen-rocq-golden` (regenerate twice, byte-diff the
  two regenerations and the committed artifact, count 35, assert the refusing
  modes refuse) enters the gate chain's default set (seven lanes) as item 2's
  golden half landing early; `tools/rules-audit.py` section 1b asserts the
  provenance from the Coq side: every generated ctor == its record fields
  re-rendered (a second, independent implementation of the render contract in
  python), tag/fig/tier/papForm equality, the six groups partition the 35 ctor
  rows exactly once and match the generated order, `Rewriting.v` carries no
  `Inductive Rew`, and the generated file carries the context closure.  The
  `.td` record parser in the audit gained a quote-aware list regex (the coq*
  fields put `]` and `\"` inside strings - e.g. Subst's papForm).

### 13.12 M1 item 1 completion: `-gen-rocq-ast` and `-gen-rocq-checker` land; the checker artifact is a registry, not statements (landed 2026-11-25, probe p516)

The two registered modes became real generators, and the last hand-glued
rule artifact retired:

- **The AST generation rule, fixed from record fields** (the measurement
  question 13.11's landing left open): the eval-side `Inductive RuleID` has
  one constructor per *distinct non-empty `kernelTag`* of the ctor rows - the
  SCHEMA arity variants sharing `R_Prim`/`R_PrimFail` are why 35 ctor rows
  map to 27 RuleIDs and 26 selected ctor rows to 19 `selected_rows`.  Group
  structure is not derived: `coq/Eval.v`'s fig grouping (12, 9, 11, 10, 8,
  13, never-selected) is historical kernel text, so it rides the records as
  seven `TimbdaRuleAstGroup` defs + `TimbdaRuleAstOrder`, transcribed verbatim
  by `tools/rules-coqctor.py` - same one-way direction as the ctor surface.
  `selected_rows` IS derived: ctor rows with `selected = 1`, `rank`-ascending,
  deduplicated by `kernelTag`; the tool measured the rank order reproduces
  `Eval.v`'s list exactly (19/19), which is what licenses generating it.
  `coq/RuleAst.v` is the emitted file; `coq/Eval.v` retired its hand block and
  now `Require Import Timbda.RuleAst`.  Group comments must be stored
  stripped: `Eval.v`'s column-aligned padding (`(* fig:9  *)`) leaked a
  trailing space into the first transcription - the tool strips, the C++
  backend collapses whitespace, and the golden lane pins the emitted bytes.
- **`-gen-rocq-checker` measured before choosing its shape**: PLAN sec. 2's
  "per-rule soundness-lemma skeleton" would mean *generating lemma
  statements*.  Measured against the 19 kernel `RewSound_*` statements (15
  discharged rows + the 2 partial SCHEMA rows at their 1-ary/2-ary arities):
  **zero** statements match a template rebuilt from the record fields alone.
  Every discharged statement is proof-side design on top of the record
  semantics - deeper fuel groups than `S (S f)` (Add runs at `S (S (S (S (S
  f))))`), `closeV`-wrapped hypotheses (`prim_total p [closeV 0 rho v0] =
  PRes (closeV 0 rho v)`), and the Prim family statements over `prim_app`
  with their own arity.  And 18 deferred rows carry *no* statement at all by
  kernel policy (docs/RULES-AUDIT.md sec. 4: no `RewSound_*` lemma, no
  `Admitted`).  A generated skeleton would therefore be fiction: statements
  with the wrong fuel budget, or 18 statements the kernel refuses to have.
  The artifact is instead the **soundness registry** `coq/CheckerManifest.v`:
  per ctor row `(ctor, tag, status, [lemma names])` as Coq *data*, in the
  generated emission order, carrying no `Lemma`/`Proof` surface at all.  The
  proof statements stay in `coq/Denotation.v` (hand-designed, proof-carrying);
  the registry makes the per-row evidence machine-readable, and audit sec. 1c
  asserts the triple identity manifest == record `soundLemmas` == kernel
  `RewSound_*` inventory, 35/35 with status-consistent counts (1/2/0).
  The `.td` gained the `soundLemmas` field per ctor row (17 rows nonempty:
  15 discharged + 2 partial); `tools/rules-coqctor.py` transcribed it from
  `coq/Denotation.v` and now verifies idempotently - re-`--apply` is a proven
  no-op on the records.
- **Refusal boundary after this increment**: `-gen-rocq-rules`,
  `-gen-rocq-ast`, `-gen-rocq-checker` all emit; only `-gen-rocq-externs`
  stays registered-and-refusing (rc=2, no output), the ContextExtern family
  bound to M4 (PLAN sec. 5.0).  The golden lane now regenerates all three
  emitted artifacts twice, byte-diffs regeneration against each committed
  file, counts 35 ctors / 27 RuleIDs / 35 manifest entries, and asserts the
  one remaining refusal.
- **Gate shape after this increment**: `rules-audit` sec. 1c asserts the
  provenance from the Coq side (AstGroup defs == generated block, RuleIDs ==
  distinct kernelTags, `selected_rows` == rank order, manifest == records ==
  kernel inventory, `Eval.v` carries no hand block, manifest has no proof
  surface); `EXPECTED_VO` and the kernel buildPhase witnesses gained
  `RuleAst` and `CheckerManifest` (16 expected .vo), and Eval.v's compile
  *depends* on RuleAst now - a kernel build missing the generated AST cannot
  reach `Eval.vo` at all.  Backend plumbing note: the three modes share
  `openOut`/`parseTD` helpers; `raw_ostream *&` binding needs the base
  pointer type at the call site (`raw_ostream *OS`, not `raw_fd_ostream *`).
- **Two Rocq 9.1 teeth the first kernel run billed, now encoded in the
  backend's prologues**: (a) a `Definition` body that opens with `[` parses
  as `[reduce]`-annotation territory unless list notation is actually in
  scope - `From Stdlib Require Import List. Import ListNotations.` is what
  makes a list body legal (measured: without it, `Definition f : T :=\n  [(…)]`
  is a syntax error in the pinned 9.1.1); and (b) a *string*-typed registry
  needs `Strings.String` imported *and* `Open Scope string_scope.` opened -
  `Import StringScope` is not a thing (scopes are `Open Scope`, and the
  literal `""` has "no interpretation" until the scope is open).  The
  manifest prologue now carries all three lines.  Third gotcha for consumers:
  Coq `Require Import` is not transitively re-exported, so the files that
  mention `RuleID`/`R_*` (`ChecksEval.v`, `tests/KernelTest.v`) `Require
  Import Timbda.RuleAst` explicitly - the same discipline increment A applied
  to `Timbda.RewRules`, and `tools/extract/extract.v`'s qualified names moved
  to `Timbda.RuleAst.selected_rows` for the same reason.

### 13.13 M1 item 2: pdll lit skeletons become a generated artifact, and the bazel evidence moves into the tree (landed 2026-11-25, probe p518)

Closing item 2 forced two contract decisions, both measurements first:

- **What a pdll lit skeleton may assert, measured before writing the
  generator.** PLAN sec. 2 artifact 3 says each record generates a lit-test
  skeleton; the honest reading is *what the rule record can derive of the
  `mlir-tblgen -gen-rewriters` output*.  Measured against the generated
  `TimbdaCanonicalization.cpp.inc`: the root-op invariant
  `::mlir::RewritePattern("timbda." + ops[0]` holds **23/23**; the
  `benefit = 100 - rank` invariant holds **21/23** - `RewGt1` and `RewIsInt1`
  emit 84 where their rank says 85, a `Pattern<>` vs `Pat<>` delta-tuning
  detail owned by `dialect/TimbdaPatterns.td` (its header ties the Prim-schema
  benefits to the `prim_total` catchall guard, not to the rank column).  So
  `-gen-pdll-tests` emits per DRR ctor row exactly the three record-derived
  assertions - `struct <ctor> : public ::mlir::RewritePattern {`, the root-op
  ctor line, and `patterns.add<<ctor>>(patterns.getContext());` - into
  `tests/lit/pdll/<ctor>.check`.  Benefit is *not* asserted; that would be a
  record-side fiction of the same species 13.12 refused for lemma statements.
- **bazel-out is invisible to nix-side checks - and a gate hole it had been
  leaving.** The audit's `populateWithGenerated` check reads the bazel-built
  `.inc`; `bazel-out/` is a symlink farm that does not survive the nix tree
  copy, so in every gate run so far that check hit its SKIP branch (confirmed
  in the gate's rules-audit log) - it had only ever run locally.  Fix: on every
  green run `tools/build/bazel-lane.sh` copies the generated `.inc` into
  `tools/build/bazel-evidence/TimbdaCanonicalization.cpp.inc` and adds its
  sha256 to
  the status source-hash block, so `checks.bazel-native-tests`' `sha256sum -c`
  binds the committed text to the attested bazel run (a stale pattern edit
  reds the attestation, an evidence edit reds the hash).  The audit and the
  lit lane both read the committed evidence; the populate check now genuinely
  runs in the gate.  Generated text as the only cross-graph interface (sec.
  13.10) applied one notch further.
- **`checks.dialect-lit-tests` joins the gate chain (now eight default
  lanes)**: regenerate the skeletons twice (byte-identical), byte-diff against
  the committed 23, then run lit 18.1.8 (nixpkgs) + FileCheck
  (`[formal.mlir_gen]` pin, llvm 23.1.0 bin) over `tests/lit` with
  `%timbda_drr_inc` bound to the committed evidence - asserting `Passed: 24`
  (23 pdll + the handwritten `dialect/populate.check` shape test: 23 structs,
  23 populate wires) and exactly `Unsupported: 1`: `canonicalize/prim-fold.mlir`
  carries `REQUIRES: timbda-opt`, which lit reports UNSUPPORTED until the M2
  opt tool exists - an honest skip, not a fake pass.  Two lit gotchas fell
  out, both measured: the token `REQUIRES:` inside prose is parsed as a
  directive, so skeleton comments must not spell it (FileCheck's
  word-boundary rule for `CHECK` inside `FileCheck` is the analogous guard);
  and lit 18 ShTest writes its script + `Output/` scratch next to
  `test.getExecPath()`, which defaults to the source tree - in the gate that
  tree is the read-only nix store, and every `.check` surfaced as UNRESOLVED
  with a `PermissionError` on `…/tests/lit/pdll/Output` (invisible in a local
  run, where the tree is writable - the local tell was stray `Output/` dirs
  littering the tree).  The cfg fixes it explicitly with
  `config.test_exec_root = tempfile.mkdtemp(...)`, redirecting all scratch
  out of the source tree.
- **Audit sec. 5 extended (48 checks)**: skeleton files partition the 23 drr
  ctor rows, each skeleton equals its record re-derivation, and the committed
  evidence carries the asserted text - the pdll artifact now closes the same
  record->Coq->MLIR->test circle the audit was built to attest.  M1 is
  declared closed in docs/PLAN.md sec. 5.0 with this increment; M2's forced
  order (T6 first) resumes.

### 13.14 T6's design obligations settled by probes p519: the statement-level `exec_stmt` realization, the `range_ok` guard, and the six-axiom cone allow-list (measured 2026-11-25)

`coq/Lower.v`'s header pins three design obligations that must be settled
*before* T6's first proof line (the Flocq audit-lane question, the 64-bit
range story, the placeholder-arm story).  Probes p519a/p519b/p519i/p519l
(sources + reproduction now committed at docs/probes/p519/) measured all
three against the installed CompCert 3.17 and the gate-built kernel `.vo`
tree; the settled rulings are decision 10 in docs/PLAN.md.

- **The realization is real at statement level.**  The kernel corner
  `add[2,3]` (an `App (Ret (VPrim PAdd))` over a `TupE` of `Ret (VInt _)`
  - exactly the shape `app_node_ok` pins) checks (`det_check = true`) and
  lowers to `Lclight (Sset lower_res (Ebinop Oadd (Econst_long 2) (Econst_long 3)
  tint64))`.  One `ClightBigstep.exec_Sset` (3.17 made it a one-premise rule:
  only `eval_expr`) over `eapply Clight.eval_Ebinop` plus two
  `eval_Econst_long` plus a `vm_compute` closed equality for
  `sem_binary_operation ge0 Oadd (Vlong (repr 2)) tint64 (Vlong (repr 3))
  tint64 Mem.empty = Some (Vlong (repr 5))` derives
  `Clight1.exec_stmt` from `ge0` (empty genv: `Genv.empty_genv Clight.fundef
  Ctypes.type nil` + `PTree.empty composite`), `Clight.empty_env`,
  `PTree.empty val`, `Mem.empty`, to the final temp env holding
  `Vlong (Int64.repr 5)` at `lower_res`.  Sequences will use `exec_Sseq_1`/
  `exec_Sseq_2` (3.17's split - `exec_Sseq` does not exist).  The whole-program
  reading stays deferred: `bigstep_program_terminates` pins main to
  `Tfunction nil type_int32s cc_default` returning a `Vint`, so the 64-bit
  result is observed at the temp-env level (`lower_res = xH = #1`), and the
  main-wrapper story belongs to the golden-test design, not to T6.
- **The axiom package is unavoidable in any CompCert-rules T6, so the audit
  gets a second, separately-pinned scope.**  `Print Assumptions` on the
  concrete derivation prints six axioms: Flocq's `ClassicalDedekindReals.sig_not_dec`
  and `sig_forall_dec`, `FunctionalExtensionality.functional_extensionality_dep`,
  `Classical_Prop.classic`, and CompCert's two external-call parameters
  `inline_assembly_sem` and `external_functions_sem`.  Localization (p519l): they
  are not proof shortcuts - they sit in the *premise types* of the rules
  themselves.  `Values.sem_binary_operation` as a whole `Fixpoint` (its float
  arms call Flocq's classically-rounded IEEE operations) carries the four
  logical axioms; `eval_Ebinop`/`exec_Sset` add the two event-semantics
  parameters; `Mem.loadv` also carries the four (its `val`-construction chain
  reaches Flocq rounding), while `Mem.empty`/`Mem.storev`, the `Genv` pieces,
  `PTree.get/set`, `Values.sem_cast`, `Clight.function_entry1`, `ge0` and the
  flattening `clight_of` print `Closed under the global context`.  Ruling
  (decision 10): the kernel lane keeps its strict `eq_rect_eq`-only allow-list
  for kernel-owned theorems (T7 etc. stay there); theorems in the
  CompCert-facing cone (T6 now, the CertiRocq/golden-test theorems later) are
  audited in a second scope against the pinned six-axiom list, reported as its
  own block; anything outside `eq_rect_eq` (kernel) plus the six (cone) reds
  the gate.  This replaces the § 13.7 guess that a T6 statement "would
  legitimately break" the kernel lane and might be dodged by formulation - it
  cannot, and pretending otherwise would put the allow-list in the proof
  instead of in the open.
- **The 64-bit range story becomes a computable guard, not a redefinition of
  the fragment.**  Kernel `VInt` is Stdlib `Z` (Syntax.v) and `vconst` wraps
  via `Int64.repr`, which is modular; preservation fails exactly when an
  evaluated value leaves the signed 64-bit window.  Because `det_check` pins
  every admitted `App` node to literal operands, every intermediate value of a
  checked term is inspectable *syntactically*: the T6 increment adds a
  computable `range_ok e` (every `VInt` constant of e, and every admitted
  prim application's kernel result, inside [-2^63, 2^63)) and T6 carries
  `range_ok e = true` as a hypothesis.  `det_check` itself does not change -
  its behaviour is pinned by the corpus and lit artifacts, and moving range
  into it would be a fragment change that decision 8's rulings do not license.
- **Placeholder arms get an explicit correspondence scope.**  The kernel's
  prim reading is the paper's: relational primops *return their first
  argument* when the guard succeeds (`Syntax.v prim_total`: `PGt [a;b] =>
  PRes (VInt a)` under `b < a`, lines 344-357), and `prim_total_res` is
  "answers `PRes`".  So T6's value claims split three ways: (1) the arithmetic
  map {add, sub, mul, div, neg} - final `lower_res = Vlong (Int64.repr z)` for
  the kernel result z.  (The parenthetical written here - "`Z.div` truncates
  like CompCert's int64 division, decision 8b's `divZ` note" - was FALSE and
  was retracted on 2026-11-26: `Z.div` is a true FLOOR and CompCert's
  `Int64.divs` truncates; the fork and its closure are decision 12, § 13.15.);
  (2) the guard map {gt, lt, geq, leq, neq} -
  prim `prim_total_res`-success is exactly CompCert's order test on the same
  in-range literals, claimed as "final `lower_res = Vint 1`"; (3) everything
  else admitted (`all_int` identity prims PPls/PIsInt reaching the `Econst 0`
  placeholder, table prims with var operands, TupE, `None`/`VVar` slots, the
  `Unify` arm) gets exec-existence only - the vacuous arms stay documented,
  not asserted.  TupE additionally has a sharp observation: its lowering is a
  sequence of `Sset lower_res` writes, so the claim is "the final temp env
  holds the *last* ret's encoding" - no tuple-value claim, the kernel's tuple
  denotation stays out of the cone.  Lambda/delay values never reach the cone:
  `app_node_ok_shape` pins heads to `Ret (VPrim p)`.
- **Spelling ledger (each cost a probe run).**  Rocq 9.1: `rocq c`, not
  `rocq v`.  `rocq c` searches `.vos` first, so `-Q` against the kernel store
  tree failed while `ROCQPATH` (the devShell still exports the deprecated
  `COQPATH` - forward it) finds the package's `.vo` set.  Bare numerals inside
  CompCert-imported scopes stay broken (§ 13.8) - the probes spell literals as
  `Zpos (xI (xO xH))`.  `apply Clight.eval_Ebinop` errors "unable to find an
  instance for v1, v2" (those occur only in premises); `eapply` fixes it.
  `Search` with multi-term patterns died with unrelated type errors on lines
  that compiled fine elsewhere - `About`/`Check` are the reliable spellers.
  `Clight1.exec_stmt` is a transparent `Definition` (`exec_stmt
  function_entry1`), so generic constructor `apply` works after one `cbn`.
  Operational note: scratch under `/tmp/opencode` proved volatile across
  sessions - which is why this probe set is committed under docs/probes/p519/
  instead of living only in the probe dir.

**Cone audit implementation (T6 increment A, landed with `coq/Realize.v`).**
The second scope from decision 10a runs inside the `timbda-kernel`
buildPhase: `rocq check -silent -o -Q _build/default Timbda Timbda.Realize`
- rocqchk re-checks the module and its entire transitive cone and prints
only the CONTEXT SUMMARY.  What gets pinned is that summary's axiom block:
**thirteen** fully-qualified names - the six derivation-level axioms above
plus the cone's transitive CompCert surface (`Events.inline_assembly_properties`,
`Events.external_functions_properties`, `ProofIrrelevance.proof_irrelevance`,
`compcert.lib.Axioms.proof_irr`, `Ensembles.Extensionality_Ensembles`,
`x86_64.Archi.win64`) - and the sweep additionally requires the
type-in-type / unsafe-(co)fixpoint / positivity sections to read `<none>`
and greps `Admitted` out of the cone log.  The kernel sweep above it is
untouched (n = 1, `eq_rect_eq`), which holds because `Realize.v` prints no
`Print Assumptions` of its own - forbidden in its header, since its output
would land in `build.log` and break the kernel audit.  rocqchk spellings
that cost a measurement each: pass the library name, not the `.vo` path
("contains library Timbda.Realize and not library Realize"); `-o` is the
assumption dump; `-norec` is a trap here - it re-exports Stdlib internals
as "axioms" instead of summarizing what is used.

**T6 increment B (landed 2026-11-25; probe p524, sources at docs/probes/p524/; PLAN
decision 11).**  `coq/Realize.v` now carries the general induction: `T6_exec_ws`
(`ws_expr d e = det_struct e = range_ok e = true` gives a `Clight1.exec_stmt`
derivation of `clight_of (lower e)` from `ge0`/`Clight.empty_env`/`PTree.empty val`/
`Mem.empty` out to `Out_normal`, with the final `lower_res` pin equal to the monadic
fold `lower_final e (le ! lower_res)`) and its `d = 0` corollary `T6_exec` at `le0`.
The fold replaces an earlier `lower_final`/`lower_get` pair that was unsound for Seq
(a `Some` write followed by a `None` claim).  The bridge layer (z64/prim_clight +
`sem_*_long`, which pin CompCert's own semantics of `Cop.O*` at `Int64.int`) and the
guard transfer (`prim_guard_ok`, `prim_guard_ok_canon`, `odiv_ready`) settle decision
10d's three-way correspondence for every admitted App shape, including the PDiv
guards, discharged from `app_node_ok_shape`'s three paths.  Arm skeletons mirror
`T7_no_switch_ws` (Lower.v), including the bans-discriminate arms for Glob/Choice/
Fail/Iter.  Toolchain findings that shaped the proof text (measured, not guessed):
multi-goal `match goal`/`solve` in Rocq 9.1 dispatch silently under-covers after
nested `destruct`s - only an explicit per-prim bullet dispatch is trustworthy;
`destruct ... eqn:E` rewrites hypotheses that contain the destructed term (and in
that case E's own statement is rewritten too, often into uselessness);
`discriminate` is syntactic - two conversion-equal hypotheses with different hidden
implicit args don't discriminate, rewrite one into the other first; `apply` fully
applied (`apply (lemma a b le H)`) is the safe bracket-free form when premises are
already hypotheses.  The cone sweep saw the increment unchanged: same thirteen
pinned axioms, all `<none>` sections intact.

### 13.15 T6 increment C: the div semantics fork measured, closed by a floor fold at lowering (landed 2026-11-26, probe p528; PLAN decision 12)

**The fork (measured, not assumed).**  The kernel's `Z.div` (`Syntax.v
prim_total`'s PDiv arm) is a true FLOOR: `Z.div 7 (-2) = -4`, `Z.div (-7) 2 =
-4` (`floor_literal_neg/pos`).  CompCert's `Int64.divs` is
`Int64.repr (Z.quot (signed .) (signed .))` (`Integers.v` 193): TRUNCATION on
the signed views - `Int64.signed (Int64.divs (repr 7) (repr (-2))) = -3`
(`divs_floor_gap_neg/pos`); `Int64.mods = repr (Z.rem .)`, dividend-signed.
The dialect's `divZ` (`TimbdaCanonicalization.cpp` 176-183, fold site :359) is
truncation plus the C99-style ladder correction (`q -= 1` iff `r <> 0` and
`sign r <> sign y`); the Coq mirror `divZ_ladder` and `divZ_ladder_div` pin it
to `Z.div` exactly - five rungs (`divZ_exact`, `divZ_same_pos`,
`divZ_same_neg`, `divZ_mixed_pos_neg`, `divZ_mixed_neg_pos`: the mixed-sign
inexact quadrants overshoot by exactly 1) plus a four-quadrant case split
through `Z_lt_ge_dec`.  Proof routing that actually works here: `lia` refuses
div/quot identities head-on against symbolic operands ("Cannot find witness");
route through `Z.div_unique` (its side condition is the disjunction
`0 <= r < b \\/ b < r <= 0`) and shield `Z.quot`/`Z.rem` atoms with
`set (q := Z.quot x y) in *.` because the div/rem rewrite pattern derails
`ring` ("not a valid ring equation").

**The ruling (decision 12).**  The fork is closed at LOWERING time.
`Lower.prim_expr`'s PDiv arm constant-folds
`Clight.Econst_long (Int64.repr (Z.div (vint_z a) (vint_z b))) tint64` - the
dialect fold's Coq counterpart - and `Realize.v`'s `prim_clight` mirrors it
arm for arm; `z64` moved from `Realize.v` to `Lower.v` because the fold needs
it at the `prim_expr` arm and the import arrow only points `Realize -> Lower`.
No `Cop.Odiv` node is ever emitted, so CompCert's truncating runtime division
and its guard ladder play no part in T6: `odiv_ready` stays in the file as a
measured bridge, permanently unreferenced by the eval dispatch.  Soundness
inside the checked domain: operands are pinned literal by `app_node_ok`, the
fold reads them through `vint_z = Int64.signed . z64` (and `vint_z_VInt` says
that is exactly the kernel Z for `int64_range` operands), an out-of-range div
result fails `prim_node_range_ok` and is excluded from T6's claim, and
`prim_total`'s `Z.eqb b 0 = false` PStuck guard keeps the kernel-side meaning
of a zero divisor (`Z.div` itself is total, 0 at 0, so the Coq side has no
partiality to smuggle in).  The fold's literal check:
`Lower.prim_expr PDiv [VInt 7; VInt (-2)] = Econst_long (Int64.repr (-4))` -
guard-free, while the old arm would have evaluated to -3.

**Correspondence lemmas (increment C; landed inside `Realize.v`, now in the fan-in leaves
described below).**  Repr-level
arith bridges (`bridge_add/sub/mul/neg`: `Int64.eqm_samerepr` fed by
`eqm_unsigned_repr`, unconditional at the repr level) give the arith map
`prim_match_add/sub/mul/neg`: `prim_clight p [...] = clight_of_val` of the
kernel result.  Signed-level cmp bridges (`bridge_cmp_Cgt/Clt/Cge/Cle/Cne`,
`zlt` destructed and the `Z.ltb` side pinned through `Z.ltb_lt/Z.ltb_ge`) give
the guard map as the two-way `prim_guard_match_P*` pairs: kernel guard success
`<->` observed `Vint (Int.repr 1)`, with `leb_as_or_lt_eq`/`leb_as_neg_lt`
translating `prim_total`'s `leb`-spelled guards into the `ltb || eqb` spelling
the CompCert side produces.  `int64_eq_signed` (Int64.eq compares UNSIGNED
views) runs through `signed_eq_of_eqm` and `signed_eq_of_mod_eq`.  The corner
denotation is exact: `denote (prim_corner p [VInt x; VInt y]) 6%nat` (the fuel
is 6 - `Checks.v`'s `e_fuel` TupE arm is `S (S (sumE ..))`, not the 5 the
earlier notes assumed), normalized by a `cbv` pass over the evaluator
constants because Rocq 9.1's `cbn` is by-name and leaves the monadic
beta-redexes.  The composition theorems (`T6_T4_match_add`, `T6_T4_match_PGt`,
`T6_T4_match_PDiv`) then glue the T4-side witness (the denotation equals
`sret (SOk ...)`) with the T6-side witness from `T6_exec_ws` (execution to
`Out_normal` with the `lower_res` pin), the pin rewritten through
`lower_final`'s App arm into `prim_match_*`.

**Spellings that cost a measurement each.**  `cbn [vint_z z64]` unfolds `z64`
but silently refuses `vint_z` (an applied constant sitting under `Z.div`),
even bare `cbn` and with `vint_z` in the delta list - `unfold vint_z` does
fire.  An `Int64.repr`-based value claim without range hypotheses is FALSE
outright (`Int64.signed (Int64.repr z) = z` only inside the signed window), so
`prim_clight_floor_div` carries `int64_range` hypotheses as substance, not
decoration.  `lia` cannot prove `S (1 + S (S (1 + (1 + 0)))) = 5%nat`
("Cannot find witness"); a full `cbn` after the delta-listed one closes it.
Fuel literals are `nat` - a `Z`-scope `5` is a type error, so `6%nat`.
`Z_lt_dec` in 9.1 is a 3-way sumbool; use `Z_lt_ge_dec` for a binary split
(destructing a `Z` directly gives 3 constructors).  `rewrite` with a
hypothesis-bearing lemma puts the MAIN goal first in the bullet sequence
(`apply` puts it last) - dispatch accordingly or closers leak.  `Realize.v`
imports no `ListNotations` and does not see bare `eqmod` (it is `Zbits`'s):
the increment-C section opens both locally.

**Build-unit split (same day, measured under failure).**  With increment C landed as one ~750-line
section in `Realize.v`, the box died twice silently - dune RC=1 with no Coq error line and no
`Realize.vo`, then a direct `coqc` RC=143 - while `strata-host` measured 41.5 then 50 GiB RSS
against 64 GiB of RAM (sec. 4.1's kill signature, exactly).  The realization side was restructured
fan-in the same evening: the increment-C text moved *verbatim* into four leaves -
`RealizeBridges.v` (the Int64<->Z bridges plus the signed-window facts), `RealizeDiv.v` (the div
fork measurements: rungs, ladder, gap literals, `bridge_divs_quot`), `RealizeCorners.v`
(`prim_corner`, the arm-equation corner machine, exact corner denotations at `≅` - sec. 13.16) and `RealizeCompose.v` (the maps, the fold
read back through them, the `T6_T4_match_*` compositions) - while `Realize.v` stays the
CompCert-side hub the leaves read (guards, `lower_final`, the eval bridges, `T6_exec_ws`).  Each
future increment lands in its own leaf - increment D (CertiRocq->C) never by inflating the hub -
so a single coqc unit is bounded by the hardest *one* theorem, not by accumulated history.  With
it, `coq/dune-workspace` dropped `(jobs 2)` to `(jobs 1)` (sec. 4.2): a 15 GiB-class unit survives
alongside the model server, two concurrent ones do not.  The flake cone sweep now checks the two
roots `Timbda.Realize` and `Timbda.RealizeCompose` (the Compose root pulls every leaf in
transitively); the thirteen-axiom pin must re-attest against the new roots at the landing gate.

### 13.16 T6 increment C, part 2: the corner denotations restated at ctrees' structural equality (landed 2026-11-26, probe p528 continuation; decision 12f)

**The memory blowup was a misstated goal, not a missing trick.**  The first fan-in draft spelled
the corner denotations as Leibniz equalities (`denote corner 6%nat = sret (SOk v)`) and tried to
normalize them with a full `cbv` (`denorm`).  Measured 2026-11-26: on the add corner the
`kernel_cbn` ladder takes 1 s at fuel 4, 18 s at fuel 5 and stalls beyond 90 s at fuel 6;
`cbn [denE]` on the TupE arm alone expands ~200k lines; `vm_compute`/`native_compute` stall on the
same terms; every fuel-2 variant normalizes instantly.  The uncapped 61 GiB `rocqworker` that
earlyoom shot was exactly this shape.  Root cause: `>>=` desugars to ctrees' `CTree.bind u k :=
subst k u`, and `subst` is a **CoFixpoint that only unstucks under `observe`** - no delta list can
fire it, and strict evaluation re-materializes the stuck cofix tower once per fuel layer.  A bind
chain is therefore *never* Leibniz equal to a `sret`: the statement itself was wrong, and no
reduction strategy can fix a false goal.  ctrees' own monad laws exist only at `equ`/`wbisim` -
the library's own admission (pinned commit `cabcf9bf`, Core/CTreeDefinitions.v).

**The ruling (decision 12f).**  Corner denotations are pinned at `≅` (`equ eq x y`, via
`Import EquNotations`) - the same equality Denotation.v and Checks.v already use for every monadic
fact - and proved by the **arm-equation machine**: every `denE`/`denE_tup`/`apply_c`/`iter` arm is
transcribed as a `reflexivity`-level unfolding equation (`denE_App_S`, `denE_tup_cons_S`,
`apply_c_VPrim_S`, ...), rewritten at the head one arm per step; binds fire through
Denotation.v's `bind_sret_l`; closure is a negative-delta pass (`cbn -[denE denE_tup apply_c ...
Z.eqb Z.ltb orb]`) that delta-BLOCKS every fixpoint, so re-opening the fuel tower is impossible
*by construction*.  Linear by design (one arm per rewrite), the whole `RealizeCorners.v` leaf
compiles in ~2 s.  The three `T6_T4_match_*` conjuncts carry the `≅` side verbatim into
`RealizeCompose.v`, where the CompCert pinning side is unchanged.

**cbn's revert semantics (measured).**  `cbn` with a delta list refuses to δ-unfold a constant when
the unfolded subtree is stuck, and the refusal propagates: `cbn [det_struct bans_okE ...
app_node_ok ...]` on the PGt corner returns the goal UNCHANGED.  Guard-bearing structure claims
therefore route through one-line equations (`prim_total_res_PGt_true`, `prim_total_res_PDiv_true`)
rewritten after an explicit `unfold` prologue (`hds_corner_prologue`), with cbn finishing only the
mutual guards it can reduce.  Related substance: `prim_args_ok` is the *structural*-prim arity
check (false for PGt/PDiv), so `det_struct` of a failed-guard corner is genuinely false - T6's
hypotheses are load-bearing, and the guard map `prim_guard_success_PGt` reads the iff forward
through the guard hypothesis.

**Toolchain traps from the same landing** (each cost one compile round; full list in
docs/probes/p528/README.md): `cbn []` and `cbn [a, b]` are syntax errors in 9.1 (delta lists are
space-separated; the all-blocked spelling is `cbn -[a b]`); `unfold a b` likewise needs a comma;
cbn does not unfold `denote`/`prim_corner` sitting in `equ` argument positions - enter goals with
`unfold`; `Z.eqb`/`Z.ltb`/`orb` must stay delta-blocked or the guard hypotheses lose their match;
`Stdlib.Bool` stays un-imported (the `&&&` ruling) so PGEq's guard is spelled `orb (..) (..)`;
`WBisimNotations` re-registers `&&&` at level 59 and clashes with compcert Coqlib's level-40 one -
the CompCert-facing leaf imports `EquNotations` only; the conjunction notation `/\'` rejects binder
terms on either side (use `/\` with parentheses); and `Local Open Scope Z_scope` retypes bare
numerals, so fuel arguments need `0%nat`/`6%nat`.  The gate's cone sweep re-attests the same
thirteen pinned axioms over `Timbda.Realize` + `Timbda.RealizeCompose`.

### 13.17 M2's compile increment planned as a fold-specialized hylomorphism: probe p529 measures the shape, the budget law, and an axiom cost of zero (measured 2026-11-26; PLAN decision 14)

**The § 13.16 diagnosis, read forward.**  13.16 established that a bind chain is never Leibniz
equal to a `sret` because `>>=` is ctrees' corecursive `subst`, unstuck only under `observe`.
The structural reason is that *no fold was chosen*: with the carrier left as `ctree` itself, the
only available equalities are the library's `≅`-level monad laws.  The pinned library carries the
alternative all along - `Interp/Fold.v:29-45`, a `fold` into a monad `M` with the loop operator
supplied *by `M`* - alongside its own warning that generic-`M` results need "heavy
axiomatization" and it "simply specializes results to specific `M`s" (`FoldCTree.v:25-29`).
Probe p529 specializes it and measures what that costs.

**What was built and measured** (docs/probes/p529/, two files, 17 goals, every proof
`reflexivity`, each file 0.42-0.43 s at ~454 MiB peak - the import cost, not the proof cost).
The target monad is inline state plus a three-conclusion result: `M X := st -> MRes X`,
`st := {fuel; ofrag : list Instr}`, `MRes = MDone frag x | MLoopR frag | MTrap frag`, and `iter`
is a fuel-decreasing `Fixpoint` whose exhausted case *emits an `i_loop` instruction and returns
`MLoopR`* - the resumption boundary is an emitted instruction, and the carrier is never
demanded.  Part B runs this against the kernel's real signature `ctree void1 B2 SResult` fed by
`denE` directly, arms `Ret`/`Fail`/kernel-fuel `SStuck`/`Choice`/`Seq`/`Seq∘Choice`, both a
left-candidate and a right-candidate scheduler.  `Print Assumptions` on four of the goals:
**`Closed under the global context`** four times - the hylo path adds no axioms, and the 13-axiom
cone belongs to the bisimilarity/certiRocq side only.

**Three rulings the measurements force** (decision 14).  (1) **The budget law:** the fold spends
one observation per arm, `RetF` included; fragment length is bounded by fuel by construction.
This is the § 4.2 memory discipline ("proportional to one instruction, never to one program")
promoted from tactic hygiene to a property of the compile's shape.  (2) **Two stucks,
permanently distinct:** kernel fuel exhaustion is a *result* (`SStuck` propagating through `>>=`;
measured by `Compute`: `Seq (Choice (Ret 1) Fail) (Ret 2)` at kernel fuel 2 compiles to
`MDone [i_branch_left] SStuck` - a `MDone`, no `i_loop`), compile fuel exhaustion is an *emitted
instruction* plus `MLoopR`.  13.16's category error stays guarded by keeping both goals adjacent.
(3) **The branch algebra is the candidate decision:** `br2 t u = br branch2 (if b then t else u)`
with `branch2 : B2 bool` - the two compiles of one `Choice` tree differ only in the bool the
algebra returns, and a polymorphic `g : B2 ~> M` must first *pattern-match the branch token* to
force the payload equation `X = bool`.  The determinacy analysis is precisely the license for
returning *which* bool, and `FoldCTree.v`'s counterexample (a branch-resolving fold need not
preserve weak bisimilarity) is RULES-AUDIT sec. 4's horn restated: the emitted C is defined on
determinate programs - the same hypothesis that makes the coalgebra side a function, i.e. that
makes the compile a hylomorphism rather than a relation.

**The regime split, stated once.**  `=` reaches the target side because the algebra is chosen and
the fold is fuel-bounded: even `Seq`'s `>>=` spine compiles arm-by-arm (`subst` under `observe` on
a `RetF` head *is* the iota step; `Seq` of two returns costs zero emitted instructions).  `≅`
stays where no fold is chosen (source-side monad laws, `RealizeCorners.v`, `RealizeCompose.v`).
`≅`-only "monad laws" are not a wart to repair; they are a flag that a fold is missing.  This is
the answer to the observation that the § 13.16 correction was disturbing: the correction was not
a retreat from `=`, it was the discovery that `=` requires planting a fold first.

**What the leaf will therefore be** (`coq/Compile.v`, its own leaf, hub untouched): `h : void1 ~>
M` empty; `g : B2 ~> M` the scheduler whose bool is justified by the hub's determinacy lemmas;
`compile := fold h g`; per-arm fusion lemmas in the `reflexivity` regime; correctness as a
`cog`-simulation composed with the existing `T6_T4_match_*` bridges, not an equality of normal
forms.  Guard rails, so the framing stays load-bearing: no `bind` on the compile path (it survives
only in the `Monad` dictionary), no whole-program normalization in any proof, and the fusion lemma
stated and used.  The ordered-vs-bag carrier question (RULES-AUDIT sec. 4) is *not* closed by
this probe - probe fact 3 makes it sharper: the carrier question is now operationally "which bool
for which program", and it must be ruled when `Compile.v` is written.  `FoldStateT.v` (a `stateT`
wrapper with `Typeclasses Opaque`, `iter` inherited from an inner monad) is ruled a distraction;
the inline state is where the resumption policy lives.  The toolchain traps measured here
(pattern-level `@` for parameterized inductives, explicit binders for class fields, `MonadIter`'s
`{R I}` order, term-position empty matches needing `return ... with`, `Import ListNotations`'s
module-path rule) are archived in the probe README, where their re-measurement recipes are.

### 13.18 The carrier question ruled by material compatibility: scoped commutativity, materialized observation nodes (ruled 2026-11-26; decision 15; closes RULES-AUDIT issue #1)

**Why it had been kept as a question.**  Decision 14 flagged the carrier open because a ruling is
only worth recording if the excluded readings fail on *named lines*, and the named-line audit had
not been run: reading (A), ordered collapse at compile time, initially looks compatible - "ordered
choice, `one` leftmost" is verbatim the route VC walks in print (issue #1).  The ruling is the
audit, and it turns (A) and (B) into material incompatibilities rather than matters of taste.

**The five anchors and what each decides.**  (1) **Fig. 13 splits; it never collapses.**
VERSE-RULES § 3.4's `IterChoice` row is the paper's *candidate-splitting* rule:
`iter(ic){B[C[b1 b2]]}{e} ⟶ iter(ic){B[C[block{b1}]]}{iter(ic){B[C[block{b2}]]}{e}}` - choice
compiles into nested observable structure.  A compiler that resolves an indeterminate `br2` into
one priority path is doing something the paper's own rule does not do.  (2) **The combs ARE the
scopes.**  `IterComb : IAll | IIf | IFor` (Syntax.v:48): the paper distinguishes observation modes
*in the syntax*, and `iter(if)` carries a first-candidate reading (issue #1) - priority exists in
print exactly where an observer exists, and nowhere else.  (3) **The candidate set is the meaning.**
T2 says the algebra "mirrors the paper's candidate-set claims"; T8 pins
`candidate_set (eval_run e) = candidate_set (sem e)`.  Collapsing a genuine multi-candidate program
to a single run at compile time contradicts T8; collapsing where determinacy *already makes the set
a singleton* is exactly the fusion side of the ruling - which is why decision 14's determinate-site
probes (`b_choice`: the bool forced by which arm has a candidate) survive unchanged.  (4) **(B)
contradicts the transcription it was meant to save**, (`iter(all){1|2}{⟨⟩}` rewrites to the distinct
ordered values `⟨1,2⟩` and `⟨2,1⟩`) and needs permutation-invariance of compiled output, which
`FoldCTree.v`'s counterexample says no branch-resolving fold can supply in general.  (5) **The
runtime layers are the nodes' landing sites.**  boost.context is carried in the plan as
setjmp/longjmp-like re-enterable control, and the WAMI/DCont leg as WebAssembly stack switching;
under this ruling they stop being an optimization annex and become where indeterminate programs'
semantics is decided - decision 2's sentence ("which steps fuse into straight-line C and which
materialize a stack switch") becomes a stated fusion lemma about the algebra map `g`, and T12/M4/M5
inherit a reason to exist.

**What changed in the tree, and what did not.**  Changed: PLAN § 3's T2 sentence (scoped in
place); issue #1's owed ruling (closed as "restricted reading, materialized"); decision 14(d)'s
`g` (fully specified: forced bool at determinate sites, choice-node emission plus the `inl`
residual at indeterminate sites - probe p529 part A's `i_loop`/`MLoopR` is the mechanism, the
future `i_choice` its generalization); the golden test's expected fragments for the corpus's 7
candidate-bag cases (they will contain choice nodes); M3's owed iter ruling (pre-decided:
`RewSound_IterChoice` and `RewSound_IterAll` both pursued under the scoped law).  Unchanged: the
discharged lemma stack (`Br2_Commut_W`/`Br2_Idem_W` remain true as wbisim facts - the reading
restriction is about what may be used as a *code-level rewrite*, not about their truth), the corpus
lane (cand_bag's list is a collection order; its bag claims stay valid under the scoped law), and
every `≈`/`≅` denotation-level proof landed so far.
