// probe5/g1 - Fig. 9 unification-row shapes (RewEqK1/RewEqK2):
//   * multi-entity value guards via Pat `preds` list: `Constraint<CPred<...>>`
//     defs applied with entity symbol references;
//   * identity destination: `Pattern` with result list [(replaceWithValue $v)]
//     (Pat sugar cannot express it: a bare `$x` result is a parse error);
//   * (addBenefit 0) here doubles as the benefit-formula probe (expect 100).
include "dialect/Timbda.td"
include "mlir/IR/PatternBase.td"

def EqK2Guard : Constraint<CPred<"::timbda::litPairDistinct($0, $1)">,
                            "both operands are literals with different values">;

def RewEqK2Probe : Pat<(TimbdaUnifyOp $lhs, $rhs),
                       (TimbdaFailOp),
                       [(EqK2Guard $lhs, $rhs)],
                       [],
                       (addBenefit 0)>;

def EqK1Guard : Constraint<CPred<"::timbda::litPairEqual($0, $1)">,
                           "both literals with the same value">;

def RewEqK1Probe : Pattern<(TimbdaUnifyOp $lhs, $rhs),
                           [(replaceWithValue $lhs)],
                           [(EqK1Guard $lhs, $rhs)],
                           [],
                           (addBenefit 0)>;
