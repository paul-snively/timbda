// probe5/g6 - normalization rows: nested op matchers at operand slots
// (RewNorm2/3/4 shapes), a native matcher that checks "the operand's defining
// op is a bind whose body ignores its binder argument" and captures that
// bind's init (RewNorm1/3/5 guards), and root-op symbols on a nested node.
include "dialect/Timbda.td"
include "mlir/IR/PatternBase.td"

def ValueLike : Constraint<CPred<"::timbda::isValueOp($0)">,
                           "operand is a unit/bool/int/tup/lambda/delay value">;

// Norm2 `v = (e1 = e2)`: static nested unify at the rhs slot.
def Norm2Rhs : NativeCodeCall<"::timbda::norm2Rhs($_builder, $0, $1, $2)">;
def RewNorm2Probe : Pat<(TimbdaUnifyOp $v, (TimbdaUnifyOp $e1, $e2)),
                        (Norm2Rhs $v, $e1, $e2),
                        [(ValueLike $v)],
                        [],
                        (addBenefit 97)>;

// Norm4 `(v = e1) = e2`: nested unify at the lhs slot, inner lhs value-guarded.
def Norm4Rhs : NativeCodeCall<"::timbda::norm4Rhs($_builder, $0, $1, $2)">;
def RewNorm4Probe : Pat<(TimbdaUnifyOp (TimbdaUnifyOp $v, $e1), $e2),
                        (Norm4Rhs $v, $e1, $e2),
                        [(ValueLike $v)],
                        [],
                        (addBenefit 95)>;

// Native operand-slot matcher: $self is the operand's defining op; the helper
// checks BindOp + unused binder argument and writes out the bind's init.
def UnusedBindMatch : NativeCodeCall<"::timbda::matchUnusedBind($_self, $0)">;

// Norm3 `(e1 ; e2) = e3` (the lhs slot matched through the native matcher).
def Norm3Rhs : NativeCodeCall<"::timbda::norm3Rhs($_builder, $0, $1, $2)">;
def RewNorm3Probe : Pat<(TimbdaUnifyOp (UnusedBindMatch $e1), $e3),
                        (Norm3Rhs $e1, $e3),   // $e2 recovered natively in the helper
                        [],
                        [],
                        (addBenefit 96)>;

// Norm1 `v = (e1 ; e2)`.
def Norm1Rhs : NativeCodeCall<"::timbda::norm1Rhs($_builder, $0, $1)">;
def RewNorm1Probe : Pat<(TimbdaUnifyOp $v, (UnusedBindMatch $e1)),
                        (Norm1Rhs $v, $e1),
                        [(ValueLike $v)],
                        [],
                        (addBenefit 98)>;

// Norm5 `(e1 ; e2) ; e3`: root bind + native matcher at *its* init slot -
// $self = defining op of the init operand, so the inner bind check must use
// the static nested-op form instead; probe which of the two works.
def Norm5Rhs : NativeCodeCall<"::timbda::norm5Rhs($_builder, $0, $1, $2)">;
def RewNorm5Probe : Pat<(TimbdaBindOp (TimbdaBindOp:$ib $e1)),
                        (Norm5Rhs $e1),   // region reads done in the helper
                        [],
                        [],
                        (addBenefit 94)>;
