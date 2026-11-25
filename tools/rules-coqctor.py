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

The same tool also transcribes the eval-side AST surface (coq/Eval.v's
`Inductive RuleID` + `selected_rows` -> TimbdaRuleAstGroup defs) and the
`RewSound_*` lemma inventory (-> per-row `soundLemmas` fields).  With both
earlier phases applied, re-running it is a verification pass: it re-checks
the record fields against the generated coq/RewRules.v, the kernel-side RuleID
block (now the generated coq/RuleAst.v), and coq/Denotation.v's lemma
inventory - and applying it a second time is a proven no-op.

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
  string papForm = "";            // audit-comment text after `tier:<n> | `
  list<string> soundLemmas = [];  // RewSound_* lemma names this row's kernel
                                  // evidence consists of (transcribed from
                                  // coq/Denotation.v; a deferred row carries
                                  // none - docs/RULES-AUDIT.md sec. 4)"""


def td_escape(s):
    return s.replace("\\", "\\\\").replace('"', '\\"')


def td_unescape(s):
    return s.replace('\\"', '"').replace("\\\\", "\\")


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


# ---------- eval-AST + soundness-lemma transcription (M1 item 1, the
# -gen-rocq-ast / -gen-rocq-checker halves): coq/Eval.v's `RuleID` /
# `selected_rows` and coq/Denotation.v's `RewSound_*` inventory move into the
# records as TimbdaRuleAstGroup defs and per-row `soundLemmas` fields, the
# same one-way direction as the ctor transcription above. ----------

EVAL_V = ROOT / "coq/Eval.v"
DENOTATION_V = ROOT / "coq/Denotation.v"

# The two SCHEMA ctor rows stand at their 1-ary and 2-ary arities
# (docs/RULES-AUDIT.md sec. 2); the audit lane carries the same map.
SCHEMA_PAIR = {"Prim1": "PrimSchema", "Prim2": "PrimSchema",
               "PrimFail1": "PrimSchemaFail", "PrimFail2": "PrimSchemaFail"}


def coq_strip(text):
    out, i, n = [], 0, len(text)
    while i < n:
        if text.startswith("(*", i):
            depth = 1
            i += 2
            while i < n and depth > 0:
                if text.startswith("(*", i):
                    depth += 1
                    i += 2
                elif text.startswith("*)", i):
                    depth -= 1
                    i += 2
                else:
                    i += 1
            continue
        out.append(text[i])
        i += 1
    return "".join(out)


def parse_ruleid_groups(raw):
    """`Inductive RuleID` block -> [(comment, [R_names])] in file order.  The
    surface is the generated coq/RuleAst.v (or, first run only, the legacy
    hand-glued Eval.v block); a group may wrap its ctor list and/or its
    comment onto continuation lines."""
    groups = []
    for line in raw[raw.index("Inductive RuleID : Type :="):].splitlines()[1:]:
        s = line.strip()
        if s.startswith("| R_"):
            cm = re.search(r"\(\* (.*?) \*\)", s)
            head = s[:cm.start()] if cm else s
            groups.append([cm.group(1).strip() if cm else "",
                           re.findall(r"\bR_\w+\b", head)])
            if head.rstrip().endswith("."):
                break
        elif groups and s.startswith("(*"):
            cm = re.search(r"\(\* (.*?) \*\)", s)
            if cm and not groups[-1][0]:
                groups[-1][0] = cm.group(1).strip()
    assert groups, "RuleID block has no ctor lines"
    return [(c, ids) for c, ids in groups]


def parse_selected_rows(raw):
    m = re.search(r"Definition selected_rows : list RuleID :=\s*\[([^\]]+)\]", raw)
    assert m, "no selected_rows in coq/Eval.v"
    return re.findall(r"\bR_\w+\b", m.group(1))


def parse_sound_lemmas(raw):
    """RewSound_* lemma suffixes actually stated (code-only scan)."""
    return sorted(set(re.findall(r"(?m)^Lemma RewSound_(\w+) :", coq_strip(raw))))


def ast_group_name(comment):
    m = re.search(r"fig:(\d+)", comment)
    if m:
        return "AstGroupFig" + m.group(1)
    return "AstGroup" + "".join(w.capitalize() for w in re.findall(r"\w+", comment))


def main():
    apply = "--apply" in sys.argv
    td = RULES_TD.read_text()
    ctor_done = "coqForall" in td
    ast_done = "TimbdaRuleAstGroup" in td      # AST groups already transcribed
    lemmas_done = "list<string> soundLemmas" in td

    # ---- ctor half ---------------------------------------------------------------
    if ctor_done:
        print("ctor surface already transcribed (coq* fields in the records); "
              "its hand-glued source coq/Rewriting.v is retired - skipping that half")
        gen = (ROOT / "coq/RewRules.v").read_text()
        td_ctors = re.findall(r'let ctor = "(\w+)";', td)
        gen_ctors = re.findall(r"(?m)^\| (Rew\w+) : ", gen)
        assert sorted(td_ctors) == sorted(gen_ctors) and len(td_ctors) == 35, \
            "ctor rows in records != generated RewRules.v ctors"
        print("ctor rows in records == generated coq/RewRules.v ctors: 35/35")
        groups = ctors = None
    else:
        groups, ctors = parse_rewriting(REWRITING.read_text())
        print(f"parsed {len(ctors)} ctors in {len(groups)} emission groups:")
        for g in groups:
            print(f"  {g['headerLines'][0]!r}: {len(g['ctors'])} ctors")
        bad = [n for n, c in ctors.items()
               if flatten(render_ctor_sig(n, c)) != c["srcFlat"]]
        assert not bad, "roundtrip mismatch: " + ", ".join(bad)
        print(f"roundtrip: all {len(ctors)} ctors re-render from fields "
              f"(whitespace-normalized); 0 mismatches")
        ctor2def = {}
        for name, body in re.findall(r"def (\w+) : TimbdaRuleRecord \{(.*?)\n\}", td, re.S):
            m = re.search(r'let ctor = "(\w+)";', body)
            if m:
                ctor2def[m.group(1)] = name
        missing = sorted(set(ctors) - set(ctor2def))
        extra = sorted(set(ctor2def) - set(ctors))
        assert not missing and not extra, f"ctor/record mismatch missing={missing} extra={extra}"
        print(f"ctor rows in TimbdaRules.td: {len(ctor2def)} - exact match with the coq ctors")

    # ---- eval-AST + soundness half -----------------------------------------------
    # The kernel-side AST surface: the generated coq/RuleAst.v once it exists
    # (M1 item 1), the hand-glued Eval.v block on the very first run.
    eval_raw = EVAL_V.read_text()
    ast_gen = ROOT / "coq/RuleAst.v"
    ast_src = ast_gen.read_text() if ast_gen.exists() else eval_raw
    ast_src_name = "coq/RuleAst.v (generated)" if ast_gen.exists() else "coq/Eval.v (hand-glued)"
    lemma_suffixes = parse_sound_lemmas(DENOTATION_V.read_text())
    ast_groups = parse_ruleid_groups(ast_src)
    rule_ids = [r for _, names in ast_groups for r in names]
    selected_coq = parse_selected_rows(ast_src)

    def td_fields(m):
        body = m.group(2)
        f = {k: v for k, v in re.findall(r'let (\w+) = "((?:[^"\\]|\\.)*)";', body)}
        f.update({k: int(v) for k, v in re.findall(r"let (\w+) = (\d+);", body)})
        return f
    row = {cm.group(1): td_fields(m)
           for m in re.finditer(r"def (\w+) : TimbdaRuleRecord \{(.*?)\n\}", td, re.S)
           if (cm := re.search(r'let ctor = "(\w+)";', m.group(2)))}
    if ctor_done:
        ctor_tag = {c: str(r.get("coqTag", "")) for c, r in row.items()}
    else:
        ctor_tag = {c: ctors[c]["tag"] for c in ctors}
    assert sorted(row) == sorted(ctor_tag), "ctor row bookkeeping mismatch"

    kt = {c: str(r.get("kernelTag", "")) for c, r in row.items()}
    assert set(rule_ids) == {t for t in kt.values() if t} and len(rule_ids) == len(set(rule_ids)), \
        "Eval.v RuleID ctors != distinct record kernelTags"
    # selected_rows: kernel-side order is the records' `rank` field (ctor rows
    # with selected=1, rank-ascending, kernelTag deduplicated).
    ranked = [kt[c] for c, r in sorted(row.items(), key=lambda kv: kv[1].get("rank", 0))
              if r.get("selected") and kt[c]]
    dedup, seen = [], set()
    for t in ranked:
        if t not in seen:
            dedup.append(t)
            seen.add(t)
    assert dedup == selected_coq, f"rank-derived selected_rows != Eval.v: {dedup}"

    # lemma inventory -> rows (coqTag identity, SCHEMA pair inversion).
    tag2ctor = {t: c for c, t in ctor_tag.items() if t}
    lemmas_by_ctor = {c: [] for c in row}
    for suf in lemma_suffixes:
        tag = SCHEMA_PAIR.get(suf, suf)
        assert tag in tag2ctor, f"orphan lemma RewSound_{suf} (no ctor row for tag {tag})"
        lemmas_by_ctor[tag2ctor[tag]].append(suf)
    counts = {"discharged": 0, "partial": 0, "deferred": 0}
    for c, r in row.items():
        st = str(r.get("status", "?"))
        assert st in counts, f"{c}: status {st}"
        counts[st] += 1
        want = 1 if st == "discharged" else 2 if st == "partial" else 0
        assert len(lemmas_by_ctor[c]) == want, \
            f"{c}: status {st} expects {want} RewSound lemma(s), kernel has {lemmas_by_ctor[c]}"
    assert counts == {"discharged": 15, "partial": 2, "deferred": 18}, counts

    # RuleID block roundtrip: re-render the block from the parsed groups and
    # compare whitespace-normalized against the kernel-side source; once the
    # records already carry TimbdaRuleAstGroup defs, they must re-render the
    # same groups (the records are then the source of truth).
    regen = ["Inductive RuleID : Type :=\n"]
    for gi, (comment, names) in enumerate(ast_groups):
        line = "| " + " | ".join(names)
        if gi == len(ast_groups) - 1:
            line += "."                  # the inductive terminator rides the
                                         # last ctor, exactly as in the source
        if comment:
            line += "        (* " + comment + " *)"
        regen.append(line)
    end = next(e for e in ("(* selected_rows", "(* ---------- redex recognisers")
               if e in ast_src)
    src_block = ast_src[ast_src.index("Inductive RuleID"):ast_src.index(end)]
    assert flatten("\n".join(regen)) == flatten(src_block), "RuleID block roundtrip mismatch"
    if ast_done:
        td_groups = [(td_unescape(m.group(2)).strip(),
                      re.findall(r"\"([^\"]+)\"", m.group(1)))
                     for m in re.finditer(
                         r'def \w+ : TimbdaRuleAstGroup \{\s*let ruleIds = \[([^\]]*)\];\s*'
                         r'let comment = "((?:[^"\\]|\\.)*)";', td)]
        assert td_groups == ast_groups, "record AstGroup defs != the kernel-side RuleID block"
    print(f"eval-AST ({ast_src_name}): {len(rule_ids)} RuleIDs in {len(ast_groups)} groups "
          f"({', '.join(ast_group_name(c) for c, _ in ast_groups)}); "
          f"selected_rows = rank order ({len(selected_coq)}); "
          f"lemmas {len(lemma_suffixes)} = 15 discharged + 2x2 partial")

    if not apply:
        print("dry run; pass --apply to rewrite dialect/TimbdaRules.td")
        return

    # class fields: the full ctor surface (if not already there) + soundLemmas.
    if ctor_done:
        if not lemmas_done:
            anchor = '  string papForm = "";            // audit-comment text after `tier:<n> | `\n}'
            assert td.count(anchor) == 1, "papForm class anchor not unique"
            td = td.replace(anchor, '  string papForm = "";            // audit-comment text after `tier:<n> | `\n'
                            "  list<string> soundLemmas = [];  // RewSound_* lemma names this row's kernel\n"
                            "                                  // evidence consists of (transcribed from\n"
                            "                                  // coq/Denotation.v; a deferred row carries\n"
                            "                                  // none - docs/RULES-AUDIT.md sec. 4)\n}")
    else:
        # TimbdaRuleRecord is the class with the commented tags line; the
        # ContextExtern class ends with a plain one.
        anchor = "  list<string> tags = [];     // audit notes (deferral class, deviation id, ...)\n}"
        assert td.count(anchor) == 1, "class anchor not unique"
        td = td.replace(anchor, "  list<string> tags = [];     // audit notes (deferral class, deviation id, ...)\n"
                        + CLASS_FIELDS + "\n}")

    def inject(m):
        name, body = m.group(1), m.group(2)
        cm = re.search(r'let ctor = "(\w+)";', body)
        if not cm:
            return m.group(0)
        lines = []
        if not ctor_done:
            c = ctors[cm.group(1)]
            lines.append(f'  let coqTag = "{td_escape(c["tag"])}";')
            if c["forall"]:
                lines.append(f'  let coqForall = "{td_escape(c["forall"])}";')
            if c["hyps"]:
                lines.append("  let coqHyps = [" + ", ".join(f'"{td_escape(h)}"' for h in c["hyps"]) + "];")
            lines.append(f'  let coqLhs = "{td_escape(c["lhs"])}";')
            lines.append(f'  let coqRhs = "{td_escape(c["rhs"])}";')
            lines.append(f'  let papForm = "{td_escape(c["papForm"])}";')
        if lemmas_by_ctor[cm.group(1)] and "soundLemmas" not in body:
            lines.append("  let soundLemmas = [" + ", ".join(
                f'"RewSound_{x}"' for x in lemmas_by_ctor[cm.group(1)]) + "];")
        return f"def {name} : TimbdaRuleRecord {{{body}\n" + "\n".join(lines) + "\n}" if lines else m.group(0)

    td = re.sub(r"def (\w+) : TimbdaRuleRecord \{(.*?)\n\}", inject, td, flags=re.S)

    parts = []
    if not ctor_done:
        parts += ["", "// ---------- -gen-rocq-rules emission groups (header comment lines and",
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

    if not ast_done:
        parts += ["", "// ---------- -gen-rocq-ast emission groups (the eval-side RuleID",
                  "// block: linewise ctor groups + their fig comments, transcribed verbatim",
                  "// by tools/rules-coqctor.py; the audit lane asserts the groups cover",
                  "// every distinct kernelTag exactly once and that selected_rows is the",
                  "// record `rank` order). ----------",
                  "class TimbdaRuleAstGroup {", "  list<string> ruleIds = [];",
                  "  string comment = \"\";", "}"]
        agnames = []
        for comment, names in ast_groups:
            gn = ast_group_name(comment)
            assert gn not in agnames, "two RuleID groups, same name"
            agnames.append(gn)
            parts += [f"def {gn} : TimbdaRuleAstGroup {{",
                      "  let ruleIds = [" + ", ".join(f'"{r}"' for r in names) + "];",
                      f"  let comment = \"{td_escape(comment)}\";", "}"]
        parts += ["def TimbdaRuleAstOrder {",
                  "  list<string> groups = [" + ", ".join(f'"{g}"' for g in agnames) + "];",
                  "}"]

    if not parts and td == RULES_TD.read_text():
        print("no-op: the records already carry the full transcribed surface; "
              "the verification printed above is the claim")
        return

    RULES_TD.write_text(td.rstrip("\n") + "\n" + "\n".join(parts) + "\n")
    gained = ("coq* fields + soundLemmas" if not ctor_done
              else "soundLemmas" if not lemmas_done else "nothing (records unchanged)")
    print(f"APPLIED: ctor records gained {gained}; {len(ast_groups)} RuleID-group defs "
          f"({'appended' if not ast_done else 'already present'}); {RULES_TD} rewritten")


if __name__ == "__main__":
    main()
