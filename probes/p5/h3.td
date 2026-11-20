// probe5/h3 - a bare symbol bound to a `variadic` ODS argument: what does
// tblgen substitute for it inside a CPred and inside a result NativeCodeCall?
// (`vals` operand_range, `(*vals.begin())`, or an error?)
include "dialect/Timbda.td"
include "mlir/IR/PatternBase.td"

def ByRangeCheck : Constraint<CPred<"::timbda::checkRange($0)">,
                            "constraint fed by a variadic-range symbol">;
def RhsByRange : NativeCodeCall<"::timbda::rhsByRange($_builder, $0)">;
def H3Range : Pat<(TimbdaPrimOp $pa, $va),
                  (RhsByRange $va),
                  [(ByRangeCheck $va)],
                  [],
                  (addBenefit 0)>;

// mixed: whole-op symbol + range symbol in one constraint
def ByRangeOpCheck : Constraint<CPred<"::timbda::checkRange2($0, $1)">,
                              "whole-op + range">;
def H3RangeOp : Pat<(TimbdaPrimOp:$p2 $pb, $vb),
                    (TimbdaUnitOp),
                    [(ByRangeOpCheck $p2, $vb)],
                    [],
                    (addBenefit 0)>;
