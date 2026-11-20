//===- probes/probe4.td - vintage DRR idiom probes (M1) -------*- tablegen -*-===//
// Probes the exact DRR shapes dialect/TimbdaPatterns.td will use, against the
// pinned vintage's mlir-tblgen (see probes/README.md).  Not part of the build.

include "dialect/Timbda.td"
include "mlir/IR/PatternBase.td"

// A. nested op matchers inside a `variadic` group (prim rows: literal operands)
def IntPairRhs : NativeCodeCall<"::timbda::identityValue(rewriter, $0)">;
def : Pat<(TimbdaPrimOp ConstantEnumCase<Timbda_PrimAttr, "add">,
           (variadic (TimbdaIntOp AnyIntegerAttr:$x), (TimbdaIntOp AnyIntegerAttr:$y))),
          (IntPairRhs $y)>;

// B. native matcher inside a variadic group (negative shape guards)
def NotIntMatch : NativeCodeCall<"::timbda::matchNotIntValue($_self, rewriter, $0)">;
def : Pat<(TimbdaPrimOp ConstantEnumCase<Timbda_PrimAttr, "isInt">,
           (variadic (NotIntMatch $v))),
          (TimbdaFailOp)>;

// C. bare captured symbol as the whole destination (identity rewrite)
def : Pat<(TimbdaUnifyOp $lhs, $rhs), $lhs>;

// D. native matcher on a fixed operand position (root-op inspection via parent)
def HnfMatch : NativeCodeCall<"::timbda::matchHnfValue($_self, rewriter, $0)">;
def BindRhs : NativeCodeCall<"::timbda::seqRewrite(rewriter, $0)">;
def : Pat<(TimbdaBindOp (HnfMatch $init)), (BindRhs $init)>;

// E. constant enum *built* in a destination (RewIterAll's prim splice)
def : Pat<(TimbdaUnifyOp $lhs, $rhs),
          (TimbdaPrimOp ConstantEnumCase<Timbda_PrimAttr, "cons">, (variadic $lhs, $rhs))>;

// F. region-op destination creation (must FAIL: vintage DRR cannot build regions)
def : Pat<(TimbdaUnifyOp $lhs, $rhs), (TimbdaBindOp $lhs)>;
