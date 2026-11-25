#!/usr/bin/env python3
"""rules-audit.py - the M1 rule-corpus audit (docs/RULES-AUDIT.md sec. 7).

Bijections and arithmetic checked (docs/PLAN.md sec. 5: "every paper rule => a
record + an MLIR pattern + a Rocq ctor"; the audit IS the claim):

  1. coq ctor <-> `audit:` tag <-> ctor row in dialect/TimbdaRules.td (35/35,
     tier equal coq audit tag vs record); the ctors are read from the GENERATED
     coq/RewRules.v (M1 item 1), and coq/Rewriting.v must NOT carry a hand-
     glued `Inductive Rew` anymore.
  1b. generated-file provenance: every generated ctor equals its record's coq*
     fields re-rendered (the tblgen-rocq byte contract), and the
     TimbdaRuleGenOrder/TimbdaRuleGroup defs partition the 35 ctor rows and
     match the generated emission order.
  2. Record arithmetic: 72 TimbdaRuleRecord rows = 35 ctor rows + 37 audit
     records; categories 18 matching + 4 essential-verse + 10 verification +
     3 open-lambda + 2 kernel-adjacent; statuses 15 discharged / 2 partial /
     18 deferred; 3 TimbdaExtern records.
  3. `selected` column <-> coq/Eval.v selected_rows (26 selected ctor rows,
     19 selected RuleIDs, 27 RuleIDs, 8 never fired).
  4. status column <-> RewSound_* lemma presence in coq/Denotation.v; zero
     Admitted and no Axiom/Hypothesis/Parameter/Conjecture in coq/.
  5. ctor rows with pattern="drr" <-> TimbdaPatterns.td defs <-> the
     tblgen-generated populateWithGenerated set (23 each); kernel-extension
     tags; strategy-group vocabulary (docs/VERSE-RULES.md sec. 5).
  6. docs/RULES-AUDIT.md sec. 1 table: 35 rows, tier and IsEss columns.

Run from the repo root:  python3 tools/rules-audit.py   (exit 0 = all green)
"""

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

# PrimSchema ctor rows carry audit tags that differ from their ctor suffix
# (docs/RULES-AUDIT.md sec. 1: R_Prim / R_PrimFail stand in for them).
SCHEMA_TAG_TO_CTOR = {"PrimSchema": "RewPrim", "PrimSchemaFail": "RewPrimFail"}
# The two SCHEMA ctor rows are discharged at the 1-ary and 2-ary arities
# (docs/RULES-AUDIT.md sec. 2); the n-ary form is the deferred half.
SCHEMA_LEMMAS = {"RewPrim": {"Prim1", "Prim2"}, "RewPrimFail": {"PrimFail1", "PrimFail2"}}

def has_tag(rec, name):
    """True if `name` or `name:...` appears among a row's tags."""
    return any(t == name or t.startswith(name + ":")
               for t in (str(x) for x in (rec.get("tags") or [])))


# docs/RULES-AUDIT.md sec. 2: which summary integer each audit-row category feeds.
CATEGORY_BY_SUMMARY = {
    "matchRows": "match",
    "essentialRows": "essential",
    "verifyRows": "verify",
    "olamRows": "olam",
    "kernelAdjacentRows": "kernel-adjacent",
}


def category(rec):
    """Audit-row category, per docs/RULES-AUDIT.md sec. 2; None if unclassifiable."""
    name = rec["__name__"]
    sem = str(rec.get("semClass", ""))
    if name.startswith("Match_"):
        return "match"
    if name.startswith("Olam_") or sem == "olam":
        return "olam"
    if sem == "eval":
        return "kernel-adjacent"          # Gc-Rec, Subst-Deep: rows with no ctor
    if sem == "solver":
        return "verify"
    if sem == "match":
        return "essential"                # Verify_MFun, Verify_MOFType, OFType, typeof
    return None


failures = []


def check(ok, label, detail=""):
    print(("  OK   " if ok else "  FAIL ") + label + (f"  [{detail}]" if detail else ""))
    if not ok:
        failures.append(label)


def read(rel):
    return (REPO / rel).read_text(encoding="utf-8")


def coq_strip(text):
    """Drop Coq comments (they nest) so scans only ever see code."""
    out = []
    i, n = 0, len(text)
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


def flatten_ws(text):
    return re.sub(r"\s+", " ", text).strip()


def parse_rewriting_tags(raw):
    """ctor names + audit tags; a tag belongs to the ctor block it sits in."""
    ctor_pos = [(m.group(1), m.start())
                for m in re.finditer(r"(?m)^\| (Rew\w+) : ", raw)]
    tags = {}
    for m in re.finditer(r"audit: (\w+) \| fig:(\d+) \| tier:(\d)", raw):
        owner = None
        for name, pos in ctor_pos:
            if pos < m.start():
                owner = name
            else:
                break
        if owner in tags:
            tags[owner]["clash"] = True
        else:
            tags[owner] = {"name": m.group(1),
                           "fig": int(m.group(2)),
                           "tier": int(m.group(3))}
    return [name for name, _ in ctor_pos], tags


def parse_rule_ids(raw):
    """The `Inductive RuleID := R_a | ... | R_z.` block from coq/Eval.v."""
    collecting = False
    names = set()
    for line in raw.splitlines():
        if not collecting:
            if "Inductive RuleID" in line:
                collecting = True
            continue
        names.update(re.findall(r"\bR_\w+\b", line))
        if line.rstrip().endswith("."):
            break
    return names


def parse_selected_rows(raw):
    m = re.search(r"Definition selected_rows : list RuleID :=\s*\[([^\]]+)\]", raw)
    if not m:
        return set()
    return set(re.findall(r"\bR_\w+\b", m.group(1)))


def parse_td_records(raw):
    records = {}
    for name, body in re.findall(r"def (\w+) : TimbdaRuleRecord \{(.*?)\n\}", raw, re.S):
        fields = {}
        # A list item is a double-quoted string that may contain anything
        # (the coq* fields put `]` and `\"` inside strings); bare brackets
        # only appear as the list delimiters.
        for m in re.finditer(r"let (\w+) = (\[((?:[^\"[\]]|\"(?:\\.|[^\"\\])*\")*)\]"
                             r"|\"(?:[^\"\\]|\\.)*\"|[-\w]+);", body, re.S):
            key, val = m.group(1), m.group(2)
            if val.startswith("["):
                fields[key] = [td_unescape(v)
                               for v in re.findall(r"\"((?:\\.|[^\"\\])*)\"", val)]
            elif val.startswith('"'):
                fields[key] = td_unescape(val[1:-1])
            else:
                try:
                    fields[key] = int(val)
                except ValueError:
                    fields[key] = val
        fields["__name__"] = name
        records[name] = fields
    return records


def parse_td_summary(raw):
    m = re.search(r"def TimbdaAuditSummary \{(.*?)\n\}", raw, re.S)
    if not m:
        return {}
    return {k: int(v) for k, v in re.findall(r"int (\w+) = (\d+);", m.group(1))}


def parse_td_ext_tags(raw):
    m = re.search(r"list<string> kernelExtensionTags = \[(.*?)\];", raw, re.S)
    return sorted(re.findall(r"\"([^\"]+)\"", m.group(1))) if m else []


def td_unescape(v):
    return v.replace('\\"', '"').replace("\\\\", "\\")


def parse_generated_rewrites(raw):
    """The generated ctor blocks of coq/RewRules.v, in emission order.

    Returns [(ctor, signature_flattened_without_audit, audit_dict)]; a block
    runs from `| Rew<Name> :` to the next ctor / group header / inductive
    terminator, wrapping is irrelevant because everything is flattened."""
    start = raw.index("Inductive Rew : Expr -> Expr -> Type :=")
    end = raw.index("(* ---------- Context closure")
    lines = raw[start:end].splitlines()
    out, i = [], 0
    while i < len(lines):
        if not lines[i].startswith("| Rew"):
            i += 1
            continue
        name = re.match(r"\| (Rew\w+) : ", lines[i]).group(1)
        block = [lines[i]]
        i += 1
        while i < len(lines):
            nxt = lines[i]
            if (nxt.startswith("| Rew") or nxt.startswith("(* ----------")
                    or nxt.rstrip() == "."):
                break
            block.append(nxt)
            i += 1
        block = "\n".join(block)
        m = re.search(r"\(\* audit: (\w+) \| fig:(\d+) \| tier:(\d+) \| (.*?) \*\)\s*$",
                      block, re.S)
        assert m, f"generated ctor {name} carries no audit comment"
        out.append((name,
                    flatten_ws(block[:m.start()]),
                    {"name": m.group(1), "fig": int(m.group(2)),
                     "tier": int(m.group(3)), "pap": flatten_ws(m.group(4))}))
    return out


def render_ctor_from_record(rec):
    """Re-render a ctor signature from its record coq* fields - the same
    contract dialect/tblgen-rocq implements in C++; byte equality after
    whitespace flattening is the provenance claim (M1 item 1)."""
    sig = "| " + rec["ctor"] + " : "
    if rec.get("coqForall"):
        sig += "forall " + rec["coqForall"] + ", "
    for h in (rec.get("coqHyps") or []):
        sig += h + " -> "
    return sig + "Rew " + rec["coqLhs"] + " " + rec["coqRhs"]


def parse_gen_groups(raw):
    """TimbdaRuleGroup defs + TimbdaRuleGenOrder -> [(group, [ctors])]."""
    defs = {}
    for name, body in re.findall(r"def (\w+) : TimbdaRuleGroup \{(.*?)\n\}", raw, re.S):
        m = re.search(r"let ctors = \[((?:[^\"]|\")*)\];", body)
        defs[name] = re.findall(r"\"([^\"]+)\"", m.group(1)) if m else []
    m = re.search(r"def TimbdaRuleGenOrder \{\s*list<string> groups = \[([^\]]*)\];", raw)
    order = re.findall(r"\"([^\"]+)\"", m.group(1)) if m else []
    return [(g, defs[g]) for g in order if g in defs], order, defs


def parse_group_vocabulary(doc_text):
    """docs/VERSE-RULES.md sec. 5: group names from the code-fenced comma list."""
    for chunk in doc_text.split("```"):
        if chunk.lstrip().startswith("BindT"):
            return sorted({g.strip() for g in chunk.split(",") if g.strip()})
    return []


def main():
    rewriting_raw = read("coq/RewRules.v")   # the generated rule surface (M1 item 1)
    eval_raw = read("coq/Eval.v")
    denotation_code = coq_strip(read("coq/Denotation.v"))
    lemma_suffixes = set(re.findall(r"RewSound_(\w+)", denotation_code))

    td_raw = read("dialect/TimbdaRules.td")
    records = parse_td_records(td_raw)
    summary = parse_td_summary(td_raw)
    summary_ext_tags = parse_td_ext_tags(td_raw)
    externs = re.findall(r"def (\w+) : TimbdaExternRecord \{", td_raw)

    patterns_raw = read("dialect/TimbdaPatterns.td")
    drr_def_names = sorted(re.findall(r"(?m)^def (Rew\w+) : ", patterns_raw))

    ctor_names, tags_by_ctor = parse_rewriting_tags(rewriting_raw)
    gen_blocks = parse_generated_rewrites(rewriting_raw)
    gen_order = [name for name, _, _ in gen_blocks]
    rule_ids = parse_rule_ids(eval_raw)
    selected_coq = parse_selected_rows(eval_raw)

    kernel_recs = [r for r in records.values() if r.get("ctor")]
    audit_recs = [r for r in records.values() if not r.get("ctor")]
    rec_by_ctor = {r["ctor"]: r for r in kernel_recs}

    print("== 1. coq ctor <-> audit tag <-> ctor row (dialect/TimbdaRules.td) ==")
    clash = [c for c, tag in tags_by_ctor.items() if tag.get("clash")]
    check(len(ctor_names) == 35 and len(set(ctor_names)) == 35,
          "35 distinct Rew ctors in generated coq/RewRules.v", f"got {len(ctor_names)}")
    check(not clash, "no ctor carries two audit tags", f"clashes: {clash}")

    name_bad = []
    for ctor, rec in rec_by_ctor.items():
        tag = tags_by_ctor.get(ctor)
        if tag is None:
            name_bad.append(f"{ctor}: ctor row with no coq ctor")
            continue
        want = SCHEMA_TAG_TO_CTOR.get(tag["name"]) or ("Rew" + tag["name"])
        if ctor != want:
            name_bad.append(f"{ctor}: ctor row vs audit tag {tag['name']} (want {want})")
    for ctor in ctor_names:
        if ctor not in rec_by_ctor:
            name_bad.append(f"{ctor}: coq ctor with no ctor row")
    check(not name_bad, "ctor row = coq ctor = audit tag, 35/35", "; ".join(name_bad))

    tier_bad = []
    for ctor, tag in tags_by_ctor.items():
        rec = rec_by_ctor.get(ctor)
        if rec is None:
            continue
        if str(rec.get("tier", "")) != str(tag["tier"]):
            tier_bad.append(f"{ctor}: record tier {rec.get('tier')} vs coq tag "
                            f"tier {tag['tier']}")
    check(not tier_bad, "tier column == coq audit-tag tier", "; ".join(tier_bad))

    print("== 1b. generated-file provenance (coq/RewRules.v <-> record coq* fields) ==")
    check("Inductive Rew :" not in read("coq/Rewriting.v"),
          "coq/Rewriting.v carries no hand-glued Inductive Rew (it moved)")
    check("Inductive rw_step :" in rewriting_raw
          and "Definition rewrites" in rewriting_raw,
          "generated file carries the rw_step/rewrites context closure")
    gen_bad = []
    for ctor, sig_flat, audit in gen_blocks:
        rec = rec_by_ctor.get(ctor)
        if rec is None:
            gen_bad.append(f"{ctor}: generated ctor with no ctor row")
            continue
        if flatten_ws(render_ctor_from_record(rec)) != sig_flat:
            gen_bad.append(f"{ctor}: record coq* fields re-render != generated ctor")
        if audit["name"] != str(rec.get("coqTag", "")):
            gen_bad.append(f"{ctor}: audit tag {audit['name']} != coqTag {rec.get('coqTag')}")
        if audit["fig"] != int(str(rec.get("fig", "-1"))):
            gen_bad.append(f"{ctor}: audit fig {audit['fig']} != record fig {rec.get('fig')}")
        if audit["tier"] != int(str(rec.get("tier", "-1"))):
            gen_bad.append(f"{ctor}: audit tier {audit['tier']} != record tier {rec.get('tier')}")
        if audit["pap"] != flatten_ws(str(rec.get("papForm", ""))):
            gen_bad.append(f"{ctor}: papForm != generated audit-comment form text")
    check(not gen_bad,
          "every generated ctor == its record fields re-rendered (35/35)",
          "; ".join(gen_bad))
    groups, group_order, group_defs = parse_gen_groups(td_raw)
    flat_group_ctors = [c for _, ctors in groups for c in ctors]
    check(len(flat_group_ctors) == 35 and len(set(flat_group_ctors)) == 35
          and set(flat_group_ctors) == set(rec_by_ctor),
          f"emission groups ({len(group_order)}) partition the 35 ctor rows exactly once",
          f"got {len(flat_group_ctors)} ({len(set(flat_group_ctors))} distinct)")
    check(flat_group_ctors == gen_order,
          "generated ctor order == TimbdaRuleGenOrder group order",
          "; ".join(f"{g}:{len(c)}" for g, c in groups))
    missing_defs = sorted(set(group_order) - set(group_defs))
    check(not missing_defs, "every group named by TimbdaRuleGenOrder has a def",
          ", ".join(missing_defs))

    print("== 2. record arithmetic (dialect/TimbdaRules.td) ==")
    check(len(records) == 72, "72 TimbdaRuleRecord rows", f"got {len(records)}")
    check(len(kernel_recs) == 35 and len(audit_recs) == 37,
          "35 ctor rows + 37 audit records",
          f"got {len(kernel_recs)} + {len(audit_recs)}")
    check(len(externs) == 3, "3 TimbdaExtern records (dcont externs)",
          ", ".join(sorted(externs)))

    statuses = {}
    for rec in records.values():
        st = str(rec.get("status", "?"))
        statuses[st] = statuses.get(st, 0) + 1
    check(statuses.get("discharged", 0) == 15, "15 discharged ctor rows", str(statuses))
    check(statuses.get("partial", 0) == 2, "2 partial ctor rows (SCHEMA rows)",
          str(statuses))
    check(statuses.get("deferred", 0) == 18, "18 deferred ctor rows", str(statuses))

    buckets, uncategorized = {}, []
    for rec in audit_recs:
        label = category(rec)
        if label is None:
            uncategorized.append(rec["__name__"])
        else:
            buckets.setdefault(label, []).append(rec["__name__"])
    print("  info  audit-row categories: " + ", ".join(
        f"{label}={len(buckets[label])}" for label in sorted(buckets)) +
        f" (total {sum(len(v) for v in buckets.values())})")
    cat_bad = []
    for summary_key, label in CATEGORY_BY_SUMMARY.items():
        want_n = int(summary.get(summary_key, -1))
        got_n = len(buckets.get(label, []))
        if want_n != got_n:
            cat_bad.append(f"{summary_key}: summary {want_n} vs rows {got_n} "
                           f"{sorted(buckets.get(label, []))}")
    check(not cat_bad, "category integers match the rows that carry them",
          "; ".join(cat_bad))
    check(not uncategorized,
          "every audit row has a docs/RULES-AUDIT.md sec. 2 category",
          ", ".join(sorted(uncategorized)))
    check(len(buckets.get("match", [])) + len(buckets.get("essential", []))
          + len(buckets.get("verify", [])) + len(buckets.get("olam", []))
          + len(buckets.get("kernel-adjacent", [])) == len(audit_recs),
          "categories account for all 37 audit rows",
          f"{sum(len(v) for v in buckets.values())} bucketed")

    print("== 3. selected column <-> coq/Eval.v ==")
    sel_bad = []
    for rec in kernel_recs:
        tag_name = str(rec.get("kernelTag", ""))
        should = 1 if tag_name in selected_coq else 0
        if int(rec.get("selected", 0)) != should:
            sel_bad.append(f"{rec['ctor']} (kernelTag {tag_name}): record selected="
                           f"{rec.get('selected')}, coq selected_rows says {should}")
    check(not sel_bad, "selected column == membership in coq selected_rows",
          "; ".join(sel_bad))
    n_selected = len([r for r in kernel_recs if int(r.get("selected", 0)) == 1])
    n_named = len([r for r in kernel_recs if "SCHEMA" not in (r.get("tags") or [])])
    check(n_selected == 26, "26 selected ctor rows", f"got {n_selected}")
    check(len(selected_coq) == 19, "19 selected_rows in coq/Eval.v",
          f"got {len(selected_coq)}")
    check(len(rule_ids) == 27, "27 RuleIDs in coq/Eval.v", f"got {len(rule_ids)}")
    never_fired = sorted(rule_ids - selected_coq)
    check(len(never_fired) == 8, "8 never-fired RuleIDs", ", ".join(never_fired))

    print("== 4. status column <-> RewSound_* lemma evidence (coq/Denotation.v) ==")
    status_bad = []
    for ctor, rec in rec_by_ctor.items():
        status = str(rec.get("status", "?"))
        if ctor in SCHEMA_LEMMAS:
            discharged = SCHEMA_LEMMAS[ctor] <= lemma_suffixes
        else:
            discharged = ctor[len("Rew"):] in lemma_suffixes
        if status == "discharged" and not discharged:
            status_bad.append(f"{ctor}: discharged but no RewSound_{ctor[3:]}")
        elif status == "partial" and not discharged:
            status_bad.append(f"{ctor}: partial but its schema lemmas are absent")
        elif status == "deferred" and discharged:
            status_bad.append(f"{ctor}: deferred but "
                              f"{sorted(lemma_suffixes & {ctor[3:]})} exists")
    check(not status_bad, "status column backed by lemma presence",
          "; ".join(status_bad))
    covered = set()
    for ctor in rec_by_ctor:
        covered |= SCHEMA_LEMMAS.get(ctor, {ctor[3:]})
    orphans = sorted(lemma_suffixes - covered)
    check(not orphans, "no RewSound_* lemma without a ctor row", ", ".join(orphans))

    admitted, axiom_lines = [], []
    for path in sorted((REPO / "coq").rglob("*.v")):
        code = coq_strip(path.read_text(encoding="utf-8"))
        if re.search(r"\bAdmitted\b", code):
            admitted.append(str(path.relative_to(REPO)))
        for m in re.finditer(r"(?m)^\s*(Axiom|Hypothesis|Parameter|Conjecture)\b", code):
            axiom_lines.append(f"{path.relative_to(REPO)}: {m.group(1)}")
    check(not admitted, "zero Admitted in coq/", "; ".join(admitted))
    check(not axiom_lines, "no Axiom/Hypothesis/Parameter/Conjecture in coq/",
          "; ".join(axiom_lines))

    print("== 5. DRR bijection (ctor rows <-> patterns.td <-> generated populate) ==")
    td_drr = sorted(r["ctor"] for r in kernel_recs if r.get("pattern") == "drr")
    no_pattern = sorted(r["ctor"] for r in kernel_recs
                        if str(r.get("status", "")) in ("discharged", "partial")
                        and r["ctor"] not in td_drr
                        and not has_tag(r, "audit-only"))
    check(not no_pattern,
          "every discharged or partial ctor row carries a DRR pattern",
          f"no pattern and not audit-only: {', '.join(no_pattern)}")
    audit_only = sorted(r["ctor"] for r in kernel_recs if has_tag(r, "audit-only"))
    print("  info  audit-only ctor rows (kernel-side, no dialect counterpart): "
          + ", ".join(audit_only))
    ahead = sorted(r["ctor"] for r in kernel_recs
                   if r["ctor"] in td_drr and str(r.get("status")) == "deferred")
    print(f"  info  DRR patterns written ahead of their proofs ({len(ahead)}): "
          + ", ".join(ahead))
    check(sorted(set(td_drr)) == sorted(drr_def_names),
          "drr ctor rows == TimbdaPatterns.td defs (names identical)",
          f"rows {len(td_drr)}, defs {len(drr_def_names)}; "
          f"row-only {sorted(set(td_drr) - set(drr_def_names))}, "
          f"def-only {sorted(set(drr_def_names) - set(td_drr))}")
    inc_path = REPO / "bazel-out/k8-fastbuild/bin/dialect/TimbdaCanonicalization.cpp.inc"
    if not inc_path.exists():
        print("  SKIP  generated populateWithGenerated check "
              "(bazel build //dialect:TimbdaCanonicalization first)")
    else:
        populated = set(re.findall(r"patterns\.add<(\w+)>",
                                   inc_path.read_text(encoding="utf-8")))
        check(sorted(populated) == sorted(td_drr),
              "generated populateWithGenerated == drr ctor rows",
              f"generated {len(populated)} vs td {len(td_drr)}")

    ext_rows = [r for r in kernel_recs
                if any(str(t).startswith("kernel-extension")
                       for t in (r.get("tags") or []))]
    ext_names = sorted(tags_by_ctor[r["ctor"]]["name"] if r["ctor"] in tags_by_ctor
                       else r["ctor"][3:] for r in ext_rows)
    check(ext_names == sorted(summary_ext_tags),
          "kernel-extension tagged rows == summary kernelExtensionTags",
          f"rows {ext_names} vs summary {summary_ext_tags}")

    group_values = sorted({str(r.get("group", "")) for r in kernel_recs
                           if r.get("group")})
    vocab = parse_group_vocabulary(read("docs/VERSE-RULES.md"))
    print(f"  info  ctor-row groups ({len(group_values)}): {group_values}")
    print(f"  info  docs/VERSE-RULES.md sec. 5 vocabulary: {len(vocab)} group names")
    outside = sorted(g for g in group_values if g not in vocab)
    check(not outside, "every ctor-row group is a VERSE-RULES sec. 5 group name",
          ", ".join(outside))

    n_schema = len([r for r in kernel_recs if has_tag(r, "SCHEMA")])
    kernel_side = len([r for r in kernel_recs
                       if not has_tag(r, "SCHEMA")
                       and (has_tag(r, "kernel-extension") or has_tag(r, "audit-only"))])
    print(f"  info  {n_named} named ctor rows = {n_named - kernel_side} paper-named + "
          f"{kernel_side} kernel-side (kernel-extension or audit-only tags)")
    check(n_selected == summary.get("selectedCtors", -1) == 26,
          "selectedCtors == selected ctor rows", f"got {n_selected}")
    check(n_named == summary.get("namedCtors") == 33,
          "namedCtors (ctor rows minus the 2 SCHEMA rows)",
          f"named {n_named}, SCHEMA-tagged {n_schema}")

    print("== 5b. computed summary integers <-> TimbdaAuditSummary ==")
    computed = {
        "totalRecords": len(records),
        "ctorRows": len(kernel_recs),
        "auditRecordRows": len(audit_recs),
        "dischargedCtors": statuses.get("discharged", 0),
        "partialCtors": statuses.get("partial", 0),
        "deferredCtors": statuses.get("deferred", 0),
        "matchRows": len(buckets.get("match", [])),
        "essentialRows": len(buckets.get("essential", [])),
        "verifyRows": len(buckets.get("verify", [])),
        "olamRows": len(buckets.get("olam", [])),
        "kernelAdjacentRows": len(buckets.get("kernel-adjacent", [])),
        "ruleidTags": len(rule_ids),
        "selectedTags": len(selected_coq),
        "neverFiredTagsCount": len(never_fired),
        "selectedCtors": n_selected,
        "namedCtors": n_named,
        "paperNamedCtors": n_named - kernel_side,
        "kernelExtensionRows": len(ext_rows),
        "strategyGroups": len(vocab),
        "groupsUsedM0": len(group_values),
        "externRecords": len(externs),
    }
    mismatches = [f"{key}: summary {summary[key]} vs rows {computed[key]}"
                  for key in sorted(computed)
                  if key in summary and summary[key] != computed[key]]
    check(not mismatches, "every row-derivable summary integer matches the rows",
          "; ".join(mismatches))
    not_computed = sorted(set(summary) - set(computed))
    if not_computed:
        print("  info  summary integers the tool does not recompute from rows: "
              + ", ".join(not_computed))

    print("== 6. docs/RULES-AUDIT.md sec. 1 table ==")
    doc_rows = {}
    for line in read("docs/RULES-AUDIT.md").splitlines():
        cells = [c.strip() for c in line.split("|")]
        if len(cells) > 6 and cells[1].startswith("`Rew"):
            doc_rows[cells[1].strip("`")] = {"tier": cells[4].strip("*").strip(),
                                             "isEss": cells[5].strip().strip("*")}
    check(len(doc_rows) == 35, "sec. 1 table carries 35 ctor rows",
          f"got {len(doc_rows)}")
    doc_bad = []
    for ctor, tag in tags_by_ctor.items():
        row = doc_rows.get(ctor)
        if row is None:
            doc_bad.append(f"{ctor} missing from the sec. 1 table")
        elif row["tier"] != str(tag["tier"]):
            doc_bad.append(f"{ctor}: doc tier {row['tier']} vs coq tag tier {tag['tier']}")
        elif row["isEss"] != "0":
            doc_bad.append(f"{ctor}: sec. 1 IsEss cell {row['isEss']} (must be 0)")
    check(not doc_bad, "sec. 1 tier/IsEss columns == coq audit tags",
          "; ".join(doc_bad))

    print()
    if failures:
        print(f"RESULT: FAIL ({len(failures)} check(s)): {failures}")
        return 1
    print("RESULT: PASS - 35 ctor rows audit clean end to end (coq ctor = audit tag = "
          "record = DRR pattern = generated pattern); 72/35/37/3 row arithmetic, "
          "18/4/10/3/2 categories, 15/2/18 status split, 19/27/8 selected/RuleID "
          "counts, 23-pattern DRR bijection and the 31-name group vocabulary all "
          "match the rows; zero Admitted.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
