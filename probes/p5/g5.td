// probe5/g5 - beta rows: operand-symbol guards on the callee, a static nested
// zero-argument tup matcher (RewBetaT0) guarded through its whole-op symbol,
// and two-argument NativeCodeCall destinations.
include "dialect/Timbda.td"
include "mlir/IR/PatternBase.td"

def CalleeIsLambda : Constraint<CPred<"::timbda::calleeIsLambda($0)">,
                               "callee operand's defining op is a lambda value op">;
def CalleeIsNonEmptyValueTuple : Constraint<CPred<"::timbda::calleeIsNonEmptyValueTuple($0)">,
                                           "callee is a tup op with >= 1 member">;

def BetaLRhs : NativeCodeCall<"::timbda::betaLRhs($_builder, $0, $1)">;
def BetaTRhs : NativeCodeCall<"::timbda::betaTRhs($_builder, $0, $1)">;

def RewBetaLProbe : Pat<(TimbdaAppOp $callee, $arg),
                        (BetaLRhs $callee, $arg),
                        [(CalleeIsLambda $callee)],
                        [],
                        (addBenefit 88)>;

def RewBetaTProbe : Pat<(TimbdaAppOp $callee2, $arg2),
                        (BetaTRhs $callee2, $arg2),
                        [(CalleeIsNonEmptyValueTuple $callee2)],
                        [],
                        (addBenefit 87)>;

// RewBetaT0: static nested zero-member tuple; the whole-op symbol carries the
// "must be exactly this empty tup op" question to the helper, because a
// variadic binding would be dereferenced (`(*x.begin())`) in a CPred.
def EmptyTupCheck : Constraint<CPred<"::timbda::isEmptyTupOp($0)">,
                               "callee is a tup op with no members">;
def RewBetaT0Probe : Pat<(TimbdaAppOp (TimbdaTupOp:$t $ms), $e),
                         (TimbdaFailOp),
                         [(EmptyTupCheck $t)],
                         [],
                         (addBenefit 86)>;
