// tests/lit/canonicalize/prim-fold.mlir - M2 skeleton (docs/PLAN.md sec. 5.0
// M2: the CertiRocq->C / Lower.v carrier and a timbda-aware opt binary).
// There is no timbda-aware mlir-opt yet, so the timbda-opt feature requirement
// below keeps this test UNSUPPORTED in checks.dialect-lit-tests - an honest
// skip, not a fake pass.  When the binary lands the gate lane sets TIMBDA_OPT;
// the exact module body and the folded output below are then pinned from the
// corpus corner's evidence (tests/corpus), not invented here.
//
// REQUIRES: timbda-opt
// RUN: %timbda_opt %s --canonicalize | FileCheck %s

// prim PAdd over two int literals: RewAdd (fig 10, rank 15) must fire and
// leave the folded literal, with the two literal operands erased.
// TODO(M2): real IR + exact CHECKs pinned from tests/corpus evidence.

// CHECK-LABEL: prim_add
// CHECK: timbda.prim
