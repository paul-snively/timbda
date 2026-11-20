//===- TimbdaDialect.h - Timbda-0 (Core Verse) dialect ----------*- C++ -*-===//
//
// Timbda-0 expression dialect: the ops, the `!timbda.value` type and the
// primop/iter enum attributes generated from dialect/Timbda.td.  The canonical-
// izer rewriters that rewrite this dialect's rows live in
// dialect/TimbdaCanonicalization.h.
//
//===----------------------------------------------------------------------===//

#pragma once

#include "mlir/Bytecode/BytecodeOpInterface.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Dialect.h"
#include "mlir/IR/OpDefinition.h"
#include "mlir/IR/Region.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"

// Dialect class (coq name space `timbda`, `!timbda.<op>` mnemonics).
#include "dialect/TimbdaDialect.h.inc"

// Enum attributes: `::timbda::Prim` (coq/Syntax.v `Prim`, 18 ctors) and
// `::timbda::IterComb` (`all | if | for`), plus their `PrimAttr` / `IterCombAttr`
// spellings and the dialect's attribute parse/print.
#include "dialect/TimbdaEnums.h.inc"

#define GET_ATTRDEF_CLASSES
#include "dialect/TimbdaAttributes.h.inc"

// `!timbda.value`: every Timbda expression yields exactly one Verse value.
#define GET_TYPEDEF_CLASSES
#include "dialect/TimbdaTypes.h.inc"

// Ops: unit/bool/int/tup/fail values, glob channels, lambda/delay, `app`,
// `bind`, `unify`, `or`, `block`, `prim`, `iter`, and the block terminators.
#define GET_OP_CLASSES
#include "dialect/TimbdaOps.h.inc"
