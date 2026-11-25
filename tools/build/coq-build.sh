#!/usr/bin/env bash
# Guarded Coq build for the Timbda-0 kernel (docs/DESIGN-NOTES.md sec. 4.1, 8.4).
#
# Why this exists.  Two separate facts, both measured on this machine.
#
# (a) The OOM killer does shoot the Coq toolchain here.  `earlyoom` fires when BOTH mem and swap
# are at/below their 10% thresholds, and its journal shows it doing exactly that to a build worker:
#   earlyoom[1185]: low memory! sending SIGTERM to process 566392 uid 1000 "rocqworker":
#                   badness 1017, VmRSS 28877 MiB, /proc/566392/cmdline="rocqworker"
# alongside several "strata-host" kills at 25-30 GiB each.  The tripwire state it reported:
#   mem avail: 6237 of 63916 MiB (9.57%), swap free: 245 of 3907 MiB (6.27%)
# i.e. the 3.8 GiB swap partition being nearly full is what makes the AND-condition satisfiable;
# swap free later measured 943-988 MiB (24%), when no kill is due.  What is constant is that swap
# has no headroom, so the AND-condition is one big allocation away from being true all the time.
#
# (b) A Coq peak is what pushes it over.  `/usr/bin/time -v` on `dune build -j 1`, measured while
# one Example in `tests/KernelTest.v` still asked the bytecode machine to decide
# `denote e 24 = denote (norm 24 e) 24`: maxrss 56,588,736 kB (53.9 GiB) over the build tree,
# 685 s user time, 11 min 38 s wall, exit 1.  That Example is gone - its claim was unprovable
# (see docs/DESIGN-NOTES.md sec. 4.2) and it was the blowup - and the kernel build inside this
# wrapper's envelope now peaks at 647 MiB in its own cgroup with dune exit 0.
#
# A killed build does not announce itself as one.  What it looks like in dune's output is
# `[got signal TERM]` in `coq/_build/log`, dune exit 1 with no `Error:` line anywhere,
# `tests/KernelTest.vo` absent, and `tests/KernelTest.glob` truncated at exactly 131072 bytes.
# Caveat learned the hard way: a SIGTERM also arrives from *the harness running this script* when
# a foreground build exceeds its own timeout, so `got signal` lines are evidence of a kill, not
# evidence of *which* killer - check `journalctl -u earlyoom` and the cgroup's `memory.events`
# before blaming the OOM killer.
#
# What this wrapper does:
#   1. preflight  - refuse to start unless MemAvailable covers the envelope;
#   2. containment - run the whole build inside a transient systemd scope with
#      MemoryHigh/MemoryMax/MemorySwapMax, so an over-growing worker is OOM-killed
#      inside its own cgroup instead of pushing the host into a swap storm;
#   3. designated victim - raise oom_score_adj on coqc/rocqworker, so that when the
#      kernel's own OOM killer (or this scope's own MemoryMax) acts, it takes the
#      restartable build rather than the database, the model server, or this login
#      shell.  Scope of that claim, measured: it does not apply to earlyoom, which ranks
#      by its own badness built from RSS - a build capped at a few GiB never outscores a
#      model server holding 43-49 GiB, so a capped build is the *marginal* allocation and
#      the model server is what earlyoom shoots.  An uncapped Coq worker does outscore it:
#      earlyoom picked "rocqworker", badness 1556, VmRSS 55022 MiB (2026-11-19 04:37:31).
#      The lever that actually protects the model server is earlyoom's --avoid/--prefer,
#      which needs root and is documented but not applied (tools/build/README.md);
#   4. host watchdog - a cgroup cap shields the host from the build only up to the
#      envelope, because the envelope is itself committed host memory: when the build fills
#      it the kernel pays by swapping *other* processes' pages, and on this box those pages
#      belong to the model server.  So the wrapper aborts the build - with a verdict line
#      that names itself - as soon as host MemAvailable or swap headroom falls under its
#      floors.  A build is restartable, a model server is not;
#   5. honest verdict - the build's own exit status, the unfiltered log, the expected .vo
#      artifacts, and the cgroup's peak and memory.events counters.  "No Error: line in the
#      log" is never treated as success: a build with no artifacts is reported as killed with
#      the OOM evidence quoted (see sec. 4.1), and a build that was throttled rather than
#      killed is reported as throttled, from memory.high counts.
#
# Usage (inside the rocq dev shell; DESIGN-NOTES sec. 4 for the toolchain contract):
#   nix develop .#devShells.x86_64-linux.rocq -c tools/build/coq-build.sh
#   nix develop .#devShells.x86_64-linux.rocq -c tools/build/coq-build.sh -j 1
#
# Knobs (environment):
#   TIMBDA_COQ_MEMORY_HIGH   default 2G    soft throttle (kernel reclaims first)
#   TIMBDA_COQ_MEMORY_MAX    default 3G    hard cap for the whole build subtree.  Sized from
#                                          measurement, not guesswork: the warm kernel build
#                                          peaks at 647 MiB inside its own scope (DESIGN-NOTES
#                                          sec. 4.2), but a cold coq/Denotation.v compile did
#                                          not fit in 3G at all - it held 3107 MiB for 522 s
#                                          without finishing (DESIGN-NOTES sec. 4.3) - so raise
#                                          HIGH/MAX for a cold rebuild, or let the preflight
#                                          refuse when the host cannot pay for it.
#   TIMBDA_COQ_HEADROOM      default 1G    MemAvailable required above MEMORY_MAX
#   TIMBDA_COQ_SWAPMAX       default 0     keep the cap honest (host swap is full)
#   TIMBDA_COQ_MIN_AVAIL     default 1G    watchdog floor: abort the build if host
#                                          MemAvailable falls below this
#   TIMBDA_COQ_MIN_SWAPFREE  default 700M  watchdog floor for swap headroom; a machine with no
#                                          swap is exempt, because earlyoom's trigger is mem AND
#                                          swap and its swap term here becomes true under ~390
#                                          MiB free of a 3.9 GiB partition - 700 MiB is a
#                                          margin, not a physical law
#   TIMBDA_COQ_DESIGNATED    default yes   raise worker oom_score_adj (no=off)
#   TIMBDA_COQ_ALLOW_UNSIZED default no    yes=skip containment, measure the true peak
#   TIMBDA_COQ_LOG           default /tmp/opencode/coq-build.log

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COQ_DIR="$REPO_DIR/coq"
LOG="${TIMBDA_COQ_LOG:-/tmp/opencode/coq-build.log}"
HIGH="${TIMBDA_COQ_MEMORY_HIGH:-2G}"
MAX="${TIMBDA_COQ_MEMORY_MAX:-3G}"
SWAPMAX="${TIMBDA_COQ_SWAPMAX:-0}"
HEADROOM="${TIMBDA_COQ_HEADROOM:-1G}"
DESIGNATED="${TIMBDA_COQ_DESIGNATED:-yes}"
ALLOW_UNSIZED="${TIMBDA_COQ_ALLOW_UNSIZED:-no}"
MIN_AVAIL="${TIMBDA_COQ_MIN_AVAIL:-1G}"
MIN_SWAPFREE="${TIMBDA_COQ_MIN_SWAPFREE:-700M}"

fail() { echo "FAIL: $*" >&2; exit 1; }

kib() { # "6G" | "6144M" | "512K" | bare number -> KiB
  case "$1" in
    *[Gg]) echo $(( ${1%[Gg]} * 1024 * 1024 ));;
    *[Mm]) echo $(( ${1%[Mm]} * 1024 ));;
    *[Kk]) echo ${1%[Kk]};;
    *) echo "$1";;
  esac
}

MAX_KIB=$(kib "$MAX"); HEAD_KIB=$(kib "$HEADROOM")
MIN_AVAIL_KIB=$(kib "$MIN_AVAIL"); MIN_SWAPFREE_KIB=$(kib "$MIN_SWAPFREE")

# ---- 0. toolchain comes from the flake, not from the host -------------------
command -v dune  >/dev/null 2>&1 || fail "dune not found: run inside 'nix develop .#devShells.x86_64-linux.rocq'"
command -v coqc  >/dev/null 2>&1 || fail "coqc not found: run inside the rocq dev shell"
command -v systemd-run >/dev/null 2>&1 || fail "systemd-run not found"

# ---- 1. preflight -----------------------------------------------------------
AVAIL_KIB=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)
SWAPFREE_KIB=$(awk '/^SwapFree:/{print $2}' /proc/meminfo)
NEED_KIB=$((MAX_KIB + HEAD_KIB))
echo "preflight: MemAvailable $((AVAIL_KIB/1024)) MiB  SwapFree $((SWAPFREE_KIB/1024)) MiB" \
     " envelope HIGH=$HIGH MAX=$MAX SWAPMAX=$SWAPMAX (+$((HEAD_KIB/1024)) MiB headroom required)"
if [ "$ALLOW_UNSIZED" != "yes" ] && [ "$AVAIL_KIB" -lt "$NEED_KIB" ]; then
  fail "envelope needs $((NEED_KIB/1024)) MiB, only $((AVAIL_KIB/1024)) MiB available.
       Options: park the model server for the build, lower TIMBDA_COQ_MEMORY_MAX,
       lower dune concurrency (-j 1), or give earlyoom an ignore rule for the Coq
       toolchain (root).  Running this build uncapped is what produced the
       '[got signal TERM]' failures described in the header."
fi

# ---- 2. containment: re-exec this script inside a capped transient scope ----
if [ "${TIMBDA_COQ_SCOPED:-}" != "1" ] && [ "$ALLOW_UNSIZED" != "yes" ]; then
  [ -n "${XDG_RUNTIME_DIR:-}" ] || fail "XDG_RUNTIME_DIR unset: no user systemd instance to create a scope"
  SETENV=(--setenv=TIMBDA_COQ_SCOPED=1
          --setenv=TIMBDA_COQ_LOG="$LOG"
          --setenv=TIMBDA_COQ_MEMORY_HIGH="$HIGH"
          --setenv=TIMBDA_COQ_MEMORY_MAX="$MAX"
          --setenv=TIMBDA_COQ_SWAPMAX="$SWAPMAX"
          --setenv=TIMBDA_COQ_HEADROOM="$HEADROOM"
          --setenv=TIMBDA_COQ_MIN_AVAIL="$MIN_AVAIL"
          --setenv=TIMBDA_COQ_MIN_SWAPFREE="$MIN_SWAPFREE"
          --setenv=TIMBDA_COQ_DESIGNATED="$DESIGNATED"
          --setenv=TIMBDA_COQ_ALLOW_UNSIZED="$ALLOW_UNSIZED")
  PROPS=(-p MemoryHigh="$HIGH" -p MemoryMax="$MAX" -p MemorySwapMax="$SWAPMAX")
  echo "containment: re-exec inside 'systemd-run --user --scope' (${PROPS[*]})"
  # No --quiet: a property systemd-run refuses must be visible, not swallowed.
  exec systemd-run --user --scope "${PROPS[@]}" "${SETENV[@]}" "${BASH_SOURCE[0]}" "$@"
fi
[ "$ALLOW_UNSIZED" = "yes" ] && echo "containment: DISABLED (TIMBDA_COQ_ALLOW_UNSIZED=yes) - measuring the uncapped peak"

cd "$COQ_DIR" || fail "no coq/ directory at $COQ_DIR"
mkdir -p "$(dirname "$LOG")" || fail "cannot create the log directory for $LOG"

# ---- 3. expected artifacts (anti-vacuity, same rule as the corpus corners) --
# M2 addition (2026-11-23): Checks is the T4 checker theory, ChecksEval its eval-side leg and
# tests/ChecksTest the corpus-mirror file (tests/corpus/m2-det.texpr's 29 verdicts), so a build
# that skipped any of them is vacuous in exactly the sense the corpus corners guard against.
# M1 (2026-11-25): RewRules is the GENERATED rule surface (coq/RewRules.v,
# dialect/tblgen-rocq); its .vo is as mandatory as any hand-written theory.
EXPECTED_VO=(Syntax Rewriting RewRules Semantics Denotation Eval Checks ChecksEval KernelStub Probe Lower tests/KernelTest tests/ChecksTest tests/LowerTest)
missing_vos() {
  local out=() t
  for t in "${EXPECTED_VO[@]}"; do
    [ -f "$COQ_DIR/_build/default/$t.vo" ] || out+=("$t")
  done
  printf '%s' "${out[*]:-}"
}

# ---- 4. sample this scope's own cgroup while the build runs ------------------
CG=$(awk -F: '$1=="0"{print $3}' /proc/self/cgroup)
CGNODE="/sys/fs/cgroup${CG}"

# Verify the envelope instead of assuming it.  A cap that silently failed to
# apply is worse than no cap: it makes a 54 GiB runaway look like a protected run.
if [ "$ALLOW_UNSIZED" != "yes" ]; then
  APPLIED_MAX=$(awk '{print $1}' "$CGNODE/memory.max" 2>/dev/null || echo unreadable)
  APPLIED_HIGH=$(awk '{print $1}' "$CGNODE/memory.high" 2>/dev/null || echo unreadable)
  want_bytes=$((MAX_KIB * 1024))
  if [ "$APPLIED_MAX" != "$want_bytes" ]; then
    fail "containment NOT enforced: cgroup $CG reports memory.max='$APPLIED_MAX', expected $want_bytes bytes. Refusing to run uncapped."
  fi
  echo "containment verified: $CG memory.max=$APPLIED_MAX memory.high=$APPLIED_HIGH"
fi
PEAK_FILE=$(mktemp)
trap 'rm -f "$PEAK_FILE"' EXIT
echo "scope cgroup: ${CG}"

(
  node="$CGNODE/memory.peak"; [ -r "$node" ] || node="$CGNODE/memory.current"
  while :; do v=$(awk '{print $1}' "$node" 2>/dev/null) || break; [ -n "$v" ] && echo "$v" > "$PEAK_FILE"; sleep 1; done
) &
SAMPLER=$!

if [ "$DESIGNATED" = "yes" ]; then
  # Raise, never lower: raising oom_score_adj on our own processes is allowed
  # unprivileged, lowering it needs CAP_SYS_RESOURCE.
  ( while :; do
      for p in $(pgrep -x coqc 2>/dev/null) $(pgrep -x rocqworker 2>/dev/null); do
        echo 500 > "/proc/$p/oom_score_adj" 2>/dev/null || true
      done; sleep 1
    done ) &
  DESIGNATED_PID=$!
fi

START_EPOCH=$(date +%s)

# ---- 4b. host watchdog: abort the build before the host has to pay for the envelope ----
# memory.max is a promise to this cgroup; the machine still has to find that memory, and when
# it cannot it swaps someone else's anonymous pages.  On this box "someone else" is the model
# server, which is exactly what earlyoom then shoots (28 such kills in 10 minutes, 2026-11-19).
# So: sample the host's own headroom while building, keep the low-water marks, and abort when
# they collapse.  A watchdog abort is reported as itself, not as a Coq failure.
WD_DIR=$(mktemp -d) || fail "cannot create a temp dir for the watchdog state"
: > "$WD_DIR/why"
trap 'rm -rf "$WD_DIR" "$PEAK_FILE"' EXIT
AVAIL_MIN_KIB=$(awk '/^MemAvailable/{print $2}' /proc/meminfo)
SWAPFREE_MIN_KIB=$(awk '/^SwapFree/{print $2}' /proc/meminfo)
SWAP_TOTAL_KIB=$(awk '/^SwapTotal/{print $2}' /proc/meminfo)

echo "build: dune build ${*:-} (default concurrency is coq/dune-workspace: jobs 2)"
echo "watchdog floors: host MemAvailable >= $((MIN_AVAIL_KIB/1024)) MiB, swap headroom >= $((MIN_SWAPFREE_KIB/1024)) MiB (swap total $((SWAP_TOTAL_KIB/1024)) MiB)"
set -m   # job control: the build gets its own process group, so the watchdog can stop the subtree
/usr/bin/time -v dune build "$@" > "$LOG" 2>&1 &
BUILD_PID=$!
while :; do
  kill -0 "$BUILD_PID" 2>/dev/null || break
  a=$(awk '/^MemAvailable/{print $2}' /proc/meminfo 2>/dev/null || echo 0)
  s=$(awk '/^SwapFree/{print $2}' /proc/meminfo 2>/dev/null || echo 0)
  [ "$a" -lt "$AVAIL_MIN_KIB" ] && AVAIL_MIN_KIB=$a
  [ "$s" -lt "$SWAPFREE_MIN_KIB" ] && SWAPFREE_MIN_KIB=$s
  reason=""
  if [ "$a" -lt "$MIN_AVAIL_KIB" ]; then
    reason="host MemAvailable fell to $((a/1024)) MiB (floor TIMBDA_COQ_MIN_AVAIL=$((MIN_AVAIL_KIB/1024)) MiB)"
  elif [ "${SWAP_TOTAL_KIB:-0}" -gt 0 ] && [ "$s" -lt "$MIN_SWAPFREE_KIB" ]; then
    reason="host swap headroom fell to $((s/1024)) MiB free of $((SWAP_TOTAL_KIB/1024)) MiB (floor TIMBDA_COQ_MIN_SWAPFREE=$((MIN_SWAPFREE_KIB/1024)) MiB)"
  fi
  if [ -n "$reason" ]; then
    echo "$reason" > "$WD_DIR/why"
    kill -TERM -- "-$BUILD_PID" 2>/dev/null || kill -TERM "$BUILD_PID" 2>/dev/null
    sleep 3
    kill -KILL -- "-$BUILD_PID" 2>/dev/null || kill -KILL "$BUILD_PID" 2>/dev/null || true
    break
  fi
  sleep 2
done
set +m
wait "$BUILD_PID"
RC=$?
END_EPOCH=$(date +%s)

[ -n "${DESIGNATED_PID:-}" ] && kill "$DESIGNATED_PID" 2>/dev/null
kill "$SAMPLER" 2>/dev/null; wait "$SAMPLER" 2>/dev/null

# ---- 5. the verdict ---------------------------------------------------------
# memory.peak/memory.current are BYTES -> MiB; cross-check against /usr/bin/time's
# maxrss (kB), which measures the whole child tree.
PEAK_MIB=$(awk 'BEGIN{m=0} {if($1>m) m=$1} END{print int(m/1048576)}' "$PEAK_FILE" 2>/dev/null)
TIME_MIB=$(awk '/Maximum resident set size/{print int($NF/1048576)}' "$LOG" 2>/dev/null)
ERRLINES=$(grep -c -e 'Error:' -e 'Admitted' "$LOG" 2>/dev/null || true)
SIGNALINES=$(grep -c 'got signal' _build/log 2>/dev/null || true)

echo "--- dune exit: $RC  (elapsed $((END_EPOCH-START_EPOCH))s) ---"
echo "--- build log, unfiltered: $LOG ($(wc -l < "$LOG") lines) ---"
cat "$LOG"
echo "--- peak: scope cgroup ${PEAK_MIB:-?} MiB   /usr/bin/time maxrss ${TIME_MIB:-?} MiB   memory.events: $(cat "$CGNODE/memory.events" 2>/dev/null | tr '\n' ' ' || echo unavailable) ---"
echo "--- 'Error:'/'Admitted' lines in the log: ${ERRLINES:-0}   'got signal' lines in coq/_build/log: ${SIGNALINES:-0} ---"

MISSING=$(missing_vos)
OOM_KILLS=$(awk '/^oom_kill /{s+=$2} END{print s+0}' "$CGNODE/memory.events" 2>/dev/null || echo 0)
HIGH_EVENTS=$(awk '/^high /{s+=$2} END{print s+0}' "$CGNODE/memory.events" 2>/dev/null || echo 0)
echo "--- host low-water while the build ran: MemAvailable min $((AVAIL_MIN_KIB/1024)) MiB, swap free low-water $((SWAPFREE_MIN_KIB/1024)) MiB of $((SWAP_TOTAL_KIB/1024)) MiB total ---"
if [ "$RC" -ne 0 ]; then
  echo "--- missing artifacts: ${MISSING:-none}   cgroup oom_kill: ${OOM_KILLS:-0}   throttled(high): ${HIGH_EVENTS:-0} ---"
  if [ -s "$WD_DIR/why" ]; then
    echo "verdict: STOPPED BY THE HOST WATCHDOG: $(cat "$WD_DIR/why")"
    echo "         This is the wrapper choosing to lose a build rather than let the machine pay for"
    echo "         the envelope: this cgroup's oom_kill=${OOM_KILLS:-0}, host MemAvailable low-water"
    echo "         $((AVAIL_MIN_KIB/1024)) MiB, swap free low-water $((SWAPFREE_MIN_KIB/1024)) MiB of"
    echo "         $((SWAP_TOTAL_KIB/1024)) MiB.  A build is restartable; the processes it was"
    echo "         displacing are not.  Next: lower TIMBDA_COQ_MEMORY_MAX, use -j 1, build a smaller"
    echo "         target, or create host headroom (tools/build/README.md).  Lower"
    echo "         TIMBDA_COQ_MIN_AVAIL only if you accept that the build now competes with the rest"
    echo "         of the box."
    exit 124
  fi
  if [ "${OOM_KILLS:-0}" -gt 0 ]; then
    echo "verdict: this build's OWN cgroup OOM-killed a worker, so the envelope MAX=$MAX"
    echo "         was too small for the unit being compiled.  Nothing else on the machine"
    echo "         was involved, and no Coq error is implied.  Options: raise" \
         "TIMBDA_COQ_MEMORY_MAX, lower the demand (split tests/KernelTest.v, vm_compute"
    echo "         instead of native conversion, -j 1), or free RAM (park the model server)."
  elif [ "${ERRLINES:-0}" = "0" ] && [ -n "$MISSING" ]; then
    echo "verdict: no Coq error AND no artifacts -> the build was killed, it did not fail."
    WINDOW="$(date -d "@$START_EPOCH" '+%H:%M:%S')..$(date -d "@$END_EPOCH" '+%H:%M:%S')"
    OOM_EVIDENCE=$(journalctl -u earlyoom -S "@$START_EPOCH" -U "@$END_EPOCH" --no-pager 2>/dev/null |
      grep -iE 'sending SIG|badness|low memory' | tail -8)
    KERNEL_EVIDENCE=$(journalctl -k -S "@$START_EPOCH" -U "@$END_EPOCH" --no-pager 2>/dev/null |
      grep -iE 'out of memory|killed process|oom' | tail -8)
    echo "earlyoom evidence for $WINDOW:"
    if [ -n "$OOM_EVIDENCE" ]; then echo "$OOM_EVIDENCE"; else echo "  (none)"; fi
    echo "kernel OOM evidence for $WINDOW:"
    if [ -n "$KERNEL_EVIDENCE" ]; then echo "$KERNEL_EVIDENCE"; else echo "  (none)"; fi
    if [ "${HIGH_EVENTS:-0}" -gt 1000 ]; then
      echo "Also measured: ${HIGH_EVENTS} memory.high throttling events in this scope - the envelope"
      echo "was fighting this build, not merely limiting it.  A stalled Coq compile and a killed one"
      echo "look identical in dune's output, which is why the verdict reads counters, not the log."
    fi
    if [ -z "$OOM_EVIDENCE" ] && [ -z "$KERNEL_EVIDENCE" ]; then
      echo "No OOM killer acted in this window.  Then the SIGTERM came from somewhere else - most" \
           "often the"
      echo "caller's own timeout (a harness that kills the scope it launched).  That is a different"
      echo "problem: raise the caller's time limit, or run with -j 1 and a smaller unit."
    else
      echo "next steps: -j 1, split tests/KernelTest.v, raise the envelope if the cgroup limit was" \
           "the thing that fired,"
      echo "            free RAM, or tell earlyoom to avoid the toolchain:"
      echo "            --avoid '(^|/)(dune|coqc|rocq|rocqworker|nix|gcc|ld|as)\$' (root; earlyoom" \
           "1.7 spells it --avoid, not --ignore)."
    fi
  fi
  exit "$RC"
fi
[ -n "$MISSING" ] && fail "dune exited 0 but expected artifacts are missing: $MISSING (vacuous build)"
echo "ok: all ${#EXPECTED_VO[@]} expected .vo artifacts present, dune exit 0"
