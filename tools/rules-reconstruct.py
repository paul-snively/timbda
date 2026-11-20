#!/usr/bin/env python3
"""Rebuild the record scaffold of dialect/TimbdaRules.td.

The 72-record rule corpus lost its scaffolding: the `def <Name> : <record class> {`
headers and the closing braces are gone, and the surviving field statements sit in
one run (`let a = x, b = y;let c = z;...` - the comma-chained-`let` style
tools/split-lets.py exists to normalize).  No field value was lost, so this is a
reconstruction, not a rewrite: each run is tokenized by a quote/bracket-aware
scanner that reads a value whole (quoted rule text contains `=` and `,`, which a
name-only regex would read as extra fields), and the headers go back on.

Names come from joining the records' own data against docs/RULES-AUDIT.md, which
is what the M1 audit diffs against:

  35 ctor rows   the docs sec. 1 table is parsed for the ctor -> rule-name column
                 (`RewSeq` -> SeqRecord, `RewPrim` -> PrimSchemaRecord), and the
                 same table's fig/tier/status columns are checked against each
                 record's own fields - a rebuilt row that disagrees with docs
                 stops the tool.
  2 kernel-adjacent  docs sec. 2 names `Gc-Rec` / `Subst-Deep`
  18 matching rows   `Match_` + the VERSE-RULES sec. 4 row label the record
                     carries in semName (`mwild` -> Match_MwildRecord)
  4 Essential-Verse  docs names Verify_MFun / Verify_MOFType / OFType / Typeof
  10 solver rows     the names VERSE-RULES sec. 4.1 quotes (`split-tup` ->
                     Verify_SplitTupRecord)
  3 open-lambda rows docs names Olam_Unify / Olam_App / Olam_ExiApp
  3 extern rows      `Extern_` + the veriFFISpec symbol (`timbda_ffi_dcont_shift`
                     -> Extern_dcont_shiftRecord)

Two guards run before anything is written: the census has to add up to the
numbers the file's own audit summary states (72 = 35 + 37, 3 externs, 27 kernel
tags of which 19 selected, 26 selected ctors, the semClass and pattern columns),
and the rebuilt text has to re-tokenize to exactly the fields the damaged file
had, in the same order.

Usage: python3 tools/rules-reconstruct.py [--dry-run] [path]
"""
import re
import sys

DEFAULT_PATH = 'dialect/TimbdaRules.td'
DEFAULT_DOCS = 'docs/RULES-AUDIT.md'
TAIL_MARK = '// -------------------------------------------------------------------------'

# docs sec. 1 table row: `| \`RewX\` | RuleName (note) | fig | tier | isEss | sel | status | ...`
DOCS_ROW_RE = re.compile(r'^\|\s*`(Rew[A-Za-z0-9]+)`\s*\|\s*([A-Za-z0-9]+)[^|]*\|'
                         r'\s*([0-9]+)\s*\|\s*\**(\d)\**\s*\|\s*\d\s*\|[^|]*\|'
                         r'\s*\**([a-z]+)\**\s*\|', re.M)

# docs sec. 2 and VERSE-RULES sec. 4/4.1 record names, keyed by the record's semName
SEMNAME_DOCS = {
    'gc-scc': 'Gc_Rec', 'subst-deep': 'Subst_Deep',
    'mfun-verify': 'Verify_MFun', 'moftype': 'Verify_MOFType',
    'oftype': 'OFType', 'typeof': 'Typeof',
    'solver': 'Verify_Solver', 'v-val': 'Verify_Val', 'v-choice': 'Verify_Choice',
    'v-fail': 'Verify_Fail', 'split-val': 'Verify_SplitVal',
    'split-op': 'Verify_SplitOp', 'split-tup': 'Verify_SplitTup',
    'split-app': 'Verify_SplitApp', 'split-appf': 'Verify_SplitAppF',
    'v-some': 'Verify_Some',
    'u-olam': 'Olam_Unify', 'app-olam': 'Olam_App', 'exi-app': 'Olam_ExiApp',
}

# VERSE-RULES sec. 4: the 18 matching-function rows (Figs. 14-15), docs order
MATCH_LABELS = ['mwild', 'mlit', 'mvar', 'mdef', 'minp', 'mblock', 'mapp',
                'munif', 'mchoice', 'mfail', 'msemi', 'mwhere', 'mtup',
                'mcolon1', 'mif', 'mall', 'mfor', 'mfun']
SOLVER_LABELS = ['solver', 'v-val', 'v-choice', 'v-fail', 'split-val', 'split-op',
                 'split-tup', 'split-app', 'split-appf', 'v-some']

NAME_AT = re.compile(r'([A-Za-z_][A-Za-z_0-9]*)\s*=\s*')
DEF_BLOCK_RE = re.compile(r'def (\w+) : (TimbdaRuleRecord|TimbdaExternRecord) \{(.*?)\n\}',
                          re.S)


def docs_table(path):
    """ctor name -> (rule name, fig, tier, status) from docs/RULES-AUDIT.md sec. 1."""
    out = {}
    for m in DOCS_ROW_RE.finditer(open(path).read()):
        out[m.group(1)] = (m.group(2), m.group(3), m.group(4), m.group(5))
    return out


def skip_ws(text, i):
    while i < len(text) and text[i] in ' \t\n':
        i += 1
    return i


def read_value(text, i):
    """Read one TableGen value at i; return (raw_text, index just past it)."""
    if i >= len(text):
        raise ValueError('value expected at end of run')
    if text[i] == '"':
        j = i + 1
        while j < len(text):
            if text[j] == '\\':
                j += 2
                continue
            if text[j] == '"':
                return text[i:j + 1], j + 1
            j += 1
        raise ValueError('unterminated string at %d' % i)
    if text[i] == '[':
        j, depth = i, 0
        while j < len(text):
            c = text[j]
            if c == '"':
                j += 1
                while j < len(text) and text[j] != '"':
                    j += 2 if text[j] == '\\' else 1
            elif c == '[':
                depth += 1
            elif c == ']':
                depth -= 1
                if depth == 0:
                    return text[i:j + 1], j + 1
            j += 1
        raise ValueError('unbalanced list at %d' % i)
    if text[i].isdigit() or text[i] == '-':
        j = i
        while j < len(text) and (text[j].isdigit() or text[j] == '-'):
            j += 1
        return text[i:j], j
    raise ValueError('unexpected %r at %d' % (text[i], i))


def parse_run(text):
    """Tokenize a run of `field = value` pairs into [(field, raw_value)].

    Accepts both shapes this tool sees: the damaged file's comma-chained run
    (`ctor = "RewEqK1", kernelTag = "R_EqK1", ...`) and the rebuilt file's
    per-field `let` statements (`let ctor = ...;` on one line each).  A
    trailing `}` - the closing brace of a def block - is tolerated, which is
    what makes the round-trip check possible.
    """
    fields, i = [], 0
    while True:
        i = skip_ws(text, i)
        while i < len(text) and text[i] in ',;':
            i = skip_ws(text, i + 1)
        if i >= len(text) or text[i] == '}':
            break
        if text.startswith('let ', i):
            i = skip_ws(text, i + 4)
        m = NAME_AT.match(text, i)
        if not m:
            raise ValueError('unparsed text at %d: %r' % (i, text[i:][:60]))
        value, i = read_value(text, m.end())
        fields.append((m.group(1), value))
    rest = text[i:].strip().strip('};')
    if rest:
        raise ValueError('unparsed tail after the last field: %r' % rest[:60])
    return fields


def camel(label):
    """Label -> Match_ def name suffix: upper-case the label's first character
    of each alphabetic run ('mwild' -> 'Mwild', 'mfor' -> 'Mfor')."""
    parts = re.findall(r'[a-z]+|\d+', label)
    return ''.join(p[0].upper() + p[1:] if p[0].isalpha() else p for p in parts)


def record_name(fields, docs):
    """The def name the docs join gives this record, or why nothing matched."""
    d = dict(fields)
    ctor = d.get('ctor', '""').strip('"')
    sem = d.get('semName', '""').strip('"')
    if ctor:
        if ctor not in docs:
            return None, 'ctor %s is not a row of docs/RULES-AUDIT.md sec. 1' % ctor
        return docs[ctor][0] + 'Record', None
    if sem in MATCH_LABELS:
        return 'Match_' + camel(sem) + 'Record', None
    if sem in SEMNAME_DOCS:
        return SEMNAME_DOCS[sem] + 'Record', None
    return None, 'record (ctor=%r semName=%r) matches no docs name' % (ctor, sem)


def check_docs(rows, docs):
    """Every rebuilt ctor row must agree with its docs sec. 1 row's columns."""
    bad = []
    for fields in rows:
        d = dict(fields)
        ctor = d.get('ctor', '""').strip('"')
        if not ctor:
            continue
        if ctor not in docs:
            bad.append('%s: no docs sec. 1 row' % ctor)
            continue
        _, fig, tier, status = docs[ctor]
        if d.get('fig', '""').strip('"') != fig:
            bad.append('%s: fig %s vs docs %s' % (ctor, d.get('fig'), fig))
        if d.get('tier') != tier:
            bad.append('%s: tier %s vs docs %s' % (ctor, d.get('tier'), tier))
        if d.get('status', '""').strip('"') != status:
            bad.append('%s: status %s vs docs %s' % (ctor, d.get('status'), status))
    return bad


HEADER = '''//===- TimbdaRules.td - transcribed paper rules (72) --------*- tablegen -*-===//
//
// The rule corpus the M1 canonicalizer and tools/rules-audit.py diff against:
// 35 rows with a coq/Rewriting.v constructor (docs/RULES-AUDIT.md sec. 1), 37
// rows with no constructor at M0 (sec. 2: 2 kernel-adjacent, 18
// matching-function, 4 Essential-Verse, 10 solver, 3 open-lambda), and 3 dcont
// extern records.
//
// Pure TableGen - no op or type references - so rules-audit.py can read the
// records as data.  Each row quotes the kernel row it stands for (ctor +
// kernelTag) and carries the docs columns that audit checks (fig, tier,
// isEssential, status), the lowering M1 gives it (pattern: "drr" = a DRR pattern
// in dialect/TimbdaPatterns.td, "pdll" = a lowering owed to the M2/M3 pass, "m3"
// = an M3 matching pattern, "none" = no lowering), and the audit's own notes.
//
// Rebuilt 2026-11-20 from this file's surviving field statements by
// tools/rules-reconstruct.py: the def/class scaffolding was lost and no field
// value was, and every name below is a docs join (sec. 1 ctor column, sec. 2
// record names, VERSE-RULES sec. 4/4.1 row labels), not an invented one.
//
//===----------------------------------------------------------------------===//

'''

CLASSES = '''class TimbdaRuleRecord {
  string ctor = "";           // coq/Rewriting.v ctor name; "" = no ctor at M0
  string kernelTag = "";      // coq/Eval.v RuleID arm the row fires through
  int selected = 0;           // 1 = that arm is in coq/Eval.v selected_rows
  int rank = 0;               // selected_rows order; 0 = not selected
  string group = "";          // strategy group (VERSE-RULES sec. 5 vocabulary)
  string fig = "";            // paper figure
  int tier = 1;               // docs tier column
  int isEssential = 0;        // Essential-Verse row (Core-Verse rejects it)
  string semClass = "";       // unify | delta | eval | match | solver | olam
  string semName = "";        // paper-side row label (mwild, iter-choice, ...)
  string status = "";         // discharged | partial | deferred | record[:Mn]
  string pattern = "none";    // drr | pdll | m3 | none
  string lhs = "";
  string rhs = "";
  string side = "";           // side condition, quoted from the paper/kernel
  list<string> ops = [];      // dialect ops the row touches
  list<string> tags = [];     // audit notes (deferral class, deviation id, ...)
}

// The dcont extern surface (docs/PLAN.md sec. 4.2): M4 records only.  At M1 the
// call sites are TD records; veriFFISpec is the name the M4 shim has to match,
// and hasWillReturn = 0 records that a shift/yield call cannot be assumed to
// return normally, which is why these rows carry llvmAttrs.
class TimbdaExternRecord {
  string cppDecl = "";
  list<string> llvmAttrs = [];
  int hasWillReturn = 1;
  string veriFFISpec = "";
  string status = "";
  list<string> tags = [];
}

'''

EXPECT = {'rule records': 72, 'ctor rows': 35, 'audit records': 37,
          'extern records': 3, 'selected ctors': 26, 'selected tags': 19,
          'kernel tags': 27, 'match rows': 18, 'essential rows': 4,
          'solver rows': 10, 'olam rows': 3, 'kernel-adjacent rows': 2}
EXPECT_SEMCLASS = {'unify': 5, 'delta': 9, 'eval': 23, 'match': 22,
                   'solver': 10, 'olam': 3}
EXPECT_PATTERN = {'drr': 23, 'm3': 18, 'pdll': 10, 'none': 21}


def census(runs):
    got = {}
    ctors = [r for r in runs if dict(r).get('ctor', '""').strip('"')]
    got['ctor rows'] = len(ctors)
    got['audit records'] = len(runs) - len(ctors)
    got['rule records'] = len(runs)
    sel = [r for r in ctors if dict(r).get('selected') == '1']
    got['selected ctors'] = len(sel)
    got['selected tags'] = len({dict(r).get('kernelTag', '""').strip('"') for r in sel})
    got['kernel tags'] = len({dict(r).get('kernelTag', '""').strip('"')
                              for r in runs} - {''})
    labels = [dict(r).get('semName', '""').strip('"') for r in runs]
    got['match rows'] = sum(1 for l in labels if l in MATCH_LABELS)
    got['essential rows'] = sum(1 for l in labels
                                if l in ('mfun-verify', 'moftype', 'oftype', 'typeof'))
    got['solver rows'] = sum(1 for l in labels if l in SOLVER_LABELS)
    got['olam rows'] = sum(1 for l in labels if l in ('u-olam', 'app-olam', 'exi-app'))
    got['kernel-adjacent rows'] = sum(1 for l in labels if l in ('gc-scc', 'subst-deep'))
    sem, pat = {}, {}
    for r in runs:
        d = dict(r)
        s = d.get('semClass', '').strip('"')
        p = d.get('pattern', '').strip('"')
        sem[s] = sem.get(s, 0) + 1
        pat[p] = pat.get(p, 0) + 1
    return got, sem, pat


def emit_def(name, fields, cls):
    out = ['def %s : %s {' % (name, cls)]
    out += ['  let %s = %s;' % (n, v) for n, v in fields]
    out.append('}')
    return '\n'.join(out)


def main():
    dry = '--dry-run' in sys.argv
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    path = args[0] if args else DEFAULT_PATH
    docs = docs_table(DEFAULT_DOCS)
    src = open(path).read()
    cut = src.index(TAIL_MARK)
    body, tail = src[:cut], src[cut:]

    rule_runs, extern_runs = [], []
    for piece in body.split(';let '):
        run = piece[4:] if piece.lstrip().startswith('let ') else piece
        fields = parse_run(run.strip())
        (extern_runs if fields and fields[0][0] == 'cppDecl' else rule_runs).append(fields)

    names, bad = [], []
    for fields in rule_runs:
        name, why = record_name(fields, docs)
        if name is None:
            bad.append(why)
        elif name in names:
            bad.append('duplicate record name %s' % name)
        else:
            names.append(name)
    extern_names = ['Extern_' + dict(r)['veriFFISpec'].strip('"').replace('timbda_ffi_', '')
                    + 'Record' for r in extern_runs]
    bad += check_docs(rule_runs, docs)

    got, semclass, patterns = census(rule_runs)
    got['extern records'] = len(extern_runs)
    bad += ['%s: want %s got %s' % (k, w, got.get(k))
            for k, w in sorted(EXPECT.items()) if got.get(k) != w]
    bad += ['semClass %s: want %s got %s' % (k, w, semclass.get(k))
            for k, w in sorted(EXPECT_SEMCLASS.items()) if semclass.get(k) != w]
    bad += ['pattern %s: want %s got %s' % (k, w, patterns.get(k))
            for k, w in sorted(EXPECT_PATTERN.items()) if patterns.get(k) != w]
    if len(docs) != got['ctor rows']:
        bad.append('docs sec. 1 lists %d ctor rows, the file has %d'
                   % (len(docs), got['ctor rows']))

    print('census   : %s' % ', '.join('%s=%s' % kv for kv in sorted(got.items())))
    print('semClass : %s' % ', '.join('%s=%s' % kv for kv in sorted(semclass.items())))
    print('pattern  : %s' % ', '.join('%s=%s' % kv for kv in sorted(patterns.items())))
    if bad:
        sys.exit('reconstruction rejected:\n  ' + '\n  '.join(bad))

    defs = [emit_def(n, r, 'TimbdaRuleRecord') for n, r in zip(names, rule_runs)]
    defs += [emit_def(n, r, 'TimbdaExternRecord') for n, r in zip(extern_names, extern_runs)]
    rebuilt = HEADER + CLASSES + '\n'.join(defs) + '\n\n' + tail

    back = [(m.group(1), parse_run(m.group(3))) for m in DEF_BLOCK_RE.finditer(rebuilt)]
    want = list(zip(names, rule_runs)) + list(zip(extern_names, extern_runs))
    if back != want:
        for i, (a, b) in enumerate(zip(back, want)):
            if a != b:
                sys.exit('round-trip mismatch at %d: rebuilt %s vs input %s'
                         % (i, a[0], b[0]))
        sys.exit('round-trip lost records: %d re-read vs %d rebuilt' % (len(back), len(want)))
    print('rebuilt  : %d rule records + %d extern records, round-trip verified'
          % (len(rule_runs), len(extern_runs)))

    if dry:
        for name, fields in zip(names, rule_runs):
            print('  %-28s %s' % (name, dict(fields).get('ctor', '""').strip('"') or '-'))
        for name, fields in zip(extern_names, extern_runs):
            print('  %-28s %s' % (name, dict(fields)['cppDecl'][:44]))
        return
    open(path, 'w').write(rebuilt)
    print('wrote    : %s' % path)


if __name__ == '__main__':
    main()
