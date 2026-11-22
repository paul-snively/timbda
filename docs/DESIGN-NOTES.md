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
tools/build/nix-gate.sh                                   # the four gate builds below, --max-jobs 1, and
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

**Concurrency is baked into the project**, not auto-detected: `coq/dune-workspace` sets `(jobs 2)`.
(dune requires `(lang dune 3.21)` as the first line of that file, and `(jobs 2)` is a top-level
field - writing `(dune (jobs 2))` gives `Invalid first line` / `Unknown field "dune"`.)  dune's
auto-detection picked 20-way concurrency on this 20-core box, which is a self-inflicted OOM before
Strata is even considered.  Override on a quiet machine with `dune build -j 8`, go lower with `-j 1`.

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

**The nix half of the gate cannot be capped from inside the repo, and that is a measured property of
this machine, not an opinion.**

- nix here is daemon-managed: `nix-daemon.service` runs as root (Determinate Nix 3.24.2, nix 2.35.3),
  `Slice=system.slice`, `MemoryHigh=infinity`, `MemoryMax=infinity`; `/nix/store` is not writable by
  the calling user.  So `systemd-run --user --scope -p MemoryMax=…` wrapped around a `nix build`
  caps only the *client* process: the sandboxed `nixbld*` worker that actually runs `coqc` lives in
  the daemon's cgroup tree, where `memory.max = max`.  Wrapping a nix build in the same scope that
  contains `dune build` would be a placebo, and a build that *looks* contained while uncapped is the
  exact failure mode § 4.2 exists to prevent.
- `nix show-config` here: `max-jobs = 20`, `sandbox = true`.  `coq/dune-workspace`'s `(jobs 2)` limits
  dune inside **one** derivation; it says nothing about how many derivations nix builds at once, and
  `nix build` with several targets on a 20-core box defaults to 20.

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
  (`nix-daemon.service` has `MemoryMax=infinity`, so the honest answer is "it may well have").  Measured
  today: `TIMBDA_NIX_GATE_ALLOW=yes … .#checks.x86_64-linux.corpus-differential` on a host with 6706 MiB
  free and a 8192 MiB floor → the watchdog fired on its first poll, the target got
  `rc=124 … STOPPED … (target not attested)`, and no `nixbld`/`rocq`/`dune` worker was alive 20 s later.
- the same exit-code discipline as `coq-build.sh`: 0 green, 1 a nix failure, 2 refused by preflight,
  124 stopped by the host watchdog - and a target stopped by the watchdog is listed as *not attested*
  rather than as failed-or-passed.
- `--max-jobs 1` (nix's default is 20), per-target rc capture, and the earlyoom / kernel-OOM journal
  windows printed after the verdict, so "the gate is green" and "the host was healthy" stay two
  separately reported facts even when both are true.


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

- The nix daemon cgroup is **`MemoryHigh=4.0G` / `MemoryMax=5.0G`** (`/etc/systemd/system/nix-daemon.service.d/override.conf`,
  re-read live: `MemoryHigh=4294967296`, `MemoryMax=5368709120`, `DelegateMemory=auto`,
  `DelegateFragment=…Max=5368709120…`).  § 10 recorded 5.4G/7.4G on 2026-11-19; that envelope is
  now a dated reading, not the live setting, and the difference matters operationally: at a 5G
  daemon ceiling a daemon-sandboxed *kernel* build (peak 20.2 GiB, § 4.3) is not a thing to attempt,
  which is precisely why § 4.3's split - `coq-build.sh` for kernel-scale builds inside a verified
  4.0G/5.0G cgroup, the gate for the small corner/check derivations - is load-bearing and not
  convenience.
- Swap is 20.3 GiB (`swap free 15.1-15.2 GiB`, 74.7% free) against 62.4 GiB of RAM, and `earlyoom`
  (v1.7, `/etc/earlyoom/earlyoom.env`: `SWAP_THRESHOLD=10`, `MT_THRESHOLD=10`, `--prefer
  '(nvidia|python|rocq|dune)'`) is a live service with `Nice=10`, `CPUAccounting=yes`, enabled.
  Nothing in the run windows killed anything.
- Preflight readings for the re-bill: 6820-7029 MiB MemAvailable (10.67-10.99%), swap free 15156
  MiB; held floors 5120 MiB mem / 1623 MiB swap at `TIMBDA_NIX_GATE_MIN=5G TIMBDA_NIX_GATE_GUARD=8`.
  The re-bill took 2 s and 3 s (targets rc=0), re-attesting 29 cases / 7 candidate bags for m2 and
  64 / 7 for m0 - the same counts § 11.2 records.
- A cache fact the re-bill makes visible rather than inferable: the check outputs have *new* store
  paths (`rc4g2jacvi0bvixwm0lqa0gp108md6b5-timbda-corpus-m2-differential`,
  `95ch4c3y81q67pbc92g04i4zyswrsjh2-timbda-corpus-differential`) purely because this file changed -
  both corner derivations consume the whole flake source.  Treat "the check rebuilt" as "the source
  hash moved", never as "the kernel moved", and cross-check the kernel-side numbers (1465 extracted
  lines, the four `Closed under the global context` footprints) before drawing a semantic
  conclusion from a rebuild.
