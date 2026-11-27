# Infra and build possibilities — parking lot

What this file is: the ledger for **workflow-infrastructure candidates** — tools and
build-loop ideas evaluated against timbda's actual loops (gate lanes, probes, leaf development,
golden test) but not yet stipulated. It is deliberately *not* PLAN § 6 (stipulated build
infrastructure: everything there is decided and load-bearing), not § 9 (claim anchors: what the
theorems stand on), not § 7 (ranked risks), and not the decision log (ruled things). The one
hard rule: **nothing is adopted here.** Adoption is a move — an entry in PLAN § 6 plus a decision
log item — after which the ledger line records only the pointer. Statuses: `parked` →
`evaluating` → `adopted (PLAN § 6 + decision N)` / `declined (reason)`.

Entry format: date · source · claim · which timbda loop it maps to · measured-or-expected cost ·
status. Each entry stays under ~15 lines; findings that outgrow the ledger become their own
probe under `docs/probes/`.

---

## T-001 · `rq` — persistent named Rocq proof sessions (Brockman)

- **Date / source.** 2026-11-26; `mbrock/filnix`, `nanofil/rocq/scripts/glibc-tools/rq/`
  (Python CLI + OCaml `worker/`), `nanofil/nix/rq-worker.nix`; documented on the Filnix wiki
  (`filnix.org/nix/nanofil-nix-rq-worker.html`). Context: nanofil is Brockman's Prolog C
  compiler with a Rocq-checked-IR campaign; `rq` serves its glibc-proof campaign, not the
  compiler itself.
- **Claim.** Each session (`R1`, …) is one long-lived worker process keeping a warm Rocq state
  (it links `rocq-core`'s parser and interpreter); every CLI call sends one JSON request over a
  Unix socket. Sentence-level transactions: `step` commits everything before the first failure;
  `try` forks candidate tactics from the same state (`--commit` keeps the first success); `back`
  drops the last N; `reload` replays an edited file from the first changed byte and restarts
  only when an imported object actually changed. No time limit per sentence; Ctrl-C stops only
  *waiting*, `cancel` interrupts the running sentence and keeps prior commits.
- **Maps to.** The probe/leaf development loop: our probe family pays the ~450 MiB CTree import
  per file per iteration (import cost, not proof cost) — a warm session makes each probe edit
  cost one sentence, not one recompile; directly relevant to the corner-by-corner `Compile.v`
  sequence in docs/COMPILE-STRATEGY.md. Same-toolkit resonances worth noting: its sessions are
  systemd transient services in their own `rq.slice` with cgroup `memory.current`/`memory.peak`
  reporting and `oom-killed`/`throttled`/`reclaiming` notes — and *without* a systemd user
  manager it reports `/proc` RSS and **refuses** requested caps "since it could not be
  enforced", the same placebo-cap ruling as `tools/build/nix-gate.sh`'s header (decision 13).
  Its honesty caveat ("Qed passed in session" ≠ "file passed the batch build") mirrors our
  probe-green ≠ gate-green split; it even ships a `verify` bridge (`rocq c -vok` over the saved
  file) for that gap.
- **Cost.** Unknown for us; its own build is Nix-built on demand from a pinned worker scope
  (Eio 1.7 + uring overrides scoped so proof libraries are not rebuilt). Adoption cost would be
  a session-lifecycle discipline around it: session files, `dropped.v` replay, and keeping the
  gate as the sole attestation authority (sessions never bypass it).
- **Status.** `parked`. Revisit when `Compile.v`'s per-arm lemma flow starts paying the
  re-import cost measurably; if it earns evaluation, run it as a probe (`docs/probes/`) against
  the current `nix develop .#rocq` loop before any PLAN change. Strata: tag "rq"/"parked".

## T-002 · `rocq-lsp` in the rocq devShell (already in service, unledggered until now)

- **Date / source.** Stipulated since M-1; PLAN § 6 devShells line:
  `rocq(withPackages + lsp)`.
- **Claim.** Editor-facing language server for the kernel tree; present in the devShell but with
  no recorded evaluation, and distinct from the CLI loops actually used day-to-day (batch
  `dune build` for gates, `coqc` for probes).
- **Maps to.** Human editing of `coq/*.v`; candidate overlap with T-001 (an LSP keeps a stateful
  session too; `rq` is the CLI-shaped sibling for terminal/agent workflows).
- **Cost.** Already paid (part of the devShell) — the debt is documentary, not computational.
- **Status.** `in use, undocumented` → candidate for a short evaluation entry if the editor loop
  ever becomes a first-class part of leaf development. If T-001 is adopted, decide the pair
  together (one interactive-loop story, not two).

## T-003 · Warm-the-gate: cgroup-capped client-side drv warm under the model server (in use since 2026-11-26)

- **Date / source.** Measured while landing M2 increment D1 (2026-11-26): the pinned gate
  (`TIMBDA_NIX_GATE_MIN=5G TIMBDA_NIX_GATE_GUARD=8 NIX_CONFIG="cores = 2"`) killed the kernel
  and corpus-differential lanes at its 5120 MiB watchdog floor TWICE on an idle run — the
  daemon-side Coq rebuild crossed 6.9 → 5.1 GiB available while the local model server is
  resident (~54.5 of 63.9 GiB). The daemon build is invisible to the host cgroup that caps
  `coq-build.sh` (same lesson the gate's own watchdog exists for), so the measured host-lane
  peak (~0.5 GiB) understates it.
- **Practice.** Before the pinned gate, warm exactly the heavy drv's CLIENT-side inside a cap:
  `systemd-run --user --scope -p MemoryMax=6G -p MemorySwapMax=0 --quiet bash -c 'nix build
  --no-link --cores 2 --max-jobs 2 .#packages.x86_64-linux.timbda-kernel
  .#checks.x86_64-linux.corpus-differential'`, then run the pinned gate, which attests them
  from store (`rc=0`, `elapsed 0s`, watchdog kills 0). Data-structure fix (store warm +
  client-side cgroup), not a system-service fix: the gate still pins the same drv's and
  their buildPhase audits (single-axiom kernel gate, 13-axiom cone diff) must pass for the
  warmed outPaths to exist at all.
- **Traps measured.** `NIX_CONFIG` takes one entry per line (a space-separated string parses
  `cores = 2 max-jobs = 0` as one invalid value); `max-jobs = 0` DISABLES local builds (it
  means "delegate to the daemon"); a nonzero value builds client-side. When outputs are
  cached, the gate's per-target log is empty — the buildPhase audit evidence lives in the
  warm build, whose nonzero exit is what catches a failing audit. Docs-only commits don't
  dirty the kernel drv (its `src` is `./coq`), so docs gates stay light even warm.
- **Status.** `in use`. Not a substitute for the watchdog (which stays armed for anything NOT
  warmed); revisit if the model server stops being resident or the lanes' memory profile changes.

### T-004: regenerating the golden-compile artifacts (D4b, 2026-11-27)

`tests/golden-compile/golden.c.expected` and `golden.stdout` are NEVER hand-edited.
They are regenerated only from the lane itself - the check derivation IS the
regeneration (one source of truth; a hand-run reproduction must replicate the
driver's `ListNotations`/`string_scope` openings, which is exactly why the lane,
not a shell recipe, is authoritative):

```sh
TIMBDA_COQ_MEMORY_HIGH=2G TIMBDA_COQ_MEMORY_MAX=3G TIMBDA_COQ_MIN_AVAIL=1G \
  nix develop .#devShells.x86_64-linux.rocq -c tools/build/coq-build.sh        # 19 .vo gate
nix build --no-link .#checks.x86_64-linux.golden-compile                       # rebuild with the current tree
OUT=$(nix build --no-link --print-out-paths .#checks.x86_64-linux.golden-compile)
diff -u "$OUT/golden.c.actual"    tests/golden-compile/golden.c.expected
diff -u "$OUT/golden.stdout.actual" tests/golden-compile/golden.stdout
```

An intentional change to the compile algebra shows up as a diff here *before* it
shows up in the gate - which is the point: a golden edit is a decision, so it lands
in the same commit as the decision that justifies it (the README table changes in the
same sweep).  A diff nobody can explain is a mis-emit; the lane fails closed.

### T-005: the push task (2026-11-27) — milestone table + GitHub About in the ritual

`tools/pins/milestones.toml` is the **milestone table of record**: one entry per
milestone (id, one-sentence summary, status, closure date when PLAN dates it, and
an `about_line` for the repo's About section).  Three surfaces assert it:

- `checks.milestones-consistency` in the gate chain (default chain now TEN lanes),
  and the CI pins job run `tools/pins/milestones.py check`: the README "Milestones
  at a glance" table must mirror the table row-for-row (anti-vacuity: missing rows,
  extra rows, or a missing section are all FAILs), PLAN must record the closure
  dates the table claims, and the derived About string must fit GitHub's 350-char cap.
- `tools/build/push-task.sh` is the **fast, verifiable tail of the landing ritual**,
  run after the pinned gate chain is green: milestone check -> bookmark `main` to @
  (recording the full commit id) -> `jj new` -> `jj git push` -> `git ls-remote`
  verification that `origin/main` is exactly the bookmarked commit -> `gh api`
  PATCH of the repo About, composed from the latest dated CLOSED milestone,
  verified by round-trip GET.  The gate stays a separate (long) step; the Strata
  memory note stays the agent-side last step.
- A milestone transition MUST edit `milestones.toml` in the same commit as its
  PLAN closure block - the check makes a stale README a red gate, not a todo item.

When a returning reader should see it: README table (statuses + one-liners,
mirrored from the table of record) and the GitHub About ("Latest milestone: ...
Next: ...").
