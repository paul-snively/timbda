//===- TimbdaCanonicalization.h - Verse kernel rules (Figs. 9-12) ---------===//
//
// Helpers backing the 23 generated DRR rewriters emitted from
// dialect/TimbdaPatterns.td into dialect/TimbdaCanonicalization.cpp.inc (kernel
// rows: coq/Rewriting.v Figs. 9-12).  Every guard mirrors exactly one kernel
// side condition and is called from a generated pattern's match phase
// (`Constraint<CPred<...>>`; a result-side NativeCodeCall may not veto a
// match, so guards never live in destinations).  Every RHS helper mirrors one
// kernel right-hand side and is invoked through a `NativeCodeCall`
// destination.  Names and argument shapes match the generated call sites one
// to one (tools/rules-audit.py checks the ctor/record/helper bijection).
//
// Root-anchor convention: each RHS helper receives the root op's result Value
// (whole-op symbol `$p`/`$u`/`$b` in the patterns file), from which it
// recovers the op and its position - cloned/rebuilt subtrees are always
// inserted immediately before the root op, the position every operand of the
// root dominates.  Region-shaped RHS shapes (Seq arms, Block binders, EqTup1
// chains) are rebuilt there because stock DRR cannot emit ops with regions
// (probe F) and stock DRR result-side calls cannot veto a match.
//
// Region convention (docs/DESIGN-NOTES DEV-16/DEV-18): a region op's value is
// the value channel of its single block's `timbda.yield` (DEV-16); the
// dialect's arm binder (the kernel Seq binder, DEV-16) is a block argument
// that is never referenced; clones only move subtrees into regions, and every
// region edit is rewriter-recorded.
//
//===----------------------------------------------------------------------===//

#ifndef DIALECT_TIMBDACANONICALIZATION_H
#define DIALECT_TIMBDACANONICALIZATION_H

#include "mlir/IR/Operation.h"

#include "mlir/IR/PatternMatch.h"

namespace mlir {
class PatternRewriter;
} // namespace mlir

namespace timbda {

//===----------------------------------------------------------------------===//
// Fig. 9 guards (Rewriting.v 259-280; kernel `is_lit_val`, `is_val`,
// `root_of`, `root_mismatch`, `no_eq_rule_pair`).
//===----------------------------------------------------------------------===//

// `is_val` (Syntax.v 53-62): unit/bool/int/lambda/delay value ops, value
// tuples (all members Vals), variable channels and DEV-6 global channels are
// Vals; expression-shaped SSA (bind/unify/app/block/...) is not.
bool isValueOp(::mlir::Value v);

// `is_lit_val` equality over the literal ladder (Rewriting.v 177-183):
// EqK1 checks equality (`same = true`), EqK2 inequality.
bool isLiteralPair(::mlir::Value lhs, ::mlir::Value rhs, bool same);

// EqTup1/EqTup2's `length vs = length ws` premise (Rewriting.v 341-349):
// both operands define value tuples, equal (EqTup1) or different (EqTup2)
// member counts.
bool isTupPairLength(::mlir::Value lhs, ::mlir::Value rhs, bool same);

// EqFail (Rewriting.v 160-175): `root_mismatch v1 v2 = true`, with the
// `no_eq_rule_pair` exclusions - same-var pairs and lambda-vs-lambda pairs
// have no unification row and stay stuck.
bool rootMismatchPair(::mlir::Value lhs, ::mlir::Value rhs);

//===----------------------------------------------------------------------===//
// Fig. 10 guards (Rewriting.v 290-315).
//===----------------------------------------------------------------------===//

// Gt1 (Rewriting.v 293-296): the first operand is an int literal and
// `Z.ltb b a = true` - `b` is the statically captured second-operand attr,
// `a` is read from the first operand's own IntOp.
bool intPairResidueFirst(::mlir::Value first, ::mlir::IntegerAttr second);

// Gt2 (Rewriting.v 297-301): `Z.ltb b a = false` over two int literal attrs.
bool intsSecondNotLessFirst(::mlir::IntegerAttr first,
                            ::mlir::IntegerAttr second);

// IsInt1 (Rewriting.v 303): operand is an int literal.  IsInt2 (305-307):
// operand is a Val that is not an int literal (arity 1 pinned statically).
bool isIntValueOperand(::mlir::Value v);
bool isNonIntValueArityOne(::mlir::Value v);

// RewPrim / RewPrimFail (Rewriting.v 317-321): the kernel `prim_total`
// (Syntax.v 344-385) evaluated over the whole op (recovered from the whole-op
// result Value).  PRes fires RewPrim, PFail fires RewPrimFail, PStuck fires
// neither and the application stays stuck (Fig. 10 line 463).
bool primTotalIsResult(::mlir::Value primResult);
bool primTotalIsFail(::mlir::Value primValue);

//===----------------------------------------------------------------------===//
// Fig. 11 guards (Rewriting.v 334-351).
//===----------------------------------------------------------------------===//

// RewBetaL: callee defines a lambda value op (kernel `VLam t b`).
bool calleeIsLambda(::mlir::Value callee);

// RewBetaT: callee is a value tuple with >= 1 member (`vs <> nil`).
bool calleeIsNonEmptyValueTuple(::mlir::Value callee);

// RewBetaT0 (Rewriting.v 346-351): `vs = nil`.  The whole-op symbol passes
// the (empty) tup's result Value, never a dereferenced empty range.
bool isEmptyValueTupleOp(::mlir::Value callee);

//===----------------------------------------------------------------------===//
// Fig. 12 guards (Rewriting.v 352-370).  Kernel `Seq e1 e2` is a bind whose
// arm binder is unused (DEV-16).
//===----------------------------------------------------------------------===//

// RewSeq (line 352, `forall v : Val`): bind whose init is a Val and whose arm
// ignores its binder argument.
bool unusedBindArm(::mlir::Value bindResult);

// Norm1/Norm3 arms (lines 355-361): arm binder unused, init any Expr.
bool unusedBindArmOfAnyInit(::mlir::Value bindResult);

// RewNorm5 (line 369): a bind whose init operand is itself a binder-free bind.
bool bindArmOfBindArm(::mlir::Value bindResult);

//===----------------------------------------------------------------------===//
// RHS builders (NativeCodeCall destinations; generated .inc call sites).
//===----------------------------------------------------------------------===//

// Fig. 9, RewEqTup1 (Rewriting.v 341-345): `eq_seq vs ws (Ret (VTup vs))` -
// member unifications `v_i = w_i` as a Seq chain; the flattened arm
// (Rewriting's `;` is the dialect region statement sequence, DEV-16) yields
// the lhs tuple value.
::mlir::Value eqTup1Rhs(::mlir::PatternRewriter &rewriter, ::mlir::Value root,
                        ::mlir::Value lhs, ::mlir::Value rhs);

// Fig. 10, RewPrim (Rewriting.v 317): `prim_total p vs = PRes v` materialized
// as the PRes value's value-op spelling.
::mlir::Value primTotalRhs(::mlir::PatternRewriter &rewriter,
                           ::mlir::Value primResult);

// Fig. 10, RewAdd (Rewriting.v 290-292): `ki1 + ki2` - `first` is the first
// operand's int-literal Value (guard-pinned), `second` the static IntOp attr.
::mlir::Value addRhs(::mlir::PatternRewriter &rewriter, ::mlir::Value prim,
                     ::mlir::Value first, ::mlir::IntegerAttr second);

// Fig. 10, RewDotDot (Rewriting.v 311-314): `map VInt (seq_z lo hi)`,
// inclusive (`Z.leb`); `lo > hi` yields the empty tuple.
::mlir::Value dotdotRhs(::mlir::PatternRewriter &rewriter, ::mlir::Value prim,
                        ::mlir::Value lo, ::mlir::IntegerAttr hi);

// Fig. 10, RewCons (Rewriting.v 308-310): `cons[v0, <v1..vn>]` yields
// `⟨v0 :: v..⟩` (t = the static nested tup operand's member range).
::mlir::Value consRhs(::mlir::PatternRewriter &rewriter, ::mlir::Value prim,
                      ::mlir::Value head, ::mlir::OperandRange tail);

// Fig. 12, RewSeq (line 352): `v ; e -> e` - splice the arm's body ops into
// the parent block before the bind and hand back the arm's value channel.
::mlir::Value seqRhs(::mlir::PatternRewriter &rewriter, ::mlir::Value bindResult);

// Fig. 12, Norm1-5 (Rewriting.v 355-370).  Rebuilds land immediately before
// the matched root op (dominated by every root operand); arm regions are the
// flattened statement sequence for the RHS arm expression.
::mlir::Value norm1Rhs(::mlir::PatternRewriter &rewriter, ::mlir::Value root,
                       ::mlir::Value lhs, ::mlir::Value rhs);
::mlir::Value norm2Rhs(::mlir::PatternRewriter &rewriter, ::mlir::Value root,
                       ::mlir::Value v, ::mlir::Value e1, ::mlir::Value e2);
::mlir::Value norm3Rhs(::mlir::PatternRewriter &rewriter, ::mlir::Value root,
                       ::mlir::Value lhs, ::mlir::Value rhs);
::mlir::Value norm4Rhs(::mlir::PatternRewriter &rewriter, ::mlir::Value root,
                       ::mlir::Value v, ::mlir::Value e1, ::mlir::Value e2);
::mlir::Value norm5Rhs(::mlir::PatternRewriter &rewriter, ::mlir::Value bindResult);

// Fig. 11 (Rewriting.v 334-345): `App (λx.b) e -> block{∃x{}. x = e;; b}` and
// `⟨v0..vn⟩[e] -> block{∃x{}. x = e;; choice (block{}. x=0;;v0) ...}` - the
// `beta_t_cands`/`choice_list` mirrors (Rewriting.v 111-137).  The outer
// block's declared slot is its region's block argument `x`; candidate blocks
// are `Block nil` bodies.
::mlir::Value betaLRhs(::mlir::PatternRewriter &rewriter, ::mlir::Value root,
                       ::mlir::Value callee, ::mlir::Value arg);
::mlir::Value betaTRhs(::mlir::PatternRewriter &rewriter, ::mlir::Value root,
                       ::mlir::Value callee, ::mlir::Value arg);

// Register the 23 generated DRR rewriters (kernel rows Figs. 9-12) into
// `patterns`.
void populateTimbdaCanonicalization(::mlir::RewritePatternSet &patterns);

} // namespace timbda

#endif // DIALECT_TIMBDACANONICALIZATION_H
