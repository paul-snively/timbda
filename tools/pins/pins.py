#!/usr/bin/env python3
"""Version-consistency check (docs/PLAN.md sec. 6): tools/pins/pins.toml is
the pin table of record; CI asserts table == MODULE.bazel == .bazelversion
== flake.lock (and, separately, the nix flake check asserts the table against
the nixpkgs-provided tool versions). Usage: pins.py check [--offline]."""
import json
import re
import sys
import urllib.request
from pathlib import Path

try:
    import tomllib
except ImportError:
    sys.exit("python3.11+ required")

ROOT = Path(__file__).resolve().parents[2]
OFFLINE = "--offline" in sys.argv
FAILS = []


def check(ok, msg):
    print(("OK   " if ok else "FAIL ") + msg)
    if not ok:
        FAILS.append(msg)


def gh_parts(s):
    s = re.sub(r"^github:", "", s)
    s = re.sub(r"^https://github\.com/", "", s)
    s = s.rstrip("/")
    return s.split("/")


def main():
    pins = tomllib.loads((ROOT / "tools/pins" / "pins.toml").read_text())
    module = (ROOT / "MODULE.bazel").read_text()
    bazelver = (ROOT / ".bazelversion").read_text().strip()
    lock_path = ROOT / "flake.lock"
    if lock_path.exists():
        nodes = json.loads(lock_path.read_text())["nodes"]
    else:
        FAILS.append("flake.lock missing (run `nix flake lock`)")
        nodes = {"root": {}}

    def locked(input_name):
        ref = nodes["root"].get("inputs", {}).get(input_name)
        if ref is None:
            return {}
        name = ref if isinstance(ref, str) else input_name
        return (nodes.get(name) or {}).get("locked", {})

    check(bazelver == pins["bazel"]["version"],
          f".bazelversion {bazelver} == pins [bazel].version {pins['bazel']['version']}")

    m = re.search(r'bazel_dep\(\s*name\s*=\s*"llvm",\s*version\s*=\s*"([^"]+)"', module)
    check(m and m.group(1) == pins["hermetic_llvm"]["bcr_version"],
          f"MODULE.bazel llvm bazel_dep version == pins [hermetic_llvm].bcr_version "
          f"{pins['hermetic_llvm']['bcr_version']}")

    gm = re.search(r'llvm\.from_git\(\s*remote\s*=\s*"([^"]+)",\s*commit\s*=\s*"([0-9a-f]{40})"',
                   module)
    if gm:
        check(gm.group(2) == pins["llvm_project"]["dcont_vintage_commit"],
              "MODULE.bazel llvm.from_git commit == pins dcont vintage")
    else:
        print("NOTE llvm.from_git source pin not active (expected until M-2 vintage switch)")

    n = locked("nixpkgs")
    check(n.get("rev") == pins["nixpkgs"]["rev"],
          f"flake.lock nixpkgs rev == pins [nixpkgs].rev {pins['nixpkgs']['rev'][:12]}")

    for group_name in ("dcont", "formal", "haskell"):
        group = pins.get(group_name, {})
        entries = {group_name: group} if group_name == "dcont" else group
        for name, tbl in entries.items():
            if not (isinstance(tbl, dict) and tbl.get("flake_input")):
                continue
            want_rev = tbl.get("rev", "")
            owner, repo = gh_parts(tbl.get("repo") or tbl.get("upstream"))
            n = locked(tbl["flake_input"])
            check(n.get("owner") == owner and n.get("repo") == repo and n.get("rev") == want_rev,
                  f"flake.lock {tbl['flake_input']} == pins {owner}/{repo}@{want_rev[:12]}")

    if not OFFLINE:
        url = (f"https://bcr.bazel.build/modules/llvm/"
               f"{pins['hermetic_llvm']['bcr_version']}/MODULE.bazel")
        try:
            text = urllib.request.urlopen(url, timeout=30).read().decode()
            mm = re.search(r'LLVM_VERSION\s*=\s*"([^"]+)"', text)
            check(mm and mm.group(1) == pins["hermetic_llvm"]["llvm_default_version"],
                  f"BCR llvm {pins['hermetic_llvm']['bcr_version']} LLVM_VERSION == pins "
                  f"{pins['hermetic_llvm']['llvm_default_version']}")
        except Exception as exc:  # noqa: BLE001
            check(False, f"BCR fetch failed: {exc}")

    print(f"{'FAIL' if FAILS else 'PASS'}: {len(FAILS)} mismatch(es)")
    return 1 if FAILS else 0


if __name__ == "__main__":
    sys.exit(main())
