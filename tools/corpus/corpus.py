#!/usr/bin/env python3
"""Timbda-0 corpus tool for the differential harness (docs/PLAN.md sec. 6).

A `.texpr` corpus specifies evaluation cases: an expression, the head-table row
its root must select, and the normal form the evaluator must reach.  This tool
reads a corpus and emits the Coq corner - assertions about Coq's own
`Timbda.Eval.norm` / `Timbda.Eval.head_redex` - which the harness compiles, so a
corpus/evaluator disagreement fails a build instead of living in a doc.  The other
corner (tools/extract/driver.ml) parses the same corpus with its own independent
reader and runs the *extracted* OCaml evaluator: the spec is read by two readers
and executed by two pipelines (Coq native, Rocq extraction).

Usage:
  corpus.py --emit-coq CORPUS    write the Coq corner to stdout
  corpus.py --summary  CORPUS    case count, which head-table rows fired, how many
                                 cases also assert a candidate bag
  corpus.py --count    CORPUS    number of cases (harness cross-check)
  corpus.py --count-cands CORPUS number of cases with a `cands` field

Case fields: `head`, `expr`, `norm`, `why`, `fuel`, and optionally `cands` (the
candidate bag `Timbda.Eval.cand_bag` must return for the normal form) plus
`cands_why` for why that bag has that shape.  Both readers - this one and
tools/corpus/driver.ml - accept exactly the same field set.

Corpus grammar and desugaring table: tools/corpus/README.md.
"""
import sys
from pathlib import Path

# coq/Eval.v `RuleID`.  `none` in a corpus case is a first-class outcome: the head
# table selects nothing at that root (stuck, which is not the same as fail).
RULE_COQ = [
    "R_Seq", "R_Norm1", "R_Norm2", "R_Norm3", "R_Norm4", "R_Norm5",
    "R_EqK1", "R_EqK2", "R_EqTup1", "R_EqTup2", "R_EqFail",
    "R_BetaL", "R_BetaT", "R_BetaT0", "R_Prim", "R_PrimFail",
    "R_Subst", "R_Gc1", "R_PromoteL", "R_PromoteR",
    "R_IterFail", "R_IterChoice", "R_IterIf", "R_IterAll", "R_IterFor",
    "R_HpAlpha", "R_LamAlpha",
]
RULE_FROM_CORPUS = {r.lower(): r for r in RULE_COQ}

# coq/Syntax.v `Prim` (corpus spelling = lower-cased constructor), `IterComb`, `Ty`.
PRIM_COQ = {
    "padd": "PAdd", "psub": "PSub", "pmul": "PMul", "pdiv": "PDiv",
    "pneg": "PNeg", "ppls": "PPls", "pgt": "PGt", "plt": "PLt",
    "pgeq": "PGEq", "pleq": "PLEq", "pneq": "PNEq", "pisint": "PIsInt",
    "pisbool": "PIsBool", "pisunit": "PIsUnit", "pcons": "PCons",
    "pcons2": "PCons2", "pdotdot": "PDotDot", "parrlen": "PArrLen",
}
COMB_COQ = {"iall": "IAll", "iif": "IIf", "ifor": "IFor"}
TY_COQ = {"tunit": "TUnit", "tbool": "TBool", "tint": "TInt", "tany": "TAny"}
VAL_ATOM_COQ = {"unit": "VUnit", "true": "VTrue", "false": "VFalse"}
DEFAULT_FUEL = 24


class CorpusError(Exception):
    pass


def is_number(text):
    body = text[1:] if text[:1] == "-" else text
    return body.isdigit()


def as_int(text, where):
    if not is_number(text):
        raise CorpusError(f"{where}: expected an integer, got {text!r}")
    return int(text)


def valid_ident(text, where):
    if not text[0].isalpha() or not all(c.isalnum() or c == "_" for c in text):
        raise CorpusError(f"{where}: not an identifier: {text!r}")
    return text


def tokenize(text):
    toks, i, n = [], 0, len(text)
    while i < n:
        if text[i].isspace():
            i += 1
        elif text[i] in "()":
            toks.append(text[i])
            i += 1
        else:
            j = i
            while j < n and not text[j].isspace() and text[j] not in "()":
                j += 1
            toks.append(text[i:j])
            i = j
    return toks


class Reader:
    """Canonical s-expression reader for the corpus grammar."""

    def __init__(self, text, ctx):
        self.toks = tokenize(text)
        self.i = 0
        self.ctx = ctx

    def peek(self):
        return self.toks[self.i] if self.i < len(self.toks) else None

    def take(self):
        tok = self.peek()
        if tok is None:
            raise CorpusError(f"{self.ctx}: form ends too early")
        self.i += 1
        return tok

    def expect(self, token):
        got = self.peek()
        if got != token:
            raise CorpusError(f"{self.ctx}: expected {token!r}, got {got!r}")
        self.i += 1

    def close(self):
        self.expect(")")

    def atom(self):
        tok = self.take()
        if tok in ("(", ")"):
            raise CorpusError(f"{self.ctx}: expected an atom, got {tok!r}")
        return tok

    def ty(self):
        name = self.atom()
        if name not in TY_COQ:
            raise CorpusError(f"{self.ctx}: unknown type {name!r}")
        return TY_COQ[name]

    def value(self):
        if self.peek() != "(":
            tok = self.take()
            if tok in VAL_ATOM_COQ:
                return ("atom", VAL_ATOM_COQ[tok])
            if is_number(tok):
                return ("int", int(tok))
            raise CorpusError(f"{self.ctx}: unexpected {tok!r} in value position")
        self.expect("(")
        head = self.atom()
        if head == "primv":
            name = self.atom()
            if name not in PRIM_COQ:
                raise CorpusError(f"{self.ctx}: unknown prim {name!r}")
            self.close()
            return ("vprim", PRIM_COQ[name])
        if head == "tupv":
            vals = []
            while self.peek() != ")":
                vals.append(self.value())
            self.close()
            return ("vtup", vals)
        if head == "lam":
            ty = self.ty()
            body = self.expr()
            self.close()
            return ("vlam", ty, body)
        if head == "delay":
            body = self.expr()
            self.close()
            return ("vdelay", body)
        if head == "var":
            n = as_int(self.atom(), self.ctx)
            self.close()
            return ("var", n)
        raise CorpusError(f"{self.ctx}: unknown value form {head!r}")

    def slot(self):
        self.expect("(")
        ty = self.ty()
        if self.peek() == ")":
            self.close()
            return (ty, None)
        val = self.value()
        self.close()
        return (ty, val)

    def expr_seq(self):
        """Parse a whitespace-separated run of expressions (the `cands` field)."""
        out = []
        while self.peek() is not None:
            out.append(self.expr())
        return out

    def expr(self):
        if self.peek() != "(":
            tok = self.take()
            if tok == "fail":
                return ("fail",)
            raise CorpusError(f"{self.ctx}: unexpected {tok!r} in expr position")
        self.expect("(")
        head = self.atom()
        if head == "ret":
            val = self.value()
            self.close()
            return ("ret", val)
        if head == "glob":
            pos = as_int(self.atom(), self.ctx)
            if pos < 1:
                raise CorpusError(f"{self.ctx}: (glob N) needs N >= 1 (ident := positive)")
            self.close()
            return ("glob", pos)
        if head == "app":
            left, arg = self.expr(), self.expr()
            self.close()
            return ("app", left, arg)
        if head == "tup":
            items = []
            while self.peek() != ")":
                items.append(self.expr())
            self.close()
            return ("tup", items)
        if head in ("seq", "unify", "choice"):
            left, arg = self.expr(), self.expr()
            self.close()
            return (head, left, arg)
        if head == "block":
            self.expect("(")
            slots = []
            while self.peek() != ")":
                slots.append(self.slot())
            self.close()
            body = self.expr()
            self.close()
            return ("block", slots, body)
        if head == "iter":
            comb = self.atom()
            if comb not in COMB_COQ:
                raise CorpusError(f"{self.ctx}: unknown iter comb {comb!r}")
            base, arg = self.expr(), self.expr()
            self.close()
            return ("iter", COMB_COQ[comb], base, arg)
        raise CorpusError(f"{self.ctx}: unknown form {head!r}")

    def read_expr(self):
        out = self.expr()
        if self.peek() is not None:
            raise CorpusError(f"{self.ctx}: trailing tokens {self.toks[self.i:]!r}")
        return out


def parse_corpus(path):
    cases, names, cur = [], set(), None
    fuel_default = DEFAULT_FUEL
    for num, raw in enumerate(Path(path).read_text().splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        key, _, rest = line.partition(" ")
        rest = rest.strip()
        where = f"{path}:{num}"
        if key == "defaults":
            parts = rest.split()
            if len(parts) != 2 or parts[0] != "fuel":
                raise CorpusError(f"{where}: expected 'defaults fuel N'")
            fuel_default = as_int(parts[1], where)
            continue
        if key == "case":
            name = valid_ident(rest, where)
            if name in names:
                raise CorpusError(f"{where}: duplicate case name {name!r}")
            names.add(name)
            cur = {"name": name, "line": num, "fuel": fuel_default,
                   "head": None, "expr": None, "norm": None, "why": "",
                   "cands": None, "cands_why": ""}
            cases.append(cur)
            continue
        if cur is None:
            raise CorpusError(f"{where}: {key!r} outside a case block")
        ctx = f"{where} (case {cur['name']} {key})"
        if key == "head":
            if rest == "none":
                cur["head"] = "none"
            elif rest in RULE_FROM_CORPUS:
                cur["head"] = RULE_FROM_CORPUS[rest]
            else:
                raise CorpusError(f"{ctx}: unknown head row {rest!r}")
        elif key == "expr":
            cur["expr"] = Reader(rest, f"{ctx} expr").read_expr()
        elif key == "norm":
            cur["norm"] = Reader(rest, f"{ctx} norm").read_expr()
        elif key == "why":
            if len(rest) < 2 or rest[0] != '"' or rest[-1] != '"':
                raise CorpusError(f"{ctx}: why must be a quoted string")
            cur["why"] = rest[1:-1].replace('\\"', '"')
        elif key == "cands":
            # Optional: the candidate bag the normal form must offer (cand_bag).
            # A run of expressions, read by the same grammar `norm` uses.
            cur["cands"] = Reader(rest, f"{ctx} cands").expr_seq()
            if not cur["cands"]:
                raise CorpusError(f"{ctx}: cands needs at least one expression "
                                  "(cand_bag never returns an empty bag)")
        elif key == "cands_why":
            if len(rest) < 2 or rest[0] != '"' or rest[-1] != '"':
                raise CorpusError(f"{ctx}: cands_why must be a quoted string")
            cur["cands_why"] = rest[1:-1].replace('\\"', '"')
        elif key == "fuel":
            cur["fuel"] = as_int(rest, where)
        else:
            raise CorpusError(f"{ctx}: unknown field {key!r} "
                              "(head/expr/norm/cands/cands_why/why/fuel)")
    for c in cases:
        for field in ("head", "expr", "norm"):
            if c[field] is None:
                raise CorpusError(f"{path}: case {c['name']} has no {field}")
    if not cases:
        raise CorpusError(f"{path}: no cases")
    return cases


# ---------------------------------------------------------------------------
# Coq corner (assertions about Coq's own evaluator)
# ---------------------------------------------------------------------------

def coq_pos(n):
    """positive literal (Syntax.v: ident := positive, constructors xH/xO/xI)."""
    if n == 1:
        return "xH"
    if n % 2 == 0:
        return f"(xO {coq_pos(n // 2)})"
    return f"(xI {coq_pos(n // 2)})"


def coq_z(n):
    """Z literal; negatives go through Z.opp so no scope is assumed."""
    return str(n) if n >= 0 else f"(Z.opp {-n})"


def coq_val(v):
    kind = v[0]
    if kind == "atom":
        return v[1]
    if kind == "int":
        return f"(VInt {coq_z(v[1])})"
    if kind == "vprim":
        return f"(VPrim {v[1]})"
    if kind == "vtup":
        return "(VTup [" + "; ".join(coq_val(x) for x in v[1]) + "])"
    if kind == "vlam":
        return f"(VLam {v[1]} {coq_expr(v[2])})"
    if kind == "vdelay":
        return f"(VDelay {coq_expr(v[1])})"
    if kind == "var":
        return f"(VVar {v[1]})"
    raise CorpusError(f"internal: bad value {v!r}")


def coq_slot(slot):
    ty, val = slot
    filled = "@None Val" if val is None else "Some " + coq_val(val)
    return f"({ty}, {filled})"


def coq_expr(e):
    kind = e[0]
    if kind == "ret":
        return f"(Ret {coq_val(e[1])})"
    if kind == "glob":
        return f"(Glob {coq_pos(e[1])})"
    if kind == "app":
        return f"(App {coq_expr(e[1])} {coq_expr(e[2])})"
    if kind == "tup":
        return "(TupE [" + "; ".join(coq_expr(x) for x in e[1]) + "])"
    if kind == "seq":
        return f"(Seq {coq_expr(e[1])} {coq_expr(e[2])})"
    if kind == "unify":
        return f"(Unify {coq_expr(e[1])} {coq_expr(e[2])})"
    if kind == "choice":
        return f"(Choice {coq_expr(e[1])} {coq_expr(e[2])})"
    if kind == "fail":
        return "Fail"
    if kind == "block":
        slots = e[1]
        head = "(@nil (Ty * option Val))" if not slots else \
            "[" + "; ".join(coq_slot(s) for s in slots) + "]"
        return f"(Block {head} {coq_expr(e[2])})"
    if kind == "iter":
        return f"(Iter {e[1]} {coq_expr(e[2])} {coq_expr(e[3])})"
    raise CorpusError(f"internal: bad expr {e!r}")


COQ_HEADER = """\
(* generated by tools/corpus/corpus.py from %s - DO NOT EDIT.
   Coq corner of the differential harness (docs/PLAN.md sec. 6): every Example is
   an assertion about Coq's own evaluator on the corpus case of the same name, so
   `rocq c` on this file either passes or fails the build - build evidence, not a
   claim in a doc (the same pattern as the timbda-kernel axiom gate).
   No Stdlib.Bool and no CTree import here, so the level-40/level-59 `&&&`
   collision (DESIGN-NOTES sec. 7.3) is unreachable from this file. *)
From Stdlib Require Import ZArith List.
Require Import Timbda.Syntax Timbda.Rewriting Timbda.Semantics Timbda.Eval.
Import ListNotations.

(* The row tag alone, so a case can name the row that fired without restating
   that row's right-hand side. *)
Definition fired_rule (e : Expr) : option RuleID :=
  match head_redex e with
  | Some (r, _) => Some r
  | None => None
  end.
"""


def coq_expr_seq(es):
    """The `cands` field as a Coq list - the order cand_bag returns them in."""
    return "[" + "; ".join(coq_expr(e) for e in es) + "]"


def emit_coq(cases, corpus_name):
    out = [COQ_HEADER % corpus_name]
    n_cands = 0
    for c in cases:
        name = "c_" + c["name"]
        want = "None" if c["head"] == "none" else f"Some {c['head']}"
        out.append(f"Definition {name} : Expr := {coq_expr(c['expr'])}.")
        out.append(f"Example {name}_head : fired_rule {name} = {want}.")
        out.append("Proof. reflexivity. Qed.")
        out.append(f"Example {name}_norm : norm {c['fuel']} {name} = "
                   f"{coq_expr(c['norm'])}.")
        out.append("Proof. reflexivity. Qed.")
        if c["cands"] is not None:
            n_cands += 1
            out.append(f"Example {name}_cands : cand_bag (norm {c['fuel']} {name}) = "
                       f"{coq_expr_seq(c['cands'])}.")
            out.append("Proof. reflexivity. Qed.")
        out.append("")
    out.append(f"Definition corner_cases : nat := {len(cases)}.")
    out.append("Print corner_cases.")
    out.append(f"Definition corner_cands : nat := {n_cands}.")
    out.append("Print corner_cands.")
    return "\n".join(out) + "\n"


def summarize(cases):
    fired = {}
    stuck = 0
    for c in cases:
        if c["head"] == "none":
            stuck += 1
        else:
            fired[c["head"]] = fired.get(c["head"], 0) + 1
    n_cands = sum(1 for c in cases if c["cands"] is not None)
    lines = [f"cases: {len(cases)}   head row fires: {len(cases) - stuck}   "
             f"no row (stuck): {stuck}   candidate bags (cand_bag): {n_cands}"]
    for rule in RULE_COQ:
        if rule in fired:
            lines.append(f"  {rule:<12} {fired[rule]}")
    never = [r for r in RULE_COQ if r not in fired]
    lines.append("rows not exercised (deferred or unreachable by the head table): "
                 + ", ".join(never))
    return "\n".join(lines)


def main(argv):
    if len(argv) != 2 or argv[0] not in ("--emit-coq", "--summary", "--count",
                                         "--count-cands"):
        print(__doc__)
        return 2
    mode, path = argv[0], argv[1]
    try:
        cases = parse_corpus(path)
    except CorpusError as exc:
        print(f"corpus error: {exc}")
        return 1
    if mode == "--emit-coq":
        sys.stdout.write(emit_coq(cases, Path(path).name))
    elif mode == "--count":
        print(len(cases))
    elif mode == "--count-cands":
        print(sum(1 for c in cases if c["cands"] is not None))
    else:
        print(summarize(cases))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
