// probe5/h2 - op symbols (`OpName:$sym`): substitution shape when a whole-op
// symbol is (a) a constraint entity and (b) a result NativeCodeCall argument.
// This is the escape hatch that lets guards and RHS builders recover the root
// op from its first result Value.
include "dialect/Timbda.td"
include "mlir/IR/PatternBase.td"

def ByOpSymCheck : Constraint<CPred<"::timbda::checkByOp($0)">,
                            "constraint fed by a whole-op symbol">;
def RhsByOp : NativeCodeCall<"::timbda::rhsByOp($_builder, $0)">;
def H2Prim : Pat<(TimbdaPrimOp:$p $pa, $va),
                 (RhsByOp $p),
                 [(ByOpSymCheck $p)],
                 [],
                 (addBenefit 0)>;

def ByBindCheck : Constraint<CPred<"::timbda::checkBind($0)">,
                           "constraint fed by a bind whole-op symbol">;
def RhsByBind : NativeCodeCall<"::timbda::rhsByBind($_builder, $0)">;
def H2Bind : Pat<(TimbdaBindOp:$b $init),
                 (RhsByBind $b),
                 [(ByBindCheck $b)],
                 [],
                 (addBenefit 0)>;

// zero-operand op symbol binding (unit op as callee): op symbol with no dag args
def ByUnitCheck : Constraint<CPred<"::timbda::checkUnitOp($0)">,
                             "unit-op symbol">;
def H2Unit : Pat<(TimbdaAppOp (TimbdaUnitOp:$u), $arg),
                 (TimbdaFailOp),
                 [(ByUnitCheck $u)],
                 [],
                 (addBenefit 0)>;
