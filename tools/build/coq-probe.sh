#!/usr/bin/env bash
# Bounded single-file probe compile, for finding which kernel test proof is the
# memory hog.  Run INSIDE a capped scope:
#   systemd-run --user --scope -p MemoryHigh=1200M -p MemoryMax=1600M -p MemorySwapMax=0 \
#     tools/build/coq-probe.sh /tmp/opencode/probeA.v   (from the repo root)
#
# It refuses to run if the cap it was given is not actually in force (the mistake
# that made a 54 GiB compile look "contained" earlier), and it never judges a
# result by filtered output: exit status plus the unfiltered log file.
set -uo pipefail
V="${1:?probe .v file}"
LIMIT="${PROBE_TIMEOUT:-600}"
COQ_DIR="$(cd "$(dirname "$0")/../.." && pwd)/coq"
LOG="${V%.v}.log"

CG=/sys/fs/cgroup$(awk -F: '$1=="0"{print $3}' /proc/self/cgroup)
MAX=$(awk '{print $1}' "$CG/memory.max" 2>/dev/null || echo max)
if [ "$MAX" = "max" ]; then
  echo "PROBE REFUSED: memory.max=max in $CG - no cap in force. Invoke under systemd-run." >&2
  exit 9
fi
echo "cap in force: $CG memory.max=$MAX memory.high=$(awk '{print $1}' "$CG/memory.high")"
echo "probe: $V (wall limit ${LIMIT}s)"

cd "$COQ_DIR" || exit 9
start=$(date +%s)
timeout "$LIMIT" /usr/bin/time -v rocq compile -Q _build/default Timbda "$V" > "$LOG" 2>&1
rc=$?
elapsed=$(( $(date +%s) - start ))
echo "--- rocq exit=$rc  elapsed=${elapsed}s ---"
cat "$LOG"
echo "--- peak: $(awk '{print int($1/1048576)}' "$CG/memory.peak" 2>/dev/null || echo '?') MiB   events: $(cat "$CG/memory.events" | tr '\n' ' ') ---"
if [ "$rc" = 124 ] || [ "$rc" = 137 ]; then echo "TIMEOUT/KILLED: this probe did not finish under ${LIMIT}s"; fi
if [ "$rc" = 139 ]; then echo "SIGSEGV (Coq stack/heap overflow)"; fi
exit "$rc"
