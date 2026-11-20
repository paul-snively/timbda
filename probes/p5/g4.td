// probe5/g4 - named prim rows: enum matcher group + variadic group with nested
// op matchers; int-pair guards as constraints over two operand symbols; cons
// group mixing a bare operand with a nested tup op matcher; identity
// destinations via replaceWithValue (RewGt1/RewIsInt1 read: the row's RHS is
// the operand value itself).
include "dialect/Timbda.td"
include "mlir/IR/PatternBase.td"

// add[ki1, ki2] exactly two int operands.
def AddRhs : NativeCodeCall<"::timbda::addRhs($_builder, $0, $1)">;
def RewAddProbe : Pat<(TimbdaPrimOp ConstantEnumCase<Timbda_PrimAttr, "add">,
                      (variadic (TimbdaIntOp $x), (TimbdaIntOp $y))),
                    (AddRhs $x, $y),
                    [],
                    [],
                    (addBenefit 85)>;

// gt[x, y] (RewGt1 / RewGt2 pair: same shape, complementary constraints,
// the first row's destination is the first operand itself).
def GtFirstCheck : Constraint<CPred<"::timbda::intsAndSecondLessFirst($0, $1)">,
                             "both int literals with Z.ltb b a">;
// complement constraint (used by the RewGt2-style row below).

def RewGt1Probe : Pattern<(TimbdaPrimOp ConstantEnumCase<Timbda_PrimAttr, "gt">,
                          (variadic (TimbdaIntOp $x), (TimbdaIntOp $y))),
                          [(replaceWithValue $x)],
                          [(GtFirstCheck $x, $y)],
                          [],
                          (addBenefit 85)>;

def GtSecondCheck : Constraint<CPred<"::timbda::intsAndSecondNotLessFirst($0, $1)">,
                            "Z.ltb b a is false">;

def RewGt2Probe : Pat<(TimbdaPrimOp ConstantEnumCase<Timbda_PrimAttr, "gt">,
                      (variadic (TimbdaIntOp $x), (TimbdaIntOp $y))),
                      (TimbdaFailOp),
                      [(GtSecondCheck $x, $y)],
                      [],
                      (addBenefit 84)>;

// isInt[ki] exactly one int operand: identity destination.
def RewIsInt1Probe : Pattern<(TimbdaPrimOp ConstantEnumCase<Timbda_PrimAttr, "isInt">,
                             (variadic (TimbdaIntOp $i))),
                             [(replaceWithValue $i)],
                             [],
                             [],
                             (addBenefit 85)>;

// isInt[v] on a non-int *value* operand: value-shape is runtime, so the group
// binds a bare symbol and the constraint reads its defining op.
def NotIntValue : Constraint<CPred<"::timbda::isValueNotInt($0)">,
                             "operand is a value-shaped op but not an int literal">;
def RewIsInt2Probe : Pat<(TimbdaPrimOp ConstantEnumCase<Timbda_PrimAttr, "isInt">,
                         (variadic $v)),
                         (TimbdaFailOp),
                         [(NotIntValue $v)],
                         [],
                         (addBenefit 85)>;

// cons[v0, t]: bare operand + nested tup op matcher.
def ConsGuard : Constraint<CPred<"::timbda::consOperandsOk($0, $1)">,
                        "first operand is a value, tup members are values">;
def ConsRhs : NativeCodeCall<"::timbda::consRhs($_builder, $0, $1)">;
def RewConsProbe : Pat<(TimbdaPrimOp ConstantEnumCase<Timbda_PrimAttr, "cons">,
                       (variadic $v0, (TimbdaTupOp $t))),
                       (ConsRhs $v0, $t),
                       [(ConsGuard $v0, $t)],
                       [],
                       (addBenefit 85)>;
