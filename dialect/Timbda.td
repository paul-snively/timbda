//===- Timbda.td - Timbda-0 dialect ODS ---------------------*- tablegen -*-===//
//
// Timbda-0 (Core Verse) dialect: the MLIR expression surface the canonicalizer
// rewrites (docs/PLAN.md § 2: "dialect/ Timbda.td, DRR rewriters").
//
// Encoding notes (docs/DESIGN-NOTES.md § 10):
//   - Every expression carries exactly one Verse value of type `!timbda.value`
//     (Verse's single-value convention; candidate multiplicity is dynamic and
//     lives in the denotation, not in SSA multiplicity). `timbda.fail` is a
//     value-carrying op whose *denotation* is the empty candidate set.
//   - Block slots: valued slots (the paper's `x v`) are operand-captured by the
//     region - SSA substitution is therefore an encoding invariant (DEV-6);
//     declared-only slots (`x{}`) are region block arguments, and the promote
//     rows turn arguments into operands.
//   - `op[a1, a2]` (Fig. 10 line 452) is canonicalized as the single `timbda.prim`
//     op; the kernel-side canonical form is `App (Ret (VPrim op)) (Tup args)`.
//   - The 72 transcribed paper rules live in TimbdaRules.td (pure TableGen, no
//     back-reference), the generated rewrite defs in TimbdaPatterns.td, and the
//     region-heavy helper bodies in TimbdaCanonicalization.cpp - all cross-checked
//     by tools/rules-audit.py.
//
//===----------------------------------------------------------------------===//

#ifndef TIMBDA_TD
#define TIMBDA_TD

include "mlir/IR/OpBase.td"
include "mlir/IR/EnumAttr.td"
include "mlir/IR/SymbolInterfaces.td"
include "mlir/Interfaces/CallInterfaces.td"
include "mlir/Interfaces/SideEffectInterfaces.td"

def Timbda_Dialect : Dialect {
  let name = "timbda";
  let cppNamespace = "::timbda";
  let summary = "Timbda-0 (Core Verse) expression dialect";
  let description = [{
    Expression dialect for Timbda-0: literals, tuples, lambdas, `delay`,
    bind/sequencing, unification, internal choice (`or`), blocks with declared
    or valued slots, `iter(all|if|for)`, canonicalizer ops (get/put/select/
    match/typeof) and primop applications. Denotation: candidate sets via the
    ctrees `br2` reading (docs/PLAN.md § 5 M0); this dialect is the rewrite
    surface, the Gallina kernel is the semantic authority.
  }];

  // Timbda has no custom attributes or types beyond `!timbda.value`; keeping
  // the default attribute/type loaders active is what lets generic-form ops
  // round-trip without any hand-written dialect parser.
  let useDefaultAttributePrinterParser = 1;
  let useDefaultTypePrinterParser = 1;
}

// Timbda's single value type. Verse evaluates every expression to one value;
// static Verse types (TUnit/TBool/TInt/TArr) are carried by the canonicalizer
// ops' shape and the `timbda.typeof` row (T10), not by the SSA type (M1
// coarse type discipline; docs/DESIGN-NOTES.md § 10).
def TimbdaValueType : TypeDef<Timbda_Dialect, "Value"> {
  let mnemonic = "value";
}

// ODS uses the TypeDef record itself (`TimbdaValueType`) as the ins/outs type
// constraint; `!timbda.value` is the only Verse value type the dialect prints.

// ---------- enums (kernel mirrors: Syntax.v Prim / IterComb) ----------

// 18 cases, in coq/Syntax.v `Prim` ctor order (PAdd -> Add ...); the assembly
// mnemonics are the prim names quoted in the rule records' `lhs` text
// (`add[...]`, `isInt[...]`, `cons[...]`, `dotdot[...]` - docs/RULES-AUDIT.md
// sec. 1), so a DRR `ConstantEnumCase` names the same symbol a record quotes.
def Timbda_PrimEnumInfo : I64EnumAttr<"Prim", "verse primops (coq/Syntax.v `Prim`)", [
  I64EnumAttrCase<"Add", 0, "add">,
  I64EnumAttrCase<"Sub", 1, "sub">,
  I64EnumAttrCase<"Mul", 2, "mul">,
  I64EnumAttrCase<"Div", 3, "div">,
  I64EnumAttrCase<"Neg", 4, "neg">,
  I64EnumAttrCase<"Pls", 5, "pls">,
  I64EnumAttrCase<"Gt", 6, "gt">,
  I64EnumAttrCase<"Lt", 7, "lt">,
  I64EnumAttrCase<"Geq", 8, "geq">,
  I64EnumAttrCase<"Leq", 9, "leq">,
  I64EnumAttrCase<"Neq", 10, "neq">,
  I64EnumAttrCase<"IsInt", 11, "isInt">,
  I64EnumAttrCase<"IsBool", 12, "isBool">,
  I64EnumAttrCase<"IsUnit", 13, "isUnit">,
  I64EnumAttrCase<"Cons", 14, "cons">,
  I64EnumAttrCase<"Cons2", 15, "cons2">,
  I64EnumAttrCase<"DotDot", 16, "dotdot">,
  I64EnumAttrCase<"ArrLen", 17, "arrLen">,
]> {
  let cppNamespace = "::timbda";

  // The attribute is the `EnumAttr` AttrDef def below each info, so the legacy
  // IntegerAttr spelling is suppressed: -gen-enum-decls then emits only the
  // C++ enum plus stringify/symbolize helpers, and the attr class (and the
  // dialect's parseAttribute/printAttribute) comes from -gen-attrdef-*.
  let genSpecializedAttr = 0;
}

def Timbda_PrimAttr : EnumAttr<Timbda_Dialect, Timbda_PrimEnumInfo, "prim">;

def Timbda_IterCombEnumInfo : I64EnumAttr<"IterComb", "iter composition (coq/Syntax.v `IterComb`)", [
  I64EnumAttrCase<"All", 0, "all">,
  I64EnumAttrCase<"If", 1, "if">,
  I64EnumAttrCase<"For", 2, "for">,
]> {
  let cppNamespace = "::timbda";

  // The attribute is the `EnumAttr` AttrDef def below each info, so the legacy
  // IntegerAttr spelling is suppressed: -gen-enum-decls then emits only the
  // C++ enum plus stringify/symbolize helpers, and the attr class (and the
  // dialect's parseAttribute/printAttribute) comes from -gen-attrdef-*.
  let genSpecializedAttr = 0;
}

def Timbda_IterCombAttr : EnumAttr<Timbda_Dialect, Timbda_IterCombEnumInfo, "comb">;

// ---------- shared op traits ----------

// Every timbda expression op yields exactly one `!timbda.value` and has no
// effects: `Pure` (mlir/Interfaces/SideEffectInterfaces.td: AlwaysSpeculable +
// NoSideEffects) is the vintage spelling of the old NoSideEffects trait.  Result
// types are declared on every op, so no InferTypeOpInterface is needed.
def TimbdaValueResultTrait : TraitList<[Pure]>;

// ---------- ops: Core Verse expression surface ----------

class TimbdaOp<string mnemonic, list<Trait> traits = []> :
    Op<Timbda_Dialect, mnemonic, traits>;

def TimbdaUnitOp : TimbdaOp<"unit", [TimbdaValueResultTrait]> {
  let summary = "unit literal (Fig. 6 line 320: k ranges over unit/true/false/int)";
  let results = (outs TimbdaValueType:$result);
  let assemblyFormat = "attr-dict";
}

def TimbdaBoolOp : TimbdaOp<"bool", [TimbdaValueResultTrait]> {
  let summary = "true/false literal";
  let arguments = (ins BoolAttr:$value);
  let results = (outs TimbdaValueType:$result);
  let assemblyFormat = "$value attr-dict";
}

def TimbdaIntOp : TimbdaOp<"int", [TimbdaValueResultTrait]> {
  let summary = "integer literal; arbitrary precision (IntegerAttr APInt); " #
                "kernel maps VInt to Z with no width truncation at rewrite rows";
  let arguments = (ins APIntAttr:$value);
  let results = (outs TimbdaValueType:$result);
  let assemblyFormat = "$value attr-dict";
}

def TimbdaFailOp : TimbdaOp<"fail", [TimbdaValueResultTrait]> {
  let summary = "fail (denotes the empty candidate set); value-carrying so the " #
                "single-value SSA convention never strands a use";
  let results = (outs TimbdaValueType:$result);
  let assemblyFormat = "attr-dict";
}

def TimbdaTupOp : TimbdaOp<"tup", [TimbdaValueResultTrait]> {
  let summary = "tuple expression: value tuple when all operands are literal/" #
                "canonical values, else the kernel TupE open-expression form " #
                "(Syntax.v TupE header: op argument lists and Fig. 13 cons/cons2 " #
                "right-hand sides hold open expressions)";
  let arguments = (ins Variadic<TimbdaValueType>:$operands);
  let results = (outs TimbdaValueType:$result);
  let assemblyFormat = "(`[` $operands^ `]`)? attr-dict";
}

def TimbdaLambdaOp : TimbdaOp<"lambda", [TimbdaValueResultTrait]> {
  let summary = "Core-Verse lambda value (line 326: lambda x.b); body region " #
                "has exactly one block argument (the binder)";
  let regions = (region AnyRegion:$body);
  let results = (outs TimbdaValueType:$result);
  let assemblyFormat = "$body attr-dict";
}

def TimbdaDelayOp : TimbdaOp<"delay", [TimbdaValueResultTrait]> {
  let summary = "delay{e} value (line 326); body region has no block arguments";
  let regions = (region AnyRegion:$body);
  let results = (outs TimbdaValueType:$result);
  let assemblyFormat = "$body attr-dict";
}

def TimbdaGlobOp : TimbdaOp<"glob", [TimbdaValueResultTrait]> {
  let summary = "verse/host global (kernel Glob ident, Syntax.v header); " #
                "host get/put targets reach the kernel as Glob applications " #
                "(M4/T12), never as bare values";
  let arguments = (ins SymbolRefAttr:$sym);
  let results = (outs TimbdaValueType:$result);
  let assemblyFormat = "$sym attr-dict";
}

def TimbdaPrimOp : TimbdaOp<"prim", [TimbdaValueResultTrait]> {
  let summary = "canonical primop application: the dialect form of " #
                "op[a1, a2] = App (Ret (VPrim op)) (Tup args) (Fig. 10, line 452); " #
                "kernel canonical form is the single source (docs/DESIGN-NOTES.md § 10)";
  let arguments = (ins Timbda_PrimAttr:$prim, Variadic<TimbdaValueType>:$operands);
  let results = (outs TimbdaValueType:$result);
  let assemblyFormat = "$prim (`[` $operands^ `]`)? attr-dict";
}

def TimbdaAppOp : TimbdaOp<"app", [TimbdaValueResultTrait]> {
  let summary = "application e1[e2] (Fig. 6 line 327); primop calls use timbda.prim " #
                "instead, so this row covers tuple narrowing (beta-t) and lambda " #
                "application (beta-l) sites only";
  let arguments = (ins TimbdaValueType:$callee, TimbdaValueType:$arg);
  let results = (outs TimbdaValueType:$result);
  let assemblyFormat = "$callee `,` $arg attr-dict";
}

def TimbdaBindOp : TimbdaOp<"bind", [TimbdaValueResultTrait]> {
  let summary = "sequencing with a bind site: e1 ; e2 when the body argument is " #
                "unused (kernel Seq), x <- e1;; e2 at the source level (whose " #
                "Core-Verse desugaring is a block with a `x = e1` heap entry, " #
                "Fig. 11 line 468); region: one block, one argument";
  let arguments = (ins TimbdaValueType:$init);
  let regions = (region AnyRegion:$body);
  let results = (outs TimbdaValueType:$result);
  let assemblyFormat = "$init `,` $body attr-dict";
  let hasCustomAssemblyFormat = 0;
}

def TimbdaUnifyOp : TimbdaOp<"unify", [TimbdaValueResultTrait]> {
  let summary = "unification e1 = e2 (Fig. 6 line 329; rules Fig. 9, lines 432-437); " #
                "violations denote RFail, function/bare-variable pairs denote " #
                "RStuck (no rule exists, lines 441-445)";
  let arguments = (ins TimbdaValueType:$lhs, TimbdaValueType:$rhs);
  let results = (outs TimbdaValueType:$result);
  let assemblyFormat = "$lhs `,` $rhs attr-dict";
}

def TimbdaOrOp : TimbdaOp<"or", [TimbdaValueResultTrait]> {
  let summary = "internal candidate choice b1 b2 (juxtaposition in Fig. 6; " #
                "kernel Choice; denotation-side br2 - candidate split)";
  let arguments = (ins TimbdaValueType:$lhs, TimbdaValueType:$rhs);
  let results = (outs TimbdaValueType:$result);
  let assemblyFormat = "$lhs `,` $rhs attr-dict";
}

def TimbdaBlockOp : TimbdaOp<"block", [TimbdaValueResultTrait]> {
  let summary = "block{def(x1 t1){...}} (Fig. 6 line 334): operands are the " #
                "valued slot entries (hp `x v` - captured directly by the body " #
                "region; SSA substitution is the encoding invariant DEV-6), " #
                "region block arguments are the declared-only slots (`x{}`, " #
                "promote targets); result is the block value";
  let arguments = (ins Variadic<TimbdaValueType>:$slots);
  let regions = (region AnyRegion:$body);
  let results = (outs TimbdaValueType:$result);
  let assemblyFormat = "(`[` $slots^ `]`)? $body attr-dict";
}

def TimbdaIterOp : TimbdaOp<"iter", [TimbdaValueResultTrait]> {
  let summary = "iter(ic){b}{e}, ic in {all, if, for} (Fig. 6 line 342, rules " #
                "Fig. 13 lines 515-523); region 0 is the candidate body b, " #
                "region 1 the continuation e";
  let arguments = (ins Timbda_IterCombAttr:$comb);
  let regions = (region AnyRegion:$body, AnyRegion:$cont);
  let results = (outs TimbdaValueType:$result);
  let assemblyFormat = "$comb $body `,` $cont attr-dict";
}

// ---------- ops: canonicalizer surface (no M0 rewrite rule touches these) ----------

def TimbdaGetOp : TimbdaOp<"get"> {
  let summary = "read a Verse ref (canonicalizer row; kernel reads host refs as " #
                "Glob applications; exercised only at M4/T12 - PLAN § 5 M0 note)";
  let arguments = (ins SymbolRefAttr:$ref);
  let results = (outs TimbdaValueType:$result);
  let assemblyFormat = "$ref attr-dict";
}

def TimbdaPutOp : TimbdaOp<"put"> {
  let summary = "write a Verse ref; no value result (0-result op is legal here " #
                "because no candidate flows out of it)";
  let arguments = (ins SymbolRefAttr:$ref, TimbdaValueType:$value);
  let assemblyFormat = "$ref `,` $value attr-dict";
}

def TimbdaSelectOp : TimbdaOp<"select", [TimbdaValueResultTrait]> {
  let summary = "candidate select: canonical select == kernel Choice " #
                "(docs/VERSE-RULES.md § 0 row table); distinct op kept so the " #
                "source-language `select` statement has a lowering target";
  let arguments = (ins TimbdaValueType:$lhs, TimbdaValueType:$rhs);
  let results = (outs TimbdaValueType:$result);
  let assemblyFormat = "$lhs `,` $rhs attr-dict";
}

def TimbdaMatchOp : TimbdaOp<"match", [TimbdaValueResultTrait]> {
  let summary = "region-based match (PLAN § 2 TableGen section: .match " #
                "(region-based)): region 0 holds the pattern expression over " #
                "one pattern-carrier block argument; the 18 Fig. 14/15 matching " #
                "rows (audit records Match_*) become lowering patterns at M3 - " #
                "Tier 2, DEV-1";
  let arguments = (ins TimbdaValueType:$scrutinee);
  let regions = (region AnyRegion:$pat);
  let results = (outs TimbdaValueType:$result);
  let assemblyFormat = "$scrutinee `,` $pat attr-dict";
}

def TimbdaTypeofOp : TimbdaOp<"typeof", [TimbdaValueResultTrait]> {
  let summary = "partial type projection (the runtime reading of `of`: PLAN § 4.1 " #
                "Core-Verse table; audit row `typeof` is Tier 3 with no kernel " #
                "constructor until M3 - DEV-2; MLIR verifier rejection <-> Gallina " #
                "typing, T10); value-carrying with a custom verifier rejection " #
                "standing in for \"denotation is empty\"";
  let arguments = (ins TimbdaValueType:$operand);
  let results = (outs TimbdaValueType:$result);
  let assemblyFormat = "$operand attr-dict";
}

// ---------- terminator ----------

def TimbdaYieldOp : TimbdaOp<"yield", [Pure, Terminator]> {
  let summary = "expression region terminator (single value)";
  let arguments = (ins TimbdaValueType:$value);
  let assemblyFormat = "$value attr-dict";
}

// ---------- record transcription (72 rows) lives in its own pure file ----------

include "TimbdaRules.td"

#endif // TIMBDA_TD
