// Timbda-0 stub dialect (M-1 skeleton only).
// Real ODS content lands with the Timbda-0 .td records (M-2+).
include "mlir/IR/DialectBase.td"

def Timbda_Dialect : Dialect {
  let name = "timbda";
  let cppNamespace = "::timbda";
  let summary = "Timbda-0 canonicalization stub dialect";
  let description = [{
    M-1 placeholder: proves the dialect builds against the hermetic-llvm
    MLIR vintage. Ops, attributes and verifier come with M-2.
  }];
}
