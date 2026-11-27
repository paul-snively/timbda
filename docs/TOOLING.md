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
