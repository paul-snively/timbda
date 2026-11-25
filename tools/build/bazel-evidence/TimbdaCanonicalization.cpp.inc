/*===- TableGen'erated file -------------------------------------*- C++ -*-===*\
|*                                                                            *|
|* Rewriters                                                                  *|
|*                                                                            *|
|* Automatically generated file, do not edit!                                 *|
|* From: TimbdaPatterns.td                                                    *|
|*                                                                            *|
\*===----------------------------------------------------------------------===*/


static ::llvm::LogicalResult __mlir_ods_local_attr_constraint_TimbdaPatterns1(
    ::mlir::PatternRewriter &rewriter, ::mlir::Operation *op, ::mlir::Attribute attr,
    ::llvm::StringRef failureStr) {
  if (!((attr == ::timbda::PrimAttr::get(rewriter.getContext(), ::timbda::Prim::Add)))) {
    return rewriter.notifyMatchFailure(op, [&](::mlir::Diagnostic &diag) {
      diag << failureStr << ": constant attribute ::timbda::Prim::Add";
    });
  }
  return ::mlir::success();
}

static ::llvm::LogicalResult __mlir_ods_local_attr_constraint_TimbdaPatterns2(
    ::mlir::PatternRewriter &rewriter, ::mlir::Operation *op, ::mlir::Attribute attr,
    ::llvm::StringRef failureStr) {
  if (!((attr == ::timbda::PrimAttr::get(rewriter.getContext(), ::timbda::Prim::Cons)))) {
    return rewriter.notifyMatchFailure(op, [&](::mlir::Diagnostic &diag) {
      diag << failureStr << ": constant attribute ::timbda::Prim::Cons";
    });
  }
  return ::mlir::success();
}

static ::llvm::LogicalResult __mlir_ods_local_attr_constraint_TimbdaPatterns3(
    ::mlir::PatternRewriter &rewriter, ::mlir::Operation *op, ::mlir::Attribute attr,
    ::llvm::StringRef failureStr) {
  if (!((attr == ::timbda::PrimAttr::get(rewriter.getContext(), ::timbda::Prim::DotDot)))) {
    return rewriter.notifyMatchFailure(op, [&](::mlir::Diagnostic &diag) {
      diag << failureStr << ": constant attribute ::timbda::Prim::DotDot";
    });
  }
  return ::mlir::success();
}

static ::llvm::LogicalResult __mlir_ods_local_attr_constraint_TimbdaPatterns4(
    ::mlir::PatternRewriter &rewriter, ::mlir::Operation *op, ::mlir::Attribute attr,
    ::llvm::StringRef failureStr) {
  if (!((attr == ::timbda::PrimAttr::get(rewriter.getContext(), ::timbda::Prim::Gt)))) {
    return rewriter.notifyMatchFailure(op, [&](::mlir::Diagnostic &diag) {
      diag << failureStr << ": constant attribute ::timbda::Prim::Gt";
    });
  }
  return ::mlir::success();
}

static ::llvm::LogicalResult __mlir_ods_local_attr_constraint_TimbdaPatterns5(
    ::mlir::PatternRewriter &rewriter, ::mlir::Operation *op, ::mlir::Attribute attr,
    ::llvm::StringRef failureStr) {
  if (!((attr == ::timbda::PrimAttr::get(rewriter.getContext(), ::timbda::Prim::IsInt)))) {
    return rewriter.notifyMatchFailure(op, [&](::mlir::Diagnostic &diag) {
      diag << failureStr << ": constant attribute ::timbda::Prim::IsInt";
    });
  }
  return ::mlir::success();
}
static ::llvm::LogicalResult static_dag_matcher_0(::mlir::PatternRewriter &rewriter, ::mlir::Operation *op0, ::llvm::SmallVector<::mlir::Operation *, 4> &tblgen_ops, ::mlir::IntegerAttr &y) {
  (void)tblgen_ops;
  auto castedOp1 = ::llvm::dyn_cast<::timbda::TimbdaIntOp>(op0); (void)castedOp1;
  if (!(castedOp1)){
    return rewriter.notifyMatchFailure(op0, [&](::mlir::Diagnostic &diag) {
      diag << "castedOp1 is not ::timbda::TimbdaIntOp type";
    });
  }
  {
    [[maybe_unused]] auto tblgen_attr = castedOp1.getProperties().getValue();
    if (!(tblgen_attr)){
      return rewriter.notifyMatchFailure(castedOp1, [&](::mlir::Diagnostic &diag) {
        diag << "expected op 'timbda.int' to have attribute 'value' of type '::mlir::IntegerAttr'";
      });
    }
    y = tblgen_attr;
  }
  return ::mlir::success();
}

static ::llvm::LogicalResult static_dag_matcher_1(::mlir::PatternRewriter &rewriter, ::mlir::Operation *op0, ::llvm::SmallVector<::mlir::Operation *, 4> &tblgen_ops, ::mlir::Operation::operand_range &arg, ::mlir::Operation::operand_range &callee, ::timbda::TimbdaAppOp &u) {
  (void)tblgen_ops;
  auto castedOp1 = ::llvm::dyn_cast<::timbda::TimbdaAppOp>(op0); (void)castedOp1;
  if (!(castedOp1)){
    return rewriter.notifyMatchFailure(op0, [&](::mlir::Diagnostic &diag) {
      diag << "castedOp1 is not ::timbda::TimbdaAppOp type";
    });
  }
  u = castedOp1;
  callee = castedOp1.getODSOperands(0);
  arg = castedOp1.getODSOperands(1);
  return ::mlir::success();
}

static ::llvm::LogicalResult static_dag_matcher_2(::mlir::PatternRewriter &rewriter, ::mlir::Operation *op0, ::llvm::SmallVector<::mlir::Operation *, 4> &tblgen_ops, ::mlir::Operation::operand_range &rhs, ::mlir::Operation::operand_range &lhs) {
  (void)tblgen_ops;
  auto castedOp1 = ::llvm::dyn_cast<::timbda::TimbdaUnifyOp>(op0); (void)castedOp1;
  if (!(castedOp1)){
    return rewriter.notifyMatchFailure(op0, [&](::mlir::Diagnostic &diag) {
      diag << "castedOp1 is not ::timbda::TimbdaUnifyOp type";
    });
  }
  lhs = castedOp1.getODSOperands(0);
  rhs = castedOp1.getODSOperands(1);
  return ::mlir::success();
}

static ::llvm::LogicalResult static_dag_matcher_3(::mlir::PatternRewriter &rewriter, ::mlir::Operation *op0, ::llvm::SmallVector<::mlir::Operation *, 4> &tblgen_ops, ::mlir::Operation::operand_range &rhs, ::mlir::Operation::operand_range &lhs, ::timbda::TimbdaUnifyOp &u) {
  (void)tblgen_ops;
  auto castedOp1 = ::llvm::dyn_cast<::timbda::TimbdaUnifyOp>(op0); (void)castedOp1;
  if (!(castedOp1)){
    return rewriter.notifyMatchFailure(op0, [&](::mlir::Diagnostic &diag) {
      diag << "castedOp1 is not ::timbda::TimbdaUnifyOp type";
    });
  }
  u = castedOp1;
  lhs = castedOp1.getODSOperands(0);
  rhs = castedOp1.getODSOperands(1);
  return ::mlir::success();
}

static ::llvm::LogicalResult static_dag_matcher_4(::mlir::PatternRewriter &rewriter, ::mlir::Operation *op0, ::llvm::SmallVector<::mlir::Operation *, 4> &tblgen_ops, ::mlir::Operation::operand_range &args) {
  (void)tblgen_ops;
  auto castedOp1 = ::llvm::dyn_cast<::timbda::TimbdaPrimOp>(op0); (void)castedOp1;
  if (!(castedOp1)){
    return rewriter.notifyMatchFailure(op0, [&](::mlir::Diagnostic &diag) {
      diag << "castedOp1 is not ::timbda::TimbdaPrimOp type";
    });
  }
  {
    [[maybe_unused]] auto tblgen_attr = castedOp1.getProperties().getPrim();
    if (!(tblgen_attr)){
      return rewriter.notifyMatchFailure(castedOp1, [&](::mlir::Diagnostic &diag) {
        diag << "expected op 'timbda.prim' to have attribute 'prim' of type '::timbda::PrimAttr'";
      });
    }
    if(::mlir::failed(__mlir_ods_local_attr_constraint_TimbdaPatterns5(rewriter, castedOp1, tblgen_attr, "op 'timbda.prim' attribute 'prim' failed to satisfy constraint: 'constant attribute ::timbda::Prim::IsInt'"))) {
      return ::mlir::failure();
    }
  }
  {
    auto variadic_operand_range = castedOp1.getODSOperands(0);
    if (variadic_operand_range.size() != 1) return ::mlir::failure();
    args = variadic_operand_range.slice(0, 1);
  }
  return ::mlir::success();
}

static ::llvm::LogicalResult static_dag_matcher_5(::mlir::PatternRewriter &rewriter, ::mlir::Operation *op0, ::llvm::SmallVector<::mlir::Operation *, 4> &tblgen_ops, ::mlir::Operation::operand_range &init, ::timbda::TimbdaBindOp &b) {
  (void)tblgen_ops;
  auto castedOp1 = ::llvm::dyn_cast<::timbda::TimbdaBindOp>(op0); (void)castedOp1;
  if (!(castedOp1)){
    return rewriter.notifyMatchFailure(op0, [&](::mlir::Diagnostic &diag) {
      diag << "castedOp1 is not ::timbda::TimbdaBindOp type";
    });
  }
  b = castedOp1;
  init = castedOp1.getODSOperands(0);
  return ::mlir::success();
}

static ::llvm::LogicalResult static_dag_matcher_6(::mlir::PatternRewriter &rewriter, ::mlir::Operation *op0, ::llvm::SmallVector<::mlir::Operation *, 4> &tblgen_ops, ::mlir::Operation::operand_range &args, ::timbda::PrimAttr &attr, ::timbda::TimbdaPrimOp &p) {
  (void)tblgen_ops;
  auto castedOp1 = ::llvm::dyn_cast<::timbda::TimbdaPrimOp>(op0); (void)castedOp1;
  if (!(castedOp1)){
    return rewriter.notifyMatchFailure(op0, [&](::mlir::Diagnostic &diag) {
      diag << "castedOp1 is not ::timbda::TimbdaPrimOp type";
    });
  }
  p = castedOp1;
  {
    [[maybe_unused]] auto tblgen_attr = castedOp1.getProperties().getPrim();
    if (!(tblgen_attr)){
      return rewriter.notifyMatchFailure(castedOp1, [&](::mlir::Diagnostic &diag) {
        diag << "expected op 'timbda.prim' to have attribute 'prim' of type '::timbda::PrimAttr'";
      });
    }
    attr = tblgen_attr;
  }
  args = castedOp1.getODSOperands(0);
  return ::mlir::success();
}

/* Generated from:
    dialect/TimbdaPatterns.td:123
*/
struct RewAdd : public ::mlir::RewritePattern {
  RewAdd(::mlir::MLIRContext *context)
      : ::mlir::RewritePattern("timbda.prim", 85, context, {}) {}
  ::llvm::LogicalResult matchAndRewrite(::mlir::Operation *op0,
      ::mlir::PatternRewriter &rewriter) const override {
    // Variables for capturing values and attributes used while creating ops
    ::mlir::Operation::operand_range x(op0->getOperands());
    ::timbda::TimbdaPrimOp p;
    ::mlir::IntegerAttr y;
    ::llvm::SmallVector<::mlir::Operation *, 4> tblgen_ops;

    // Match
    tblgen_ops.push_back(op0);
    auto castedOp0 = ::llvm::dyn_cast<::timbda::TimbdaPrimOp>(op0); (void)castedOp0;
    p = castedOp0;
    {
      [[maybe_unused]] auto tblgen_attr = castedOp0.getProperties().getPrim();
      if (!(tblgen_attr)){
        return rewriter.notifyMatchFailure(castedOp0, [&](::mlir::Diagnostic &diag) {
          diag << "expected op 'timbda.prim' to have attribute 'prim' of type '::timbda::PrimAttr'";
        });
      }
      if(::mlir::failed(__mlir_ods_local_attr_constraint_TimbdaPatterns1(rewriter, castedOp0, tblgen_attr, "op 'timbda.prim' attribute 'prim' failed to satisfy constraint: 'constant attribute ::timbda::Prim::Add'"))) {
        return ::mlir::failure();
      }
    }
    {
      auto variadic_operand_range = castedOp0.getODSOperands(0);
      if (variadic_operand_range.size() != 2) return ::mlir::failure();
      x = variadic_operand_range.slice(0, 1);
      {
        auto *local_op_1 = variadic_operand_range[1].getDefiningOp();
        if (!(local_op_1)){
          return rewriter.notifyMatchFailure(castedOp0, [&](::mlir::Diagnostic &diag) {
            diag << "There's no operation that defines variadic operand 0 (variadic sub-opearnd #1) of castedOp0";
          });
        }
        if(::mlir::failed(static_dag_matcher_0(rewriter, local_op_1, tblgen_ops, y))) {
          return ::mlir::failure();
        }
        tblgen_ops.push_back(local_op_1);
      }
    }
    if (!((::timbda::isIntValueOperand((*x.begin()))))){
      return rewriter.notifyMatchFailure(op0, [&](::mlir::Diagnostic &diag) {
        diag << "entities 'x' failed to satisfy constraint: 'operand defines an int literal'";
      });
    }

    // Rewrite
    auto odsLoc = rewriter.getFusedLoc({tblgen_ops[0]->getLoc(), tblgen_ops[1]->getLoc()}); (void)odsLoc;
    ::llvm::SmallVector<::mlir::Value, 4> tblgen_repl_values;
    auto nativeVar_0 = ::timbda::addRhs(rewriter, (*p.getODSResults(0).begin()), (*x.begin()), y); (void)nativeVar_0;

    for (auto v: ::llvm::SmallVector<::mlir::Value, 4>{ {nativeVar_0} }) {
      tblgen_repl_values.push_back(v);
    }

    rewriter.replaceOp(op0, tblgen_repl_values);
    return ::mlir::success();
  }
};

/* Generated from:
    dialect/TimbdaPatterns.td:240
*/
struct RewBetaL : public ::mlir::RewritePattern {
  RewBetaL(::mlir::MLIRContext *context)
      : ::mlir::RewritePattern("timbda.app", 88, context, {}) {}
  ::llvm::LogicalResult matchAndRewrite(::mlir::Operation *op0,
      ::mlir::PatternRewriter &rewriter) const override {
    // Variables for capturing values and attributes used while creating ops
    ::mlir::Operation::operand_range arg(op0->getOperands());
    ::mlir::Operation::operand_range callee(op0->getOperands());
    ::timbda::TimbdaAppOp u;
    ::llvm::SmallVector<::mlir::Operation *, 4> tblgen_ops;

    // Match
    tblgen_ops.push_back(op0);
    if(::mlir::failed(static_dag_matcher_1(rewriter, op0, tblgen_ops, arg, callee, u))) {
      return ::mlir::failure();
    }
    auto castedOp0 = ::llvm::dyn_cast_or_null<::timbda::TimbdaAppOp>(op0); (void)castedOp0;
    if (!((::timbda::calleeIsLambda((*callee.begin()))))){
      return rewriter.notifyMatchFailure(op0, [&](::mlir::Diagnostic &diag) {
        diag << "entities 'callee' failed to satisfy constraint: 'callee operand defines a lambda value op'";
      });
    }

    // Rewrite
    auto odsLoc = rewriter.getFusedLoc({tblgen_ops[0]->getLoc()}); (void)odsLoc;
    ::llvm::SmallVector<::mlir::Value, 4> tblgen_repl_values;
    auto nativeVar_0 = ::timbda::betaLRhs(rewriter, (*u.getODSResults(0).begin()), (*callee.begin()), (*arg.begin())); (void)nativeVar_0;

    for (auto v: ::llvm::SmallVector<::mlir::Value, 4>{ {nativeVar_0} }) {
      tblgen_repl_values.push_back(v);
    }

    rewriter.replaceOp(op0, tblgen_repl_values);
    return ::mlir::success();
  }
};

/* Generated from:
    dialect/TimbdaPatterns.td:246
*/
struct RewBetaT : public ::mlir::RewritePattern {
  RewBetaT(::mlir::MLIRContext *context)
      : ::mlir::RewritePattern("timbda.app", 87, context, {}) {}
  ::llvm::LogicalResult matchAndRewrite(::mlir::Operation *op0,
      ::mlir::PatternRewriter &rewriter) const override {
    // Variables for capturing values and attributes used while creating ops
    ::mlir::Operation::operand_range arg(op0->getOperands());
    ::mlir::Operation::operand_range callee(op0->getOperands());
    ::timbda::TimbdaAppOp u;
    ::llvm::SmallVector<::mlir::Operation *, 4> tblgen_ops;

    // Match
    tblgen_ops.push_back(op0);
    if(::mlir::failed(static_dag_matcher_1(rewriter, op0, tblgen_ops, arg, callee, u))) {
      return ::mlir::failure();
    }
    auto castedOp0 = ::llvm::dyn_cast_or_null<::timbda::TimbdaAppOp>(op0); (void)castedOp0;
    if (!((::timbda::calleeIsNonEmptyValueTuple((*callee.begin()))))){
      return rewriter.notifyMatchFailure(op0, [&](::mlir::Diagnostic &diag) {
        diag << "entities 'callee' failed to satisfy constraint: 'callee operand defines a tup op with >= 1 member'";
      });
    }

    // Rewrite
    auto odsLoc = rewriter.getFusedLoc({tblgen_ops[0]->getLoc()}); (void)odsLoc;
    ::llvm::SmallVector<::mlir::Value, 4> tblgen_repl_values;
    auto nativeVar_0 = ::timbda::betaTRhs(rewriter, (*u.getODSResults(0).begin()), (*callee.begin()), (*arg.begin())); (void)nativeVar_0;

    for (auto v: ::llvm::SmallVector<::mlir::Value, 4>{ {nativeVar_0} }) {
      tblgen_repl_values.push_back(v);
    }

    rewriter.replaceOp(op0, tblgen_repl_values);
    return ::mlir::success();
  }
};

/* Generated from:
    dialect/TimbdaPatterns.td:255
*/
struct RewBetaT0 : public ::mlir::RewritePattern {
  RewBetaT0(::mlir::MLIRContext *context)
      : ::mlir::RewritePattern("timbda.app", 86, context, {"timbda.fail"}) {}
  ::llvm::LogicalResult matchAndRewrite(::mlir::Operation *op0,
      ::mlir::PatternRewriter &rewriter) const override {
    // Variables for capturing values and attributes used while creating ops
    ::mlir::Operation::operand_range e(op0->getOperands());
    ::mlir::Operation::operand_range members(op0->getOperands());
    ::timbda::TimbdaTupOp t;
    ::llvm::SmallVector<::mlir::Operation *, 4> tblgen_ops;

    // Match
    tblgen_ops.push_back(op0);
    auto castedOp0 = ::llvm::dyn_cast<::timbda::TimbdaAppOp>(op0); (void)castedOp0;
    {
      auto *op1 = (*castedOp0.getODSOperands(0).begin()).getDefiningOp();
      if (!(op1)){
        return rewriter.notifyMatchFailure(castedOp0, [&](::mlir::Diagnostic &diag) {
          diag << "There's no operation that defines operand 0 of castedOp0";
        });
      }
      auto castedOp1 = ::llvm::dyn_cast<::timbda::TimbdaTupOp>(op1); (void)castedOp1;
      if (!(castedOp1)){
        return rewriter.notifyMatchFailure(op1, [&](::mlir::Diagnostic &diag) {
          diag << "castedOp1 is not ::timbda::TimbdaTupOp type";
        });
      }
      t = castedOp1;
      members = castedOp1.getODSOperands(0);
      tblgen_ops.push_back(op1);
    }
    e = castedOp0.getODSOperands(1);
    if (!((::timbda::isEmptyValueTupleOp((*t.getODSResults(0).begin()))))){
      return rewriter.notifyMatchFailure(op0, [&](::mlir::Diagnostic &diag) {
        diag << "entities 't' failed to satisfy constraint: 'callee operand defines a tup op with no members'";
      });
    }

    // Rewrite
    auto odsLoc = rewriter.getFusedLoc({tblgen_ops[0]->getLoc(), tblgen_ops[1]->getLoc()}); (void)odsLoc;
    ::llvm::SmallVector<::mlir::Value, 4> tblgen_repl_values;
    ::timbda::TimbdaFailOp tblgen_TimbdaFailOp_0;
    {
      ::llvm::SmallVector<::mlir::Value, 4> tblgen_values; (void)tblgen_values;
      ::timbda::TimbdaFailOp::Properties tblgen_props; (void)tblgen_props;
      ::llvm::SmallVector<::mlir::Type, 4> tblgen_types; (void)tblgen_types;
      for (auto v: castedOp0.getODSResults(0)) {
        tblgen_types.push_back(v.getType());
      }
      tblgen_TimbdaFailOp_0 = ::timbda::TimbdaFailOp::create(rewriter, odsLoc, tblgen_types, tblgen_values, tblgen_props);
    }

    for (auto v: ::llvm::SmallVector<::mlir::Value, 4>{ tblgen_TimbdaFailOp_0.getODSResults(0) }) {
      tblgen_repl_values.push_back(v);
    }

    rewriter.replaceOp(op0, tblgen_repl_values);
    return ::mlir::success();
  }
};

/* Generated from:
    dialect/TimbdaPatterns.td:183
*/
struct RewCons : public ::mlir::RewritePattern {
  RewCons(::mlir::MLIRContext *context)
      : ::mlir::RewritePattern("timbda.prim", 85, context, {}) {}
  ::llvm::LogicalResult matchAndRewrite(::mlir::Operation *op0,
      ::mlir::PatternRewriter &rewriter) const override {
    // Variables for capturing values and attributes used while creating ops
    ::timbda::TimbdaPrimOp p;
    ::mlir::Operation::operand_range v0(op0->getOperands());
    ::mlir::Operation::operand_range t(op0->getOperands());
    ::llvm::SmallVector<::mlir::Operation *, 4> tblgen_ops;

    // Match
    tblgen_ops.push_back(op0);
    auto castedOp0 = ::llvm::dyn_cast<::timbda::TimbdaPrimOp>(op0); (void)castedOp0;
    p = castedOp0;
    {
      [[maybe_unused]] auto tblgen_attr = castedOp0.getProperties().getPrim();
      if (!(tblgen_attr)){
        return rewriter.notifyMatchFailure(castedOp0, [&](::mlir::Diagnostic &diag) {
          diag << "expected op 'timbda.prim' to have attribute 'prim' of type '::timbda::PrimAttr'";
        });
      }
      if(::mlir::failed(__mlir_ods_local_attr_constraint_TimbdaPatterns2(rewriter, castedOp0, tblgen_attr, "op 'timbda.prim' attribute 'prim' failed to satisfy constraint: 'constant attribute ::timbda::Prim::Cons'"))) {
        return ::mlir::failure();
      }
    }
    {
      auto variadic_operand_range = castedOp0.getODSOperands(0);
      if (variadic_operand_range.size() != 2) return ::mlir::failure();
      v0 = variadic_operand_range.slice(0, 1);
      {
        auto *local_op_1 = variadic_operand_range[1].getDefiningOp();
        if (!(local_op_1)){
          return rewriter.notifyMatchFailure(castedOp0, [&](::mlir::Diagnostic &diag) {
            diag << "There's no operation that defines variadic operand 0 (variadic sub-opearnd #1) of castedOp0";
          });
        }
        auto castedOp1 = ::llvm::dyn_cast<::timbda::TimbdaTupOp>(local_op_1); (void)castedOp1;
        if (!(castedOp1)){
          return rewriter.notifyMatchFailure(local_op_1, [&](::mlir::Diagnostic &diag) {
            diag << "castedOp1 is not ::timbda::TimbdaTupOp type";
          });
        }
        t = castedOp1.getODSOperands(0);
        tblgen_ops.push_back(local_op_1);
      }
    }
    if (!((::timbda::isValueOp((*v0.begin()))))){
      return rewriter.notifyMatchFailure(op0, [&](::mlir::Diagnostic &diag) {
        diag << "entities 'v0' failed to satisfy constraint: 'operand defines a value-shaped op'";
      });
    }

    // Rewrite
    auto odsLoc = rewriter.getFusedLoc({tblgen_ops[0]->getLoc(), tblgen_ops[1]->getLoc()}); (void)odsLoc;
    ::llvm::SmallVector<::mlir::Value, 4> tblgen_repl_values;
    auto nativeVar_0 = ::timbda::consRhs(rewriter, (*p.getODSResults(0).begin()), (*v0.begin()), t); (void)nativeVar_0;

    for (auto v: ::llvm::SmallVector<::mlir::Value, 4>{ {nativeVar_0} }) {
      tblgen_repl_values.push_back(v);
    }

    rewriter.replaceOp(op0, tblgen_repl_values);
    return ::mlir::success();
  }
};

/* Generated from:
    dialect/TimbdaPatterns.td:194
*/
struct RewDotDot : public ::mlir::RewritePattern {
  RewDotDot(::mlir::MLIRContext *context)
      : ::mlir::RewritePattern("timbda.prim", 85, context, {}) {}
  ::llvm::LogicalResult matchAndRewrite(::mlir::Operation *op0,
      ::mlir::PatternRewriter &rewriter) const override {
    // Variables for capturing values and attributes used while creating ops
    ::mlir::Operation::operand_range x(op0->getOperands());
    ::timbda::TimbdaPrimOp p;
    ::mlir::IntegerAttr y;
    ::llvm::SmallVector<::mlir::Operation *, 4> tblgen_ops;

    // Match
    tblgen_ops.push_back(op0);
    auto castedOp0 = ::llvm::dyn_cast<::timbda::TimbdaPrimOp>(op0); (void)castedOp0;
    p = castedOp0;
    {
      [[maybe_unused]] auto tblgen_attr = castedOp0.getProperties().getPrim();
      if (!(tblgen_attr)){
        return rewriter.notifyMatchFailure(castedOp0, [&](::mlir::Diagnostic &diag) {
          diag << "expected op 'timbda.prim' to have attribute 'prim' of type '::timbda::PrimAttr'";
        });
      }
      if(::mlir::failed(__mlir_ods_local_attr_constraint_TimbdaPatterns3(rewriter, castedOp0, tblgen_attr, "op 'timbda.prim' attribute 'prim' failed to satisfy constraint: 'constant attribute ::timbda::Prim::DotDot'"))) {
        return ::mlir::failure();
      }
    }
    {
      auto variadic_operand_range = castedOp0.getODSOperands(0);
      if (variadic_operand_range.size() != 2) return ::mlir::failure();
      x = variadic_operand_range.slice(0, 1);
      {
        auto *local_op_1 = variadic_operand_range[1].getDefiningOp();
        if (!(local_op_1)){
          return rewriter.notifyMatchFailure(castedOp0, [&](::mlir::Diagnostic &diag) {
            diag << "There's no operation that defines variadic operand 0 (variadic sub-opearnd #1) of castedOp0";
          });
        }
        if(::mlir::failed(static_dag_matcher_0(rewriter, local_op_1, tblgen_ops, y))) {
          return ::mlir::failure();
        }
        tblgen_ops.push_back(local_op_1);
      }
    }
    if (!((::timbda::isIntValueOperand((*x.begin()))))){
      return rewriter.notifyMatchFailure(op0, [&](::mlir::Diagnostic &diag) {
        diag << "entities 'x' failed to satisfy constraint: 'operand defines an int literal'";
      });
    }

    // Rewrite
    auto odsLoc = rewriter.getFusedLoc({tblgen_ops[0]->getLoc(), tblgen_ops[1]->getLoc()}); (void)odsLoc;
    ::llvm::SmallVector<::mlir::Value, 4> tblgen_repl_values;
    auto nativeVar_0 = ::timbda::dotdotRhs(rewriter, (*p.getODSResults(0).begin()), (*x.begin()), y); (void)nativeVar_0;

    for (auto v: ::llvm::SmallVector<::mlir::Value, 4>{ {nativeVar_0} }) {
      tblgen_repl_values.push_back(v);
    }

    rewriter.replaceOp(op0, tblgen_repl_values);
    return ::mlir::success();
  }
};

/* Generated from:
    dialect/TimbdaPatterns.td:100
*/
struct RewEqFail : public ::mlir::RewritePattern {
  RewEqFail(::mlir::MLIRContext *context)
      : ::mlir::RewritePattern("timbda.unify", 89, context, {"timbda.fail"}) {}
  ::llvm::LogicalResult matchAndRewrite(::mlir::Operation *op0,
      ::mlir::PatternRewriter &rewriter) const override {
    // Variables for capturing values and attributes used while creating ops
    ::mlir::Operation::operand_range rhs(op0->getOperands());
    ::mlir::Operation::operand_range lhs(op0->getOperands());
    ::llvm::SmallVector<::mlir::Operation *, 4> tblgen_ops;

    // Match
    tblgen_ops.push_back(op0);
    if(::mlir::failed(static_dag_matcher_2(rewriter, op0, tblgen_ops, rhs, lhs))) {
      return ::mlir::failure();
    }
    auto castedOp0 = ::llvm::dyn_cast_or_null<::timbda::TimbdaUnifyOp>(op0); (void)castedOp0;
    if (!((::timbda::rootMismatchPair((*lhs.begin()), (*rhs.begin()))))){
      return rewriter.notifyMatchFailure(op0, [&](::mlir::Diagnostic &diag) {
        diag << "entities 'lhs, rhs' failed to satisfy constraint: 'value pair with different root kinds, no-rule pairs excluded'";
      });
    }

    // Rewrite
    auto odsLoc = rewriter.getFusedLoc({tblgen_ops[0]->getLoc()}); (void)odsLoc;
    ::llvm::SmallVector<::mlir::Value, 4> tblgen_repl_values;
    ::timbda::TimbdaFailOp tblgen_TimbdaFailOp_0;
    {
      ::llvm::SmallVector<::mlir::Value, 4> tblgen_values; (void)tblgen_values;
      ::timbda::TimbdaFailOp::Properties tblgen_props; (void)tblgen_props;
      ::llvm::SmallVector<::mlir::Type, 4> tblgen_types; (void)tblgen_types;
      for (auto v: castedOp0.getODSResults(0)) {
        tblgen_types.push_back(v.getType());
      }
      tblgen_TimbdaFailOp_0 = ::timbda::TimbdaFailOp::create(rewriter, odsLoc, tblgen_types, tblgen_values, tblgen_props);
    }

    for (auto v: ::llvm::SmallVector<::mlir::Value, 4>{ tblgen_TimbdaFailOp_0.getODSResults(0) }) {
      tblgen_repl_values.push_back(v);
    }

    rewriter.replaceOp(op0, tblgen_repl_values);
    return ::mlir::success();
  }
};

/* Generated from:
    dialect/TimbdaPatterns.td:76
*/
struct RewEqK1 : public ::mlir::RewritePattern {
  RewEqK1(::mlir::MLIRContext *context)
      : ::mlir::RewritePattern("timbda.unify", 93, context, {}) {}
  ::llvm::LogicalResult matchAndRewrite(::mlir::Operation *op0,
      ::mlir::PatternRewriter &rewriter) const override {
    // Variables for capturing values and attributes used while creating ops
    ::mlir::Operation::operand_range rhs(op0->getOperands());
    ::mlir::Operation::operand_range lhs(op0->getOperands());
    ::llvm::SmallVector<::mlir::Operation *, 4> tblgen_ops;

    // Match
    tblgen_ops.push_back(op0);
    if(::mlir::failed(static_dag_matcher_2(rewriter, op0, tblgen_ops, rhs, lhs))) {
      return ::mlir::failure();
    }
    auto castedOp0 = ::llvm::dyn_cast_or_null<::timbda::TimbdaUnifyOp>(op0); (void)castedOp0;
    if (!((::timbda::isLiteralPair((*lhs.begin()), (*rhs.begin()), true)))){
      return rewriter.notifyMatchFailure(op0, [&](::mlir::Diagnostic &diag) {
        diag << "entities 'lhs, rhs' failed to satisfy constraint: 'both literals with the same value'";
      });
    }

    // Rewrite
    auto odsLoc = rewriter.getFusedLoc({tblgen_ops[0]->getLoc()}); (void)odsLoc;
    ::llvm::SmallVector<::mlir::Value, 4> tblgen_repl_values;

    for (auto v: ::llvm::SmallVector<::mlir::Value, 4>{ lhs }) {
      tblgen_repl_values.push_back(v);
    }

    rewriter.replaceOp(op0, tblgen_repl_values);
    return ::mlir::success();
  }
};

/* Generated from:
    dialect/TimbdaPatterns.td:82
*/
struct RewEqK2 : public ::mlir::RewritePattern {
  RewEqK2(::mlir::MLIRContext *context)
      : ::mlir::RewritePattern("timbda.unify", 92, context, {"timbda.fail"}) {}
  ::llvm::LogicalResult matchAndRewrite(::mlir::Operation *op0,
      ::mlir::PatternRewriter &rewriter) const override {
    // Variables for capturing values and attributes used while creating ops
    ::mlir::Operation::operand_range rhs(op0->getOperands());
    ::mlir::Operation::operand_range lhs(op0->getOperands());
    ::llvm::SmallVector<::mlir::Operation *, 4> tblgen_ops;

    // Match
    tblgen_ops.push_back(op0);
    if(::mlir::failed(static_dag_matcher_2(rewriter, op0, tblgen_ops, rhs, lhs))) {
      return ::mlir::failure();
    }
    auto castedOp0 = ::llvm::dyn_cast_or_null<::timbda::TimbdaUnifyOp>(op0); (void)castedOp0;
    if (!((::timbda::isLiteralPair((*lhs.begin()), (*rhs.begin()), false)))){
      return rewriter.notifyMatchFailure(op0, [&](::mlir::Diagnostic &diag) {
        diag << "entities 'lhs, rhs' failed to satisfy constraint: 'both literals with different values'";
      });
    }

    // Rewrite
    auto odsLoc = rewriter.getFusedLoc({tblgen_ops[0]->getLoc()}); (void)odsLoc;
    ::llvm::SmallVector<::mlir::Value, 4> tblgen_repl_values;
    ::timbda::TimbdaFailOp tblgen_TimbdaFailOp_0;
    {
      ::llvm::SmallVector<::mlir::Value, 4> tblgen_values; (void)tblgen_values;
      ::timbda::TimbdaFailOp::Properties tblgen_props; (void)tblgen_props;
      ::llvm::SmallVector<::mlir::Type, 4> tblgen_types; (void)tblgen_types;
      for (auto v: castedOp0.getODSResults(0)) {
        tblgen_types.push_back(v.getType());
      }
      tblgen_TimbdaFailOp_0 = ::timbda::TimbdaFailOp::create(rewriter, odsLoc, tblgen_types, tblgen_values, tblgen_props);
    }

    for (auto v: ::llvm::SmallVector<::mlir::Value, 4>{ tblgen_TimbdaFailOp_0.getODSResults(0) }) {
      tblgen_repl_values.push_back(v);
    }

    rewriter.replaceOp(op0, tblgen_repl_values);
    return ::mlir::success();
  }
};

/* Generated from:
    dialect/TimbdaPatterns.td:88
*/
struct RewEqTup1 : public ::mlir::RewritePattern {
  RewEqTup1(::mlir::MLIRContext *context)
      : ::mlir::RewritePattern("timbda.unify", 91, context, {}) {}
  ::llvm::LogicalResult matchAndRewrite(::mlir::Operation *op0,
      ::mlir::PatternRewriter &rewriter) const override {
    // Variables for capturing values and attributes used while creating ops
    ::mlir::Operation::operand_range rhs(op0->getOperands());
    ::mlir::Operation::operand_range lhs(op0->getOperands());
    ::timbda::TimbdaUnifyOp u;
    ::llvm::SmallVector<::mlir::Operation *, 4> tblgen_ops;

    // Match
    tblgen_ops.push_back(op0);
    if(::mlir::failed(static_dag_matcher_3(rewriter, op0, tblgen_ops, rhs, lhs, u))) {
      return ::mlir::failure();
    }
    auto castedOp0 = ::llvm::dyn_cast_or_null<::timbda::TimbdaUnifyOp>(op0); (void)castedOp0;
    if (!((::timbda::isTupPairLength((*lhs.begin()), (*rhs.begin()), true)))){
      return rewriter.notifyMatchFailure(op0, [&](::mlir::Diagnostic &diag) {
        diag << "entities 'lhs, rhs' failed to satisfy constraint: 'tuple pair with equal member counts'";
      });
    }

    // Rewrite
    auto odsLoc = rewriter.getFusedLoc({tblgen_ops[0]->getLoc()}); (void)odsLoc;
    ::llvm::SmallVector<::mlir::Value, 4> tblgen_repl_values;
    auto nativeVar_0 = ::timbda::eqTup1Rhs(rewriter, (*u.getODSResults(0).begin()), (*lhs.begin()), (*rhs.begin())); (void)nativeVar_0;

    for (auto v: ::llvm::SmallVector<::mlir::Value, 4>{ {nativeVar_0} }) {
      tblgen_repl_values.push_back(v);
    }

    rewriter.replaceOp(op0, tblgen_repl_values);
    return ::mlir::success();
  }
};

/* Generated from:
    dialect/TimbdaPatterns.td:94
*/
struct RewEqTup2 : public ::mlir::RewritePattern {
  RewEqTup2(::mlir::MLIRContext *context)
      : ::mlir::RewritePattern("timbda.unify", 90, context, {"timbda.fail"}) {}
  ::llvm::LogicalResult matchAndRewrite(::mlir::Operation *op0,
      ::mlir::PatternRewriter &rewriter) const override {
    // Variables for capturing values and attributes used while creating ops
    ::mlir::Operation::operand_range rhs(op0->getOperands());
    ::mlir::Operation::operand_range lhs(op0->getOperands());
    ::llvm::SmallVector<::mlir::Operation *, 4> tblgen_ops;

    // Match
    tblgen_ops.push_back(op0);
    if(::mlir::failed(static_dag_matcher_2(rewriter, op0, tblgen_ops, rhs, lhs))) {
      return ::mlir::failure();
    }
    auto castedOp0 = ::llvm::dyn_cast_or_null<::timbda::TimbdaUnifyOp>(op0); (void)castedOp0;
    if (!((::timbda::isTupPairLength((*lhs.begin()), (*rhs.begin()), false)))){
      return rewriter.notifyMatchFailure(op0, [&](::mlir::Diagnostic &diag) {
        diag << "entities 'lhs, rhs' failed to satisfy constraint: 'tuple pair with unequal member counts'";
      });
    }

    // Rewrite
    auto odsLoc = rewriter.getFusedLoc({tblgen_ops[0]->getLoc()}); (void)odsLoc;
    ::llvm::SmallVector<::mlir::Value, 4> tblgen_repl_values;
    ::timbda::TimbdaFailOp tblgen_TimbdaFailOp_0;
    {
      ::llvm::SmallVector<::mlir::Value, 4> tblgen_values; (void)tblgen_values;
      ::timbda::TimbdaFailOp::Properties tblgen_props; (void)tblgen_props;
      ::llvm::SmallVector<::mlir::Type, 4> tblgen_types; (void)tblgen_types;
      for (auto v: castedOp0.getODSResults(0)) {
        tblgen_types.push_back(v.getType());
      }
      tblgen_TimbdaFailOp_0 = ::timbda::TimbdaFailOp::create(rewriter, odsLoc, tblgen_types, tblgen_values, tblgen_props);
    }

    for (auto v: ::llvm::SmallVector<::mlir::Value, 4>{ tblgen_TimbdaFailOp_0.getODSResults(0) }) {
      tblgen_repl_values.push_back(v);
    }

    rewriter.replaceOp(op0, tblgen_repl_values);
    return ::mlir::success();
  }
};

/* Generated from:
    dialect/TimbdaPatterns.td:141
*/
struct RewGt1 : public ::mlir::RewritePattern {
  RewGt1(::mlir::MLIRContext *context)
      : ::mlir::RewritePattern("timbda.prim", 84, context, {}) {}
  ::llvm::LogicalResult matchAndRewrite(::mlir::Operation *op0,
      ::mlir::PatternRewriter &rewriter) const override {
    // Variables for capturing values and attributes used while creating ops
    ::mlir::IntegerAttr y;
    ::mlir::Operation::operand_range x(op0->getOperands());
    ::llvm::SmallVector<::mlir::Operation *, 4> tblgen_ops;

    // Match
    tblgen_ops.push_back(op0);
    auto castedOp0 = ::llvm::dyn_cast<::timbda::TimbdaPrimOp>(op0); (void)castedOp0;
    {
      [[maybe_unused]] auto tblgen_attr = castedOp0.getProperties().getPrim();
      if (!(tblgen_attr)){
        return rewriter.notifyMatchFailure(castedOp0, [&](::mlir::Diagnostic &diag) {
          diag << "expected op 'timbda.prim' to have attribute 'prim' of type '::timbda::PrimAttr'";
        });
      }
      if(::mlir::failed(__mlir_ods_local_attr_constraint_TimbdaPatterns4(rewriter, castedOp0, tblgen_attr, "op 'timbda.prim' attribute 'prim' failed to satisfy constraint: 'constant attribute ::timbda::Prim::Gt'"))) {
        return ::mlir::failure();
      }
    }
    {
      auto variadic_operand_range = castedOp0.getODSOperands(0);
      if (variadic_operand_range.size() != 2) return ::mlir::failure();
      x = variadic_operand_range.slice(0, 1);
      {
        auto *local_op_1 = variadic_operand_range[1].getDefiningOp();
        if (!(local_op_1)){
          return rewriter.notifyMatchFailure(castedOp0, [&](::mlir::Diagnostic &diag) {
            diag << "There's no operation that defines variadic operand 0 (variadic sub-opearnd #1) of castedOp0";
          });
        }
        if(::mlir::failed(static_dag_matcher_0(rewriter, local_op_1, tblgen_ops, y))) {
          return ::mlir::failure();
        }
        tblgen_ops.push_back(local_op_1);
      }
    }
    if (!((::timbda::intPairResidueFirst((*x.begin()), y)))){
      return rewriter.notifyMatchFailure(op0, [&](::mlir::Diagnostic &diag) {
        diag << "entities 'x, y' failed to satisfy constraint: 'first operand is an int literal; Z.ltb second first'";
      });
    }

    // Rewrite
    auto odsLoc = rewriter.getFusedLoc({tblgen_ops[0]->getLoc(), tblgen_ops[1]->getLoc()}); (void)odsLoc;
    ::llvm::SmallVector<::mlir::Value, 4> tblgen_repl_values;

    for (auto v: ::llvm::SmallVector<::mlir::Value, 4>{ x }) {
      tblgen_repl_values.push_back(v);
    }

    rewriter.replaceOp(op0, tblgen_repl_values);
    return ::mlir::success();
  }
};

/* Generated from:
    dialect/TimbdaPatterns.td:148
*/
struct RewGt2 : public ::mlir::RewritePattern {
  RewGt2(::mlir::MLIRContext *context)
      : ::mlir::RewritePattern("timbda.prim", 85, context, {"timbda.fail"}) {}
  ::llvm::LogicalResult matchAndRewrite(::mlir::Operation *op0,
      ::mlir::PatternRewriter &rewriter) const override {
    // Variables for capturing values and attributes used while creating ops
    ::mlir::IntegerAttr y;
    ::mlir::IntegerAttr x;
    ::llvm::SmallVector<::mlir::Operation *, 4> tblgen_ops;

    // Match
    tblgen_ops.push_back(op0);
    auto castedOp0 = ::llvm::dyn_cast<::timbda::TimbdaPrimOp>(op0); (void)castedOp0;
    {
      [[maybe_unused]] auto tblgen_attr = castedOp0.getProperties().getPrim();
      if (!(tblgen_attr)){
        return rewriter.notifyMatchFailure(castedOp0, [&](::mlir::Diagnostic &diag) {
          diag << "expected op 'timbda.prim' to have attribute 'prim' of type '::timbda::PrimAttr'";
        });
      }
      if(::mlir::failed(__mlir_ods_local_attr_constraint_TimbdaPatterns4(rewriter, castedOp0, tblgen_attr, "op 'timbda.prim' attribute 'prim' failed to satisfy constraint: 'constant attribute ::timbda::Prim::Gt'"))) {
        return ::mlir::failure();
      }
    }
    {
      auto variadic_operand_range = castedOp0.getODSOperands(0);
      if (variadic_operand_range.size() != 2) return ::mlir::failure();
      {
        auto *local_op_0 = variadic_operand_range[0].getDefiningOp();
        if (!(local_op_0)){
          return rewriter.notifyMatchFailure(castedOp0, [&](::mlir::Diagnostic &diag) {
            diag << "There's no operation that defines variadic operand 0 (variadic sub-opearnd #0) of castedOp0";
          });
        }
        auto castedOp1 = ::llvm::dyn_cast<::timbda::TimbdaIntOp>(local_op_0); (void)castedOp1;
        if (!(castedOp1)){
          return rewriter.notifyMatchFailure(local_op_0, [&](::mlir::Diagnostic &diag) {
            diag << "castedOp1 is not ::timbda::TimbdaIntOp type";
          });
        }
        {
          [[maybe_unused]] auto tblgen_attr = castedOp1.getProperties().getValue();
          if (!(tblgen_attr)){
            return rewriter.notifyMatchFailure(castedOp1, [&](::mlir::Diagnostic &diag) {
              diag << "expected op 'timbda.int' to have attribute 'value' of type '::mlir::IntegerAttr'";
            });
          }
          x = tblgen_attr;
        }
        tblgen_ops.push_back(local_op_0);
      }
      {
        auto *local_op_1 = variadic_operand_range[1].getDefiningOp();
        if (!(local_op_1)){
          return rewriter.notifyMatchFailure(castedOp0, [&](::mlir::Diagnostic &diag) {
            diag << "There's no operation that defines variadic operand 0 (variadic sub-opearnd #1) of castedOp0";
          });
        }
        if(::mlir::failed(static_dag_matcher_0(rewriter, local_op_1, tblgen_ops, y))) {
          return ::mlir::failure();
        }
        tblgen_ops.push_back(local_op_1);
      }
    }
    if (!((::timbda::intsSecondNotLessFirst(x, y)))){
      return rewriter.notifyMatchFailure(op0, [&](::mlir::Diagnostic &diag) {
        diag << "entities 'x, y' failed to satisfy constraint: 'int pair with Z.ltb b a = false'";
      });
    }

    // Rewrite
    auto odsLoc = rewriter.getFusedLoc({tblgen_ops[0]->getLoc(), tblgen_ops[1]->getLoc(), tblgen_ops[2]->getLoc()}); (void)odsLoc;
    ::llvm::SmallVector<::mlir::Value, 4> tblgen_repl_values;
    ::timbda::TimbdaFailOp tblgen_TimbdaFailOp_0;
    {
      ::llvm::SmallVector<::mlir::Value, 4> tblgen_values; (void)tblgen_values;
      ::timbda::TimbdaFailOp::Properties tblgen_props; (void)tblgen_props;
      ::llvm::SmallVector<::mlir::Type, 4> tblgen_types; (void)tblgen_types;
      for (auto v: castedOp0.getODSResults(0)) {
        tblgen_types.push_back(v.getType());
      }
      tblgen_TimbdaFailOp_0 = ::timbda::TimbdaFailOp::create(rewriter, odsLoc, tblgen_types, tblgen_values, tblgen_props);
    }

    for (auto v: ::llvm::SmallVector<::mlir::Value, 4>{ tblgen_TimbdaFailOp_0.getODSResults(0) }) {
      tblgen_repl_values.push_back(v);
    }

    rewriter.replaceOp(op0, tblgen_repl_values);
    return ::mlir::success();
  }
};

/* Generated from:
    dialect/TimbdaPatterns.td:160
*/
struct RewIsInt1 : public ::mlir::RewritePattern {
  RewIsInt1(::mlir::MLIRContext *context)
      : ::mlir::RewritePattern("timbda.prim", 84, context, {}) {}
  ::llvm::LogicalResult matchAndRewrite(::mlir::Operation *op0,
      ::mlir::PatternRewriter &rewriter) const override {
    // Variables for capturing values and attributes used while creating ops
    ::mlir::Operation::operand_range args(op0->getOperands());
    ::llvm::SmallVector<::mlir::Operation *, 4> tblgen_ops;

    // Match
    tblgen_ops.push_back(op0);
    if(::mlir::failed(static_dag_matcher_4(rewriter, op0, tblgen_ops, args))) {
      return ::mlir::failure();
    }
    auto castedOp0 = ::llvm::dyn_cast_or_null<::timbda::TimbdaPrimOp>(op0); (void)castedOp0;
    if (!((::timbda::isIntValueOperand((*args.begin()))))){
      return rewriter.notifyMatchFailure(op0, [&](::mlir::Diagnostic &diag) {
        diag << "entities 'args' failed to satisfy constraint: 'operand defines an int literal'";
      });
    }

    // Rewrite
    auto odsLoc = rewriter.getFusedLoc({tblgen_ops[0]->getLoc()}); (void)odsLoc;
    ::llvm::SmallVector<::mlir::Value, 4> tblgen_repl_values;

    for (auto v: ::llvm::SmallVector<::mlir::Value, 4>{ args }) {
      tblgen_repl_values.push_back(v);
    }

    rewriter.replaceOp(op0, tblgen_repl_values);
    return ::mlir::success();
  }
};

/* Generated from:
    dialect/TimbdaPatterns.td:171
*/
struct RewIsInt2 : public ::mlir::RewritePattern {
  RewIsInt2(::mlir::MLIRContext *context)
      : ::mlir::RewritePattern("timbda.prim", 85, context, {"timbda.fail"}) {}
  ::llvm::LogicalResult matchAndRewrite(::mlir::Operation *op0,
      ::mlir::PatternRewriter &rewriter) const override {
    // Variables for capturing values and attributes used while creating ops
    ::mlir::Operation::operand_range args(op0->getOperands());
    ::llvm::SmallVector<::mlir::Operation *, 4> tblgen_ops;

    // Match
    tblgen_ops.push_back(op0);
    if(::mlir::failed(static_dag_matcher_4(rewriter, op0, tblgen_ops, args))) {
      return ::mlir::failure();
    }
    auto castedOp0 = ::llvm::dyn_cast_or_null<::timbda::TimbdaPrimOp>(op0); (void)castedOp0;
    if (!((::timbda::isNonIntValueArityOne((*args.begin()))))){
      return rewriter.notifyMatchFailure(op0, [&](::mlir::Diagnostic &diag) {
        diag << "entities 'args' failed to satisfy constraint: 'single operand defining a value op, not an int'";
      });
    }

    // Rewrite
    auto odsLoc = rewriter.getFusedLoc({tblgen_ops[0]->getLoc()}); (void)odsLoc;
    ::llvm::SmallVector<::mlir::Value, 4> tblgen_repl_values;
    ::timbda::TimbdaFailOp tblgen_TimbdaFailOp_0;
    {
      ::llvm::SmallVector<::mlir::Value, 4> tblgen_values; (void)tblgen_values;
      ::timbda::TimbdaFailOp::Properties tblgen_props; (void)tblgen_props;
      ::llvm::SmallVector<::mlir::Type, 4> tblgen_types; (void)tblgen_types;
      for (auto v: castedOp0.getODSResults(0)) {
        tblgen_types.push_back(v.getType());
      }
      tblgen_TimbdaFailOp_0 = ::timbda::TimbdaFailOp::create(rewriter, odsLoc, tblgen_types, tblgen_values, tblgen_props);
    }

    for (auto v: ::llvm::SmallVector<::mlir::Value, 4>{ tblgen_TimbdaFailOp_0.getODSResults(0) }) {
      tblgen_repl_values.push_back(v);
    }

    rewriter.replaceOp(op0, tblgen_repl_values);
    return ::mlir::success();
  }
};

/* Generated from:
    dialect/TimbdaPatterns.td:286
*/
struct RewNorm1 : public ::mlir::RewritePattern {
  RewNorm1(::mlir::MLIRContext *context)
      : ::mlir::RewritePattern("timbda.unify", 98, context, {}) {}
  ::llvm::LogicalResult matchAndRewrite(::mlir::Operation *op0,
      ::mlir::PatternRewriter &rewriter) const override {
    // Variables for capturing values and attributes used while creating ops
    ::mlir::Operation::operand_range rhs(op0->getOperands());
    ::mlir::Operation::operand_range lhs(op0->getOperands());
    ::timbda::TimbdaUnifyOp u;
    ::llvm::SmallVector<::mlir::Operation *, 4> tblgen_ops;

    // Match
    tblgen_ops.push_back(op0);
    if(::mlir::failed(static_dag_matcher_3(rewriter, op0, tblgen_ops, rhs, lhs, u))) {
      return ::mlir::failure();
    }
    auto castedOp0 = ::llvm::dyn_cast_or_null<::timbda::TimbdaUnifyOp>(op0); (void)castedOp0;
    if (!((::timbda::isValueOp((*lhs.begin()))))){
      return rewriter.notifyMatchFailure(op0, [&](::mlir::Diagnostic &diag) {
        diag << "entities 'lhs' failed to satisfy constraint: 'operand defines a value-shaped op'";
      });
    }
    if (!((::timbda::unusedBindArmOfAnyInit((*rhs.begin()))))){
      return rewriter.notifyMatchFailure(op0, [&](::mlir::Diagnostic &diag) {
        diag << "entities 'rhs' failed to satisfy constraint: 'bind arm: body ignores its binder arg (init shape unconstrained)'";
      });
    }

    // Rewrite
    auto odsLoc = rewriter.getFusedLoc({tblgen_ops[0]->getLoc()}); (void)odsLoc;
    ::llvm::SmallVector<::mlir::Value, 4> tblgen_repl_values;
    auto nativeVar_0 = ::timbda::norm1Rhs(rewriter, (*u.getODSResults(0).begin()), (*lhs.begin()), (*rhs.begin())); (void)nativeVar_0;

    for (auto v: ::llvm::SmallVector<::mlir::Value, 4>{ {nativeVar_0} }) {
      tblgen_repl_values.push_back(v);
    }

    rewriter.replaceOp(op0, tblgen_repl_values);
    return ::mlir::success();
  }
};

/* Generated from:
    dialect/TimbdaPatterns.td:295
*/
struct RewNorm2 : public ::mlir::RewritePattern {
  RewNorm2(::mlir::MLIRContext *context)
      : ::mlir::RewritePattern("timbda.unify", 97, context, {}) {}
  ::llvm::LogicalResult matchAndRewrite(::mlir::Operation *op0,
      ::mlir::PatternRewriter &rewriter) const override {
    // Variables for capturing values and attributes used while creating ops
    ::mlir::Operation::operand_range e2(op0->getOperands());
    ::mlir::Operation::operand_range e1(op0->getOperands());
    ::mlir::Operation::operand_range lhs(op0->getOperands());
    ::timbda::TimbdaUnifyOp u;
    ::llvm::SmallVector<::mlir::Operation *, 4> tblgen_ops;

    // Match
    tblgen_ops.push_back(op0);
    auto castedOp0 = ::llvm::dyn_cast<::timbda::TimbdaUnifyOp>(op0); (void)castedOp0;
    u = castedOp0;
    lhs = castedOp0.getODSOperands(0);
    {
      auto *op1 = (*castedOp0.getODSOperands(1).begin()).getDefiningOp();
      if (!(op1)){
        return rewriter.notifyMatchFailure(castedOp0, [&](::mlir::Diagnostic &diag) {
          diag << "There's no operation that defines operand 1 of castedOp0";
        });
      }
      auto castedOp1 = ::llvm::dyn_cast<::timbda::TimbdaUnifyOp>(op1); (void)castedOp1;
      if (!(castedOp1)){
        return rewriter.notifyMatchFailure(op1, [&](::mlir::Diagnostic &diag) {
          diag << "castedOp1 is not ::timbda::TimbdaUnifyOp type";
        });
      }
      e1 = castedOp1.getODSOperands(0);
      e2 = castedOp1.getODSOperands(1);
      tblgen_ops.push_back(op1);
    }
    if (!((::timbda::isValueOp((*lhs.begin()))))){
      return rewriter.notifyMatchFailure(op0, [&](::mlir::Diagnostic &diag) {
        diag << "entities 'lhs' failed to satisfy constraint: 'operand defines a value-shaped op'";
      });
    }

    // Rewrite
    auto odsLoc = rewriter.getFusedLoc({tblgen_ops[0]->getLoc(), tblgen_ops[1]->getLoc()}); (void)odsLoc;
    ::llvm::SmallVector<::mlir::Value, 4> tblgen_repl_values;
    auto nativeVar_0 = ::timbda::norm2Rhs(rewriter, (*u.getODSResults(0).begin()), (*lhs.begin()), (*e1.begin()), (*e2.begin())); (void)nativeVar_0;

    for (auto v: ::llvm::SmallVector<::mlir::Value, 4>{ {nativeVar_0} }) {
      tblgen_repl_values.push_back(v);
    }

    rewriter.replaceOp(op0, tblgen_repl_values);
    return ::mlir::success();
  }
};

/* Generated from:
    dialect/TimbdaPatterns.td:304
*/
struct RewNorm3 : public ::mlir::RewritePattern {
  RewNorm3(::mlir::MLIRContext *context)
      : ::mlir::RewritePattern("timbda.unify", 96, context, {}) {}
  ::llvm::LogicalResult matchAndRewrite(::mlir::Operation *op0,
      ::mlir::PatternRewriter &rewriter) const override {
    // Variables for capturing values and attributes used while creating ops
    ::mlir::Operation::operand_range rhs(op0->getOperands());
    ::mlir::Operation::operand_range lhs(op0->getOperands());
    ::timbda::TimbdaUnifyOp u;
    ::llvm::SmallVector<::mlir::Operation *, 4> tblgen_ops;

    // Match
    tblgen_ops.push_back(op0);
    if(::mlir::failed(static_dag_matcher_3(rewriter, op0, tblgen_ops, rhs, lhs, u))) {
      return ::mlir::failure();
    }
    auto castedOp0 = ::llvm::dyn_cast_or_null<::timbda::TimbdaUnifyOp>(op0); (void)castedOp0;
    if (!((::timbda::unusedBindArmOfAnyInit((*lhs.begin()))))){
      return rewriter.notifyMatchFailure(op0, [&](::mlir::Diagnostic &diag) {
        diag << "entities 'lhs' failed to satisfy constraint: 'bind arm: body ignores its binder arg (init shape unconstrained)'";
      });
    }

    // Rewrite
    auto odsLoc = rewriter.getFusedLoc({tblgen_ops[0]->getLoc()}); (void)odsLoc;
    ::llvm::SmallVector<::mlir::Value, 4> tblgen_repl_values;
    auto nativeVar_0 = ::timbda::norm3Rhs(rewriter, (*u.getODSResults(0).begin()), (*lhs.begin()), (*rhs.begin())); (void)nativeVar_0;

    for (auto v: ::llvm::SmallVector<::mlir::Value, 4>{ {nativeVar_0} }) {
      tblgen_repl_values.push_back(v);
    }

    rewriter.replaceOp(op0, tblgen_repl_values);
    return ::mlir::success();
  }
};

/* Generated from:
    dialect/TimbdaPatterns.td:314
*/
struct RewNorm4 : public ::mlir::RewritePattern {
  RewNorm4(::mlir::MLIRContext *context)
      : ::mlir::RewritePattern("timbda.unify", 95, context, {}) {}
  ::llvm::LogicalResult matchAndRewrite(::mlir::Operation *op0,
      ::mlir::PatternRewriter &rewriter) const override {
    // Variables for capturing values and attributes used while creating ops
    ::mlir::Operation::operand_range e2(op0->getOperands());
    ::mlir::Operation::operand_range e1(op0->getOperands());
    ::mlir::Operation::operand_range v(op0->getOperands());
    ::timbda::TimbdaUnifyOp u;
    ::llvm::SmallVector<::mlir::Operation *, 4> tblgen_ops;

    // Match
    tblgen_ops.push_back(op0);
    auto castedOp0 = ::llvm::dyn_cast<::timbda::TimbdaUnifyOp>(op0); (void)castedOp0;
    u = castedOp0;
    {
      auto *op1 = (*castedOp0.getODSOperands(0).begin()).getDefiningOp();
      if (!(op1)){
        return rewriter.notifyMatchFailure(castedOp0, [&](::mlir::Diagnostic &diag) {
          diag << "There's no operation that defines operand 0 of castedOp0";
        });
      }
      auto castedOp1 = ::llvm::dyn_cast<::timbda::TimbdaUnifyOp>(op1); (void)castedOp1;
      if (!(castedOp1)){
        return rewriter.notifyMatchFailure(op1, [&](::mlir::Diagnostic &diag) {
          diag << "castedOp1 is not ::timbda::TimbdaUnifyOp type";
        });
      }
      v = castedOp1.getODSOperands(0);
      e1 = castedOp1.getODSOperands(1);
      tblgen_ops.push_back(op1);
    }
    e2 = castedOp0.getODSOperands(1);
    if (!((::timbda::isValueOp((*v.begin()))))){
      return rewriter.notifyMatchFailure(op0, [&](::mlir::Diagnostic &diag) {
        diag << "entities 'v' failed to satisfy constraint: 'operand defines a value-shaped op'";
      });
    }

    // Rewrite
    auto odsLoc = rewriter.getFusedLoc({tblgen_ops[0]->getLoc(), tblgen_ops[1]->getLoc()}); (void)odsLoc;
    ::llvm::SmallVector<::mlir::Value, 4> tblgen_repl_values;
    auto nativeVar_0 = ::timbda::norm4Rhs(rewriter, (*u.getODSResults(0).begin()), (*v.begin()), (*e1.begin()), (*e2.begin())); (void)nativeVar_0;

    for (auto v: ::llvm::SmallVector<::mlir::Value, 4>{ {nativeVar_0} }) {
      tblgen_repl_values.push_back(v);
    }

    rewriter.replaceOp(op0, tblgen_repl_values);
    return ::mlir::success();
  }
};

/* Generated from:
    dialect/TimbdaPatterns.td:327
*/
struct RewNorm5 : public ::mlir::RewritePattern {
  RewNorm5(::mlir::MLIRContext *context)
      : ::mlir::RewritePattern("timbda.bind", 94, context, {}) {}
  ::llvm::LogicalResult matchAndRewrite(::mlir::Operation *op0,
      ::mlir::PatternRewriter &rewriter) const override {
    // Variables for capturing values and attributes used while creating ops
    ::mlir::Operation::operand_range init(op0->getOperands());
    ::timbda::TimbdaBindOp b;
    ::llvm::SmallVector<::mlir::Operation *, 4> tblgen_ops;

    // Match
    tblgen_ops.push_back(op0);
    if(::mlir::failed(static_dag_matcher_5(rewriter, op0, tblgen_ops, init, b))) {
      return ::mlir::failure();
    }
    auto castedOp0 = ::llvm::dyn_cast_or_null<::timbda::TimbdaBindOp>(op0); (void)castedOp0;
    if (!((::timbda::bindArmOfBindArm((*b.getODSResults(0).begin()))))){
      return rewriter.notifyMatchFailure(op0, [&](::mlir::Diagnostic &diag) {
        diag << "entities 'b' failed to satisfy constraint: 'bind arm whose init operand defines a bind arm'";
      });
    }

    // Rewrite
    auto odsLoc = rewriter.getFusedLoc({tblgen_ops[0]->getLoc()}); (void)odsLoc;
    ::llvm::SmallVector<::mlir::Value, 4> tblgen_repl_values;
    auto nativeVar_0 = ::timbda::norm5Rhs(rewriter, (*b.getODSResults(0).begin())); (void)nativeVar_0;

    for (auto v: ::llvm::SmallVector<::mlir::Value, 4>{ {nativeVar_0} }) {
      tblgen_repl_values.push_back(v);
    }

    rewriter.replaceOp(op0, tblgen_repl_values);
    return ::mlir::success();
  }
};

/* Generated from:
    dialect/TimbdaPatterns.td:209
*/
struct RewPrim : public ::mlir::RewritePattern {
  RewPrim(::mlir::MLIRContext *context)
      : ::mlir::RewritePattern("timbda.prim", 85, context, {}) {}
  ::llvm::LogicalResult matchAndRewrite(::mlir::Operation *op0,
      ::mlir::PatternRewriter &rewriter) const override {
    // Variables for capturing values and attributes used while creating ops
    ::mlir::Operation::operand_range args(op0->getOperands());
    ::timbda::PrimAttr attr;
    ::timbda::TimbdaPrimOp p;
    ::llvm::SmallVector<::mlir::Operation *, 4> tblgen_ops;

    // Match
    tblgen_ops.push_back(op0);
    if(::mlir::failed(static_dag_matcher_6(rewriter, op0, tblgen_ops, args, attr, p))) {
      return ::mlir::failure();
    }
    auto castedOp0 = ::llvm::dyn_cast_or_null<::timbda::TimbdaPrimOp>(op0); (void)castedOp0;
    if (!((::timbda::primTotalIsResult((*p.getODSResults(0).begin()))))){
      return rewriter.notifyMatchFailure(op0, [&](::mlir::Diagnostic &diag) {
        diag << "entities 'p' failed to satisfy constraint: 'prim_total p vs = PRes v'";
      });
    }

    // Rewrite
    auto odsLoc = rewriter.getFusedLoc({tblgen_ops[0]->getLoc()}); (void)odsLoc;
    ::llvm::SmallVector<::mlir::Value, 4> tblgen_repl_values;
    auto nativeVar_0 = ::timbda::primTotalRhs(rewriter, (*p.getODSResults(0).begin())); (void)nativeVar_0;

    for (auto v: ::llvm::SmallVector<::mlir::Value, 4>{ {nativeVar_0} }) {
      tblgen_repl_values.push_back(v);
    }

    rewriter.replaceOp(op0, tblgen_repl_values);
    return ::mlir::success();
  }
};

/* Generated from:
    dialect/TimbdaPatterns.td:219
*/
struct RewPrimFail : public ::mlir::RewritePattern {
  RewPrimFail(::mlir::MLIRContext *context)
      : ::mlir::RewritePattern("timbda.prim", 84, context, {"timbda.fail"}) {}
  ::llvm::LogicalResult matchAndRewrite(::mlir::Operation *op0,
      ::mlir::PatternRewriter &rewriter) const override {
    // Variables for capturing values and attributes used while creating ops
    ::mlir::Operation::operand_range args(op0->getOperands());
    ::timbda::PrimAttr attr;
    ::timbda::TimbdaPrimOp p;
    ::llvm::SmallVector<::mlir::Operation *, 4> tblgen_ops;

    // Match
    tblgen_ops.push_back(op0);
    if(::mlir::failed(static_dag_matcher_6(rewriter, op0, tblgen_ops, args, attr, p))) {
      return ::mlir::failure();
    }
    auto castedOp0 = ::llvm::dyn_cast_or_null<::timbda::TimbdaPrimOp>(op0); (void)castedOp0;
    if (!((::timbda::primTotalIsFail((*p.getODSResults(0).begin()))))){
      return rewriter.notifyMatchFailure(op0, [&](::mlir::Diagnostic &diag) {
        diag << "entities 'p' failed to satisfy constraint: 'prim_total p vs = PFail'";
      });
    }

    // Rewrite
    auto odsLoc = rewriter.getFusedLoc({tblgen_ops[0]->getLoc()}); (void)odsLoc;
    ::llvm::SmallVector<::mlir::Value, 4> tblgen_repl_values;
    ::timbda::TimbdaFailOp tblgen_TimbdaFailOp_0;
    {
      ::llvm::SmallVector<::mlir::Value, 4> tblgen_values; (void)tblgen_values;
      ::timbda::TimbdaFailOp::Properties tblgen_props; (void)tblgen_props;
      ::llvm::SmallVector<::mlir::Type, 4> tblgen_types; (void)tblgen_types;
      for (auto v: castedOp0.getODSResults(0)) {
        tblgen_types.push_back(v.getType());
      }
      tblgen_TimbdaFailOp_0 = ::timbda::TimbdaFailOp::create(rewriter, odsLoc, tblgen_types, tblgen_values, tblgen_props);
    }

    for (auto v: ::llvm::SmallVector<::mlir::Value, 4>{ tblgen_TimbdaFailOp_0.getODSResults(0) }) {
      tblgen_repl_values.push_back(v);
    }

    rewriter.replaceOp(op0, tblgen_repl_values);
    return ::mlir::success();
  }
};

/* Generated from:
    dialect/TimbdaPatterns.td:276
*/
struct RewSeq : public ::mlir::RewritePattern {
  RewSeq(::mlir::MLIRContext *context)
      : ::mlir::RewritePattern("timbda.bind", 99, context, {}) {}
  ::llvm::LogicalResult matchAndRewrite(::mlir::Operation *op0,
      ::mlir::PatternRewriter &rewriter) const override {
    // Variables for capturing values and attributes used while creating ops
    ::mlir::Operation::operand_range init(op0->getOperands());
    ::timbda::TimbdaBindOp b;
    ::llvm::SmallVector<::mlir::Operation *, 4> tblgen_ops;

    // Match
    tblgen_ops.push_back(op0);
    if(::mlir::failed(static_dag_matcher_5(rewriter, op0, tblgen_ops, init, b))) {
      return ::mlir::failure();
    }
    auto castedOp0 = ::llvm::dyn_cast_or_null<::timbda::TimbdaBindOp>(op0); (void)castedOp0;
    if (!((::timbda::unusedBindArm((*b.getODSResults(0).begin()))))){
      return rewriter.notifyMatchFailure(op0, [&](::mlir::Diagnostic &diag) {
        diag << "entities 'b' failed to satisfy constraint: 'bind arm: init operand is a value op, body ignores its binder arg'";
      });
    }

    // Rewrite
    auto odsLoc = rewriter.getFusedLoc({tblgen_ops[0]->getLoc()}); (void)odsLoc;
    ::llvm::SmallVector<::mlir::Value, 4> tblgen_repl_values;
    auto nativeVar_0 = ::timbda::seqRhs(rewriter, (*b.getODSResults(0).begin())); (void)nativeVar_0;

    for (auto v: ::llvm::SmallVector<::mlir::Value, 4>{ {nativeVar_0} }) {
      tblgen_repl_values.push_back(v);
    }

    rewriter.replaceOp(op0, tblgen_repl_values);
    return ::mlir::success();
  }
};

[[maybe_unused]] void populateWithGenerated(::mlir::RewritePatternSet &patterns) {
  patterns.add<RewAdd>(patterns.getContext());
  patterns.add<RewBetaL>(patterns.getContext());
  patterns.add<RewBetaT>(patterns.getContext());
  patterns.add<RewBetaT0>(patterns.getContext());
  patterns.add<RewCons>(patterns.getContext());
  patterns.add<RewDotDot>(patterns.getContext());
  patterns.add<RewEqFail>(patterns.getContext());
  patterns.add<RewEqK1>(patterns.getContext());
  patterns.add<RewEqK2>(patterns.getContext());
  patterns.add<RewEqTup1>(patterns.getContext());
  patterns.add<RewEqTup2>(patterns.getContext());
  patterns.add<RewGt1>(patterns.getContext());
  patterns.add<RewGt2>(patterns.getContext());
  patterns.add<RewIsInt1>(patterns.getContext());
  patterns.add<RewIsInt2>(patterns.getContext());
  patterns.add<RewNorm1>(patterns.getContext());
  patterns.add<RewNorm2>(patterns.getContext());
  patterns.add<RewNorm3>(patterns.getContext());
  patterns.add<RewNorm4>(patterns.getContext());
  patterns.add<RewNorm5>(patterns.getContext());
  patterns.add<RewPrim>(patterns.getContext());
  patterns.add<RewPrimFail>(patterns.getContext());
  patterns.add<RewSeq>(patterns.getContext());
}
