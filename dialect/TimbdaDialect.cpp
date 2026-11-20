//===- TimbdaDialect.cpp - Timbda-0 dialect registration ------------------===//
//
// Dialect registration plus the generated enum, attribute and type bodies
// (dialect/Timbda.td).  The ops' generated bodies compile in TimbdaOps.cpp;
// the Verse kernel rewrite rules live in TimbdaCanonicalization.cpp.
//
//===----------------------------------------------------------------------===//

#include "dialect/TimbdaDialect.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/DialectImplementation.h"

#include "llvm/ADT/TypeSwitch.h"

void timbda::TimbdaDialect::initialize() {
  addOperations<
#define GET_OP_LIST
#include "dialect/TimbdaOps.cpp.inc"
      >();
  addAttributes<
#define GET_ATTRDEF_LIST
#include "dialect/TimbdaAttributes.cpp.inc"
      >();
  addTypes<
#define GET_TYPEDEF_LIST
#include "dialect/TimbdaTypes.cpp.inc"
      >();
}

// The dialect constructor (`loadDialect` entry point) and its type/attribute
// registries.
#include "dialect/TimbdaDialect.cpp.inc"

// `PrimAttr` / `IterCombAttr` bodies, including `TimbdaDialect::parseAttribute`
// and `TimbdaDialect::printAttribute`.
#define GET_ATTRDEF_CLASSES
#include "dialect/TimbdaAttributes.cpp.inc"

// `stringifyPrim` / `symbolizePrim` / `stringifyIterComb` / `symbolizeIterComb`
// and the enum `FieldParser` instantiations.
#include "dialect/TimbdaEnums.cpp.inc"

// `!timbda.value` bodies, including `TimbdaDialect::parseType` / `printType`.
#define GET_TYPEDEF_CLASSES
#include "dialect/TimbdaTypes.cpp.inc"
