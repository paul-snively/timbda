//===- TimbdaRules.td - transcribed paper rules (72) --------*- tablegen -*-===//
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

class TimbdaRuleRecord {
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
  // Coq ctor surface consumed by dialect/tblgen-rocq -gen-rocq-rules
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

def EqK1Record : TimbdaRuleRecord {
  let ctor = "RewEqK1";
  let kernelTag = "R_EqK1";
  let selected = 1;
  let rank = 7;
  let group = "Norm";
  let fig = "9";
  let tier = 1;
  let semClass = "unify";
  let semName = "eqk1";
  let lhs = "k = k";
  let rhs = "k";
  let status = "discharged";
  let pattern = "drr";
  let ops = ["unify", "int", "bool", "unit"];
  let tags = [];
  let coqTag = "EqK1";
  let coqForall = "v : Val";
  let coqHyps = ["is_lit_val v = true"];
  let coqLhs = "(Unify (Ret v) (Ret v))";
  let coqRhs = "(Ret v)";
  let papForm = "k = k -> k (line 432; k ranges over the literals unit/true/false/int — the kernel states the literal-general form, recorded in docs/RULES-AUDIT.md; eqtup1 handles tuples, eqfail the rest)";
}
def EqK2Record : TimbdaRuleRecord {
  let ctor = "RewEqK2";
  let kernelTag = "R_EqK2";
  let selected = 1;
  let rank = 8;
  let group = "Norm";
  let fig = "9";
  let tier = 1;
  let semClass = "unify";
  let semName = "eqk2";
  let lhs = "k1 = k2";
  let rhs = "fail";
  let side = "if k1 <> k2";
  let status = "discharged";
  let pattern = "drr";
  let ops = ["unify", "int", "bool", "unit", "fail"];
  let tags = [];
  let coqTag = "EqK2";
  let coqForall = "v1 v2 : Val";
  let coqHyps = ["is_lit_val v1 = true", "is_lit_val v2 = true", "v1 <> v2"];
  let coqLhs = "(Unify (Ret v1) (Ret v2))";
  let coqRhs = "Fail";
  let papForm = "k1 = k2 -> fail if k1 <> k2 (line 433)";
}
def EqTup1Record : TimbdaRuleRecord {
  let ctor = "RewEqTup1";
  let kernelTag = "R_EqTup1";
  let selected = 1;
  let rank = 9;
  let group = "Norm";
  let fig = "9";
  let tier = 1;
  let semClass = "unify";
  let semName = "eqtup1";
  let lhs = "⟨v1..vn⟩ = ⟨w1..wn⟩";
  let rhs = "v1=w1; .. ; vn=wn; ⟨v1..vn⟩";
  let status = "deferred";
  let pattern = "drr";
  let ops = ["unify", "tup", "bind"];
  let tags = ["deferral:C2"];
  let coqTag = "EqTup1";
  let coqForall = "vs ws : list Val";
  let coqHyps = ["length vs = length ws"];
  let coqLhs = "(Unify (Ret (VTup vs)) (Ret (VTup ws)))";
  let coqRhs = "(eq_seq vs ws (Ret (VTup vs)))";
  let papForm = "⟨v1..vn⟩ = ⟨w1..wn⟩ -> v1=w1; .. ; vn=wn; ⟨v1..vn⟩";
}
def EqTup2Record : TimbdaRuleRecord {
  let ctor = "RewEqTup2";
  let kernelTag = "R_EqTup2";
  let selected = 1;
  let rank = 10;
  let group = "Norm";
  let fig = "9";
  let tier = 1;
  let semClass = "unify";
  let semName = "eqtup2";
  let lhs = "⟨v1..vn⟩ = ⟨w1..wm⟩";
  let rhs = "fail";
  let side = "if n <> m";
  let status = "discharged";
  let pattern = "drr";
  let ops = ["unify", "tup", "fail"];
  let tags = [];
  let coqTag = "EqTup2";
  let coqForall = "vs ws : list Val";
  let coqHyps = ["length vs <> length ws"];
  let coqLhs = "(Unify (Ret (VTup vs)) (Ret (VTup ws)))";
  let coqRhs = "Fail";
  let papForm = "⟨v1..vn⟩ = ⟨w1..wm⟩ -> fail if n <> m";
}
def EqFailRecord : TimbdaRuleRecord {
  let ctor = "RewEqFail";
  let kernelTag = "R_EqFail";
  let selected = 1;
  let rank = 11;
  let group = "Norm";
  let fig = "9";
  let tier = 1;
  let semClass = "unify";
  let semName = "eqfail";
  let lhs = "hnf1 = hnf2";
  let rhs = "fail";
  let side = "if different root shapes";
  let status = "discharged";
  let pattern = "drr";
  let ops = ["unify", "fail"];
  let tags = [];
  let coqTag = "EqFail";
  let coqForall = "v1 v2 : Val";
  let coqHyps = ["root_mismatch v1 v2 = true"];
  let coqLhs = "(Unify (Ret v1) (Ret v2))";
  let coqRhs = "Fail";
  let papForm = "hnf1 = hnf2 -> fail if different root shapes; NO rule when either side is a bare variable or both are lambdas (no_eq_rule_pair, lines 441-445): those stay stuck";
}
def AddRecord : TimbdaRuleRecord {
  let ctor = "RewAdd";
  let kernelTag = "R_Prim";
  let selected = 1;
  let rank = 15;
  let group = "Return";
  let fig = "10";
  let tier = 1;
  let semClass = "delta";
  let semName = "add";
  let lhs = "add[ki1, ki2]";
  let rhs = "ki1 + ki2";
  let status = "discharged";
  let pattern = "drr";
  let ops = ["prim", "int"];
  let tags = [];
  let coqTag = "Add";
  let coqForall = "a b : Z";
  let coqLhs = "(prim_app PAdd [Ret (VInt a); Ret (VInt b)])";
  let coqRhs = "(Ret (VInt (a + b)))";
  let papForm = "add[ki1, ki2] -> ki1 + ki2";
}
def Gt1Record : TimbdaRuleRecord {
  let ctor = "RewGt1";
  let kernelTag = "R_Prim";
  let selected = 1;
  let rank = 15;
  let group = "Return";
  let fig = "10";
  let tier = 1;
  let semClass = "delta";
  let semName = "gt1";
  let lhs = "gt[ki1, ki2]";
  let rhs = "ki1";
  let side = "if ki1 > ki2";
  let status = "discharged";
  let pattern = "drr";
  let ops = ["prim", "int"];
  let tags = [];
  let coqTag = "Gt1";
  let coqForall = "a b : Z";
  let coqHyps = ["Z.ltb b a = true"];
  let coqLhs = "(prim_app PGt [Ret (VInt a); Ret (VInt b)])";
  let coqRhs = "(Ret (VInt a))";
  let papForm = "gt[ki1, ki2] -> ki1 if ki1 > ki2";
}
def Gt2Record : TimbdaRuleRecord {
  let ctor = "RewGt2";
  let kernelTag = "R_Prim";
  let selected = 1;
  let rank = 15;
  let group = "Return";
  let fig = "10";
  let tier = 1;
  let semClass = "delta";
  let semName = "gt2";
  let lhs = "gt[ki1, ki2]";
  let rhs = "fail";
  let side = "if ki1 <= ki2";
  let status = "discharged";
  let pattern = "drr";
  let ops = ["prim", "int", "fail"];
  let tags = ["kernel-extension"];
  let coqTag = "Gt2";
  let coqForall = "a b : Z";
  let coqHyps = ["Z.ltb b a = false"];
  let coqLhs = "(prim_app PGt [Ret (VInt a); Ret (VInt b)])";
  let coqRhs = "Fail";
  let papForm = "gt[ki1, ki2] -> fail if ki1 <= ki2";
}
def IsInt1Record : TimbdaRuleRecord {
  let ctor = "RewIsInt1";
  let kernelTag = "R_Prim";
  let selected = 1;
  let rank = 15;
  let group = "Return";
  let fig = "10";
  let tier = 1;
  let semClass = "delta";
  let semName = "isInt1";
  let lhs = "isInt[ki]";
  let rhs = "ki";
  let status = "discharged";
  let pattern = "drr";
  let ops = ["prim", "int"];
  let tags = [];
  let coqTag = "IsInt1";
  let coqForall = "a : Z";
  let coqLhs = "(prim_app PIsInt [Ret (VInt a)])";
  let coqRhs = "(Ret (VInt a))";
  let papForm = "isInt[ki] -> ki";
}
def IsInt2Record : TimbdaRuleRecord {
  let ctor = "RewIsInt2";
  let kernelTag = "R_Prim";
  let selected = 1;
  let rank = 15;
  let group = "Return";
  let fig = "10";
  let tier = 1;
  let semClass = "delta";
  let semName = "isInt2";
  let lhs = "isInt[v]";
  let rhs = "fail";
  let side = "if v not an integer";
  let status = "discharged";
  let pattern = "drr";
  let ops = ["prim", "int", "fail"];
  let tags = ["kernel-extension"];
  let coqTag = "IsInt2";
  let coqForall = "v : Val";
  let coqHyps = ["is_int_val v = false"];
  let coqLhs = "(prim_app PIsInt [Ret v])";
  let coqRhs = "Fail";
  let papForm = "isInt[v] -> fail if v not an integer";
}
def ConsRecord : TimbdaRuleRecord {
  let ctor = "RewCons";
  let kernelTag = "R_Prim";
  let selected = 1;
  let rank = 15;
  let group = "Return";
  let fig = "10";
  let tier = 1;
  let semClass = "delta";
  let semName = "cons";
  let lhs = "cons[v0, ⟨v1..vn⟩]";
  let rhs = "⟨v0, v1, .., vn⟩";
  let status = "discharged";
  let pattern = "drr";
  let ops = ["prim", "tup"];
  let tags = [];
  let coqTag = "Cons";
  let coqForall = "(v0 : Val) (vs : list Val)";
  let coqLhs = "(prim_app PCons [Ret v0; Ret (VTup vs)])";
  let coqRhs = "(Ret (VTup (v0 :: vs)))";
  let papForm = "cons[v0, ⟨v1..vn⟩] -> ⟨v0, v1, .., vn⟩";
}
def DotDotRecord : TimbdaRuleRecord {
  let ctor = "RewDotDot";
  let kernelTag = "R_Prim";
  let selected = 1;
  let rank = 15;
  let group = "Return";
  let fig = "10";
  let tier = 1;
  let semClass = "delta";
  let semName = "dotdot";
  let lhs = "dotdot[ki1, ki2]";
  let rhs = "ki1 (ki1+1) .. ki2";
  let status = "discharged";
  let pattern = "drr";
  let ops = ["prim", "int", "tup"];
  let tags = ["inclusive-range:seq_z"];
  let coqTag = "DotDot";
  let coqForall = "a b : Z";
  let coqLhs = "(prim_app PDotDot [Ret (VInt a); Ret (VInt b)])";
  let coqRhs = "(Ret (VTup (map VInt (seq_z a b))))";
  let papForm = "dotdot[ki1, ki2] -> ki1 (ki1+1) .. ki2; kernel form: the range literal is materialised as a tuple of ints";
}
def PrimSchemaRecord : TimbdaRuleRecord {
  let ctor = "RewPrim";
  let kernelTag = "R_Prim";
  let selected = 1;
  let rank = 15;
  let group = "Return";
  let fig = "10";
  let tier = 1;
  let semClass = "delta";
  let semName = "prim-schema";
  let lhs = "op[gv ..]";
  let rhs = "result of the total primop table";
  let status = "partial";
  let pattern = "drr";
  let ops = ["prim", "int", "tup", "unit", "bool", "lambda", "delay"];
  let tags = ["SCHEMA", "kernel-extension"];
  let coqTag = "PrimSchema";
  let coqForall = "(p : Prim) (vs : list Val) (v : Val)";
  let coqHyps = ["prim_total p vs = PRes v"];
  let coqLhs = "(prim_app p (map Ret vs))";
  let coqRhs = "(Ret v)";
  let papForm = "op[gv ..] -> result of the total primop table; SCHEMA record, not one of the 33 named rule rows (VERSE-RULES § 3)";
}
def PrimSchemaFailRecord : TimbdaRuleRecord {
  let ctor = "RewPrimFail";
  let kernelTag = "R_PrimFail";
  let selected = 1;
  let rank = 16;
  let group = "Return";
  let fig = "10";
  let tier = 1;
  let semClass = "delta";
  let semName = "prim-schema-fail";
  let lhs = "op[gv ..]";
  let rhs = "fail";
  let side = "gt2/isInt2 are the named instances";
  let status = "partial";
  let pattern = "drr";
  let ops = ["prim", "fail"];
  let tags = ["SCHEMA", "kernel-extension"];
  let coqTag = "PrimSchemaFail";
  let coqForall = "(p : Prim) (vs : list Val)";
  let coqHyps = ["prim_total p vs = PFail"];
  let coqLhs = "(prim_app p (map Ret vs))";
  let coqRhs = "Fail";
  let papForm = "explicit-failure branch of the same schema (gt2/isInt2 are the named instances); SCHEMA record";
}
def BetaLRecord : TimbdaRuleRecord {
  let ctor = "RewBetaL";
  let kernelTag = "R_BetaL";
  let selected = 1;
  let rank = 12;
  let group = "Bind";
  let fig = "11";
  let tier = 1;
  let semClass = "eval";
  let semName = "beta-l";
  let lhs = "(λx.b)[e]";
  let rhs = "block{∃x{}. x = e; block{b}}";
  let status = "deferred";
  let pattern = "drr";
  let ops = ["app", "lambda", "bind", "unify"];
  let tags = ["deferral:C1"];
  let coqTag = "BetaL";
  let coqForall = "(t : Ty) (b e : Expr)";
  let coqLhs = "(App (Ret (VLam t b)) e)";
  let coqRhs = "(Block [(t, @None Val)] (Seq (Unify (Ret (VVar 0)) (liftE 1 0 e)) b))";
  let papForm = "(λx.b)[e] -> block{∃x{}. x = e; block{b}}";
}
def BetaTRecord : TimbdaRuleRecord {
  let ctor = "RewBetaT";
  let kernelTag = "R_BetaT";
  let selected = 1;
  let rank = 13;
  let group = "Bind";
  let fig = "11";
  let tier = 1;
  let semClass = "eval";
  let semName = "beta-t";
  let lhs = "⟨v0,..,vn⟩[e]";
  let rhs = "block{∃x{}. x = e; ((∃{}. x = 0; v0) .. (∃{}. x = n; vn))}";
  let side = "vs <> nil (narrowing)";
  let status = "deferred";
  let pattern = "drr";
  let ops = ["app", "tup", "bind", "unify", "or"];
  let tags = ["deferral:C1"];
  let coqTag = "BetaT";
  let coqForall = "(vs : list Val) (e : Expr)";
  let coqHyps = ["vs <> nil"];
  let coqLhs = "(App (Ret (VTup vs)) e)";
  let coqRhs = "(Block [(@TAny, @None Val)] (Seq (Unify (Ret (VVar 0)) (liftE 1 0 e)) (choice_list (beta_t_cands 0 vs))))";
  let papForm = "⟨v0,..,vn⟩[e] -> block{∃x{}. x = e; ((∃{}. x = 0; v0) .. (∃{}. x = n; vn))}; narrowing; the paper's `∃{}` is an empty slot list, hence index-neutral";
}
def BetaT0Record : TimbdaRuleRecord {
  let ctor = "RewBetaT0";
  let kernelTag = "R_BetaT0";
  let selected = 1;
  let rank = 14;
  let group = "Bind";
  let fig = "11";
  let tier = 1;
  let semClass = "eval";
  let semName = "beta-t0";
  let lhs = "⟨⟩[e]";
  let rhs = "fail";
  let status = "discharged";
  let pattern = "drr";
  let ops = ["app", "tup", "fail"];
  let tags = ["kernel-extension:base-case"];
  let coqTag = "BetaT0";
  let coqForall = "(e : Expr)";
  let coqLhs = "(App (Ret (VTup (@nil Val))) e)";
  let coqRhs = "Fail";
  let papForm = "base case of beta-t: ⟨⟩[e] -> fail (line 475); KERNEL-SIDE named rule extracted from that note";
}
def SeqRecord : TimbdaRuleRecord {
  let ctor = "RewSeq";
  let kernelTag = "R_Seq";
  let selected = 1;
  let rank = 1;
  let group = "BindL";
  let fig = "12";
  let tier = 1;
  let semClass = "eval";
  let semName = "seq";
  let lhs = "v ; e";
  let rhs = "e";
  let status = "discharged";
  let pattern = "drr";
  let ops = ["bind"];
  let tags = [];
  let coqTag = "Seq";
  let coqForall = "(v : Val) (e : Expr)";
  let coqLhs = "(Seq (Ret v) e)";
  let coqRhs = "e";
  let papForm = "v ; e -> e";
}
def Norm1Record : TimbdaRuleRecord {
  let ctor = "RewNorm1";
  let kernelTag = "R_Norm1";
  let selected = 1;
  let rank = 2;
  let group = "Norm";
  let fig = "12";
  let tier = 1;
  let semClass = "eval";
  let semName = "norm1";
  let lhs = "v = (e1 ; e2)";
  let rhs = "e1 ; v = e2";
  let status = "deferred";
  let pattern = "drr";
  let ops = ["unify", "bind"];
  let tags = ["deferral:C3"];
  let coqTag = "Norm1";
  let coqForall = "(v : Val) (e1 e2 : Expr)";
  let coqLhs = "(Unify (Ret v) (Seq e1 e2))";
  let coqRhs = "(Seq e1 (Unify (Ret v) e2))";
  let papForm = "v = (e1 ; e2) -> e1 ; v = e2";
}
def Norm2Record : TimbdaRuleRecord {
  let ctor = "RewNorm2";
  let kernelTag = "R_Norm2";
  let selected = 1;
  let rank = 3;
  let group = "Norm";
  let fig = "12";
  let tier = 1;
  let semClass = "eval";
  let semName = "norm2";
  let lhs = "v = (e1 = e2)";
  let rhs = "v = e1 ; v = e2";
  let status = "deferred";
  let pattern = "drr";
  let ops = ["unify", "bind"];
  let tags = ["deferral:C3"];
  let coqTag = "Norm2";
  let coqForall = "(v : Val) (e1 e2 : Expr)";
  let coqLhs = "(Unify (Ret v) (Unify e1 e2))";
  let coqRhs = "(Seq (Unify (Ret v) e1) (Unify (Ret v) e2))";
  let papForm = "v = (e1 = e2) -> v = e1 ; v = e2";
}
def Norm3Record : TimbdaRuleRecord {
  let ctor = "RewNorm3";
  let kernelTag = "R_Norm3";
  let selected = 1;
  let rank = 4;
  let group = "Norm";
  let fig = "12";
  let tier = 1;
  let semClass = "eval";
  let semName = "norm3";
  let lhs = "(e1 ; e2) = e3";
  let rhs = "e1 ; e2 = e3";
  let status = "deferred";
  let pattern = "drr";
  let ops = ["unify", "bind"];
  let tags = ["deferral:C3"];
  let coqTag = "Norm3";
  let coqForall = "(e1 e2 e3 : Expr)";
  let coqLhs = "(Unify (Seq e1 e2) e3)";
  let coqRhs = "(Seq e1 (Unify e2 e3))";
  let papForm = "(e1 ; e2) = e3 -> e1 ; e2 = e3";
}
def Norm4Record : TimbdaRuleRecord {
  let ctor = "RewNorm4";
  let kernelTag = "R_Norm4";
  let selected = 1;
  let rank = 5;
  let group = "Norm";
  let fig = "12";
  let tier = 1;
  let semClass = "eval";
  let semName = "norm4";
  let lhs = "(v = e1) = e2";
  let rhs = "v = e1 ; v = e2";
  let status = "deferred";
  let pattern = "drr";
  let ops = ["unify", "bind"];
  let tags = ["deferral:C3:progress"];
  let coqTag = "Norm4";
  let coqForall = "(v : Val) (e1 e2 : Expr)";
  let coqLhs = "(Unify (Unify (Ret v) e1) e2)";
  let coqRhs = "(Seq (Unify (Ret v) e1) (Unify (Ret v) e2))";
  let papForm = "(v = e1) = e2 -> v = e1 ; v = e2 (progress note, lines 502-503: unifying x with 5 may unlock p)";
}
def Norm5Record : TimbdaRuleRecord {
  let ctor = "RewNorm5";
  let kernelTag = "R_Norm5";
  let selected = 1;
  let rank = 6;
  let group = "NormL";
  let fig = "12";
  let tier = 1;
  let semClass = "eval";
  let semName = "norm5";
  let lhs = "(e1 ; e2) ; e3";
  let rhs = "e1 ; (e2 ; e3)";
  let status = "deferred";
  let pattern = "drr";
  let ops = ["bind"];
  let tags = ["deferral:C3:de-clutter"];
  let coqTag = "Norm5";
  let coqForall = "(e1 e2 e3 : Expr)";
  let coqLhs = "(Seq (Seq e1 e2) e3)";
  let coqRhs = "(Seq e1 (Seq e2 e3))";
  let papForm = "(e1 ; e2) ; e3 -> e1 ; (e2 ; e3) (de-clutter, line 504)";
}
def HpAlphaRecord : TimbdaRuleRecord {
  let ctor = "RewHpAlpha";
  let kernelTag = "R_HpAlpha";
  let selected = 0;
  let rank = 0;
  let group = "Norm";
  let fig = "12";
  let tier = 1;
  let semClass = "eval";
  let semName = "hp-alpha";
  let lhs = "∃X,x{hp}. e";
  let rhs = "∃X,y{hp[y/x]}. e[y/x]";
  let side = "y not in fvs(hp,e); renaming is identity under de Bruijn";
  let status = "discharged";
  let pattern = "none";
  let ops = ["block"];
  let tags = ["audit-only"];
  let coqTag = "HpAlpha";
  let coqForall = "(slots : list (Ty * option Val)) (body : Expr)";
  let coqLhs = "(Block slots body)";
  let coqRhs = "(Block slots body)";
  let papForm = "∃X,x{hp}. e <-> ∃X,y{hp[y/x]}. e[y/x] if y ∉ fvs(hp,e); representationally trivial under de Bruijn (renaming = identity), so this constructor is audit-only and Eval.v's strategy table never selects it. The named-syntax rename lives in the dialect (M1).";
}
def LamAlphaRecord : TimbdaRuleRecord {
  let ctor = "RewLamAlpha";
  let kernelTag = "R_LamAlpha";
  let selected = 0;
  let rank = 0;
  let group = "Norm";
  let fig = "12";
  let tier = 1;
  let semClass = "eval";
  let semName = "lambda-alpha";
  let lhs = "λx.e";
  let rhs = "λy.e[x/y]";
  let side = "same treatment as HpAlpha";
  let status = "discharged";
  let pattern = "none";
  let ops = ["lambda"];
  let tags = ["audit-only"];
  let coqTag = "LamAlpha";
  let coqForall = "(t : Ty) (e : Expr)";
  let coqLhs = "(Ret (VLam t e))";
  let coqRhs = "(Ret (VLam t e))";
  let papForm = "λx.e <-> λy.e[x/y]; same treatment as HpAlpha";
}
def FloatRecord : TimbdaRuleRecord {
  let ctor = "RewFloat";
  let kernelTag = "";
  let selected = 0;
  let rank = 0;
  let group = "Block";
  let fig = "12";
  let tier = 2;
  let semClass = "eval";
  let semName = "float";
  let lhs = "∃X{hx}. C[block{∃Y{hy}. e}]";
  let rhs = "∃X,Y{hx,hy}. C[e]";
  let side = "X # Y, Y not in fvs(C), fvsol(rng(hy)) # X; kernel states C = square";
  let status = "deferred";
  let pattern = "pdll";
  let ops = ["block"];
  let tags = ["deferral:C1", "kernel-stated-form:block-block"];
  let coqTag = "Float";
  let coqForall = "(sx sy : list (Ty * option Val)) (body : Expr)";
  let coqLhs = "(Block sx (Block sy body))";
  let coqRhs = "(Block (sx ++ sy) body)";
  let papForm = "∃X{hx}. C[block{∃Y{hy}. e}] -> ∃X,Y{hx,hy}. C[e] if X # Y, Y ∉ fvs(C), fvsol(rng(hy)) # X. Two kernel-side restrictions, both recorded: (i) the constructor states C = □ (the C-general form needs the flatten-substitution lemma, M3/T1); (ii) under the outermost-first slot convention the merge is *free* — `sx ++ sy` lists the outer slots first, so every slot value and the body keep their indices and the paper's freshness side conditions hold by construction.";
}
def SubstRecord : TimbdaRuleRecord {
  let ctor = "RewSubst";
  let kernelTag = "R_Subst";
  let selected = 1;
  let rank = 17;
  let group = "BindSub";
  let fig = "8";
  let tier = 1;
  let semClass = "eval";
  let semName = "subst";
  let lhs = "existsX{hp, x v}. S[x]";
  let rhs = "existsX{hp, x v}. S[v]";
  let side = "x not in bvs(S); binder-free CtxS kernel restriction";
  let status = "deferred";
  let pattern = "pdll";
  let ops = ["block"];
  let tags = ["deferral:C1"];
  let coqTag = "Subst";
  let coqForall = "slots (p : nat) (v : Val) (k : CtxS)";
  let coqHyps = ["slot_value_at slots p = Some v"];
  let coqLhs = "(Block slots (fillS k (Ret (VVar (slot_body_idx (length slots) p)))))";
  let coqRhs = "(Block slots (fillS k (Ret (slotValueFromBody (length slots) p v))))";
  let papForm = "existsX{hp, x v}. S[x] -> existsX{hp, x v}. S[v] if x not in bvs(S); binder-free-S kernel restriction + CtxS closure recorded";
}
def Gc1Record : TimbdaRuleRecord {
  let ctor = "RewGc1";
  let kernelTag = "R_Gc1";
  let selected = 0;
  let rank = 0;
  let group = "BindSub";
  let fig = "8";
  let tier = 1;
  let semClass = "eval";
  let semName = "gc1";
  let lhs = "existsX,Y{hp}. e";
  let rhs = "existsX{hp_Y}. e";
  let side = "Y a single unused value binding; SCC form is the Gc-Rec record";
  let status = "deferred";
  let pattern = "pdll";
  let ops = ["block"];
  let tags = ["deferral:C1", "kernel-extension:split-from-Gc",
                               "never-fired-by-design:M2"];
  let coqTag = "Gc1";
  let coqForall = "slots (p : nat) (body : Expr)";
  let coqHyps = ["slot_value_at slots p <> @None Val", "slot_unused (length slots) p slots body = true"];
  let coqLhs = "(Block slots body)";
  let coqRhs = "(Block (dropSlot (length slots) p slots) (shrinkE (slot_body_idx (length slots) p) body))";
  let papForm = "existsX,Y{hp}. e -> existsX{hp_Y}. e for Y a single unused value binding; the paper's SCC form (recursive heaps) is the admitted Tier-2 row `Gc-Rec` (VERSE-RULES 3.2), and the non-recursive M0 restriction is recorded there too";
}
def PromoteLRecord : TimbdaRuleRecord {
  let ctor = "RewPromoteL";
  let kernelTag = "R_PromoteL";
  let selected = 1;
  let rank = 18;
  let group = "BindSub";
  let fig = "8";
  let tier = 2;
  let semClass = "eval";
  let semName = "promote-l";
  let lhs = "existsX,x{hp}. C[x = v]";
  let rhs = "existsX,x{hp[v/x], x v}. C[v]";
  let side = "promote_ok && promote_hp_ok (hp[v/x] = identity at M0)";
  let status = "deferred";
  let pattern = "pdll";
  let ops = ["block", "unify"];
  let tags = ["deferral:C1", "tier2-evolving-heap:M3/T1"];
  let coqTag = "PromoteL";
  let coqForall = "slots (p : nat) (k : CtxC) (v : Val)";
  let coqHyps = ["slot_value_at slots p = @None Val", "promote_ok (length slots) v = true", "promote_hp_ok slots p = true"];
  let coqLhs = "(Block slots (fillC k (Unify (Ret (VVar (slot_body_idx (length slots) p))) (Ret v))))";
  let coqRhs = "(Block (fillSlot p (bodyToSlotV (length slots) p v) slots) (fillC k (Ret v)))";
  let papForm = "existsX,x{hp}. C[x = v] -> existsX,x{hp[v/x], x v}. C[v]; Tier 2: the constructor carries the successful promotion (fill slot + discharge unification to `Ret v`, matching eqk1's \"unification returns its value\"), while `hp[v/x]` is restricted to the identity by `promote_hp_ok` — the general evolving-heap form is admitted until M3/T1";
}
def PromoteRRecord : TimbdaRuleRecord {
  let ctor = "RewPromoteR";
  let kernelTag = "R_PromoteR";
  let selected = 1;
  let rank = 19;
  let group = "BindSub";
  let fig = "8";
  let tier = 2;
  let semClass = "eval";
  let semName = "promote-r";
  let lhs = "existsX,x{hp}. C[v = x]";
  let rhs = "existsX,x{hp[v/x], x v}. C[v]";
  let side = "as PromoteL; kept separate because a swap rule could loop (lines 425-428)";
  let status = "deferred";
  let pattern = "pdll";
  let ops = ["block", "unify"];
  let tags = ["deferral:C1", "kernel-extension:explicit",
                                        "tier2-evolving-heap:M3/T1"];
  let coqTag = "PromoteR";
  let coqForall = "slots (p : nat) (k : CtxC) (v : Val)";
  let coqHyps = ["slot_value_at slots p = @None Val", "promote_ok (length slots) v = true", "promote_hp_ok slots p = true"];
  let coqLhs = "(Block slots (fillC k (Unify (Ret v) (Ret (VVar (slot_body_idx (length slots) p))))))";
  let coqRhs = "(Block (fillSlot p (bodyToSlotV (length slots) p v) slots) (fillC k (Ret v)))";
  let papForm = "existsX,x{hp}. C[v = x] -> ... just like promote-l (line 417); kept as its own constructor because the paper rules out a swap rule (lines 425-428: x = y could loop)";
}
def IterFailRecord : TimbdaRuleRecord {
  let ctor = "RewIterFail";
  let kernelTag = "R_IterFail";
  let selected = 0;
  let rank = 0;
  let group = "Norm";
  let fig = "13";
  let tier = 1;
  let semClass = "eval";
  let semName = "iter-fail";
  let lhs = "iter(ic){B[C[fail]]}{e}";
  let rhs = "e";
  let status = "deferred";
  let pattern = "pdll";
  let ops = ["iter", "block", "fail"];
  let tags = ["deferral:C4", "never-fired:M3"];
  let coqTag = "IterFail";
  let coqForall = "(ic : IterComb) (slots : list (Ty * option Val)) (k : CtxC) (e : Expr)";
  let coqLhs = "(Iter ic (Block slots (fillC k Fail)) e)";
  let coqRhs = "e";
  let papForm = "iter(ic){B[C[fail]]}{e} -> e";
}
def IterChoiceRecord : TimbdaRuleRecord {
  let ctor = "RewIterChoice";
  let kernelTag = "R_IterChoice";
  let selected = 0;
  let rank = 0;
  let group = "Choice";
  let fig = "13";
  let tier = 1;
  let semClass = "eval";
  let semName = "iter-choice";
  let lhs = "iter(ic){B[C[b1 b2]]}{e}";
  let rhs = "iter(ic){B[C[block{b1}]]}{iter(ic){B[C[block{b2}]]}{e}}";
  let status = "deferred";
  let pattern = "pdll";
  let ops = ["iter", "block", "or"];
  let tags = ["deferral:C4", "never-fired:M3",
                                             "T2:interchange-is-br2-bind"];
  let coqTag = "IterChoice";
  let coqForall = "(ic : IterComb) (slots : list (Ty * option Val)) (k : CtxC) (e1 e2 e : Expr)";
  let coqHyps = ["leftChoiceFreeC k = true"];
  let coqLhs = "(Iter ic (Block slots (fillC k (Choice e1 e2))) e)";
  let coqRhs = "(Iter ic (Block slots (fillC k (Block nil e1))) (Iter ic (Block slots (fillC k (Block nil e2))) e))";
  let papForm = "iter(ic){B[C[b1 b2]]}{e} -> iter(ic){B[C[block{b1}]]}{iter(ic){B[C[block{b2}]]}{e}} if leftChoiceFree(C); the figure prints the inner continuation as `e3` (line 517-518) — read as the shared continuation `e`, as transcribed in VERSE-RULES 3.4; kernel Choice = select, `block{b}` = Block nil; the ctrees-side soundness of this rule IS the bind/br2 interchange (Denotation.v)";
}
def IterIfRecord : TimbdaRuleRecord {
  let ctor = "RewIterIf";
  let kernelTag = "R_IterIf";
  let selected = 0;
  let rank = 0;
  let group = "IfS";
  let fig = "13";
  let tier = 1;
  let semClass = "eval";
  let semName = "iter-if";
  let lhs = "iter(if){B[delay{e1}]}{e2}";
  let rhs = "block{B[e1]}";
  let status = "deferred";
  let pattern = "pdll";
  let ops = ["iter", "block", "delay"];
  let tags = ["deferral:C4", "never-fired:M3"];
  let coqTag = "IterIf";
  let coqForall = "(slots : list (Ty * option Val)) (e1 e2 : Expr)";
  let coqLhs = "(Iter IIf (Block slots (Ret (VDelay e1))) e2)";
  let coqRhs = "(Block nil (Block slots e1))";
  let papForm = "iter(if){B[delay{e1}]}{e2} -> block{B[e1]}";
}
def IterAllRecord : TimbdaRuleRecord {
  let ctor = "RewIterAll";
  let kernelTag = "R_IterAll";
  let selected = 0;
  let rank = 0;
  let group = "AllU";
  let fig = "13";
  let tier = 1;
  let semClass = "eval";
  let semName = "iter-all";
  let lhs = "iter(all){B[v]}{e}";
  let rhs = "cons[B[v], e]";
  let status = "deferred";
  let pattern = "pdll";
  let ops = ["iter", "block", "prim"];
  let tags = ["deferral:C4", "never-fired:M3"];
  let coqTag = "IterAll";
  let coqForall = "(slots : list (Ty * option Val)) (v : Val) (e : Expr)";
  let coqLhs = "(Iter IAll (Block slots (Ret v)) e)";
  let coqRhs = "(prim_app PCons [Block slots (Ret v); e])";
  let papForm = "iter(all){B[v]}{e} -> cons[B[v], e]; `cons[...]` takes open expressions, hence prim_app over TupE";
}
def IterForRecord : TimbdaRuleRecord {
  let ctor = "RewIterFor";
  let kernelTag = "R_IterFor";
  let selected = 0;
  let rank = 0;
  let group = "ForU";
  let fig = "13";
  let tier = 1;
  let semClass = "eval";
  let semName = "iter-for";
  let lhs = "iter(for){B[v]}{e}";
  let rhs = "block{exists x{}. cons2[<x, B[v]>, e]}";
  let side = "new slot declared-unvalued; explicit lift-1";
  let status = "deferred";
  let pattern = "pdll";
  let ops = ["iter", "block", "prim"];
  let tags = ["deferral:C4", "never-fired:M3"];
  let coqTag = "IterFor";
  let coqForall = "(slots : list (Ty * option Val)) (v : Val) (e : Expr)";
  let coqLhs = "(Iter IFor (Block slots (Ret v)) e)";
  let coqRhs = "(Block [(@TAny, @None Val)] (prim_app PCons2 [TupE [Ret (VVar 0); liftE 1 0 (Block slots (Ret v))]; liftE 1 0 e]))";
  let papForm = "iter(for){B[v]}{e} -> block{exists x{}. cons2[<x, B[v]>, e]}; the new slot x is declared-unvalued (`exists x{}`), and B[v] and e move *inside* it, hence the explicit lift-1 (docs/DESIGN-NOTES.md 1); x = body index 0.";
}
def Gc_RecRecord : TimbdaRuleRecord {
  let ctor = "";
  let kernelTag = "";
  let selected = 0;
  let rank = 0;
  let group = "";
  let fig = "8";
  let tier = 2;
  let isEssential = 0;
  let semClass = "eval";
  let semName = "gc-scc";
  let lhs = "Gc's SCC form over mutually-recursive heaps";
  let rhs = "";
  let status = "record";
  let pattern = "none";
  let ops = ["block"];
  let tags = ["M3/T1-obligation", "VERSE:3.2"];
}
def Subst_DeepRecord : TimbdaRuleRecord {
  let ctor = "";
  let kernelTag = "";
  let selected = 0;
  let rank = 0;
  let group = "";
  let fig = "6/8";
  let tier = 2;
  let isEssential = 0;
  let semClass = "eval";
  let semName = "subst-deep";
  let lhs = "rewriting in place inside slot values (the paper's B[S ], lambda x.B[S ])";
  let rhs = "";
  let status = "record";
  let pattern = "none";
  let ops = ["block", "lambda"];
  let tags = ["deferral:C1", "barrier:TupE-Choice-Iter-Block"];
}
def Match_MwildRecord : TimbdaRuleRecord {
  let ctor = "";
  let group = "";
  let fig = "14";
  let tier = 2;
  let isEssential = 1;
  let semClass = "match";
  let semName = "mwild";
  let lhs = "u maps-wild -> -";
  let rhs = "u";
  let status = "record";
  let pattern = "m3";
  let ops = ["match"];
  let tags = ["dev-1", "M3-obligation"];
}
def Match_MlitRecord : TimbdaRuleRecord {
  let ctor = "";
  let group = "";
  let fig = "14";
  let tier = 2;
  let isEssential = 1;
  let semClass = "match";
  let semName = "mlit";
  let lhs = "u maps-wild -> k";
  let rhs = "u = k";
  let status = "record";
  let pattern = "m3";
  let ops = ["match", "unify"];
  let tags = ["dev-1", "M3-obligation"];
}
def Match_MvarRecord : TimbdaRuleRecord {
  let ctor = "";
  let group = "";
  let fig = "14";
  let tier = 2;
  let isEssential = 1;
  let semClass = "match";
  let semName = "mvar";
  let lhs = "u maps-wild -> y";
  let rhs = "u = y";
  let status = "record";
  let pattern = "m3";
  let ops = ["match", "unify"];
  let tags = ["dev-1", "M3-obligation"];
}
def Match_MdefRecord : TimbdaRuleRecord {
  let ctor = "";
  let group = "";
  let fig = "14";
  let tier = 2;
  let isEssential = 1;
  let semClass = "match";
  let semName = "mdef";
  let lhs = "u maps-wild -> x := t";
  let rhs = "x = (u maps-wild -> t)";
  let status = "record";
  let pattern = "m3";
  let ops = ["match", "bind"];
  let tags = ["dev-1", "M3-obligation"];
}
def Match_MinpRecord : TimbdaRuleRecord {
  let ctor = "";
  let group = "";
  let fig = "14";
  let tier = 2;
  let isEssential = 1;
  let semClass = "match";
  let semName = "minp";
  let lhs = "u maps-wild -> x : t";
  let rhs = "x = u; u maps-wild -> t";
  let status = "record";
  let pattern = "m3";
  let ops = ["match", "bind"];
  let tags = ["dev-1", "M3-obligation"];
}
def Match_MblockRecord : TimbdaRuleRecord {
  let ctor = "";
  let group = "";
  let fig = "14";
  let tier = 2;
  let isEssential = 1;
  let semClass = "match";
  let semName = "mblock";
  let lhs = "u maps-wild -> block{t}";
  let rhs = "block{exists tbs(t){}. u maps-wild -> t}";
  let status = "record";
  let pattern = "m3";
  let ops = ["match", "block"];
  let tags = ["dev-1", "M3-obligation"];
}
def Match_MappRecord : TimbdaRuleRecord {
  let ctor = "";
  let group = "";
  let fig = "14";
  let tier = 2;
  let isEssential = 1;
  let semClass = "match";
  let semName = "mapp";
  let lhs = "u maps-wild -> t1[t2]";
  let rhs = "u = desugar-w(t1) [ desugar-w(t2) ]";
  let status = "record";
  let pattern = "m3";
  let ops = ["match", "app", "unify"];
  let tags = ["dev-1", "M3-obligation"];
}
def Match_MunifRecord : TimbdaRuleRecord {
  let ctor = "";
  let group = "";
  let fig = "14";
  let tier = 2;
  let isEssential = 1;
  let semClass = "match";
  let semName = "munif";
  let lhs = "u maps-wild -> t1 = t2";
  let rhs = "(u maps-wild -> t1) = (u maps-wild -> t2)";
  let status = "record";
  let pattern = "m3";
  let ops = ["match", "unify"];
  let tags = ["dev-1", "M3-obligation"];
}
def Match_MchoiceRecord : TimbdaRuleRecord {
  let ctor = "";
  let group = "";
  let fig = "14";
  let tier = 2;
  let isEssential = 1;
  let semClass = "match";
  let semName = "mchoice";
  let lhs = "u maps-wild -> t1 t2";
  let rhs = "(u maps-wild -> block{t1}) (u maps-wild -> block{t2})";
  let status = "record";
  let pattern = "m3";
  let ops = ["match", "or", "block"];
  let tags = ["dev-1", "M3-obligation"];
}
def Match_MfailRecord : TimbdaRuleRecord {
  let ctor = "";
  let group = "";
  let fig = "14";
  let tier = 2;
  let isEssential = 1;
  let semClass = "match";
  let semName = "mfail";
  let lhs = "u maps-wild -> fail";
  let rhs = "fail";
  let status = "record";
  let pattern = "m3";
  let ops = ["match", "fail"];
  let tags = ["dev-1", "M3-obligation"];
}
def Match_MsemiRecord : TimbdaRuleRecord {
  let ctor = "";
  let group = "";
  let fig = "14";
  let tier = 2;
  let isEssential = 1;
  let semClass = "match";
  let semName = "msemi";
  let lhs = "u maps-wild -> t1 ; t2";
  let rhs = "desugar-w(t1) ; (u maps-wild -> t2)";
  let status = "record";
  let pattern = "m3";
  let ops = ["match", "bind"];
  let tags = ["dev-1", "M3-obligation"];
}
def Match_MwhereRecord : TimbdaRuleRecord {
  let ctor = "";
  let group = "";
  let fig = "14";
  let tier = 2;
  let isEssential = 1;
  let semClass = "match";
  let semName = "mwhere";
  let lhs = "u maps-wild -> t1 where t2";
  let rhs = "exists y{}. y = (u maps-wild -> t1); desugar-w(t2); y";
  let side = "keep t1 and t2 in the same order, in case they have effects (line 566)";
  let status = "record";
  let pattern = "m3";
  let ops = ["match", "block", "bind"];
  let tags = ["dev-1", "M3-obligation"];
}
def Match_MtupRecord : TimbdaRuleRecord {
  let ctor = "";
  let group = "";
  let fig = "14";
  let tier = 2;
  let isEssential = 1;
  let semClass = "match";
  let semName = "mtup";
  let lhs = "u maps-wild -> array{t1 ... tn}";
  let rhs = "block{exists u1...un, y1...yn{}. u = <u1...un>; y1=(u1 maps-wild -> t1); ...; <y1...yn>}";
  let status = "record";
  let pattern = "m3";
  let ops = ["match", "block", "tup", "bind"];
  let tags = ["dev-1", "M3-obligation"];
}
def Match_Mcolon1Record : TimbdaRuleRecord {
  let ctor = "";
  let group = "";
  let fig = "14";
  let tier = 2;
  let isEssential = 1;
  let semClass = "match";
  let semName = "mcolon1";
  let lhs = "x maps-wild -> :t";
  let rhs = "desugar-w(t) [x]";
  let status = "record";
  let pattern = "m3";
  let ops = ["match", "app"];
  let tags = ["dev-1", "M3-obligation"];
}
def Match_MifRecord : TimbdaRuleRecord {
  let ctor = "";
  let group = "If";
  let fig = "14";
  let tier = 2;
  let isEssential = 1;
  let semClass = "match";
  let semName = "mif";
  let lhs = "u maps-wild -> if(t0){t1} else {t2}";
  let rhs = "iter(if){exists tbs(t0){}. desugar-w(t0); delay{u maps-wild -> block{t1}}}{u maps-wild -> block{t2}}";
  let status = "record";
  let pattern = "m3";
  let ops = ["match", "iter", "delay", "block"];
  let tags = ["dev-1", "M3-obligation"];
}
def Match_MallRecord : TimbdaRuleRecord {
  let ctor = "";
  let group = "AllS";
  let fig = "14";
  let tier = 2;
  let isEssential = 1;
  let semClass = "match";
  let semName = "mall";
  let lhs = "u maps-wild -> for{t}";
  let rhs = "u = iter(all){exists tbs(t){}. desugar-w(t)}{<empty>}";
  let status = "record";
  let pattern = "m3";
  let ops = ["match", "iter", "unify"];
  let tags = ["dev-1", "M3-obligation"];
}
def Match_MforRecord : TimbdaRuleRecord {
  let ctor = "";
  let group = "ForS";
  let fig = "14";
  let tier = 2;
  let isEssential = 1;
  let semClass = "match";
  let semName = "mfor";
  let lhs = "u maps-wild -> for(t0) do{t1}";
  let rhs = "block{exists y{}. <u,y> = iter(for){... desugar-w(t0); lambda u'. u' maps-wild -> block{t1}}{<<empty>,<empty>>}; y}";
  let status = "record";
  let pattern = "m3";
  let ops = ["match", "iter", "block", "tup"];
  let tags = ["dev-1", "M3-obligation"];
}
def Match_MfunRecord : TimbdaRuleRecord {
  let ctor = "";
  let group = "Match";
  let fig = "15";
  let tier = 2;
  let isEssential = 1;
  let semClass = "match";
  let semName = "mfun";
  let lhs = "h maps-wild -> fun(at){bt}";
  let rhs = "lambda u. exists p,q,tbs(at){}. p = (u maps-wild -> at); Wbb[q = h[p]]; q maps-wild -> block{bt}";
  let side = "(bb,dr,vx) = w; W-open[e] = <empty>; W-closed[e] = e";
  let status = "record";
  let pattern = "m3";
  let ops = ["match", "lambda", "block"];
  let tags = ["dev-1", "M3-obligation"];
}
def Verify_MFunRecord : TimbdaRuleRecord {
  let ctor = "";
  let group = "";
  let fig = "16";
  let tier = 2;
  let isEssential = 1;
  let semClass = "match";
  let semName = "mfun-verify";
  let lhs = "h maps-wild -> fun(at){bt} (verification mode, angle-omega effects)";
  let rhs = "";
  let status = "record";
  let pattern = "none";
  let ops = [];
  let tags = ["rejected-by-legality-checker", "lines:585-612"];
}
def Verify_MOFTypeRecord : TimbdaRuleRecord {
  let ctor = "";
  let group = "";
  let fig = "16";
  let tier = 2;
  let isEssential = 1;
  let semClass = "match";
  let semName = "moftype";
  let lhs = "u maps-wild -> t1 of-omega t2";
  let rhs = "";
  let status = "record";
  let pattern = "none";
  let ops = [];
  let tags = ["rejected-by-legality-checker", "core-verse-fragment:deferred"];
}
def OFTypeRecord : TimbdaRuleRecord {
  let ctor = "";
  let group = "";
  let fig = "16";
  let tier = 2;
  let isEssential = 1;
  let semClass = "match";
  let semName = "oftype";
  let lhs = "e1 of-omega e2";
  let rhs = "e2[e1]";
  let side = "outside verify";
  let status = "record";
  let pattern = "none";
  let ops = [];
  let tags = ["rejected-by-legality-checker"];
}
def TypeofRecord : TimbdaRuleRecord {
  let ctor = "";
  let group = "";
  let fig = "";
  let tier = 3;
  let isEssential = 1;
  let semClass = "match";
  let semName = "typeof";
  let lhs = "the AST-level runtime projection of `of` (PLAN sec. 4.1)";
  let rhs = "";
  let status = "record";
  let pattern = "none";
  let ops = ["typeof"];
  let tags = ["dev-2", "M3-obligation"];
}
def Verify_SolverRecord : TimbdaRuleRecord {
  let ctor = "";
  let group = "";
  let fig = "17";
  let tier = 3;
  let isEssential = 1;
  let semClass = "solver";
  let semName = "solver";
  let lhs = "verify(R; A){b}";
  let rhs = "<empty>";
  let side = "if R; A is inconsistent";
  let status = "record";
  let pattern = "none";
  let ops = [];
  let tags = ["rejected:verify"];
}
def Verify_ValRecord : TimbdaRuleRecord {
  let ctor = "";
  let group = "";
  let fig = "17";
  let tier = 3;
  let isEssential = 1;
  let semClass = "solver";
  let semName = "v-val";
  let lhs = "verify(R; A){B[v]}";
  let rhs = "<empty>";
  let status = "record";
  let pattern = "none";
  let ops = [];
  let tags = ["rejected:verify"];
}
def Verify_ChoiceRecord : TimbdaRuleRecord {
  let ctor = "";
  let group = "";
  let fig = "17";
  let tier = 3;
  let isEssential = 1;
  let semClass = "solver";
  let semName = "v-choice";
  let lhs = "verify(R; A){P[e1 e2]}";
  let rhs = "verify(R; A){P[e1]}; verify(R; A){P[e2]}";
  let status = "record";
  let pattern = "none";
  let ops = [];
  let tags = ["rejected:verify"];
}
def Verify_FailRecord : TimbdaRuleRecord {
  let ctor = "";
  let group = "";
  let fig = "17";
  let tier = 3;
  let isEssential = 1;
  let semClass = "solver";
  let semName = "v-fail";
  let lhs = "verify(R; A){P[fail]}";
  let rhs = "<empty>";
  let status = "record";
  let pattern = "none";
  let ops = [];
  let tags = ["rejected:verify"];
}
def Verify_SplitValRecord : TimbdaRuleRecord {
  let ctor = "";
  let group = "";
  let fig = "17";
  let tier = 3;
  let isEssential = 1;
  let semClass = "solver";
  let semName = "split-val";
  let lhs = "verify(R; A){P[r = gv; e]}";
  let rhs = "verify(R; A, r = gv){P[e]}; verify(R; A, r <> gv){P[fail]}";
  let status = "record";
  let pattern = "none";
  let ops = [];
  let tags = ["rejected:verify", "skolems:no-kernel-case"];
}
def Verify_SplitOpRecord : TimbdaRuleRecord {
  let ctor = "";
  let group = "";
  let fig = "17";
  let tier = 3;
  let isEssential = 1;
  let semClass = "solver";
  let semName = "split-op";
  let lhs = "verify(R; A){P[op[gv]]}";
  let rhs = "verify(R, r; A, r = op[gv]){P[r]}; verify(R; A, not op[gv]){P[fail]}";
  let side = "if r not in R";
  let status = "record";
  let pattern = "none";
  let ops = [];
  let tags = ["rejected:verify", "skolems:no-kernel-case"];
}
def Verify_SplitTupRecord : TimbdaRuleRecord {
  let ctor = "";
  let group = "";
  let fig = "17";
  let tier = 3;
  let isEssential = 1;
  let semClass = "solver";
  let semName = "split-tup";
  let lhs = "verify(R; A){P[r = <v1...vn>; e]}";
  let rhs = "verify(R, r1...rn; A, r = <r1...rn>){P[r1 = v1; ...; rn = vn; e]}; verify(R; A, r <> < , ..., >){P[fail]}";
  let status = "record";
  let pattern = "none";
  let ops = [];
  let tags = ["rejected:verify", "skolems:no-kernel-case"];
}
def Verify_SplitAppRecord : TimbdaRuleRecord {
  let ctor = "";
  let group = "";
  let fig = "17";
  let tier = 3;
  let isEssential = 1;
  let semClass = "solver";
  let semName = "split-app";
  let lhs = "verify(R; A){P[f[gv]]}";
  let rhs = "verify(R, r; A, r = AP[f, gv]){P[r]}";
  let side = "if f in R, r not in R";
  let status = "record";
  let pattern = "none";
  let ops = [];
  let tags = ["rejected:verify", "skolems:no-kernel-case"];
}
def Verify_SplitAppFRecord : TimbdaRuleRecord {
  let ctor = "";
  let group = "";
  let fig = "17";
  let tier = 3;
  let isEssential = 1;
  let semClass = "solver";
  let semName = "split-appf";
  let lhs = "verify(R; A){P[f[lambda x.e]]}";
  let rhs = "verify(R, r; A){P[r]}";
  let side = "if f in R, r not in R";
  let status = "record";
  let pattern = "none";
  let ops = [];
  let tags = ["rejected:verify", "skolems:no-kernel-case"];
}
def Verify_SomeRecord : TimbdaRuleRecord {
  let ctor = "";
  let group = "";
  let fig = "17";
  let tier = 3;
  let isEssential = 1;
  let semClass = "solver";
  let semName = "v-some";
  let lhs = "verify(R; A){P[e1 of-omega e2]}";
  let rhs = "verify(R, r; A){exists x. x = e2[r]; P[x]}; verify(R; A){exists x. x = e2[r]; P[fail]}";
  let side = "if r not in R and fvs(v) disjoint bvs(P)";
  let status = "record";
  let pattern = "none";
  let ops = [];
  let tags = ["rejected:verify", "skolems:no-kernel-case"];
}
def Olam_UnifyRecord : TimbdaRuleRecord {
  let ctor = "";
  let group = "";
  let fig = "18";
  let tier = 3;
  let isEssential = 1;
  let semClass = "olam";
  let semName = "u-olam";
  let lhs = "olam(z1, v1) = olam(z2, v2); e";
  let rhs = "exists z3. z1 = olam(z3, v2); z2 = olam(z3, v1); e";
  let status = "record";
  let pattern = "none";
  let ops = [];
  let tags = ["paper-incomplete:fig18", "no-kernel:olam"];
}
def Olam_AppRecord : TimbdaRuleRecord {
  let ctor = "";
  let group = "";
  let fig = "18";
  let tier = 3;
  let isEssential = 1;
  let semClass = "olam";
  let semName = "app-olam";
  let lhs = "(olam(z, v1))[v2]";
  let rhs = "exists x. x = z[v2]; x = v1[v2]; x";
  let status = "record";
  let pattern = "none";
  let ops = [];
  let tags = ["paper-incomplete:fig18", "no-kernel:olam"];
}
def Olam_ExiAppRecord : TimbdaRuleRecord {
  let ctor = "";
  let group = "";
  let fig = "18";
  let tier = 3;
  let isEssential = 1;
  let semClass = "olam";
  let semName = "exi-app";
  let lhs = "exists z. e";
  let rhs = "e[(lambda x. exists y. y)/z]";
  let side = "if z occurs in e only as z[v]";
  let status = "record";
  let pattern = "none";
  let ops = [];
  let tags = ["paper-incomplete:fig18", "no-kernel:olam"];
}
def Extern_dcont_shiftRecord : TimbdaExternRecord {
  let cppDecl = "int timbda_dcont_shift(void* dcont, void* frame);";
  let llvmAttrs = ["convergent", "nobuiltin", "nocf_check"];
  let hasWillReturn = 0;
  let veriFFISpec = "timbda_ffi_dcont_shift";
  let status = "record:M4";
  let tags = ["m4-boost-context"];
}
def Extern_dcont_resetRecord : TimbdaExternRecord {
  let cppDecl = "int timbda_dcont_reset(void* dcont, void* frame);";
  let llvmAttrs = ["convergent", "nobuiltin", "nocf_check"];
  let hasWillReturn = 0;
  let veriFFISpec = "timbda_ffi_dcont_reset";
  let status = "record:M4";
  let tags = ["m4-boost-context"];
}
def Extern_dcont_yieldRecord : TimbdaExternRecord {
  let cppDecl = "int timbda_dcont_yield(void* dcont);";
  let llvmAttrs = ["convergent", "nobuiltin", "nocf_check"];
  let hasWillReturn = 0;
  let veriFFISpec = "timbda_ffi_dcont_yield";
  let status = "record:M4";
  let tags = ["m4-boost-context"];
}

// ---------------------------------------------------------------------------
// Audit summary (the arithmetic the rules-audit tool must reproduce):
// 72 = 35 ctor rows (15 discharged + 2 partial + 18 deferred) + 37 audit
// records (18 match + 4 essential + 10 verify + 3 olam + 2 kernel-adjacent);
// 27 RuleID tags = 19 selected_rows + 8 never-fired; selected ctors = 26
// (19 tags standing in for 26 ctor rows: 8 share R_Prim, 1 is R_PrimFail);
// 33 named ctors = 26 paper + 7 kernel-extension rows (tag below).
// ---------------------------------------------------------------------------

def TimbdaAuditSummary {
  int totalRecords = 72;
  int ctorRows = 35;
  int dischargedCtors = 15;
  int partialCtors = 2;
  int deferredCtors = 18;
  int auditRecordRows = 37;
  int matchRows = 18;
  int essentialRows = 4;
  int verifyRows = 10;
  int olamRows = 3;
  int kernelAdjacentRows = 2;
  int ruleidTags = 27;
  int selectedTags = 19;
  int neverFiredTagsCount = 8;
  int selectedCtors = 26;
  int namedCtors = 33;
  int paperNamedCtors = 26;
  int kernelExtensionRows = 7;
  int strategyGroups = 31;
  int groupsUsedM0 = 11;
  int externRecords = 3;
  list<string> kernelExtensionTags = [
    "Gt2", "IsInt2", "BetaT0", "PromoteR", "Gc1", "PrimSchema", "PrimSchemaFail"];
}

// ---------- -gen-rocq-rules emission groups (header comment lines and
// ctor order transcribed verbatim from the hand-glued ctor file by
// tools/rules-coqctor.py; the audit lane asserts the groups cover the 35
// ctor rows exactly once). ----------
class TimbdaRuleGroup {
  list<string> headerLines = [];
  list<string> ctors = [];
}
def GenGroupFig9 : TimbdaRuleGroup {
  let headerLines = ["---------- Fig. 9 (lines 432-437): unification ----------"];
  let ctors = ["RewEqK1", "RewEqK2", "RewEqTup1", "RewEqTup2", "RewEqFail"];
}
def GenGroupFig10 : TimbdaRuleGroup {
  let headerLines = ["---------- Fig. 10 (lines 452-459): primitive operations ----------", "Canonical primop application: `op[a1, a2]` = App (Ret (VPrim op)) (TupE [...]).", "`prim_total` (Syntax.v) is the kernel reading of Fig. 10 plus the pinned", "verse-semantics PrimOp table; `PStuck` means *no rule applies* (line 463)."];
  let ctors = ["RewAdd", "RewGt1", "RewGt2", "RewIsInt1", "RewIsInt2", "RewCons", "RewDotDot", "RewPrim", "RewPrimFail"];
}
def GenGroupFig11 : TimbdaRuleGroup {
  let headerLines = ["---------- Fig. 11 (lines 468-469): beta reduction ----------", "beta-l: the paper's side condition `x ∉ fvs(e)` (line 468) is discharged by the", "representation: `e` is lifted past the new slot, and `b` keeps its indices because", "the block's slot 0 replaces the lambda's binder at the same index.  The kernel's", "slot is *declared* (`None`) and the binding is written literally as the unification", "`x = e` in the body, exactly as the paper has it; `subst`/promote turn it into a", "heap value binding later (VERSE-RULES § 3.1)."];
  let ctors = ["RewBetaL", "RewBetaT", "RewBetaT0"];
}
def GenGroupFig12 : TimbdaRuleGroup {
  let headerLines = ["---------- Fig. 12 (lines 479-491): structural and normalisation ----------"];
  let ctors = ["RewSeq", "RewNorm1", "RewNorm2", "RewNorm3", "RewNorm4", "RewNorm5", "RewHpAlpha", "RewLamAlpha", "RewFloat"];
}
def GenGroupFig8 : TimbdaRuleGroup {
  let headerLines = ["---------- Fig. 8 (lines 412-417): substitution and promotion ----------", "`subst`: x = the body-position index of a *valued* slot; S = the binder-free", "CtxS fragment (Syntax.v header: with bvs(S) = empty the paper side condition", "x not in bvs(S) is automatic).  The heap entry v lives at the slot's own entry", "position, the occurrence S[x] at the body position: `slotValueFromBody` is the", "reindexing between the two, and the block wrapper is common to both sides."];
  let ctors = ["RewSubst", "RewGc1", "RewPromoteL", "RewPromoteR"];
}
def GenGroupFig13 : TimbdaRuleGroup {
  let headerLines = ["---------- Fig. 13 (lines 515-523): iteration and choice ----------", "`B[ ]` = block contexts `existsX{hp}. hole` (VERSE-RULES 3.4): the kernel states", "each rule as ONE block layer quantified over its slot list, with the plug written", "at the block's body position — exactly where the paper's hole is, so no lift is", "needed for B, and `C[ ]` is the binder-free CtxC fragment (leftChoiceFreeC per", "1).  `iter(all){B[v]}{e}` etc. match only when the hole is *directly* filled", "(with a value / fail / delay / choice), which is the paper's intended reading:", "the iter rule fires once the candidate body has reduced to that shape."];
  let ctors = ["RewIterFail", "RewIterChoice", "RewIterIf", "RewIterAll", "RewIterFor"];
}
def TimbdaRuleGenOrder {
  list<string> groups = ["GenGroupFig9", "GenGroupFig10", "GenGroupFig11", "GenGroupFig12", "GenGroupFig8", "GenGroupFig13"];
}
