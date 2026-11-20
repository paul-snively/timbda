//===- TimbdaPatterns.td ----------------------------------------*- tablegen-*-===//
//
// The 23 rule records in dialect/TimbdaRules.td whose `pattern` is "drr" get one
// stock-DRR rewriter each, named exactly after the coq/Rewriting.v constructor
// the record quotes (tools/rules-audit.py checks the name bijection).
//
// Stock-DRR encoding (vintage `mlir-tblgen -gen-rewriters`; the semantics of
// every construct used here was pinned by probes/p4/ and probes/p5/ before this
// file was written):
//   * Side conditions live on the MATCH side as `Constraint<CPred<...>>` defs
//     applied in `Pat`'s pred list over operand symbols (`(*x.begin())`),
//     whole-op symbols (`(*x.getODSResults(0).begin())` - the helper recovers
//     the op via getDefiningOp), variadic-range symbols (the operand_range
//     itself) and enum-attr symbols (the typed PrimAttr).  Result-side
//     NativeCodeCall may NOT veto a match (RewriterGen.cpp emits its value
//     unchecked), so guards never live in destinations.
//   * Identity rows (RHS = an operand) use `Pattern<..., [(replaceWithValue $x)], ...>`;
//     `Pat` sugar cannot express it (a bare `$x` result is a parse error).
//   * Region-building rows (Seq, Norm1-5, BetaL, BetaT, EqTup1) have their RHS
//     materialised by a NativeCodeCall destination helper: stock DRR cannot
//     create region-ops (probe F: a destination op with regions fails to
//     compile), so the helper builds blocks/binds and splices regions.
//   * Rows whose guard is a runtime operand property (int literals, arity,
//     value-vs-variable shape) put it in the constraint too; enum cases are
//     matched statically (`ConstantEnumCase`, the same mnemonic the record's
//     `lhs` column quotes - probe g4).
//   * Benefit = 100 - rank (rank column = coq/Eval.v selected_rows priority);
//     `Pat`'s emitted benefit is (source-op count + addBenefit), so each delta
//     below is 100 - rank - opCount(row), verified against the generated
//     constructors by probes/sweep.sh.  The Prim-schema ties (RewAdd/Gt1/Gt2/
//     IsInt1/IsInt2/Cons/DotDot 85 vs RewPrim 85) are safe: the catchall guard
//     is `prim_total p vs = PRes v` itself, so whichever fires yields the same
//     result (and RewPrimFail at 84 is the unique PFail branch).
//
//===----------------------------------------------------------------------===*/

include "dialect/Timbda.td"
include "mlir/IR/PatternBase.td"

//===----------------------------------------------------------------------===//
// Fig. 9 (lines 432-437): unification - TimbdaUnifyOp root rows.
// Guards read both operands' defining ops (kernel `Ret v` side conditions).
//===----------------------------------------------------------------------===//

// EqK1: k = k -> k (k a unit/bool/int literal; tuples are EqTup1's row).
def LitPairEqual : Constraint<CPred<"::timbda::isLiteralPair($0, $1, true)">,
                              "both literals with the same value">;

// EqK2: k1 = k2 -> fail if k1 <> k2 (both literals, distinct).
def LitPairDistinct : Constraint<CPred<"::timbda::isLiteralPair($0, $1, false)">,
                                 "both literals with different values">;

// EqTup1: ⟨v..⟩ = ⟨w..⟩ -> v1=w1; .. ; vn=wn; ⟨v..⟩ (length vs = ws premise).
def TupPairSameLength : Constraint<CPred<"::timbda::isTupPairLength($0, $1, true)">,
                                   "tuple pair with equal member counts">;

// EqTup2: ⟨v..⟩ = ⟨w..⟩ -> fail if lengths differ.
def TupPairDiffLength : Constraint<CPred<"::timbda::isTupPairLength($0, $1, false)">,
                                   "tuple pair with unequal member counts">;

// EqFail: hnf1 = hnf2 -> fail on different root shapes.  The guard implements
// the root taxonomy (Rewriting.v lines 140-160): it refuses the no-rule pairs
// (bare-variable pair, lambda-vs-lambda), so those stays stuck - no rewriter.
def RootMismatchPair : Constraint<CPred<"::timbda::rootMismatchPair($0, $1)">,
                                  "value pair with different root kinds, no-rule pairs excluded">;

// The whole-op symbol $u gives every region-building helper its root anchor:
// the generated call site passes the root op's result Value, the helper
// recovers the op (getDefiningOp) and anchors all new ops immediately before
// it - values that dominate the root dominate an insertion at the root.
def EqTup1Rhs : NativeCodeCall<"::timbda::eqTup1Rhs($_builder, $0, $1, $2)">;

// (Benefit formula: emitted benefit = source-op count + addBenefit delta; the
// deltas below are 100 - rank - source-ops, checked against the generated ctors.)

def RewEqK1 : Pattern<(TimbdaUnifyOp $lhs, $rhs),
                      [(replaceWithValue $lhs)],
                      [(LitPairEqual $lhs, $rhs)],
                      [],
                      (addBenefit 92)>;

def RewEqK2 : Pat<(TimbdaUnifyOp $lhs, $rhs),
                  (TimbdaFailOp),
                  [(LitPairDistinct $lhs, $rhs)],
                  [],
                  (addBenefit 91)>;

def RewEqTup1 : Pat<(TimbdaUnifyOp:$u $lhs, $rhs),
                    (EqTup1Rhs $u, $lhs, $rhs),
                    [(TupPairSameLength $lhs, $rhs)],
                    [],
                    (addBenefit 90)>;

def RewEqTup2 : Pat<(TimbdaUnifyOp $lhs, $rhs),
                    (TimbdaFailOp),
                    [(TupPairDiffLength $lhs, $rhs)],
                    [],
                    (addBenefit 89)>;

def RewEqFail : Pat<(TimbdaUnifyOp $lhs, $rhs),
                    (TimbdaFailOp),
                    [(RootMismatchPair $lhs, $rhs)],
                    [],
                    (addBenefit 88)>;

//===----------------------------------------------------------------------===//
// Fig. 10 (lines 452-459): primitive operations - TimbdaPrimOp root rows.
// (ins PrimAttr:$op_name, variadic-operands:$args): every row binds the attr
// (statically by enum case, or by symbol for the schema rows) and the operand
// range, which the guards read as `args` (`(*o.begin())` for single slots).
//===----------------------------------------------------------------------===//

// Add: add[ki1, ki2] -> ki1 + ki2 (exact two int operands).  The helper needs
// a type/location exemplar, and a whole-op capture of a leaf IntOp is illegal
// (its single argument is the value attr), so the first operand is bound bare
// (pinned to an int literal by the guard) and the second stays a static IntOp
// attr capture; `:$p` gives the helper the prim root for the insertion anchor.
def SingleIntValueOperand : Constraint<CPred<"::timbda::isIntValueOperand($0)">,
                                       "operand defines an int literal">;

def AddRhs : NativeCodeCall<"::timbda::addRhs($_builder, $0, $1, $2)">;

def RewAdd : Pat<(TimbdaPrimOp:$p ConstantEnumCase<Timbda_PrimAttr, "add">,
                  (variadic $x, (TimbdaIntOp $y))),
                 (AddRhs $p, $x, $y),
                 [(SingleIntValueOperand $x)],
                 [],
                 (addBenefit 83)>;

// Gt1: gt[ki1, ki2] -> ki1 if Z.ltb b a.  The RHS is the first operand itself:
// a DRR identity rewrite can only splice a VALUE capture, and `(TimbdaIntOp $x)`
// captures the operand's IntegerAttr, so Gt1 binds the first operand bare and
// statically pins only the second as an IntOp; the helper recovers the first
// operand's IntOp attr itself.  Gt2 (complement -> fail) keeps both operands
// statically matched, since its RHS creates no values.
def GtFirstIsIntSecondLess : Constraint<CPred<"::timbda::intPairResidueFirst($0, $1)">,
                                        "first operand is an int literal; Z.ltb second first">;
def SecondNotLessFirst : Constraint<CPred<"::timbda::intsSecondNotLessFirst($0, $1)">,
                                    "int pair with Z.ltb b a = false">;

def RewGt1 : Pattern<(TimbdaPrimOp ConstantEnumCase<Timbda_PrimAttr, "gt">,
                     (variadic $x, (TimbdaIntOp $y))),
                     [(replaceWithValue $x)],
                     [(GtFirstIsIntSecondLess $x, $y)],
                     [],
                     (addBenefit 82)>;

def RewGt2 : Pat<(TimbdaPrimOp ConstantEnumCase<Timbda_PrimAttr, "gt">,
                 (variadic (TimbdaIntOp $x), (TimbdaIntOp $y))),
                 (TimbdaFailOp),
                 [(SecondNotLessFirst $x, $y)],
                 [],
                 (addBenefit 82)>;

// IsInt1: isInt[ki] -> ki (exactly one operand).  Its RHS is the operand itself,
// and an identity rewrite can only splice VALUES, so the single-operand binding
// is bare (the `variadic` group still pins arity 1 statically); the helper guard
// enforces that the operand's defining op is an int literal (the
// `SingleIntValueOperand` def above).
def RewIsInt1 : Pattern<(TimbdaPrimOp ConstantEnumCase<Timbda_PrimAttr, "isInt">,
                        (variadic $args)),
                        [(replaceWithValue $args)],
                        [(SingleIntValueOperand $args)],
                        benefitAdded = (addBenefit 83)>;

// IsInt2: isInt[v] -> fail if v is not an int literal (exactly one operand,
// non-int value shape - the guard checks arity via the operand_range).
def NonIntValueOperand : Constraint<CPred<"::timbda::isNonIntValueArityOne($0)">,
                                    "single operand defining a value op, not an int">;

def RewIsInt2 : Pat<(TimbdaPrimOp ConstantEnumCase<Timbda_PrimAttr, "isInt">,
                    (variadic $args)),
                    (TimbdaFailOp),
                    [(NonIntValueOperand $args)],
                    [],
                    (addBenefit 84)>;

// Cons: cons[v0, ⟨v..⟩] -> ⟨v0, v..⟩ (bare operand + static nested tup).
def ValueOpGuard : Constraint<CPred<"::timbda::isValueOp($0)">,
                                "operand defines a value-shaped op">;
def ConsRhs : NativeCodeCall<"::timbda::consRhs($_builder, $0, $1, $2)">;

def RewCons : Pat<(TimbdaPrimOp:$p ConstantEnumCase<Timbda_PrimAttr, "cons">,
                  (variadic $v0, (TimbdaTupOp $t))),
                  (ConsRhs $p, $v0, $t),
                  [(ValueOpGuard $v0)],
                  [],
                  (addBenefit 83)>;

// DotDot: dotdot[ki1, ki2] -> ki1 (ki1+1) .. ki2 (`map VInt (seq_z a b)`,
// inclusive per Syntax.v `Z.leb`; a > b yields the empty tuple).
def DotDotRhs : NativeCodeCall<"::timbda::dotdotRhs($_builder, $0, $1, $2)">;

def RewDotDot : Pat<(TimbdaPrimOp:$p ConstantEnumCase<Timbda_PrimAttr, "dotdot">,
                    (variadic $x, (TimbdaIntOp $y))),
                    (DotDotRhs $p, $x, $y),
                    [(SingleIntValueOperand $x)],
                    [],
                    (addBenefit 83)>;

// PrimSchema (RewPrim): op[gv ..] -> the `prim_total` table result.  Whole-op
// symbol $p gives the guard and the builder the enum + operands; the guard is
// PRes-only so PFail cases go to RewPrimFail and PStuck cases stay stuck.
def PrimTotalResGuard : Constraint<CPred<"::timbda::primTotalIsResult($0)">,
                                   "prim_total p vs = PRes v">;

def PrimRhs : NativeCodeCall<"::timbda::primTotalRhs($_builder, $0)">;

def RewPrim : Pat<(TimbdaPrimOp:$p $attr, $args),
                  (PrimRhs $p),
                  [(PrimTotalResGuard $p)],
                  [],
                  (addBenefit 84)>;

// PrimSchemaFail (RewPrimFail): prim_total p vs = PFail -> fail.
def PrimTotalFailGuard : Constraint<CPred<"::timbda::primTotalIsFail($0)">,
                                    "prim_total p vs = PFail">;

def RewPrimFail : Pat<(TimbdaPrimOp:$p $attr, $args),
                      (TimbdaFailOp),
                      [(PrimTotalFailGuard $p)],
                      [],
                      (addBenefit 83)>;

//===----------------------------------------------------------------------===//
// Fig. 11 (lines 468-469): beta reduction - TimbdaAppOp root rows.  Region
// construction (beta_l's block, beta_t's narrowing) is helper-built (probe F).
//===----------------------------------------------------------------------===//

def CalleeLambdaGuard : Constraint<CPred<"::timbda::calleeIsLambda($0)">,
                                   "callee operand defines a lambda value op">;
def CalleeNonEmptyTupGuard : Constraint<CPred<"::timbda::calleeIsNonEmptyValueTuple($0)">,
                                        "callee operand defines a tup op with >= 1 member">;
def CalleeEmptyTupGuard : Constraint<CPred<"::timbda::isEmptyValueTupleOp($0)">,
                                     "callee operand defines a tup op with no members">;

def BetaLRhs : NativeCodeCall<"::timbda::betaLRhs($_builder, $0, $1, $2)">;
def BetaTRhs : NativeCodeCall<"::timbda::betaTRhs($_builder, $0, $1, $2)">;

def RewBetaL : Pat<(TimbdaAppOp:$u $callee, $arg),
                   (BetaLRhs $u, $callee, $arg),
                   [(CalleeLambdaGuard $callee)],
                   [],
                   (addBenefit 87)>;

def RewBetaT : Pat<(TimbdaAppOp:$u $callee, $arg),
                   (BetaTRhs $u, $callee, $arg),
                   [(CalleeNonEmptyTupGuard $callee)],
                   [],
                   (addBenefit 86)>;

// BetaT0: ⟨⟩[e] -> fail.  The static nested tup matcher pins the shape; the
// whole-op symbol carries the empty-members check (a range binding would be
// deref'd to (*begin()) in a CPred - empty range would be UB).
def RewBetaT0 : Pat<(TimbdaAppOp (TimbdaTupOp:$t $members), $e),
                    (TimbdaFailOp),
                    [(CalleeEmptyTupGuard $t)],
                    [],
                    (addBenefit 84)>;

//===----------------------------------------------------------------------===//
// Fig. 12 (lines 486-491): sequencing and normalization - TimbdaBindOp /
// TimbdaUnifyOp root rows.  `Seq e1 e2` is the BindOp whose body region ignores
// its binder argument (dialect summary); the guards below encode that shape.
//===----------------------------------------------------------------------===//

// Seq: v ; e -> e (init operand defines a value op AND binder unused; the
// helper splices the binder-free body region - same guard as Norm3/Norm5 arms).
def UnusedBindArmGuard : Constraint<CPred<"::timbda::unusedBindArm($0)">,
                                    "bind arm: init operand is a value op, body ignores its binder arg">;
def UnusedBindValueArmGuard : Constraint<CPred<"::timbda::unusedBindArmOfAnyInit($0)">,
                                         "bind arm: body ignores its binder arg (init shape unconstrained)">;

def SeqRhs : NativeCodeCall<"::timbda::seqRhs($_builder, $0)">;

def RewSeq : Pat<(TimbdaBindOp:$b $init),
                 (SeqRhs $b),
                 [(UnusedBindArmGuard $b)],
                 [],
                 (addBenefit 98)>;

// Norm1: v = (e1 ; e2) -> e1 ; (v = e2).  lhs value-shape guard + rhs bind-arm
// guard (Norm1's kernel arm has `Ret v` on the lhs only).
def Norm1Rhs : NativeCodeCall<"::timbda::norm1Rhs($_builder, $0, $1, $2)">;

def RewNorm1 : Pat<(TimbdaUnifyOp:$u $lhs, $rhs),
                   (Norm1Rhs $u, $lhs, $rhs),
                   [(ValueOpGuard $lhs), (UnusedBindValueArmGuard $rhs)],
                   [],
                   (addBenefit 97)>;

// Norm2: v = (e1 = e2) -> (v = e1) ; (v = e2).  Static nested unify arm.
def Norm2Rhs : NativeCodeCall<"::timbda::norm2Rhs($_builder, $0, $1, $2, $3)">;

def RewNorm2 : Pat<(TimbdaUnifyOp:$u $lhs, (TimbdaUnifyOp $e1, $e2)),
                   (Norm2Rhs $u, $lhs, $e1, $e2),
                   [(ValueOpGuard $lhs)],
                   [],
                   (addBenefit 95)>;

// Norm3: (e1 ; e2) = e3 -> e1 ; (e2 = e3).  Lhs is a bind arm (any init).
def Norm3Rhs : NativeCodeCall<"::timbda::norm3Rhs($_builder, $0, $1, $2)">;

def RewNorm3 : Pat<(TimbdaUnifyOp:$u $lhs, $rhs),
                   (Norm3Rhs $u, $lhs, $rhs),
                   [(UnusedBindValueArmGuard $lhs)],
                   [],
                   (addBenefit 95)>;

// Norm4: (v = e1) = e2 -> (v = e1) ; (v = e2).  Static nested unify arm; the
// inner lhs carries the `Ret v` guard (the arm is Unify(Unify(Ret v, e1), e2)).
def Norm4Rhs : NativeCodeCall<"::timbda::norm4Rhs($_builder, $0, $1, $2, $3)">;

def RewNorm4 : Pat<(TimbdaUnifyOp:$u (TimbdaUnifyOp $v, $e1), $e2),
                   (Norm4Rhs $u, $v, $e1, $e2),
                   [(ValueOpGuard $v)],
                   [],
                   (addBenefit 93)>;

// Norm5: (e1 ; e2) ; e3 -> e1 ; (e2 ; e3).  Root bind arm whose init arm is
// itself a bind arm; the whole-op symbol reads both regions' binder usage.
def BindArmIsBindArmGuard : Constraint<CPred<"::timbda::bindArmOfBindArm($0)">,
                                       "bind arm whose init operand defines a bind arm">;

def Norm5Rhs : NativeCodeCall<"::timbda::norm5Rhs($_builder, $0)">;

def RewNorm5 : Pat<(TimbdaBindOp:$b $init),
                   (Norm5Rhs $b),
                   [(BindArmIsBindArmGuard $b)],
                   [],
                   (addBenefit 93)>;
