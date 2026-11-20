// probe5/g2 - region-op guards (RewSeq/RewNorm1/RewNorm3/RewNorm5 need "the
// bind body ignores its binder argument", which no operand matcher can see):
//   (A) bind the root op with `:$b` and feed the op symbol to a constraint;
//   (B) zero-entity constraint referencing `$_self` - inspect what tblgen
//       substitutes for it;
//   (C) native matcher at the operand slot (its `$_self` is the operand's
//       defining op) producing the operand as a capture.
include "dialect/Timbda.td"
include "mlir/IR/PatternBase.td"

// (A)
def BodyUnusedSym : Constraint<CPred<"::timbda::bindBodyIgnoresBinder($0)">,
                               "bind body region never references its argument">;

def RewSeqSymProbe : Pat<(TimbdaBindOp:$b $init),
                         (TimbdaUnitOp),
                         [(BodyUnusedSym $b)],
                         [],
                         (addBenefit 99)>;

// (B)
def BodyUnusedSelf : Constraint<CPred<"::timbda::bindBodyIgnoresBinderSelf($_self)">,
                                "same check, $_self form">;

def RewSeqSelfProbe : Pat<(TimbdaBindOp $init),
                          (TimbdaUnitOp),
                          [(BodyUnusedSelf)],
                          [],
                          (addBenefit 98)>;

// (C)
def InitValueCheck : NativeCodeCall<"::timbda::matchValueInit($_self, $0)">;

def RewSeqNativeProbe : Pat<(TimbdaBindOp (InitValueCheck $init)),
                            (TimbdaUnitOp),
                            [],
                            [],
                            (addBenefit 97)>;
