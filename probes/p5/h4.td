// probe5/h4 - a bare symbol bound to an *attribute* ODS argument inside a
// constraint entity (would let RewPrim guard read the enum directly).
include "dialect/Timbda.td"
include "mlir/IR/PatternBase.td"

def ByAttrCheck : Constraint<CPred<"::timbda::checkAttr($0)">,
                           "constraint fed by an attribute symbol">;
def H4Attr : Pat<(TimbdaPrimOp $pa, $va),
                 (TimbdaUnitOp),
                 [(ByAttrCheck $pa)],
                 [],
                 (addBenefit 0)>;
