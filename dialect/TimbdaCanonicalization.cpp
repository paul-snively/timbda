//===- TimbdaCanonicalization.cpp - Verse kernel rules Figs. 9-12 ---------===//
//
// Backing helpers for the 23 generated DRR rewriters emitted from
// dialect/TimbdaPatterns.td into dialect/TimbdaCanonicalization.cpp.inc (kernel
// rows: coq/Rewriting.v Figs. 9-12).  Guard helpers mirror kernel side
// conditions and run in the generated match phase (CPred call sites); RHS
// helpers mirror kernel right-hand sides and run through the generated
// NativeCodeCall destinations.  Names and argument shapes match the generated
// call sites one to one (tools/rules-audit.py checks the ctor/record/helper
// name bijection).
//
// Root anchoring: every whole-op pattern symbol (`$u`, `$p`, `$b`) delivers the
// root op's result Value to its helper (`(*sym.getODSResults(0).begin())` at
// the generated call site); the helper recovers the root op from that Value and
// inserts every rebuilt subtree immediately before the root - the position each
// of the root's operands dominates.  Cloned arm bodies land there with their
// outer-scope references mapping through unchanged (DEV-6: the kernel's
// `liftV`/`liftE` capture shifting is exactly this pass-through).
//
// Region discipline (docs/DESIGN-NOTES.md DEV-16/DEV-18, dialect/Timbda.td op
// summaries): a region op's value is its single block's `timbda.yield` operand;
// a `timbda.bind` region is one block with one argument - the kernel `Seq`
// binder - referenced only by source-level binds, never by a kernel `Seq` arm.
// Kernel `Seq e1 e2` is the bind whose init operand carries `e1`'s value
// channel and whose arm carries `e2`'s statement sequence, ending in `e2`'s
// value channel (the kernel's `;` is region statement sequencing).  Every edit
// goes through PatternRewriter (create / clone / createBlock / modifyOpInPlace);
// `Region::cloneInto` is never used.  Cloned-from ops are never erased out of a
// live region (eraseOp's use_empty precondition): the generated `replaceOp`
// erases only the matched root, and the fixpoint driver drops use-less
// leftovers (measured by the golden runs in M4).
//
//===----------------------------------------------------------------------===//

#include "dialect/TimbdaCanonicalization.h"

#include "dialect/TimbdaDialect.h"

#include <optional>

#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/IRMapping.h"
#include "mlir/IR/PatternMatch.h"

using namespace mlir;

// The dialect's op types (`TimbdaBindOp`, `Prim`, ...) are used unqualified
// throughout, as in MLIR's own dialect implementation files.
using namespace timbda;

namespace {

//===----------------------------------------------------------------------===//
// Kernel mirrors: Val / literal readings.  Syntax.v `Val` (53-62), Rewriting.v
// `is_lit_val` (181-183), `is_int_val` (177), `root_of` (Syntax.v 299-308),
// `root_mismatch` + `no_eq_rule_pair` (Rewriting.v 164-175).
//===----------------------------------------------------------------------===//

// A Val-shaped SSA value: a Val-constructor defining op (unit/bool/int/lambda/
// delay, or a tup whose members are themselves Vals - the kernel VTup-vs-TupE
// split), a glob channel (DEV-6: the kernel `Glob` is an Expr whose dialect
// spelling is the definition's value channel), or a block argument (VVar is a
// Val in the kernel ladder).  Expression-shaped SSA (bind/app/unify/or/block/
// ...) is not a Val: the kernel's `forall v : Val` rows never read it.
bool isValOperand(Value v) {
  Operation *op = v.getDefiningOp();
  if (!op)
    return isa<BlockArgument>(v); // VVar
  if (isa<TimbdaGlobOp>(op))
    return true; // DEV-6 channel reading
  return isa<TimbdaUnitOp, TimbdaBoolOp, TimbdaIntOp, TimbdaLambdaOp,
             TimbdaDelayOp>(op) ||
         (isa<TimbdaTupOp>(op) &&
          llvm::all_of(op->getOperands(), isValOperand));
}

// `is_lit_val` (Rewriting.v 181-183): unit/true/false/int literals only.
bool isLitOperand(Value v) {
  Operation *op = v.getDefiningOp();
  return op && isa<TimbdaUnitOp, TimbdaBoolOp, TimbdaIntOp>(op);
}

// `is_int_val` (Rewriting.v 177).
bool isIntOperand(Value v) {
  Operation *op = v.getDefiningOp();
  return op && isa<TimbdaIntOp>(op);
}

// A kernel `VTup vs`: a tup op whose members are all Vals (a TupE has no VTup
// reading and no root_of reading either).
TimbdaTupOp vtup(Value v) {
  auto tup = dyn_cast_or_null<TimbdaTupOp>(v.getDefiningOp());
  if (!tup || !llvm::all_of(tup.getOperands(), isValOperand))
    return nullptr;
  return tup;
}

// `root_of` (Syntax.v 299-308).  SSA values with no kernel root reading
// (expression-shaped SSA; prim applications are App-shaped in the dialect, so
// there is no VPrim-as-value spelling) get none: no `forall v : Val` row reads
// them, the root-pair guards refuse them, and the application stays stuck
// exactly like the kernel's no-rule cases.
std::optional<StringRef> rootOf(Value v) {
  if (isa<BlockArgument>(v))
    return std::optional<StringRef>("var"); // VVar -> RootOther
  Operation *op = v.getDefiningOp();
  if (!op)
    return std::nullopt;
  if (isa<TimbdaIntOp>(op))
    return std::optional<StringRef>("int"); // RInt
  if (isa<TimbdaBoolOp>(op))
    return std::optional<StringRef>("bool"); // RBool
  if (isa<TimbdaUnitOp>(op))
    return std::optional<StringRef>("unit"); // RUnit
  if (vtup(v))
    return std::optional<StringRef>("tup"); // RTup
  if (isa<TimbdaLambdaOp>(op))
    return std::optional<StringRef>("lam"); // RLam
  if (isa<TimbdaDelayOp>(op))
    return std::optional<StringRef>("delay"); // RDelay
  if (isa<TimbdaGlobOp>(op))
    return std::optional<StringRef>("var"); // DEV-6 channel reading
  return std::nullopt; // app/bind/unify/or/block/... have no root reading
}

// Equality over the kernel's literal Val ladder (EqK2's `v1 <> v2` is its
// negation: unit/bool/int carry no member structure at this level).
bool litEqual(Value lhs, Value rhs) {
  Operation *lo = lhs.getDefiningOp(), *ro = rhs.getDefiningOp();
  if (!lo || !ro || lo->getName() != ro->getName())
    return false;
  if (isa<TimbdaUnitOp>(lo))
    return true;
  if (auto lb = dyn_cast<TimbdaBoolOp>(lo))
    return lb.getValueAttr() == cast<TimbdaBoolOp>(ro).getValueAttr();
  auto li = dyn_cast<TimbdaIntOp>(lo);
  return li && li.getValueAttr() == cast<TimbdaIntOp>(ro).getValueAttr();
}

// int-literal operand reading (`ki`).
APInt intOf(Value v) { return cast<TimbdaIntOp>(v.getDefiningOp()).getValue(); }

// `VInt` readings of a matcher-pinned int-literal pair (`ki1`, `ki2`).
SmallVector<APInt, 4> intAttrsOf(OperandRange args) {
  SmallVector<APInt, 4> out;
  for (Value a : args)
    out.push_back(intOf(a));
  return out;
}

//===----------------------------------------------------------------------===//
// Z mirror (docs/DESIGN-NOTES.md DEV-20).  The kernel computes over Z; the
// dialect mirrors Z with APInt and computes at 128 bits (the golden corpus and
// probe kernels stay far inside Z's magnitudes; APInt's signed + - * trap
// loudly on overflow instead of silently wrapping).  Fresh int literals keep
// the width already carried by the row's int literals and grow to 64-bit, then
// to the 128-bit Z mirror: literals grow, they never truncate (DEV-20).
//
// `Z.div` floor-divides (`Z.div_mod` signs the remainder like the divisor);
// `sdiv` truncates toward zero, so `divZ` corrects the quotient.
//===----------------------------------------------------------------------===//

constexpr unsigned kZBits = 128;

APInt zOf(const APInt &a) { return a.zext(kZBits); }

APInt addZ(const APInt &a, const APInt &b) { return zOf(a) + zOf(b); }
APInt subZ(const APInt &a, const APInt &b) { return zOf(a) - zOf(b); }
APInt mulZ(const APInt &a, const APInt &b) { return zOf(a) * zOf(b); }

APInt divZ(const APInt &a, const APInt &b) {
  APInt za = zOf(a), zb = zOf(b);
  APInt q = za.sdiv(zb), r = za.srem(zb);
  if (!r.isZero() && (r.isNegative() != zb.isNegative()))
    q -= 1; // floor correction (`Z.div_mod` signs the remainder like the divisor)
  return q;
}

APInt negZ(const APInt &a) { return -zOf(a); }

// Coq's `Z.ltb`.
bool ltZ(const APInt &a, const APInt &b) { return zOf(a).slt(zOf(b)); }

// Widest of two (possibly absent) int-literal types.
static IntegerType wider(Type a, Type b) {
  IntegerType ia = dyn_cast_or_null<IntegerType>(a);
  IntegerType ib = dyn_cast_or_null<IntegerType>(b);
  if (!ia)
    return ib;
  if (!ib)
    return ia;
  return ia.getWidth() >= ib.getWidth() ? ia : ib;
}

IntegerType seedFromIntOps(ValueRange args) {
  IntegerType best;
  for (Value v : args)
    if (isIntOperand(v))
      best = wider(best,
                   cast<TimbdaIntOp>(v.getDefiningOp()).getValueAttr().getType());
  return best;
}

IntegerType seedFrom(IntegerAttr a, IntegerAttr b) {
  return wider(a.getType(), b ? b.getType() : IntegerType());
}

IntegerType seedFromBits(MLIRContext *ctx, unsigned wa, unsigned wb) {
  IntegerType a = IntegerType::get(ctx, wa);
  IntegerType b = IntegerType::get(ctx, wb);
  return wider(a, b);
}

// `VInt k` as its dialect spelling (kernel `Ret k`, Fig. 6 line 329): the seed
// width when the value fits signed there, else i64, else the 128-bit Z mirror.
Value makeIntValue(PatternRewriter &rewriter, Location loc, const APInt &k,
                   IntegerType seed) {
  IntegerType t = seed && k.isSignedIntN(seed.getWidth())
                      ? seed
                      : (k.isSignedIntN(64) ? rewriter.getI64Type()
                                            : rewriter.getIntegerType(kZBits));
  return rewriter.create<TimbdaIntOp>(loc, ValueType::get(rewriter.getContext()),
                                      IntegerAttr::get(t, k));
}

//===----------------------------------------------------------------------===//
// prim_total (Syntax.v 344-368) evaluated over the whole prim application
// (recovered from the whole-op result Value).  Res fires RewPrim (Fig. 10 line
// 463), Fail fires RewPrimFail (line 464); Stuck fires neither and the
// application stays stuck.  The op-shaped rows (add/gt1/gt2/isInt1/isInt2/cons/
// dotdot) read the same table through their matchers, so the catchall rows tie
// their benefits (patterns-file header).
//===----------------------------------------------------------------------===//

struct PrimRes {
  enum Status { Stuck, Fail, Res };
  enum Kind { None, Int, Bool, Unit, Tup, IntTup };

  Status status = Stuck;
  Kind kind = None;
  APInt i;                    // Res(Int)
  bool b = false;             // Res(Bool)
  SmallVector<Value, 4> vals; // Res(Tup)
  SmallVector<APInt, 8> ints; // Res(IntTup): `map VInt (seq_z lo hi)`
  IntegerType seed;           // int-literal width seed for fresh literals

  PrimRes() : i(1, 0) {}

  static PrimRes stuck() { return PrimRes(); }
  static PrimRes ofFail() {
    PrimRes r;
    r.status = Fail;
    return r;
  }
  static PrimRes ofInt(const APInt &v, IntegerType s = {}) {
    PrimRes r;
    r.status = Res;
    r.kind = Int;
    r.i = zOf(v);
    r.seed = s;
    return r;
  }
  static PrimRes ofBool(bool v) {
    PrimRes r;
    r.status = Res;
    r.kind = Bool;
    r.b = v;
    return r;
  }
  static PrimRes ofUnit() {
    PrimRes r;
    r.status = Res;
    r.kind = Unit;
    return r;
  }
  static PrimRes ofTup(ArrayRef<Value> vs) {
    PrimRes r;
    r.status = Res;
    r.kind = Tup;
    r.vals.append(vs.begin(), vs.end());
    return r;
  }
  static PrimRes ofIntTup(ArrayRef<APInt> ks, IntegerType s) {
    PrimRes r;
    r.status = Res;
    r.kind = IntTup;
    r.ints.append(ks.begin(), ks.end());
    r.seed = s;
    return r;
  }
};

// Materialise a PRes kernel value as its dialect value-op spelling (DEV-20:
// `Ret k` is the SSA value of the corresponding value-shaped op).
Value makePrimVal(PatternRewriter &rewriter, const PrimRes &r, Location loc) {
  switch (r.status) {
  case PrimRes::Res:
    switch (r.kind) {
    case PrimRes::Int:
      return makeIntValue(rewriter, loc, r.i, r.seed);
    case PrimRes::Bool:
      return rewriter.create<TimbdaBoolOp>(
          loc, ValueType::get(rewriter.getContext()),
          BoolAttr::get(rewriter.getContext(), r.b));
    case PrimRes::Unit:
      return rewriter.create<TimbdaUnitOp>(loc,
                                           ValueType::get(rewriter.getContext()));
    case PrimRes::Tup:
      return rewriter.create<TimbdaTupOp>(
          loc, ValueType::get(rewriter.getContext()), r.vals);
    case PrimRes::IntTup: {
      SmallVector<Value, 8> vs;
      for (const APInt &k : r.ints)
        vs.push_back(makeIntValue(rewriter, loc, k, r.seed));
      return rewriter.create<TimbdaTupOp>(
          loc, ValueType::get(rewriter.getContext()), vs);
    }
    }
    break;
  case PrimRes::Fail:
    return rewriter.create<TimbdaFailOp>(loc,
                                       ValueType::get(rewriter.getContext())); // PFail as the FailOp spelling
  case PrimRes::Stuck:
    break;
  }
  llvm_unreachable("no value spelling for a stuck prim_total row");
}

PrimRes primTotal(TimbdaPrimOp prim) {
  Prim p = prim.getPrim();
  OperandRange args = prim.getOperands();

  auto intPair = [&]() -> std::optional<SmallVector<APInt, 4>> {
    if (args.size() != 2 || !isIntOperand(args[0]) || !isIntOperand(args[1]))
      return std::nullopt; // the kernel row's `_` catchall
    return intAttrsOf(args);
  };

  switch (p) {
  case Prim::Add:
  case Prim::Sub:
  case Prim::Mul:
  case Prim::Div: {
    auto ab = intPair();
    if (!ab)
      return PrimRes::stuck(); // `PAdd/PSub/PMul, _` and `PDiv, _` catchalls
    const APInt a = (*ab)[0], b = (*ab)[1];
    if (p == Prim::Div && zOf(b).isZero())
      return PrimRes::stuck(); // `if Z.eqb b 0 then PStuck` (Syntax.v 349)
    APInt v = p == Prim::Add ? addZ(a, b)
                : p == Prim::Sub ? subZ(a, b)
                : p == Prim::Mul ? mulZ(a, b)
                                 : divZ(a, b);
    return PrimRes::ofInt(v, seedFromIntOps(args)); // Syntax.v 346-349
  }
  case Prim::Neg: {
    if (args.size() != 1 || !isIntOperand(args[0]))
      return PrimRes::stuck();
    return PrimRes::ofInt(negZ(intOf(args[0])), seedFromIntOps(args)); // 350
  }
  case Prim::Pls: {
    if (args.size() != 1)
      return PrimRes::stuck(); // no row for a different arity (368)
    if (!isIntOperand(args[0]))
      return PrimRes::ofFail(); // `PPls, [_] => PFail` (353)
    return PrimRes::ofInt(intOf(args[0]), seedFromIntOps(args)); // 352
  }
  case Prim::Gt:
  case Prim::Lt:
  case Prim::Geq:
  case Prim::Leq: {
    auto ab = intPair();
    if (!ab)
      return PrimRes::stuck(); // the comparison rows quantify int pairs only
    const APInt a = (*ab)[0], b = (*ab)[1];
    // Syntax.v 354-357: `PGt: Z.ltb b a`, `PLt: Z.ltb a b`, `PGEq: Z.ltb b a
    // || a = b`, `PLEq: Z.ltb a b || a = b`; on success the value is the
    // *first* operand's `VInt a`.
    bool success = p == Prim::Gt ? ltZ(b, a)
                    : p == Prim::Lt ? ltZ(a, b)
                    : p == Prim::Geq ? (!ltZ(b, a) || zOf(a).eq(zOf(b)))
                                     : (!ltZ(a, b) || zOf(a).eq(zOf(b)));
    if (!success)
      return PrimRes::ofFail();
    return PrimRes::ofInt(a, seedFromIntOps(args));
  }
  case Prim::Neq: {
    auto ab = intPair();
    if (!ab)
      return PrimRes::stuck();
    if (zOf((*ab)[0]).eq(zOf((*ab)[1])))
      return PrimRes::ofFail(); // `if Z.eqb a b then PFail` (358)
    return PrimRes::ofInt((*ab)[0], seedFromIntOps(args));
  }
  case Prim::IsInt: {
    if (args.size() != 1 || !isValOperand(args[0]))
      return PrimRes::stuck();
    if (isIntOperand(args[0]))
      return PrimRes::ofInt(intOf(args[0]), seedFromIntOps(args)); // 359, isInt1
    return PrimRes::ofFail(); // `PIsInt, [_] => PFail` (360, isInt2)
  }
  case Prim::IsBool: {
    if (args.size() != 1 || !isValOperand(args[0]))
      return PrimRes::stuck();
    if (auto def = dyn_cast_or_null<TimbdaBoolOp>(args[0].getDefiningOp()))
      return PrimRes::ofBool(def.getValue()); // `PIsBool, [VTrue] / [VFalse]`
    return PrimRes::ofFail(); // `PIsBool, [_] => PFail`
  }
  case Prim::IsUnit: {
    if (args.size() != 1 || !isValOperand(args[0]))
      return PrimRes::stuck();
    if (args[0].getDefiningOp() && isa<TimbdaUnitOp>(args[0].getDefiningOp()))
      return PrimRes::ofUnit();
    return PrimRes::ofFail(); // `PIsUnit, [_] => PFail`
  }
  case Prim::Cons: {
    if (args.size() != 2 || !isValOperand(args[0]) || !isValOperand(args[1]))
      return PrimRes::stuck(); // `PCons, _ => PStuck` (362)
    auto tail = vtup(args[1]);
    if (!tail)
      return PrimRes::stuck(); // the row is `[v0; VTup vs]` (361)
    SmallVector<Value, 8> vs;
    vs.push_back(args[0]);
    vs.append(tail.getOperands().begin(), tail.getOperands().end());
    return PrimRes::ofTup(vs); // `PRes (VTup (v0 :: vs))` (361)
  }
  case Prim::Cons2: {
    if (args.size() != 2 || !isValOperand(args[0]) || !isValOperand(args[1]))
      return PrimRes::stuck();
    SmallVector<Value, 2> vs(args.begin(), args.end());
    return PrimRes::ofTup(vs); // `PCons2, [v1; v2]` (363, Fig. 13 `for` helper)
  }
  case Prim::DotDot: {
    auto ab = intPair();
    if (!ab)
      return PrimRes::stuck(); // `PDotDot, _ => PStuck` (365)
    APInt lo = zOf((*ab)[0]), hi = zOf((*ab)[1]);
    SmallVector<APInt, 8> ks;
    APInt one(kZBits, 1);
    // `seq_z` (Syntax.v 329-335) counts while `Z.leb lo hi` holds, inclusive:
    // an empty VTup when lo > hi.
    for (APInt k = lo; !k.sgt(hi); k = k + one)
      ks.push_back(k);
    IntegerType seed = seedFromBits(prim.getContext(), (*ab)[0].getBitWidth(),
                                    (*ab)[1].getBitWidth());
    return PrimRes::ofIntTup(ks, seed); // `map VInt (seq_z lo hi)` (364)
  }
  case Prim::ArrLen: {
    if (args.size() != 1)
      return PrimRes::stuck();
    if (auto t = vtup(args[0]))
      return PrimRes::ofInt(APInt(kZBits, t.getOperands().size()),
                            seedFromIntOps(args)); // 364-365
    return PrimRes::stuck(); // `PArrLen, [_] => PStuck` (365)
  }
  default:
    return PrimRes::stuck(); // `| _ => PStuck` catchall (368)
  }
}

//===----------------------------------------------------------------------===//
// Region machinery (rewriter-recorded only - DEV-18).
//===----------------------------------------------------------------------===//

// The value a well-formed region block carries: its single terminator's yield
// operand (DEV-16).
Value yieldValue(Block &block) {
  return cast<TimbdaYieldOp>(block.getTerminator()).getValue();
}

// The value channel of a well-formed bind arm.  Guards establish the block
// before any helper reads it.
Value armValue(TimbdaBindOp bind) { return yieldValue(bind.getBody().front()); }

// `timbda.bind` in the kernel `Seq` spelling: exactly one block, one argument
// (the kernel binder), the argument referenced by nothing - a referenced
// binder is a source-level bind (binder substitution lives in the source), not
// a `Seq` arm.  `initValPremise` adds RewSeq's `forall v : Val` premise on the
// init operand; Norm arms quantify any Expr init.
bool isBindArm(Value v, bool initValPremise) {
  auto bind = dyn_cast_or_null<TimbdaBindOp>(v.getDefiningOp());
  if (!bind)
    return false;
  Region &region = bind.getBody();
  if (region.empty())
    return false; // one block; a block-less bind region is malformed
  Block &block = region.front();
  if (!block.getTerminator())
    return false;
  if (block.getNumArguments() == 0)
    return false; // our `Seq` arms always carry their (unused) binder argument
  for (BlockArgument arg : block.getArguments())
    if (!arg.use_empty())
      return false;
  if (initValPremise && !isValOperand(bind.getInit()))
    return false;
  return true;
}

// Add one block (with one binder-slot argument) to a region an ODS build
// created empty: OpBuilder::createBlock records the insert with the rewriter's
// driver, appended at the region's end (the `(Region*, Region::iterator,
// TypeRange, locs)` overload needs the explicit `end()` iterator).
Block *addArmBlock(PatternRewriter &rewriter, Region &region, Type binderType) {
  SmallVector<Type, 1> argTypes{binderType};
  SmallVector<Location, 1> argLocs{
      UnknownLoc::get(rewriter.getContext())};
  return rewriter.createBlock(&region, region.end(), argTypes, argLocs);
}


// A fresh bind in the kernel `Seq` spelling: the arm (one block, one unused
// binder argument, ending in a yield the body builder must have written) is
// built by `armBody`.  The bind is created at the rewriter's current insertion
// point - callers set it to the root-anchored position first - and the
// insertion point is re-anchored before `rootOp` afterwards so a caller's loop
// keeps inserting at the root position (root-anchored insertion is dominance
// safe for every value that dominates the root).
Value makeBindWithArm(PatternRewriter &rewriter, Operation *rootOp,
                      Type valueType, Value init,
                      llvm::function_ref<void(Block &, IRMapping &)> armBody) {
  auto bind = rewriter.create<TimbdaBindOp>(rootOp->getLoc(), valueType, init);
  Block *arm = addArmBlock(rewriter, bind.getBody(), valueType);
  rewriter.setInsertionPointToStart(arm);
  IRMapping map;
  armBody(*arm, map);
  rewriter.setInsertionPoint(rootOp);
  return bind.getResult();
}

// Kernel `v = e1 ;; e2`-style arm extension: append `Unify lhs rhs` as the
// arm's last statement and re-carrier the arm's yield through it (the kernel's
// `; k` sequencing at the arm tail, DEV-16).  In-place, driver-notified.
Value extendArmTail(PatternRewriter &rewriter, TimbdaBindOp bind, Value lhs,
                    Value rhs) {
  Block &arm = bind.getBody().front();
  Operation *term = arm.getTerminator();
  rewriter.setInsertionPoint(term);
  auto unify =
      rewriter.create<TimbdaUnifyOp>(term->getLoc(), bind.getType(), lhs, rhs);
  rewriter.modifyOpInPlace(term, [&] { term->setOperand(0, unify.getResult()); });
  return bind.getResult();
}

} // namespace

//===----------------------------------------------------------------------===//
// Fig. 9 guards (Rewriting.v 432-437: kernel premises `is_lit_val`, `root_of`
// root_mismatch, `is_val`).
//===----------------------------------------------------------------------===//

namespace timbda {

bool isValueOp(Value v) { return isValOperand(v); }

// EqK1 (`v1 = v2`) / EqK2 (`v1 <> v2`): both literals, equal or distinct.
bool isLiteralPair(Value lhs, Value rhs, bool same) {
  if (!isLitOperand(lhs) || !isLitOperand(rhs))
    return false; // `is_lit_val v1 /\ is_lit_val v2`
  return litEqual(lhs, rhs) == same;
}

// EqTup1 (equal member counts) / EqTup2 (different counts) over `list Val`
// tuples: both operands must be value tuples (Rewriting.v 341-348).
bool isTupPairLength(Value lhs, Value rhs, bool same) {
  auto l = vtup(lhs), r = vtup(rhs);
  if (!l || !r)
    return false;
  return (l.getOperands().size() == r.getOperands().size()) == same;
}

// EqFail: `root_mismatch v1 v2` (Rewriting.v 164-175) - different roots, with
// the `no_eq_rule_pair` exclusions subtracted: variable pairs (bare-variable
// unification stays stuck "until x gets a value") and lambda-vs-lambda pairs
// have no unification row and stay stuck; same-root pairs are handled by the
// root-specific rows (eqk1/eqtup1); different-root pairs fail (EqFail).
bool rootMismatchPair(Value lhs, Value rhs) {
  auto l = rootOf(lhs), r = rootOf(rhs);
  if (!l || !r)
    return false; // no kernel root reading: no Val row reads this pair
  bool noEqRule = *l == "var" || *r == "var" || (*l == "lam" && *r == "lam");
  if (noEqRule)
    return false;
  return *l != *r; // `negb (root_eqb r1 r2)`
}

//===----------------------------------------------------------------------===//
// Fig. 10 guards (Rewriting.v 452-463).
//===----------------------------------------------------------------------===//

// Gt1 (Rewriting.v 453): `Z.ltb b a = true`.  The generated matcher captures
// only the second operand's attr (the identity RHS needs a Value for the
// first); the helper pins the first operand to an IntOp and reads its attr.
bool intPairResidueFirst(Value first, IntegerAttr second) {
  if (!isIntOperand(first))
    return false; // `Gt, [VInt a; VInt b]` quantification
  return ltZ(second.getValue(), intOf(first)); // `Z.ltb b a`
}

// Gt2 (Rewriting.v 454): `Z.ltb b a = false` over the two captured attrs.
bool intsSecondNotLessFirst(IntegerAttr first, IntegerAttr second) {
  return !ltZ(second.getValue(), first.getValue());
}

// IsInt1 / IsInt2 (Rewriting.v 455-456): int literal vs. non-int Val (arity
// 1 is pinned by the pattern).
bool isIntValueOperand(Value v) { return isIntOperand(v); }

bool isNonIntValueArityOne(Value v) { return isValOperand(v) && !isIntOperand(v); }

// RewPrim / RewPrimFail (Rewriting.v 463-464): the kernel `prim_total` table
// over the whole op; Stuck fires neither rewriter and the application stays
// stuck exactly like the kernel.
bool primTotalIsResult(Value primResult) {
  auto prim = dyn_cast_or_null<TimbdaPrimOp>(primResult.getDefiningOp());
  return prim && primTotal(prim).status == PrimRes::Res;
}

bool primTotalIsFail(Value primValue) {
  auto prim = dyn_cast_or_null<TimbdaPrimOp>(primValue.getDefiningOp());
  return prim && primTotal(prim).status == PrimRes::Fail;
}

//===----------------------------------------------------------------------===//
// Fig. 11 guards (Rewriting.v 468-470).
//===----------------------------------------------------------------------===//

// RewBetaL: the App's callee operand defines a lambda value (`VLam t b`).
bool calleeIsLambda(Value callee) {
  return callee.getDefiningOp() && isa<TimbdaLambdaOp>(callee.getDefiningOp());
}

// RewBetaT: `⟨v0..vn⟩ [e]` with `vs <> nil`.
bool calleeIsNonEmptyValueTuple(Value callee) {
  auto t = vtup(callee);
  return t && !t.getOperands().empty();
}

// RewBetaT0 (Rewriting.v 470): `vs = nil`.  The guard receives the (empty)
// tuple's result Value - an empty operand range is never dereferenced.
bool isEmptyValueTupleOp(Value callee) {
  auto t = vtup(callee);
  return t && t.getOperands().empty();
}

//===----------------------------------------------------------------------===//
// Fig. 12 guards (Rewriting.v 486-491).
//===----------------------------------------------------------------------===//

bool unusedBindArm(Value bindResult) {
  return isBindArm(bindResult, /*initValPremise=*/true); // RewSeq `forall v`
}

bool unusedBindArmOfAnyInit(Value bindResult) {
  return isBindArm(bindResult, /*initValPremise=*/false); // Norm1/Norm3 arms
}

// RewNorm5: a bind whose init operand is itself a binder-free bind (`Seq (Seq
// e1 e2) e3`).
bool bindArmOfBindArm(Value bindResult) {
  auto bind = dyn_cast_or_null<TimbdaBindOp>(bindResult.getDefiningOp());
  return bind && isBindArm(bindResult, /*initValPremise=*/false) &&
         isBindArm(bind.getInit(), /*initValPremise=*/false);
}

//===----------------------------------------------------------------------===//
// Fig. 9-10 RHS builders (NativeCodeCall destinations at the generated call
// sites).  Kernel `;` is region statement sequencing; whole expressions are
// rebuilt root-anchored (immediately before the matched op).
//===----------------------------------------------------------------------===//

// RewEqTup1 (Rewriting.v 341-345): `eqtup1[⟨vs⟩, ⟨ws⟩] -> eq_seq v::vs w::ws
// (Ret (VTup vs))` - member unifications `Unify (Ret v_i) (Ret w_i)` sequence
// outward and the innermost arm carries the lhs tuple value `k`.  Unrolling
// `eq_seq` (Rewriting.v 121-131) bottom-up: each level is a `Seq` bind (bind
// with unused binder, DEV-16) whose arm is `[Unify v_i w_i ;; <next level's
// value>]`.  A zero-length pair rewrites to `Ret (VTup vs)` directly (the
// `k`), which is why the loop returns `lhs` when the fold is empty.
Value eqTup1Rhs(PatternRewriter &rewriter, Value root, Value lhs, Value rhs) {
  Operation *rootOp = root.getDefiningOp(); // the matched Unify
  auto lhsTup = cast<TimbdaTupOp>(lhs.getDefiningOp());
  auto rhsTup = cast<TimbdaTupOp>(rhs.getDefiningOp());
  // The fold is built innermost-first: each level is a fresh bind *at the root
  // position* (never a clone of the previous level - the kernel's eq_seq
  // reuses `Ret (VTup vs)` and each member value at every level; a value
  // outside the chain dominates every fresh bind built at the root position,
  // and the level-nesting dominance is strictly linear: bind_{i} dominates
  // bind_{i+1} through the region entry of bind_{i}'s arm).  `rest` carries
  // the kernel `eq_seq` accumulator value; the innermost accumulator is the
  // lhs tuple itself (the `k`).
  Value rest = lhs; // the kernel `k = Ret (VTup vs)`
  for (int64_t i = static_cast<int64_t>(lhsTup.getOperands().size()) - 1;
       i >= 0; --i) {
    Value v_i = lhsTup.getOperand(i), w_i = rhsTup.getOperand(i);
    Value prev = rest;
    rewriter.setInsertionPoint(rootOp);
    rest = makeBindWithArm(
        rewriter, rootOp, lhs.getType(), lhs,
        [&](Block &arm, IRMapping &) {
          auto unify = rewriter.create<TimbdaUnifyOp>(rootOp->getLoc(),
                                                      lhs.getType(), v_i, w_i);
          rewriter.create<TimbdaYieldOp>(rootOp->getLoc(), prev);
        });
  }
  return rest; // the outermost bind; a zero-length pair returns `lhs` (the k)
}

// RewPrim (Rewriting.v 463): `prim_total p vs = PRes v` materialised as the
// PRes value's value-op spelling at the root position.
Value primTotalRhs(PatternRewriter &rewriter, Value primResult) {
  auto prim = cast<TimbdaPrimOp>(primResult.getDefiningOp());
  PrimRes r = primTotal(prim);
  assert(r.status == PrimRes::Res && "RewPrim fires only on PRes");
  rewriter.setInsertionPoint(prim);
  return makePrimVal(rewriter, r, prim.getLoc());
}

// RewAdd (Rewriting.v 452): `add[ki1, ki2] -> VInt (ki1 + ki2)`; both attrs
// are captured by the matcher (`x` pinned to an IntOp by the guard).
Value addRhs(PatternRewriter &rewriter, Value primResult, Value first,
             IntegerAttr second) {
  auto prim = cast<TimbdaPrimOp>(primResult.getDefiningOp());
  IntegerAttr firstAttr =
      cast<TimbdaIntOp>(first.getDefiningOp()).getValueAttr();
  rewriter.setInsertionPoint(prim); // root-anchored
  PrimRes r =
      PrimRes::ofInt(addZ(firstAttr.getValue(), second.getValue()),
                     seedFrom(firstAttr, second));
  return makePrimVal(rewriter, r, prim.getLoc());
}

// RewDotDot (Rewriting.v 459): `dotdot[ki1, ki2] -> VTup (map VInt (seq_z ki1
// ki2))`, inclusive; `lo > hi` yields the empty tuple (Syntax.v 329-335).
Value dotdotRhs(PatternRewriter &rewriter, Value primResult, Value lo,
                IntegerAttr hi) {
  auto prim = cast<TimbdaPrimOp>(primResult.getDefiningOp());
  rewriter.setInsertionPoint(prim); // root-anchored
  SmallVector<APInt, 8> ks;
  APInt one(kZBits, 1);
  IntegerAttr loAttr = cast<TimbdaIntOp>(lo.getDefiningOp()).getValueAttr();
  APInt loZ = zOf(loAttr.getValue()), hiZ = zOf(hi.getValue());
  for (APInt k = loZ; !k.sgt(hiZ); k = k + one)
    ks.push_back(k);
  PrimRes r = PrimRes::ofIntTup(ks, seedFrom(loAttr, hi));
  return makePrimVal(rewriter, r, prim.getLoc());
}

// RewCons (Rewriting.v 308-310): `cons[v0, <v1..vn>] -> <v0, v1..vn>` (t =
// the static nested tuple op's member range).
Value consRhs(PatternRewriter &rewriter, Value primResult, Value head,
              OperandRange tail) {
  auto prim = cast<TimbdaPrimOp>(primResult.getDefiningOp());
  rewriter.setInsertionPoint(prim); // root-anchored
  SmallVector<Value, 8> vs;
  vs.push_back(head);
  vs.append(tail.begin(), tail.end());
  return makePrimVal(rewriter, PrimRes::ofTup(vs), prim.getLoc());
}

// RewSeq (Rewriting.v 486): `v ; e -> e` - splice the arm's statements in
// front of the bind and hand back the arm's value channel.  Outer-scope
// references dominate the bind (they dominated the arm, and the bind dominates
// its arm), so the clones land legally before it.
Value seqRhs(PatternRewriter &rewriter, Value bindResult) {
  auto bind = cast<TimbdaBindOp>(bindResult.getDefiningOp());
  Block &arm = bind.getBody().front();
  rewriter.setInsertionPoint(bind);
  IRMapping map;
  for (Operation &op : arm.without_terminator())
    rewriter.clone(op, map); // the arm binder is unreferenced (guard)
  // The returned channel is the arm value spelled at the splice site: its
  // defining op cloned through the same map when it lives in the dying arm,
  // the channel itself when it is an outer value, and never the dying arm's
  // own block argument.
  Value channel = arm.getTerminator()->getOperand(0);
  if (!map.contains(channel)) {
    if (Operation *def = channel.getDefiningOp())
      rewriter.clone(*def, map);
  }
  return map.lookupOrDefault(channel);
}

// RewNorm1 (Rewriting.v 487): `v = (e1 ; e2) -> e1 ; (v = e2)` - the arm bind
// survives, its arm gains `Unify v e2` as last statement and carries the
// unify's value (in-place edit; the kernel's `k` is congruent here).
Value norm1Rhs(PatternRewriter &rewriter, Value root, Value lhs, Value rhs) {
  (void)root; // the root dies under the generated replaceOp; the edit is here
  auto bind = cast<TimbdaBindOp>(rhs.getDefiningOp());
  return extendArmTail(rewriter, bind, lhs, armValue(bind));
}

// RewNorm3 (Rewriting.v 489): `(e1 ; e2) = e3 -> e1 ; (e2 = e3)`.
Value norm3Rhs(PatternRewriter &rewriter, Value root, Value lhs, Value rhs) {
  (void)root;
  auto bind = cast<TimbdaBindOp>(lhs.getDefiningOp());
  return extendArmTail(rewriter, bind, armValue(bind), rhs);
}

// RewNorm2 (Rewriting.v 488) / RewNorm4 (Rewriting.v 490):
// `v = (e1 = e2) -> (v = e1) ; (v = e2)` and `(v = e1) = e2 -> (v = e1) ; (v
// = e2)`.  Both restate `U1 = Unify(v, e1)` root-anchored (the root dies with
// the rewrite, so the inner node's SSA value must be restated when it becomes
// a live init); the restated U1 is the new bind's init value channel (DEV-16:
// the first Seq statement's value flows into the unused binder), and the arm
// restates `U2 = Unify(v, e2)` as its value channel.  Norm2 matches the root's
// operand pair (e1, e2); Norm4 captures its own lhs (v) and rhs (e1) operands
// in the generated matcher, and the arm restates the root's value with e2.
Value norm2Rhs(PatternRewriter &rewriter, Value root, Value v, Value e1,
               Value e2) {
  auto rootUnify = cast<TimbdaUnifyOp>(root.getDefiningOp());
  rewriter.setInsertionPoint(rootUnify);
  auto u1 = rewriter.create<TimbdaUnifyOp>(rootUnify.getLoc(), root.getType(),
                                           v, e1);
  rewriter.setInsertionPoint(rootUnify); // bind ahead of u1: u1 is the bound
  // value (re-created because the root it spells dies in this rewrite)
  return makeBindWithArm(rewriter, rootUnify, root.getType(), u1.getResult(),
                         [&](Block &arm, IRMapping &) {
                           auto u2 = rewriter.create<TimbdaUnifyOp>(
                               rootUnify.getLoc(), root.getType(), v, e2);
                           rewriter.create<TimbdaYieldOp>(rootUnify.getLoc(),
                                                          u2.getResult());
                         });
}

Value norm4Rhs(PatternRewriter &rewriter, Value root, Value v, Value e1,
               Value e2) {
  auto rootUnify = cast<TimbdaUnifyOp>(root.getDefiningOp());
  rewriter.setInsertionPoint(rootUnify);
  auto u1 = rewriter.create<TimbdaUnifyOp>(rootUnify.getLoc(), root.getType(),
                                           v, e1);
  rewriter.setInsertionPoint(rootUnify); // bind ahead of u1: u1 is the bound
  // value (re-created because the root it spells dies in this rewrite)
  return makeBindWithArm(rewriter, rootUnify, root.getType(), u1.getResult(),
                         [&](Block &arm, IRMapping &) {
                           auto u2 = rewriter.create<TimbdaUnifyOp>(
                               rootUnify.getLoc(), root.getType(), v, e2);
                           rewriter.create<TimbdaYieldOp>(rootUnify.getLoc(),
                                                          u2.getResult());
                         });
}

//===----------------------------------------------------------------------===//
// Region-splicing helpers shared by the Norm5 / Beta rows: cloning a source
// block's *whole* statement sequence (terminator value mapped, terminator not
// cloned - the destination keeps its own).  The clone chain's def->use edges
// are remapped through IRMapping, exactly mirroring the kernel's lifting of a
// desugared subtree into a new block position (DEV-6 liftV/liftE pass-through).
//===----------------------------------------------------------------------===//

namespace {

// Clone a source block's statement sequence into a destination block that
// already carries its own terminator: the terminator is not cloned, and the
// destination's yield is re-pointed (driver-notified) to carry the source
// arm's value channel in cloned spelling.  This is the subtree-spelling move
// (Norm5, BetaL); def->use edges inside the moved subtree are remapped by
// clone() through the same IRMapping (`liftV` pass-through, DEV-6).
void spliceStatementsIntoTerminated(PatternRewriter &rewriter, Block &src,
                                    Block &dst, IRMapping &map) {
  Value srcChannel = src.getTerminator()->getOperand(0);
  rewriter.setInsertionPoint(dst.getTerminator());
  for (Operation &op : src.without_terminator())
    rewriter.clone(op, map);
  // Spell the source channel at the destination: the clone chain's own
  // spelling (mapped), a fresh clone of its defining op when the loop did not
  // already clone it (and the caller mapped anything it captures), or the
  // channel itself when it is an outer value that dominates the clone.  A
  // channel that is a *source-block argument* must have been mapped by the
  // caller before this helper runs.
  if (!map.contains(srcChannel)) {
    if (Operation *def = srcChannel.getDefiningOp())
      rewriter.clone(*def, map); // pure duplication at the arm tail
  }
  Value dstChannel = map.lookupOrDefault(srcChannel);
  Operation *dstTerm = dst.getTerminator();
  rewriter.modifyOpInPlace(dstTerm,
                           [&] { dstTerm->setOperand(0, dstChannel); });
}

// Build a fresh terminated arm for a source block's statements (BetaL's
// desugared lambda body): clones land in `dst` in source order, the channel
// def is duplicated at the arm tail when the loop did not already clone it,
// and a fresh yield carries it.  The caller pre-maps any source-block
// argument the captures reference.
void copyBlockBodyIntoFreshArm(PatternRewriter &rewriter, Block &src,
                               Block &dst, IRMapping &map) {
  for (Operation &op : src.without_terminator())
    rewriter.clone(op, map);
  Value srcChannel = src.getTerminator()->getOperand(0);
  if (!map.contains(srcChannel)) {
    if (Operation *def = srcChannel.getDefiningOp())
      rewriter.clone(*def, map); // pure expression duplication at the arm tail
  }
  rewriter.create<TimbdaYieldOp>(src.getTerminator()->getLoc(),
                                 map.lookupOrDefault(srcChannel));
}

} // namespace

// RewNorm5 (Rewriting.v 491): `(e1 ; e2) ; e3 -> e1 ; (e2 ; e3)`.  The inner
// arm bind (the root's init) is cloned whole - its arm already carries e2's
// statement sequence and value channel - and the outer arm's statements (e3)
// are spliced ahead of the clone's yield, which now carries the outer arm's
// value channel (e3's value).  The clone stands at the root position; the root
// (outer bind) dies under the generated replaceOp.
Value norm5Rhs(PatternRewriter &rewriter, Value bindResult) {
  auto outer = cast<TimbdaBindOp>(bindResult.getDefiningOp());
  auto inner = cast<TimbdaBindOp>(outer.getInit().getDefiningOp());
  rewriter.setInsertionPoint(outer); // root-anchored
  IRMapping map; // clone() records the inner subtree's def->use remaps
  auto newInner = cast<TimbdaBindOp>(rewriter.clone(*inner.getOperation(), map));
  spliceStatementsIntoTerminated(rewriter, outer.getBody().front(),
                                 newInner.getBody().front(), map);
  rewriter.setInsertionPoint(outer); // re-anchor for the generated replaceOp
  return newInner.getResult();
}

// RewBetaL (Rewriting.v 468): `App (λx.b) e -> block{ x = e ;; b }` (the
// source-level `x <- e;; b` desugaring).  The block's region block argument
// IS the kernel binder x (the declared-only slot, DEV-18); `Unify x e` is the
// block's first statement; the desugared arm (a bind in the `Seq` spelling,
// DEV-16 - its init carries e's value channel) holds b's statements, with the
// lambda body's binder references mapped onto x.  The arm binder (the kernel
// Seq binder at the App's binder level) is the arm's fresh unused block
// argument.
Value betaLRhs(PatternRewriter &rewriter, Value root, Value callee, Value arg) {
  auto app = cast<TimbdaAppOp>(root.getDefiningOp());
  auto lambda = cast<TimbdaLambdaOp>(callee.getDefiningOp());
  rewriter.setInsertionPoint(app);
  auto blockOp = rewriter.create<TimbdaBlockOp>(app.getLoc(), app.getType(),
                                                 ValueRange{});
  Block *outer = addArmBlock(rewriter, blockOp.getBody(), app.getType());
  BlockArgument x = outer->getArgument(0); // the declared binder slot
  auto bind = rewriter.create<TimbdaBindOp>(app.getLoc(), app.getType(), arg);
  rewriter.setInsertionPointToStart(outer);
  rewriter.create<TimbdaUnifyOp>(app.getLoc(), app.getType(), x,
                                 arg); // the `x = e` statement
  Block *arm = addArmBlock(rewriter, bind.getBody(), app.getType());
  IRMapping map;
  map.map(lambda.getBody().front().getArgument(0), x); // the lambda binder's
  // references land on the block's declared slot (the `x <- e` substitution)
  copyBlockBodyIntoFreshArm(rewriter, lambda.getBody().front(), *arm, map);
  rewriter.setInsertionPoint(app); // re-anchor: the generated replaceOp follows
  return blockOp.getResult();
}

// RewBetaT (Rewriting.v 469): `⟨v0..vn⟩[e] -> block{ x = e ;; choice of the
// `beta_t_cands i vs` }` (Rewriting.v 121-137).  The kernel's candidate is
// `Block nil (Seq (Unify (VVar 0) (Ret i)) (Ret v_i))`: spelled as a bind in
// the arm `Seq` spelling - init carrying the `Unify x (Ret i)` statement's
// value, the arm restating that unification as its value channel.  `x = e` is
// the outer block's own statement (the binder slot `x`); `x`'s value matches
// exactly one candidate (`X = VInt ki`), so the left-nested choice mirrors the
// kernel's `Left` juxtaposition narrowing exactly (never ambiguity).
Value betaTRhs(PatternRewriter &rewriter, Value root, Value callee, Value arg) {
  auto app = cast<TimbdaAppOp>(root.getDefiningOp());
  auto tup = vtup(callee);
  assert(tup && !tup.getOperands().empty() && "RewBetaT pins vs <> nil");
  rewriter.setInsertionPoint(app);
  auto blockOp = rewriter.create<TimbdaBlockOp>(app.getLoc(), app.getType(),
                                                 ValueRange{});
  Block *outer = addArmBlock(rewriter, blockOp.getBody(), app.getType());
  BlockArgument x = outer->getArgument(0); // the declared binder slot
  rewriter.setInsertionPointToStart(outer);
  rewriter.create<TimbdaUnifyOp>(app.getLoc(), app.getType(), x,
                                 arg); // the `x = e` statement
  SmallVector<Value, 4> cands;
  for (unsigned i = 0; i < tup.getOperands().size(); ++i) {
    rewriter.setInsertionPoint(outer->getTerminator()); // candidates in order
    Value vi = tup.getOperand(i);
    // The kernel candidate `Seq (Unify (VVar 0) (Ret i)) (Ret v_i)`: the
    // unification is spelled in the outer block ahead of its bind (DEV-16:
    // the bind's init carries the statement's value), the arm yields the
    // member value, and the arm binder (the kernel `Seq` binder) is the
    // unused fresh block argument.
    auto iVal = makeIntValue(rewriter, app.getLoc(), APInt(64, i),
                             seedFromIntOps(tup.getOperands()));
    auto cu = rewriter.create<TimbdaUnifyOp>(app.getLoc(), app.getType(), x,
                                             iVal);
    cands.push_back(makeBindWithArm(
        rewriter, app, app.getType(), cu.getResult(),
        [&](Block &arm, IRMapping &) {
          rewriter.create<TimbdaYieldOp>(app.getLoc(), vi);
        }));
  }
  // `choice_list` juxtaposition (Rewriting.v 111-119): fold left, `or` binds
  // left; the chain is the block's final value (the region carries it out).
  Value chain = cands[0];
  for (size_t i = 1; i < cands.size(); ++i) {
    rewriter.setInsertionPoint(outer->getTerminator());
    chain = rewriter
                .create<TimbdaOrOp>(app.getLoc(), app.getType(), chain,
                                    cands[i])
                .getResult();
  }
  rewriter.setInsertionPoint(outer->getTerminator());
  rewriter.modifyOpInPlace(outer->getTerminator(), [&] {
    outer->getTerminator()->setOperand(0, chain);
  });
  rewriter.setInsertionPoint(app); // re-anchor: the generated replaceOp follows
  return blockOp.getResult();
}

} // namespace timbda

//===----------------------------------------------------------------------===//
// The generated 23 DRR rewriters (kernel rows Figs. 9-12) live in
// dialect/TimbdaCanonicalization.cpp.inc; register them with the driver.
//===----------------------------------------------------------------------===//

#include "dialect/TimbdaCanonicalization.cpp.inc"

void timbda::populateTimbdaCanonicalization(::mlir::RewritePatternSet &patterns) {
  ::populateWithGenerated(patterns);
}
