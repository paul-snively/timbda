#!/usr/bin/env bash
# Guarded `nix build` runner for the Timbda gate chain (docs/DESIGN-NOTES.md sec. 4.3).
#
# WHY THIS EXISTS, AND WHY IT IS NOT tools/build/coq-build.sh.
#
# `tools/build/coq-build.sh` can contain a build because `dune build` runs as *this* user, so
# `systemd-run --user --scope -p MemoryMax=…` puts it in a cgroup we own.  `nix build` cannot be
# contained that way, and that is a measured property of this machine, not a guess:
#
#   * nix here is daemon-managed: `nix-daemon.service` runs as root (Determinate Nix 3.24.2, nix
#     2.35.3) in `Slice=system.slice`, and `/nix/store` is not writable by the calling user.  A scope
#     cap around `nix build` caps only the *client* process; the sandboxed `nixbld*` worker that
#     actually runs `coqc` lives in the daemon's cgroup tree.  RE-READ 2026-11-26 (this bullet used to
#     say `MemoryHigh=infinity MemoryMax=infinity`, true before the 2026-11-19 root-side override
#     landed): `systemctl show -p MemoryMax -p MemoryHigh -p MemorySwapMax -p Slice nix-daemon.service`
#     answers `Slice=system.slice`, `MemoryHigh=4294967296`, `MemoryMax=5368709120`,
#     `MemorySwapMax=infinity`, with cgroup read-back `/sys/fs/cgroup/system.slice/nix-daemon.service/
#     memory.max = 5368709120`.  So the Coq lane IS capped - but by a 5 GiB host-side limit chosen by
#     root, not by this caller, and with swap unlimited a throttled build spills into swap instead of
#     dying, which is exactly the 2026-11-19 storm shape.  The containment conclusion is unchanged:
#     nothing this unprivileged script can wrap `nix build` in changes what the daemon's workers get.
#   * `nix show-config` on this box: `max-jobs = 20`, `cores = 0`, `sandbox = true`.  So
#     `nix build a b c d e` may run up to 20 derivations concurrently, each with its own
#     dune/Rocq compile.  `coq/dune-workspace`'s `(jobs 1)` limits dune *inside one* derivation and
#     says nothing about how many derivations nix builds at once.
#   * The uncontrolled version of that is what this box died of.  `journalctl -u earlyoom -b -1`
#     for 08:24:41-08:33:56 (previous boot): 30 SIGTERM decisions, 28 of them the model server
#     (`strata` / `strata-host`, VmRSS 41094-47169 MiB), 2 a Brave renderer; mem avail 2.44-9.03%,
#     swap free 0-8.91%; the machine rebooted at 08:34.  The gate chain started at 08:23:24 never
#     finished.  No Coq process was a victim in that window, because earlyoom ranks by RSS (+swap):
#     a 4 GiB build is never the biggest process on a box whose model server holds 43-50 GiB of 62
#     GiB.  A build capped *below* the model server is therefore not "the designated victim" - it is
#     the marginal allocation, and the model server is what dies.  (At 04:37:31 earlyoom did pick
#     `"rocqworker"` - badness 1556, VmRSS 55022 MiB - i.e. an *uncapped* Coq worker big enough to
#     outrank the model server.)
#
# MEASURED, 2026-11-19 11:46:33-11:59:39 - the run that this script's first version survived, and
# the reason it now has a swap floor and a during-run watchdog:  preflight passed on MemAvailable
# alone (8236 MiB = 12.9% of 63916 MiB), with swap free already at 116 MiB = 2.97%.  24 s in,
# `journalctl -u earlyoom` recorded "mem avail: 6379 of 63916 MiB ( 9.98%), swap free: 110 of 3907
# MiB ( 2.82%)", "low memory! at or below SIGTERM limits: mem 10.00%, swap 10.00%", and "sending
# SIGTERM to process 5473 uid 1000 \"strata-host\": badness 1238, VmRSS 42653 MiB".  The model server
# died, reloaded, and the gate chain finished green 12 minutes later.  So "preflight passed" and
# "the guard prevented damage" were not the same fact: a MemAvailable-only floor of 6G on a 62 GiB
# box is 9.6% of RAM, i.e. *below* earlyoom's own 10% trigger, and the run passed while earlyoom was
# one hundred milliseconds of allocation away from firing.  The floors below are therefore stated as
# percentages of what the kernel reports, and set above earlyoom's 10%/10% thresholds rather than
# below them.  Those thresholds are the program's own defaults, re-read 2026-11-26 from `earlyoom -h`
# (v1.7): `-m` defaults to 10 %, `-s` to 10 %, SIGKILL at half the SIGTERM threshold, and "both
# memory and swap must be below minimum for earlyoom to act"; the running unit is
# `/usr/bin/earlyoom -r 3600` with no `-m`/`-s` flags (`EARLYOOM_ARGS` in `/etc/default/earlyoom`),
# so 10%/10% is what this box enforces.
#
# What the levers are, since containment is not one of them:  refuse to start unless the host has
# headroom on *both* mem and swap; build one derivation at a time; poll the host while a build runs
# and kill our own `nix build` if the host crosses the floors mid-run; and never judge a target from
# a filtered pipeline - the target's rc is `nix build`'s rc, nothing else.  Killing our own client
# does not promise to stop the daemon-side build (the worker is root's child, not ours): after a
# watchdog hit this script reports whether a `nixbld`/`coqc` worker was still alive 20 s later, which
# is the honest version of "I stopped it".
#
# Usage:
#   tools/build/nix-gate.sh                       # the documented chain, one derivation at a time
#   tools/build/nix-gate.sh .#checks.x86_64-linux.corpus-differential …   # or explicit targets
#   TIMBDA_NIX_GATE_MIN=8G TIMBDA_NIX_GATE_SWAPMIN=1G tools/build/nix-gate.sh
#   TIMBDA_NIX_GATE_TARGETS=".#checks.x86_64-linux.version-consistency" tools/build/nix-gate.sh
#
# Knobs:
#   TIMBDA_NIX_GATE_MIN       default 8G     MemAvailable floor, further raised to
#                                            max(MIN, EARLYOOM_GUARD% of MemTotal) - see below.
#   TIMBDA_NIX_GATE_SWAPMIN   default 700M   swap-free floor, further raised to
#                                            max(SWAPMIN, EARLYOOM_GUARD% of SwapTotal).
#   TIMBDA_NIX_GATE_GUARD     default 12     percent-of-total floors; must exceed earlyoom's 10%.
#   TIMBDA_NIX_GATE_WATCHDOG  default on     poll the host during each target (see below); `off`
#                                            disables it, which is the way to make this script worse.
#   TIMBDA_NIX_GATE_JOBS      default 1      passed as `nix build --max-jobs`.
#   TIMBDA_NIX_GATE_ALLOW     default no     `yes` runs past a failed preflight, at your own risk.
#   TIMBDA_NIX_GATE_TARGETS   default: the eight documented targets (the four M2-era
#                                            lanes + the four M1 lanes of decision 9 § 5.0),
#                                            cheapest-first EXCEPT that the Coq package lane
#                                            runs before the check lanes that drag it; a
#                                            space-separated override.
#
#   TIMBDA_NIX_GATE_GCROOTS   default ~/.local/state/timbda-gcroots - where the indirect GC roots of
#                                            the kept lanes are written.
#   TIMBDA_NIX_GATE_KEEP      default: the Coq package lane and corpus-differential - lanes whose
#                                            green output is registered as a GC root so Determinate
#                                            Nix's collector cannot collect it.  `KEEP=" "` roots
#                                            nothing; a ghc-fetching lane rooted here would pin 3.3 GiB
#                                            for no benefit, which is why it is not in the default.
#
# Exit codes: 0 all targets green; 1 a target failed in nix/Coq; 2 preflight refused; 124 the
# host watchdog killed a target's build (measured floors crossed while it ran).

set -u

MIN="${TIMBDA_NIX_GATE_MIN:-8G}"
SWAPMIN="${TIMBDA_NIX_GATE_SWAPMIN:-700M}"
GUARD_PCT="${TIMBDA_NIX_GATE_GUARD:-12}"
WATCHDOG="${TIMBDA_NIX_GATE_WATCHDOG:-on}"
# Where indirect GC roots for the Coq-side lanes live, and which lanes get one (space-separated).
# Measured reason 2026-11-26: Determinate Nix's collector collects any store path no GC root
# references, so this morning's green kernel output was `error: path … is not valid` by 15:02 and the
# afternoon chain paid the kernel's full 4 min 30 s buildPhase again.  A trusted user CAN register a
# root - `nix-store --realise --add-root <link> --indirect <out>` writes the symlink where we are
# allowed to write and registers it under /nix/var/nix/gcroots/auto (verified on this box:
# /nix/var/nix/profiles/… is Permission denied, --add-root --indirect is not).  Only the named lanes
# are rooted: the ghc-fetching golden-test lane would pin 3.3 GiB for no benefit.
GCROOTS="${TIMBDA_NIX_GATE_GCROOTS:-$HOME/.local/state/timbda-gcroots}"
KEEP="${TIMBDA_NIX_GATE_KEEP:- .#packages.x86_64-linux.timbda-kernel .#checks.x86_64-linux.corpus-differential }"
JOBS="${TIMBDA_NIX_GATE_JOBS:-1}"
ALLOW="${TIMBDA_NIX_GATE_ALLOW:-no}"
OUTDIR="${TIMBDA_NIX_GATE_LOGDIR:-/tmp/opencode}"
mkdir -p "$OUTDIR"
mkdir -p "$GCROOTS"

to_kib() { # "8G" | "700M" | "2048K" -> KiB
  local n="${1%[KMGkmg]}"; local u="${1: -1}"
  case "$u" in
    G|g) echo $(( n * 1024 * 1024 )) ;;
    M|m) echo $(( n * 1024 )) ;;
    K|k) echo "$n" ;;
    *)   echo "$n" ;;
  esac
}

mem_available_kib() { awk '/^MemAvailable/{print $2; exit}' /proc/meminfo; }
mem_total_kib()     { awk '/^MemTotal/{print $2; exit}' /proc/meminfo; }
swap_total_kib()    { awk '/^SwapTotal/{print $2; exit}' /proc/meminfo; }
swap_free_kib()     { awk '/^SwapFree/{print $2; exit}' /proc/meminfo; }

mem_line() {
  printf 'MemAvailable %d of %d MiB (%.2f%%)  swap free %d of %d MiB (%.2f%%)\n' \
    "$(( $(mem_available_kib) / 1024 ))" "$(( $(mem_total_kib) / 1024 ))" \
    "$(awk -v a="$(mem_available_kib)" -v t="$(mem_total_kib)" 'BEGIN{printf "%.2f", 100*a/t}')" \
    "$(( $(swap_free_kib) / 1024 ))" "$(( $(swap_total_kib) / 1024 ))" \
    "$(awk -v a="$(swap_free_kib)" -v t="$(swap_total_kib)" 'BEGIN{ if (t==0) {printf "n/a"; exit} printf "%.2f", 100*a/t }')"
}

# The floors the run is actually held to: whichever is stricter, the knob or GUARD_PCT of what the
# kernel reports.  earlyoom (v1.7 here) fires at 10% mem AND 10% swap free, so a floor at or under
# 10% is not a guard at all - the 11:46 run proved that.
MEM_FLOOR_KIB=$(( $(to_kib "$MIN") ))
pct_floor_kib() { awk -v t="$1" -v p="$GUARD_PCT" 'BEGIN{printf "%d", t*p/100}'; }
if [ "$GUARD_PCT" != 0 ]; then
  guard=$(( $(pct_floor_kib "$(mem_total_kib)") ))
  [ "$guard" -gt "$MEM_FLOOR_KIB" ] && MEM_FLOOR_KIB=$guard
  guard=$(( $(pct_floor_kib "$(swap_total_kib)") ))
  SWAP_FLOOR_KIB=$(to_kib "$SWAPMIN")
  [ "$guard" -gt "$SWAP_FLOOR_KIB" ] && SWAP_FLOOR_KIB=$guard
else
  SWAP_FLOOR_KIB=$(to_kib "$SWAPMIN")
fi

pct_str() { awk -v a="$1" -v t="$2" 'BEGIN{ if (t==0) { print "n/a"; exit } printf "%.1f%% of total", 100*a/t }'; }

echo "=== preflight ==="
echo "$(mem_line)"
echo "mem floor:  MemAvailable >= $(( MEM_FLOOR_KIB / 1024 )) MiB ($(pct_str "$MEM_FLOOR_KIB" "$(mem_total_kib)"))  [knob $MIN, guard ${GUARD_PCT}%]"
echo "swap floor: swap free    >= $(( SWAP_FLOOR_KIB / 1024 )) MiB ($(pct_str "$SWAP_FLOOR_KIB" "$(swap_total_kib)"))  [knob $SWAPMIN, guard ${GUARD_PCT}%]"
echo "earlyoom on this box triggers at 10% mem AND 10% swap free - a floor at or below 10% is not a guard"
echo "nix daemon containment: $(systemctl show -p MemoryMax -p MemoryHigh -p Slice nix-daemon.service --no-pager 2>/dev/null | tr '\n' ' ' || echo 'no systemd')"
echo "nix concurrency: $(nix show-config 2>/dev/null | grep -E '^max-jobs|^sandbox =' | tr '\n' ' ')  -> running with --max-jobs $JOBS"
echo "watchdog: $WATCHDOG (polls MemAvailable/swap free every 2 s while a target builds)"

REFUSE=""
[ "$(mem_available_kib)" -lt "$MEM_FLOOR_KIB" ] && REFUSE="MemAvailable $(( $(mem_available_kib) / 1024 )) MiB < floor $(( MEM_FLOOR_KIB / 1024 )) MiB"
if [ "$SWAP_FLOOR_KIB" -gt 0 ] && [ "$(swap_free_kib)" -lt "$SWAP_FLOOR_KIB" ]; then
  REFUSE="${REFUSE}${REFUSE:+ ; }swap free $(( $(swap_free_kib) / 1024 )) MiB < floor $(( SWAP_FLOOR_KIB / 1024 )) MiB"
fi
if [ -n "$REFUSE" ]; then
  echo "REFUSED: $REFUSE - and a cold Coq derivation is not contained by systemd here (the daemon's" \
       "build cgroup has memory.max=max), so this run would be an unbounded allocation on top of a" \
       "model server holding 43-50 GiB."
  echo "Options, in the order that does not damage anything else: build fewer targets at a time" \
       "(TIMBDA_NIX_GATE_JOBS=1, already the default), drop a target (TIMBDA_NIX_GATE_TARGETS), free" \
       "swap (a 3.9 GiB swap partition means swap free is the binding constraint on this box), or" \
       "cap the daemon root-side (tools/build/README.md, root-side options - documented, NOT applied" \
       "here).  Do not lower TIMBDA_NIX_GATE_GUARD below earlyoom's 10% to talk yourself into" \
       "running: that is how the 08:24-08:34 storm, and the 11:46:57 strata-host kill, happened."
  [ "$ALLOW" = yes ] || exit 2
  echo "continuing anyway because TIMBDA_NIX_GATE_ALLOW=yes - at your own risk, see the header"
fi

TARGETS=("$@")
if [ "$#" -eq 0 ]; then
  if [ -n "${TIMBDA_NIX_GATE_TARGETS:-}" ]; then
    read -r -a TARGETS <<< "$TIMBDA_NIX_GATE_TARGETS"
  fi
  if [ "${#TARGETS[@]}" -eq 0 ]; then
    # cheapest-first, Coq-side targets late: on a headroom-poor host the expensive failure should be
    # the one that costs the least already-spent work.  M1 lanes (decision 9 § 5.0) ride
    # the chain too: rules-audit, tblgen-rocq-golden, dialect-lit-tests and bazel-native-tests
    # are seconds each.
    #
    # ONE ORDERING EXCEPTION, measured 2026-11-26 (docs/DESIGN-NOTES.md sec. 4.3.1): the Coq package
    # lane goes before the check lanes that drag it, because `checks.corpus-differential` takes
    # `packages.timbda-kernel` in `buildInputs` through the two corpus corners, so a cold store
    # compiles the whole Coq kernel *inside* the corpus target.  Measured on this box (63.9 GiB,
    # model server resident at ~54.5 GiB): corpus-differential cold dipped MemAvailable 6918 -> 5021
    # MiB and crossed the 5120 MiB watchdog floor, target unattested (rc=124), with the log still in
    # `timbda-kernel>` output; the same target with the kernel derivation already in the store ran
    # rc=0 and never went below 5799 MiB, and the kernel lane on its own (270 s) never dipped at all
    # (7362 -> 7393 MiB).  Ordering does not make the Coq work cheaper - `--max-jobs 1` makes it
    # sequential either way - it decides *which target's poll window* the kernel's allocation lands
    # in, and the evidence lines up with the lane that actually costs the memory.
    TARGETS=(
      .#checks.x86_64-linux.version-consistency
      .#checks.x86_64-linux.rules-audit
      .#checks.x86_64-linux.bazel-native-tests
      .#checks.x86_64-linux.tblgen-rocq-golden
      .#checks.x86_64-linux.dialect-lit-tests
      .#packages.x86_64-linux.timbda-kernel
      .#checks.x86_64-linux.corpus-differential
      .#checks.x86_64-linux.golden-test
    )
  fi
fi

WD_HIT=""          # set to the reason when the watchdog kills a build
wd_poll() {        # $1 = pid of the nix client to kill, $2 = hit-marker file
  local pid="$1" marker="$2"
  while :; do
    kill -0 "$pid" 2>/dev/null || return 0
    if [ "$(mem_available_kib)" -lt "$MEM_FLOOR_KIB" ]; then
      echo "   WATCHDOG: MemAvailable $(( $(mem_available_kib) / 1024 )) MiB crossed the floor $(( MEM_FLOOR_KIB / 1024 )) MiB mid-build" | tee -a "$marker"
    elif [ "$SWAP_FLOOR_KIB" -gt 0 ] && [ "$(swap_free_kib)" -lt "$SWAP_FLOOR_KIB" ]; then
      echo "   WATCHDOG: swap free $(( $(swap_free_kib) / 1024 )) MiB crossed the floor $(( SWAP_FLOOR_KIB / 1024 )) MiB mid-build" | tee -a "$marker"
    else
      sleep 2; continue
    fi
    echo "   $(mem_line)  -> killing our own nix build (pid $pid); the root-side daemon worker is not ours to kill"
    kill -TERM "$pid" 2>/dev/null
    sleep 3
    kill -KILL "$pid" 2>/dev/null
    return 0
  done
}

START_EPOCH=$(date +%s)
echo "=== chain: ${#TARGETS[@]} target(s), nix --max-jobs $JOBS ==="
FAIL=0
WD_KILLS=0
RESULT_LINES=()
for t in "${TARGETS[@]}"; do
  log="$OUTDIR/nix-gate$(echo "$t" | tr '.#' '--').log"
  marker="$OUTDIR/nix-gate-wd$(echo "$t" | tr '.#' '--').txt"
  : > "$marker"
  t_start=$(date +%s)
  before=$(mem_available_kib)
  printf '%s %s  start: %s\n' "== $(date +%H:%M:%S)" "$t" "$(mem_line)"
  # --no-link: this script judges a target by its own rc and its log, never by a ./result symlink -
  # and a `result` symlink left in the repo is an untracked path that a flake `src = ./.` would copy.
  nix build "$t" -L --max-jobs "$JOBS" --no-link > "$log" 2>&1 &
  nixpid=$!
  wdpid=""
  if [ "$WATCHDOG" = on ]; then
    wd_poll "$nixpid" "$marker" &
    wdpid=$!
  fi
  wait "$nixpid"; rc=$?
  if [ -n "$wdpid" ]; then
    kill "$wdpid" 2>/dev/null; wait "$wdpid" 2>/dev/null
  fi
  t_end=$(date +%s)
  printf '   rc=%s  elapsed %ss  MemAvailable %d -> %d MiB  log: %s\n' \
    "$rc" "$(( t_end - t_start ))" $(( before / 1024 )) $(( $(mem_available_kib) / 1024 )) "$log"
  if [ -s "$marker" ]; then
    WD_HIT=yes; WD_KILLS=$(( WD_KILLS + 1 ))
    echo "   HOST WATCHDOG killed this target's build (nix client exited rc=$rc):  $(cat "$marker")"
    echo "   did the root-side build survive our kill?  checking 20 s later:"
    sleep 20
    if pgrep -af 'nixbld|rocq|dune build|nix build' 2>/dev/null | sed 's/^/     /' | head -6 | grep -q .; then
      echo "     builder/worker processes are still alive - our kill reached only our own client."
    else
      echo "     no nixbld/rocq/dune worker survived the kill."
    fi
    for d in $(grep -oE '/nix/store/[a-z0-9]{32}-[A-Za-z0-9._-]+\.drv' "$log" | sort -u); do
      b=$(basename "$d")
      hits=$(journalctl -u nix-daemon --since "@$(( t_end - 1 ))" --no-pager 2>/dev/null | grep -c "$b")
      echo "     $b : daemon journal mentions in the 20 s after the kill = $hits"
    done
    if ! grep -qE '/nix/store/[a-z0-9]{32}-[A-Za-z0-9._-]+\.drv' "$log"; then
      echo "     (the client died before it named any derivation, so there is nothing to check in the"
      echo "     daemon journal for this target - the kill landed early)"
    fi
    RESULT_LINES+=("target=$t rc=124 verdict=STOPPED BY THE HOST WATCHDOG (target not attested)")
    FAIL=$(( FAIL + 1 ))
    continue                      # the host is the reason; do not spend more allocations on it
  fi
  if [ "$rc" -ne 0 ]; then
    echo "   FAIL: nix exited $rc for $t (unfiltered log above path; tail follows)"
    tail -20 "$log"
    RESULT_LINES+=("target=$t rc=$rc")
    FAIL=$(( FAIL + 1 ))
  else
    outpath=$(nix build "$t" --no-link --print-out-paths 2>/dev/null | head -1)
    echo "   ok  out=$outpath"
    for st in "$outpath"/status.txt "$outpath"/*status.txt; do
      [ -f "$st" ] || continue
      echo "   $(basename "$st") from this derivation:"
      sed 's/^/     /' "$st"
    done
    RESULT_LINES+=("target=$t rc=0 out=$outpath")
    # Store-warming for the Coq-side lanes (see the GCROOTS block near the knobs): a green lane whose
    # output the collector can reach is a lane the next gate run pays for twice.
    case " $KEEP " in
      *" $t "*)
        rootname="$GCROOTS/$(echo "$t" | tr '.#' '--')"
        if [ -n "$outpath" ] && nix-store --realise --add-root "$rootname" --indirect "$outpath" \
             > /dev/null 2>&1; then
          echo "   gc root: $rootname -> $outpath (survives the store collector; $(du -sh "$outpath" 2>/dev/null | cut -f1))"
        else
          echo "   gc root refused for $t - host policy; the next run may pay for this build again"
        fi
        ;;
    esac
  fi
done

END_EPOCH=$(date +%s)
echo "=== verdict ==="
for l in "${RESULT_LINES[@]}"; do echo "  $l"; done
echo "  nix failures: $FAIL   watchdog kills: $WD_KILLS"
WINDOW="$(date -d "@$START_EPOCH" +%H:%M:%S)-$(date -d "@$END_EPOCH" +%H:%M:%S)"
echo "  earlyoom evidence for $WINDOW (a storm here is a host fact, not a gate result):"
journalctl -u earlyoom -S "@$START_EPOCH" -U "@$END_EPOCH" --no-pager 2>/dev/null \
  | grep -E "low memory|sending SIGTERM|mem avail" | sed 's/^/    /' | tail -20
echo "  kernel OOM evidence for $WINDOW:"
journalctl -k -S "@$START_EPOCH" -U "@$END_EPOCH" --no-pager 2>/dev/null \
  | grep -iE 'out of memory|killed process|oom' | sed 's/^/    /' | tail -10
echo "  $(mem_line)"
if [ "$WD_KILLS" -gt 0 ]; then
  echo "  NOTE: a green 'nix failures: 0' next to a nonzero 'watchdog kills' is not a pass: the killed"
  echo "  target(s) above were never attested.  Read the earlyoom lines as the cost of the run."
  exit 124
fi
[ "$FAIL" -eq 0 ] || exit 1
exit 0
