# `tools/build/` — guarded build runners

Three scripts.  None of them changes what a successful build *means*: the kernel gate is still `dune
build` plus the `Print Assumptions` single-axiom check that `flake.nix` runs (`docs/DESIGN-NOTES.md`
§ 4, § 6).  What they change is the failure modes you can *tell apart*: on this machine a build that
was **killed**, a build that was **throttled to a stall**, and a build that **failed in Coq** all look
identical in dune's output, and one of them is the thing that takes the model server down with it.

| script | covers | can it contain the build? |
|---|---|---|
| `coq-build.sh` | the dev-shell `dune build` of `coq/` | yes: it runs in the caller's own cgroup |
| `coq-probe.sh` | one `.v` file, bounded, for localising a blowup | yes (it refuses to run if the cap it was given is absent) |
| `nix-gate.sh` | the `nix build` gate chain | **no** - see the measured reasons below; it substitutes a refusal-to-start and `--max-jobs 1` |

## `coq-build.sh`

```sh
nix develop .#devShells.x86_64-linux.rocq -c tools/build/coq-build.sh
nix develop .#devShells.x86_64-linux.rocq -c tools/build/coq-build.sh -j 1     # extra args go to dune
```

**Why it exists.**  `earlyoom` fires only when **both** memory and swap are at/below 10%, and this box
has 3.9 GiB of swap against a model server holding 43-49 GiB, so the swap half is usually near-false
and one big allocation away from near-true.  From `journalctl -u earlyoom` (verbatim, this machine):

```
01:50-03:50  mem avail 82.45%, swap free 0 of 3907 MiB (0.00%)          -> no kill (mem term false)
04:26:04     low memory! at or below SIGTERM limits: mem 10.00%, swap 10.00%
             sending SIGTERM to "strata-host": badness 1238, VmRSS 42651 MiB
04:37:31     mem avail: 951 of 63916 MiB (1.49%), swap free: 364 of 3907 MiB (9.32%)
             sending SIGTERM to "rocqworker": badness 1556, VmRSS 55022 MiB
05:06:11     sending SIGTERM to "strata-host": badness 1243, VmRSS 44542 MiB
```

The 04:37 row is the whole point of this script: the biggest process earlyoom could find was a **55 GiB
`rocqworker` from this project's own build**, and the model server was shot on either side of it.  A
dry run (`earlyoom --dryrun -r 1 -m 99 -s 99`, nothing killed) shows the ordering when nothing else is
allocating: it picked `"strata-host"`, badness 1280, VmRSS 48856 MiB.

And a killed build does not look like a failed one: `coq/_build/log` ending `[got signal TERM]`, dune
exit 1 with no `Error:` line anywhere, `tests/KernelTest.vo` absent, `tests/KernelTest.glob` sitting at
exactly 131072 bytes.  Honest caveat, learned the hard way: a `[got signal TERM]` can also be the agent
harness's own command timeout killing the scope it launched - which is why the wrapper reports cgroup
`oom_kill` counts, journal kill evidence, and "neither happened" as three different verdicts.

| step | what it does |
|---|---|
| preflight | refuses to start unless `MemAvailable` covers the envelope plus `TIMBDA_COQ_HEADROOM` |
| containment | re-execs itself inside `systemd-run --user --scope` with `MemoryHigh`/`MemoryMax`/`MemorySwapMax` (defaults 2G / 3G / 0) |
| **verified** containment | reads back `$CG/memory.max` and **fails if it is not the requested byte count**.  Not paranoia: an early version of this script dropped the `-p` properties across its own `exec systemd-run`, silently produced `memory.max=max`, and let a 54 GiB compile look "contained".  A cap assumed is not a cap |
| designated victim | raises `oom_score_adj=500` on `coqc`/`rocqworker` (raising is unprivileged; lowering needs `CAP_SYS_RESOURCE`), so the *kernel's* OOM choice and this scope's own `MemoryMax` take the restartable build.  It does **not** make the build the sacrifice `earlyoom` picks - earlyoom ranks by RSS, and a capped build never outscores a 43-49 GiB model server (see `docs/DESIGN-NOTES.md` § 4.3) |
| host watchdog | samples host `MemAvailable` and swap headroom while the build runs, records the low-water marks, and aborts the build's own process group when either falls under `TIMBDA_COQ_MIN_AVAIL` (default 1G) or `TIMBDA_COQ_MIN_SWAPFREE` (default 700M).  A `memory.max` is a promise to the cgroup; the *machine* still has to find that memory, and when it cannot it swaps someone else's pages - here, the model server's |
| honest verdict | dune's own exit code + the **unfiltered** log + `memory.events` counters + the host low-water marks + the expected `.vo` set.  `oom_kill > 0` = this envelope was too small for that unit; `oom_kill = 0` with missing artifacts = killed externally, with the journal window quoted; `memory.high` counts over ~10^5 = throttled to a stall, not limited; `dune exit 0` with a missing `.vo` = vacuous build, hard failure.  A watchdog abort prints `verdict: STOPPED BY THE HOST WATCHDOG: <which floor, at what value>` and exits 124 |

Calibration, all measured on this machine:

- **warm** full kernel build, guarded: **647 MiB** scope peak, dune exit 0, all 8 expected `.vo`
  present (`HIGH=2G MAX=3G`);
- the same build while `tests/KernelTest.v` still contained one unprovable `Example`
  (`denote e 24 = denote (norm 24 e) 24`, proved by `vm_compute`): **56,588,736 kB maxrss (53.9 GiB)**,
  685 s user time, 11 min 38 s wall, exit 1.  That Example was also simply *unprovable* - `reflexivity`
  fails as `Unable to unify`, `vm_compute` at fuel 4 leaves an open goal, `vm_compute` at fuel 24 never
  finished inside a 1.6 GiB cap (540,907 `memory.high` events).  It is gone; `KernelTest.v` records the
  measurements instead (`docs/DESIGN-NOTES.md` § 4.2);
- **cold** builds (no `coq/_build`) do **not** fit in the warm envelope: `HIGH=2G MAX=3G` stalled for
  ~2 h with 251,745 `high` events, `oom_kill` 0 and a `D`-state worker at 2858516 kB;
  `HIGH=4G MAX=5G -j 1` had still not produced `_build/default/Denotation.vo` after 900 s.  The unit is
  `coq/Denotation.v` and the likely hot spot is `Ltac t1_norm := … repeat (setoid_rewrite bind_ret_l;
  kernel_cbn)` (`coq/Denotation.v:100`).  Details and the third attempt in `docs/DESIGN-NOTES.md` § 4.3;
- the watchdog path itself, tested by asking for the impossible (`TIMBDA_COQ_MIN_AVAIL=55G`): aborted in
  3 s, exit 124, named verdict line naming the floor and the measured value, and no orphaned
  `dune`/`rocqworker` afterwards.

Concurrency comes from `coq/dune-workspace` (`(jobs 2)`), not from dune's auto-detection (which picked
20 on this box, i.e. 20 concurrent `rocqworker`s - a self-inflicted OOM).  Knobs are env vars, listed
in the script header; `TIMBDA_COQ_ALLOW_UNSIZED=yes` skips containment when the point of the run *is* to
measure the uncapped peak.

## `coq-probe.sh`

A bounded single-file compile, for localising a blowup instead of guessing at it:

```sh
PROBE_TIMEOUT=120 nix develop .#devShells.x86_64-linux.rocq -c bash -c \
  'systemd-run --user --scope -p MemoryHigh=1200M -p MemoryMax=1600M -p MemorySwapMax=0 \
     tools/build/coq-probe.sh /tmp/opencode/probeA.v'
```

It **refuses to run** if the cgroup it was placed in reports `memory.max=max`, prints the cap in force,
prints the peak and `memory.events`, and judges the compile by exit status plus the unfiltered log file.
This is how the 54 GiB compile was attributed to one `Example`: three probe variants (fuel 24
`reflexivity`, fuel 4 `vm_compute`, fuel 24 `vm_compute`), each capped, each failing for its own
measurable reason.

## `nix-gate.sh` — the gate chain, which cannot be capped

```sh
tools/build/nix-gate.sh                                   # documented chain, one derivation at a time
tools/build/nix-gate.sh .#checks.x86_64-linux.corpus-differential   # or explicit targets
TIMBDA_NIX_GATE_MIN=10G TIMBDA_NIX_GATE_SWAPMIN=1G tools/build/nix-gate.sh …
```

Why it is not just `coq-build.sh` with `nix build` inside it - measured on this machine:

- nix is daemon-managed: `nix-daemon.service` runs as root (Determinate Nix 3.24.2, nix 2.35.3),
  `Slice=system.slice`, `MemoryHigh=infinity`, `MemoryMax=infinity`, and `/nix/store` is not writable by
  the calling user.  So a user scope around `nix build` caps only the *client*: the sandboxed `nixbld*`
  worker that runs `coqc` is in the daemon's cgroup tree, where `memory.max = max`.  Wrapping a nix
  build in the envelope that contains `dune build` would be a placebo - worse than no cap, because it
  *looks* contained;
- `nix show-config`: `max-jobs = 20`, `sandbox = true`.  `(jobs 2)` in `coq/dune-workspace` limits dune
  inside **one** derivation; it says nothing about how many *derivations* nix compiles at once, and
  `nix build` with several targets on a 20-core box uses 20;
- what that costs here, from `journalctl -u earlyoom -b -1` (during a `nix build` gate chain that
  started at 08:23:24 and never finished; machine rebooted at 08:34): **30 SIGTERM decisions in 10
  minutes, 28 of them the model server** (`strata`/`strata-host`, VmRSS 41094-47169 MiB), 2 a Brave
  renderer, at mem avail 2.44-9.03% and swap free 0-8.91%.  Not one Coq process was a victim, because
  earlyoom ranks by RSS and the capped build was never the biggest thing on the box.  (2026-11-19
  amendment, measured: `max-jobs = 1` has since been applied in the interactive account's
  `~/.config/nix/nix.conf` - plain no-flag `nix build` with three independent ~7 s burn derivations
  went from 3 concurrent nixbld workers / 8 s wall to 1 worker / 22 s wall.  The daemon's own setting
  is still `auto`: builds from other accounts (root, CI) still fan out.  Status and the open
  root-side follow-up: § "Status after 2026-11-19".)

And the measurement that rewrote this script, today at 11:46:33.  The version described above required
`MemAvailable >= 6 GiB` and nothing else.  It passed - `8236 MiB`, 12.9% of 63916 - with swap free
already at **116 MiB (2.97% of 3907)**.  Twenty-four seconds later `journalctl -u earlyoom` recorded
`mem avail: 6379 of 63916 MiB ( 9.98%), swap free: 110 of 3907 MiB ( 2.82%)`, `low memory! at or below
SIGTERM limits: mem 10.00%, swap 10.00%`, and `sending SIGTERM to process 5473 uid 1000
"strata-host": badness 1238, VmRSS 42653 MiB`; the chain went on to print four green targets, having
cost a 42 GiB model server.  A 6 GiB floor on a 62 GiB box is 9.6% of RAM - *below* earlyoom's own 10%
trigger - and a preflight that reads memory only says nothing about what happens during a 13-minute
build.  So, with the levers an unprivileged caller actually has:

1. **two floors, each `max(knob, 12% of the kernel-reported total)`**: `TIMBDA_NIX_GATE_MIN` (default
   8G) against `MemAvailable`, `TIMBDA_NIX_GATE_SWAPMIN` (default 700M) against swap free,
   `TIMBDA_NIX_GATE_GUARD` (default 12) setting the percentage - 12 rather than 10 so the floor sits
   above earlyoom's trigger instead of on top of it;
2. **a watchdog per target** (`TIMBDA_NIX_GATE_WATCHDOG`, default on): polls `MemAvailable` and swap
   free every 2 s and, on a crossing, kills our own `nix build`, says which floor moved, and then
   reports whether the root-side build outlived that kill - the honest version of "I stopped it", since
   `nix-daemon.service` has `MemoryMax=infinity`.  A target killed this way is recorded as
   `rc=124 … (target not attested)`, never as a pass;
3. **`--max-jobs 1`** instead of nix's 20, targets ordered cheap-first, so an abort wastes the least
   already-spent work;
4. **per-target exit codes** recorded by name (`target=… rc=…`), never a filtered pipeline, plus the
   `status.txt` / `*status.txt` files read out of each built output path - a nix build that "succeeded"
   while writing nothing is the same vacuity this repo's corners are built to catch;
5. the **earlyoom and kernel-OOM journal windows for the run** printed after the verdict, so "the gate
   is green" and "the host was healthy" stay two separately reported facts - and `nix failures: 0` next
   to `watchdog kills: 1` is not a pass.

Exit codes: 0 green, 1 a nix failure, 2 refused by preflight, 124 stopped by the host watchdog.

Measured today, five ways through it:

| run | result |
|---|---|
| default chain, default knobs, host at 6663 MiB free and 1725 MiB swap free | refuses before invoking nix, exit 2: `REFUSED: MemAvailable 6663 MiB < floor 8192 MiB`, printing both floors it applied - `mem >= 8192 MiB (12.8% of total) [knob 8G, guard 12%]` and `swap >= 700 MiB (17.9% of SwapTotal)`.  Run twice, at 12:11 and 12:47 |
| the 11:46:33 host state (8236 MiB free, swap free 116 MiB) | the script that existed at 11:46 admitted it; that run cost `strata-host` (42653 MiB) and still printed four green targets.  Today's floors would refuse the same state - 116 MiB of swap free is under the 700 MiB swap floor - but that is arithmetic on the recorded numbers, not a run: nobody put the host back into that state |
| `TIMBDA_NIX_GATE_MIN=999G` | refuses, exit 2, without invoking nix, printing the daemon's `MemoryMax=infinity` and `max-jobs = 20` as the reason a cap would be a placebo |
| `TIMBDA_NIX_GATE_MIN=6G TIMBDA_NIX_GATE_GUARD=0 … .#checks.x86_64-linux.corpus-differential`, 12:12:33 | `rc=0` in 0 s: everything this target needs was already realised by the 11:46 chain, so nothing was rebuilt.  It printed `out=/nix/store/xdsy2v844zfnixkqjdw0qz8cdw0bbcwj-timbda-corpus-differential` and re-read that output's `coq-corner-status.txt` (`reader_cases=64`, `corner_lines=421`) and `ocaml-corner-status.txt` (`extracted_lines=1465`, `driver_rc=0`).  Watchdog quiet |
| `TIMBDA_NIX_GATE_ALLOW=yes … .#checks.x86_64-linux.corpus-differential`, 12:11:36, host at 6706 MiB free against an 8192 MiB floor | the watchdog fired on its first poll: `MemAvailable 6713 MiB crossed the floor 8192 MiB mid-build`, our own client was killed, `target=… rc=124 … (target not attested)`, `no nixbld/rocq/dune worker survived the kill`, exit 124 |

What each of the four default targets currently costs here - measured, so the chain is not run blind:

| target | measured cost, 2026-11-19 |
|---|---|
| `checks.version-consistency` | 0-1 s.  Its output is a 112-byte file (`runCommand` ends in `touch $out`, `nix path-info` reports `ultimate: true`), so the evidence is a log line - `timbda version-consistency ok (11 pinned tool versions match)` - not an artifact.  It re-reads `docs/PLAN.md` and `docs/DESIGN-NOTES.md`, which is why `--dry-run` drv hashes move when documentation is edited |
| `packages.timbda-kernel` | cold: 12 min 43 s of `dune build` in the daemon's uncapped cgroup, peaking over 4.4 GiB (sec. 4.2).  Today's build: output 1,047,784 B with all eight `.vo` files, `buildPhase` log ending on the single-axiom audit.  Once realised: 0 s |
| `checks.corpus-differential` | 764 s, because it drags `timbda-kernel` with it through `buildInputs`; its output carries both corners' status files and `report.txt` |
| `checks.golden-test` | 21 s by substitution: 14 paths fetched, 415.4 MiB down / 3.3 GiB unpacked, `f6c6xf50wg0s32ph74i3xn4c1bdj5k00-ghc-9.12.3` among them.  At 09:37-10:24 the same target looked blocked for hours, because narinfo queries to both substituters timed out at 15 s and that GHC path answered 404 - a cache-reachability state this file mistook for a property of the dependency |

The store paths an earlier version of this file named - `z2bh66b7dl8izxpqlwmssshsvvrm9ry4-timbda-kernel`,
`783h7rakq85bx8f9ldwx7lf3rzwvcpyq-…` and `zr3lw60ma4jrgjqmikhdb1ik186d31yp-…` (the two corners),
`fgqpnm06kfz651qjpbdfi3070c56zpx6-…` (the pre-fix corner), `4ad7nky40jibbh89d141n795n332c1df-…` (the
check), and the kernel's source tree `k0vbgca354871nias6vmsv2l38lr9z7j-coq` - were read at 10:44-10:49
and deleted by Determinate Nix's collector at 10:50:10-10:50:11, in the same GC cycle that took 320 other
paths.  Rebuilt at 11:46-11:59 by the chain above: kernel output `sn9hfhilnjiqhc8w705f0pj07zi6ism7` (the
`dune build` artifact whose `nix log` ends with the single-axiom audit), differential output
`xdsy2v844zfnixkqjdw0qz8cdw0bbcwj`, whose `status.txt` files are the numbers quoted in its row of the
table.  Store paths here are not durable evidence - the collector runs on a timer and does not ask - so
what a claim rests on is the run and the status files it wrote, with their timestamps.  Full sequence,
with journal times: `docs/DESIGN-NOTES.md` § 4.3 and § 8.2-8.3.

## Root-side options (1 and 3 applied 2026-11-19; 2 and 4 not applied)

These would remove the pressure instead of containing it.  Options 1 and 3 were executed on this box
(15:42-15:49 EST) and verified against the live system on 2026-11-19; options 2 and 4 remain
unapplied.  Current facts: `earlyoom.service` runs `/usr/bin/earlyoom -r 3600` (v1.7) via
`EARLYOOM_ARGS` in `/etc/default/earlyoom` - no `--avoid`/`--prefer`; swap is now ~19.8 GiB total
(`/dev/dm-2` 3.8 GiB + a 16 GiB `/swapfile`, mode 600, fstab line `/swapfile none swap sw 0 0`);
`nix-daemon.service` carries `MemoryHigh=4G` `MemoryMax=5G` via
`/etc/systemd/system/nix-daemon.service.d/override.conf` (cgroup read-back `memory.max = 5368709120`;
`MemorySwapMax` unchanged at `infinity`); the ext4 root filesystem has ~127 GiB free (`/swapfile`
accounts for 16 of it).  The scripts below stand as what was run.

1. **Swap with real headroom** (raises commit headroom; stops the storm at its source):
   ```sh
   sudo dd if=/dev/zero of=/swapfile bs=1M count=16384 status=progress   # 16 GiB
   sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile
   printf '/swapfile none swap sw 0 0\n' | sudo tee -a /etc/fstab
   swapon --show      # verify; earlyoom's own log line shows the new swap-free percentage
   ```
2. **Tell `earlyoom` what it may not shoot.**  v1.7 spells this `--avoid` / `--prefer` (no `--ignore`
   flag in this version) and matches process *names*.  `sudoedit /etc/default/earlyoom`, replace the one
   `EARLYOOM_ARGS` line with:
   ```sh
   EARLYOOM_ARGS="-r 3600 --avoid '(^|/)(init|systemd|sshd|dbus|gala|dune|coqc|rocq|rocqworker|nix|gcc|ld|as)$' --prefer '(^|/)(strata|strata-host|llama|redpanda)$'"
   ```
   then `sudo systemctl restart earlyoom.service`, and verify with `systemctl show -p ExecStart
   earlyoom.service` plus `journalctl -u earlyoom -n 5`.  Trade-off, stated plainly: with `--prefer`
   aimed at the model server, a real OOM decision sacrifices Strata (which restarts) instead of
   SIGTERMed-ing a half-compiled Coq file.  With `--avoid` on the toolchain, `coq-build.sh`'s cgroup
   accounting becomes the thing that decides, and it reports `oom_kill` instead of leaving you to infer
   a kill from a truncated `.glob`.
3. **Cap the nix build sandbox** (the only way to make `nix build` itself fit an envelope):
   ```sh
   sudo systemctl edit nix-daemon.service   # then:
   #   [Service]
   #   MemoryHigh=4G
   #   MemoryMax=5G
   sudo systemctl daemon-reload && sudo systemctl restart nix-daemon.service
   systemctl show -p MemoryMax nix-daemon.service   # verify it is no longer `infinity`
   ```
   Without this, `nix-gate.sh` is a refusal policy, not a cap.  Note the interaction: a `MemoryMax` here
   means an over-large Coq derivation is killed *by the daemon's* cgroup, which the gate script reports
   as a `nix build` failure - so pick the envelope from the cold-build numbers in `docs/DESIGN-NOTES.md`
   § 4.3, not from the warm 647 MiB.
4. Optional kernel tuning: `vm.swappiness=10`, `vm.watermark_scale_factor=500` (unapplied; measured
   2026-11-19: `vm.swappiness=1`, `vm.watermark_scale_factor=10`).

### Status after 2026-11-19 (verified live)

- **Option 1 applied** - as scripted: 16 GiB `/swapfile` (mode 600) + fstab entry; `SwapTotal`
  20,778,488 kB.  Side effect: `nix-gate.sh`'s floors are `max(knob, 12% of total)`, so its swap floor
  auto-raises from the 700 MiB knob to ~2.4 GiB against the new total.
- **Option 3 applied** - values exactly as scripted (4 G / 5 G), verified both by `systemctl show` and
  by reading `/sys/fs/cgroup/system.slice/nix-daemon.service/memory.max`; accounting on, no
  per-worker overrides below it.  Envelope sized per this file's own warning (cold kernel peak
  >4.4 GiB, `Denotation.v` alone >3.5 GiB cold): one Coq-bearing derivation at a time fits; two at
  once would be killed by the daemon cgroup and surface as a `nix build` failure - which is why the
  `max-jobs` follow-up below matters.
- **Applied without root, client-side, for the interactive account only**: `max-jobs = 1` appended to
  `~/.config/nix/nix.conf` (per-key override of the system `max-jobs = auto`; per-invocation
  `nix build --max-jobs N` still wins, and `TIMBDA_NIX_GATE_JOBS` is untouched).  Measured with three
  independent ~7 s trivial burn derivations, plain no-flag `nix build`: 3 concurrent nixbld workers /
  8 s wall before, 1 worker / 22 s wall after; `nix config show` (client view) now reports
  `max-jobs = 1`.  What it does **not** do: change the daemon's own setting (`/etc/nix/nix.conf` is
  Determinate-managed: "do not modify ... put user changes in `nix.custom.conf`"), and builds started
  by other accounts (root, CI) still fan out.
- **Root-side follow-up, still open** - daemon-side concurrency for all accounts.  Run only when no
  build is in flight, because restarting the daemon aborts in-progress `nix build`s:
  ```sh
  sudo sh -c 'echo "max-jobs = 1" >> /etc/nix/nix.custom.conf'
  sudo systemctl restart nix-daemon.service
  sudo nix config show | grep max-jobs   # system view; expect 1
  ```
- **Still unapplied**: option 2 (`EARLYOOM_ARGS` is still just `-r 3600`) and option 4.

The option that *would* fit in the repo but severs this machine's model host: parking
`llama-swap.service` for the duration of a build (`systemctl --user stop llama-swap.service;
tools/build/nix-gate.sh; systemctl --user start llama-swap.service`) frees ~50 GiB exactly when needed -
and disconnects the model that is answering the session, so it is a command a human runs, not one a
guard runs.
