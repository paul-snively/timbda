#include "TimbdaDialect.h"

// tblgen declares initialize() but only emits a definition when the dialect
// has ops/attrs/types; the M-1 stub has none, so provide the empty one.
namespace timbda {
void TimbdaDialect::initialize() {}
} // namespace timbda

#include "dialect/TimbdaDialect.cpp.inc"
