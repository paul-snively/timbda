#include <cstdio>

#include "mlir/IR/DialectRegistry.h"
#include "mlir/IR/MLIRContext.h"

#include "TimbdaDialect.h"

int main() {
  mlir::DialectRegistry registry;
  registry.insert<timbda::TimbdaDialect>();
  mlir::MLIRContext context(registry);
  mlir::Dialect *dialect = context.getOrLoadDialect("timbda");
  if (!dialect) {
    std::fprintf(stderr, "FAIL: timbda dialect not loaded\n");
    return 1;
  }
  std::printf("timbda-dialect-ok timbda\n");
  return 0;
}
