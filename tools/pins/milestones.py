#!/usr/bin/env python3
"""Milestone-status consistency (docs/PLAN.md sec. 6 doctrine, TOOLING T-005):
tools/pins/milestones.toml is the table of record; the README's "Milestones at a
glance" table must mirror it exactly; the GitHub About section is derived from
the latest CLOSED milestone.  Subcommands:

  check       assert README table == milestones.toml (and PLAN closure dates)
  about       print the derived About string (with the 350-char cap assertion)
  sync-about  PATCH the GitHub About via gh and verify the round-trip

Anti-vacuity, same pattern as every pins check: the README table must have
EXACTLY one row per milestone, in order (missing rows, extra rows, and a
missing section are all FAILs); a CLOSED milestone PLAN dates must appear in
PLAN; the derived About must fit GitHub's 350-char cap."""
import re
import subprocess
import sys
from pathlib import Path

try:
    import tomllib
except ImportError:
    sys.exit("python3.11+ required")

ROOT = Path(__file__).resolve().parents[2]
FAILS = []


def check(ok, msg):
    print(("OK   " if ok else "FAIL ") + msg)
    if not ok:
        FAILS.append(msg)


def norm(s):
    return " ".join(s.split())


def load():
    return tomllib.loads((ROOT / "tools" / "pins" / "milestones.toml").read_text())


def expected_rows(pins):
    """The rows the README must carry, derived from the table of record."""
    rows = []
    for mm in pins["milestone"]:
        status = f"CLOSED {mm['closed']}" if mm.get("closed") else mm["status"]
        rows.append((mm["id"], norm(mm["summary"]), status))
    return rows


def readme_rows():
    """Parse the README milestone table: `| id | summary | status |` rows inside
    the '## Milestones at a glance' section; header/separator skipped."""
    text = (ROOT / "README.md").read_text()
    m = re.search(r"^## Milestones at a glance\s*$", text, re.M)
    if not m:
        return None
    tail = text[m.end():]
    nxt = re.search(r"^## ", tail, re.M)
    section = tail[: nxt.start()] if nxt else tail
    rows = []
    for line in section.splitlines():
        line = line.strip()
        if not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip("|").split("|")]
        if len(cells) != 3:
            continue
        if cells[0] == "Milestone" or set(cells[0]) <= set("-: "):
            continue
        rows.append((cells[0], norm(cells[1]), norm(cells[2].strip("*"))))
    return rows


def latest_closed(pins):
    dated = [mm for mm in pins["milestone"] if mm["status"] == "CLOSED" and mm.get("closed")]
    return max(dated, key=lambda mm: mm["closed"]) if dated else None


def about_string(pins):
    mm = latest_closed(pins)
    if mm is None:
        return None
    nxt = next((x for x in pins["milestone"] if x["status"] != "CLOSED"), None)
    s = (pins["about"]["prefix"]
         + f"Latest milestone: {mm['id']} closed {mm['closed']} - {mm['about_line']} "
         + (f"Next: {nxt['id']}." if nxt else "All milestones closed."))
    return s + pins["about"]["suffix"]


def do_check():
    pins = load()
    want = expected_rows(pins)
    rows = readme_rows()
    if rows is None:
        check(False, "README has no '## Milestones at a glance' section")
    elif rows != want:
        detail = "row count differs" if len(rows) != len(want) else [
            (w, r) for w, r in zip(want, rows) if w != r]
        check(False, f"README milestone table != milestones.toml "
                     f"({len(rows)} rows vs {len(want)}; {detail})")
    else:
        check(True, f"README milestone table == milestones.toml ({len(want)} rows, in order)")

    for mm in pins["milestone"]:
        check(mm["status"] in ("CLOSED", "NOT STARTED"),
              f"{mm['id']} status '{mm['status']}' is CLOSED or NOT STARTED")

    plan = (ROOT / "docs" / "PLAN.md").read_text()
    for mm in pins["milestone"]:
        if mm["status"] == "CLOSED" and mm.get("closed"):
            check(f"CLOSED {mm['closed']}" in plan or f"closed {mm['closed']}" in plan,
                  f"PLAN records {mm['id']} closed {mm['closed']}")

    s = about_string(pins)
    check(s is not None, "About string derivable (at least one dated CLOSED milestone)")
    if s:
        check(len(s) <= 350, f"About string fits GitHub cap ({len(s)} <= 350)")
    return pins


def repo_slug():
    url = subprocess.run(["git", "remote", "get-url", "origin"], capture_output=True,
                         text=True, check=True).stdout.strip()
    m = re.search(r"github\.com[:/](?P<o>[^/]+)/(?:(?P<r>[^/]+?)(?:\.git)?/?)$", url)
    if not m:
        sys.exit(f"FAIL: cannot parse owner/repo from origin url {url!r}")
    return f"{m.group('o')}/{m.group('r')}"


def gh_api(*args):
    return subprocess.run(["gh", "api", *args], capture_output=True, text=True)


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "check"
    pins = do_check()
    if FAILS and cmd != "about":
        print(f"FAIL: {len(FAILS)} mismatch(es)")
        return 1
    if cmd == "about":
        print(about_string(pins))
        return 0
    if cmd == "sync-about":
        desc = about_string(pins)
        slug = repo_slug()
        # gh api takes the method as -X/--method; a bare "PATCH" positional is
        # parsed as an endpoint (measured: "accepts 1 arg(s), received 2").
        r = gh_api("-X", "PATCH", f"/repos/{slug}", "-f", f"description={desc}")
        if r.returncode != 0:
            print(f"FAIL: gh PATCH: {r.stderr.strip()}")
            return 1
        got = gh_api(f"/repos/{slug}", "--jq", ".description")
        if got.stdout.strip() != desc:
            print(f"FAIL: About round-trip mismatch: {got.stdout.strip()!r}")
            return 1
        print(f"OK About synced on {slug}: {desc}")
        return 0
    print(f"PASS: milestones table of record consistent ({len(pins['milestone'])} milestones)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
