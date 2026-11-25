#!/usr/bin/env python3
"""rules-coqctor.py - move the hand-glued `Rew` ctor surface into the records.

M1 item 1 (docs/PLAN.md sec. 5.0) requires the `Rew` constructors in coq/ to
become GENERATED artifacts of the TimbdaRuleRecord family.  The signatures are
today bespoke in coq/Rewriting.v; this tool transcribes them, mechanically and
losslessly, into structured `coq*` fields on the records in
dialect/TimbdaRules.td, plus the emission-group definitions (group header
comment lines + ctor order, exactly as the hand-glued file has them).

Direction matters for the audit story: this is the one-way move of the source
of truth INTO the records (the hand-glued ctor block is retired afterwards);
it is not a reconstruction from generated files.  After this tool ran, the
audit lane asserts ctor-equality between record fields and the GENERATED coq
file; generation determinism is attested by checks.tblgen-rocq-golden, and
semantic equivalence by the kernel lane re-compiling every unchanged proof
against the generated constructors.

Usage: python3 tools/rules-coqctor.py [--apply]
  (no flag: dry run with a summary; --apply rewrites dialect/TimbdaRules.td)
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REWRITING = ROOT / "coq/Rewriting.v"
RULES_TD = ROOT / "dialect/TimbdaRules.td"

CLASS_FIELDS = """  // Coq ctor surface consumed by dialect/tblgen-rocq -gen-rocq-rules
  // (coq/RewRules.v).  Transcribed 2026-11-25 from the hand-glued constructors
  // by tools/rules-coqctor.py; the audit lane asserts generated ctor == these
  // fields and checks.tblgen-rocq-golden attests regeneration byte-for-byte.
  string coqTag = "";             // audit-tag name (may differ from the ctor
                                  // suffix: RewPrim carries tag PrimSchema)
  string coqForall = "";          // the `forall ...` text; "" = no forall
  list<string> coqHyps = [];      // one entry per hypothesis
  string coqLhs = "";             // lhs term of the `Rew lhs rhs` conclusion
  string coqRhs = "";             // rhs term (one group or an atom)
  string papForm = "";            // audit-comment text after `tier:<n> | `"""


def td_escape(s):
    return s.replace("\\", "\\\\").replace('"', '\\"')


def flatten(s):
    return re.sub(r"\s+", " ", s).strip()


def top_split_arrows(s):
    """Split at every top-level ` -> `.  Returns (hyp_segments, conclusion)."""
    segs, i, depth, last = [], 0, 0, 0
    while i < len(s):
        c = s[i]
        if c in "([":
            depth += 1
        elif c in ")]":
            depth -= 1
        elif depth == 0 and s.startswith(" -> ", i):
            segs.append(s[last:i].strip())
            i += 4
            while i < len(s) and s[i] == " ":
                i += 1
            last = i
            continue
        i += 1
    return segs, s[last:].strip()


def split_concl(concl):
    """`lhs rhs` (top-level): rhs is the LAST top-level group/atom."""
    toks, i, depth, cur = [], 0, 0, ""
    while i < len(concl):
        c = concl[i]
        if c in "([{":
            depth += 1
            cur += c
        elif c in ")]}":
            depth -= 1
            cur += c
        elif c == " " and depth == 0:
            if cur:
                toks.append(cur)
                cur = ""
        else:
            cur += c
        i += 1
    if cur:
        toks.append(cur)
    assert len(toks) >= 2, concl
    return " ".join(toks[:-1]), toks[-1]


def parse_rewriting(raw):
    """Extract (groups, ctors) from the Inductive Rew region of coq/Rewriting.v.

    groups: [{headerLines, ctors: [names in emission order]}]
    ctors:  {name: {forall, hyps, lhs, rhs, fig, tier, papForm, srcFlat}}
    """
    start = raw.index("Inductive Rew : Expr -> Expr -> Type :=")
    end = raw.index("(* ---------- Context closure")
    lines = raw[start:end].splitlines()

    groups, ctors = [], {}
    i = 0
    while i < len(lines):
        line = lines[i]
        if line.startswith("(* ----------"):
            hdr = []
            while True:
                hdr.append(line)
                if line.rstrip().endswith("*)"):
                    break
                i += 1
                line = lines[i]
            groups.append({"headerLines":
                           [re.sub(r"^\(\*\s*| \*\)$", "", h).strip() for h in hdr],
                           "ctors": []})
            # i points at the header's last line; step past it or the outer
            # loop re-enters this branch forever (a one-line header is its own
            # terminator).
            i += 1
        elif line.startswith("| Rew"):
            name = re.match(r"\| (Rew\w+) : ", line).group(1)
            block = [line]
            i += 1
            while i < len(lines):
                nxt = lines[i]
                if (nxt.startswith("| Rew") or nxt.startswith("(* ----------")
                        or nxt.rstrip() == "."):
                    break
                block.append(nxt)
                i += 1
            block = "\n".join(block)
            am = re.search(r"\(\* audit: (\w+) \| fig:(\d+) \| tier:(\d+) \| (.*?) \*\)\s*$",
                           block.strip(), re.S)
            assert am, f"no audit tag for {name}"
            src_flat = flatten(block[:am.start()] + block[am.end():])
            body = src_flat[len("| " + name + " : "):]
            forall_txt, hyps = "", []
            if body.startswith("forall "):
                # the forall segment ends at the FIRST top-level comma (binder
                # groups may carry parenthesized commas); keep it verbatim - the
                # backend round-trips it exactly.
                first = None
                depth = 0
                for j, c in enumerate(body[len("forall "):]):
                    if c in "([":
                        depth += 1
                    elif c in ")]":
                        depth -= 1
                    elif c == "," and depth == 0:
                        first = j
                        break
                assert first is not None, name
                forall_txt = body[len("forall "):len("forall ") + first].strip()
                body = body[len("forall ") + first + 1:].strip()
            hyps, concl = top_split_arrows(body)
            assert concl.startswith("Rew "), (name, concl)
            lhs, rhs = split_concl(concl[len("Rew "):])
            ctors[name] = {"tag": am.group(1), "forall": forall_txt, "hyps": hyps, "lhs": lhs, "rhs": rhs,
                           "fig": int(am.group(2)), "tier": int(am.group(3)),
                           "papForm": flatten(am.group(4)), "srcFlat": src_flat}
            groups[-1]["ctors"].append(name)
        else:
            i += 1
    return groups, ctors


def render_ctor_sig(name, c):
    sig = "| " + name + " : "
    if c["forall"]:
        sig += "forall " + c["forall"] + ", "
    for h in c["hyps"]:
        sig += h + " -> "
    return sig + "Rew " + c["lhs"] + " " + c["rhs"]


def main():
    apply = "--apply" in sys.argv
    groups, ctors = parse_rewriting(REWRITING.read_text())
    print(f"parsed {len(ctors)} ctors in {len(groups)} emission groups:")
    for g in groups:
        print(f"  {g['headerLines'][0]!r}: {len(g['ctors'])} ctors")

    bad = []
    for name, c in ctors.items():
        if flatten(render_ctor_sig(name, c)) != c["srcFlat"]:
            bad.append(name)
    assert not bad, "roundtrip mismatch: " + ", ".join(bad)
    print(f"roundtrip: all {len(ctors)} ctors re-render from fields "
          f"(whitespace-normalized); 0 mismatches")

    td = RULES_TD.read_text()
    assert "coqForall" not in td, "TimbdaRules.td already carries coq* fields"
    ctor2def = {}
    for name, body in re.findall(r"def (\w+) : TimbdaRuleRecord \{(.*?)\n\}", td, re.S):
        m = re.search(r'let ctor = "(\w+)";', body)
        if m:
            ctor2def[m.group(1)] = name
    missing = sorted(set(ctors) - set(ctor2def))
    extra = sorted(set(ctor2def) - set(ctors))
    assert not missing and not extra, f"ctor/record mismatch missing={missing} extra={extra}"
    print(f"ctor rows in TimbdaRules.td: {len(ctor2def)} - exact match with the coq ctors")

    if not apply:
        print("dry run; pass --apply to rewrite dialect/TimbdaRules.td")
        return

    # TimbdaRuleRecord is the class with the commented tags line; the
    # ContextExtern class ends with a plain one.
    anchor = "  list<string> tags = [];     // audit notes (deferral class, deviation id, ...)\n}"
    assert td.count(anchor) == 1, "class anchor not unique"
    td = td.replace(anchor, "  list<string> tags = [];\n" + CLASS_FIELDS + "\n}")

    def inject(m):
        name, body = m.group(1), m.group(2)
        cm = re.search(r'let ctor = "(\w+)";', body)
        if not cm:
            return m.group(0)
        c = ctors[cm.group(1)]
        lines = []
        lines.append(f'  let coqTag = "{td_escape(c["tag"])}";')
        if c["forall"]:
            lines.append(f'  let coqForall = "{td_escape(c["forall"])}";')
        if c["hyps"]:
            lines.append("  let coqHyps = [" + ", ".join(f'"{td_escape(h)}"' for h in c["hyps"]) + "];")
        lines.append(f'  let coqLhs = "{td_escape(c["lhs"])}";')
        lines.append(f'  let coqRhs = "{td_escape(c["rhs"])}";')
        lines.append(f'  let papForm = "{td_escape(c["papForm"])}";')
        return f"def {name} : TimbdaRuleRecord {{{body}\n" + "\n".join(lines) + "\n}"

    td = re.sub(r"def (\w+) : TimbdaRuleRecord \{(.*?)\n\}", inject, td, flags=re.S)

    parts = ["", "// ---------- -gen-rocq-rules emission groups (header comment lines and",
             "// ctor order transcribed verbatim from the hand-glued ctor file by",
             "// tools/rules-coqctor.py; the audit lane asserts the groups cover the 35",
             "// ctor rows exactly once). ----------",
             "class TimbdaRuleGroup {", "  list<string> headerLines = [];",
             "  list<string> ctors = [];", "}"]
    gnames = []
    for g in groups:
        assert g["headerLines"], "group with no header"
        fig = ctors[g["ctors"][0]]["fig"]
        gn = f"GenGroupFig{fig}"
        assert gn not in gnames, "two groups, same fig"
        gnames.append(gn)
        hdr = ", ".join(f'"{td_escape(h)}"' for h in g["headerLines"])
        ctorl = ", ".join(f'"{c}"' for c in g["ctors"])
        parts += [f"def {gn} : TimbdaRuleGroup {{",
                  f"  let headerLines = [{hdr}];",
                  f"  let ctors = [{ctorl}];", "}"]
    parts += ["def TimbdaRuleGenOrder {",
              "  list<string> groups = [" + ", ".join(f'"{g}"' for g in gnames) + "];",
              "}"]
    RULES_TD.write_text(td.rstrip("\n") + "\n" + "\n".join(parts) + "\n")
    print(f"APPLIED: fields on {len(ctor2def)} ctor records; {len(groups)} group defs "
          f"{gnames}; {RULES_TD} rewritten")


if __name__ == "__main__":
    main()
