// probe5/g3 - the two catch-all prim rows (RewPrim / RewPrimFail) in the
// final design: bind the attribute and operand range with plain symbols, the
// whole op with `:$p`, guard and build through whole-op entities (helper
// recovers the enum and operands from the op it recovers via getDefiningOp).
include "dialect/Timbda.td"
include "mlir/IR/PatternBase.td"

def PrimResGuard : Constraint<CPred<"::timbda::primTotalIsResult($0)">,
                           "prim_total evaluates to PRes for these operands">;
def PrimFailGuard : Constraint<CPred<"::timbda::primTotalIsFail($0)">,
                            "prim_total evaluates to PFail for these operands">;

def PrimRhsN : NativeCodeCall<"::timbda::primTotalRhs($_builder, $0)">;

def RewPrimProbe : Pat<(TimbdaPrimOp:$p $pa, $va),
                       (PrimRhsN $p),
                       [(PrimResGuard $p)],
                       [],
                       (addBenefit 85)>;

def RewPrimFailProbe : Pat<(TimbdaPrimOp:$q $qb, $vq),
                           (TimbdaFailOp),
                           [(PrimFailGuard $q)],
                           [],
                           (addBenefit 84)>;
