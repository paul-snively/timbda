/*===- TableGen'erated file -------------------------------------*- C++ -*-===*\
|*                                                                            *|
|* Enum Utility Definitions                                                   *|
|*                                                                            *|
|* Automatically generated file, do not edit!                                 *|
|* From: Timbda.td                                                            *|
|*                                                                            *|
\*===----------------------------------------------------------------------===*/

namespace timbda {

::llvm::StringRef stringifyIterComb(IterComb val) {
  switch (val) {
    case IterComb::All: return "all";
    case IterComb::If: return "if";
    case IterComb::For: return "for";
  }
  return "";
}

::std::optional<IterComb> symbolizeIterComb(::llvm::StringRef str) {
  return ::llvm::StringSwitch<::std::optional<IterComb>>(str)
      .Case("all", IterComb::All)
      .Case("if", IterComb::If)
      .Case("for", IterComb::For)
      .Default(::std::nullopt);
}
::std::optional<IterComb> symbolizeIterComb(uint64_t value) {
  switch (value) {
  case 0: return IterComb::All;
  case 1: return IterComb::If;
  case 2: return IterComb::For;
  default: return ::std::nullopt;
  }
}

bool IterCombAttr::classof(::mlir::Attribute attr) {
  return (((::llvm::isa<::mlir::IntegerAttr>(attr))) && ((::llvm::cast<::mlir::IntegerAttr>(attr).getType().isSignlessInteger(64)))) && (((
    ::llvm::cast<::mlir::IntegerAttr>(attr).getValue().eq(::llvm::APInt(64, 0)))) || ((
    ::llvm::cast<::mlir::IntegerAttr>(attr).getValue().eq(::llvm::APInt(64, 1)))) || ((
    ::llvm::cast<::mlir::IntegerAttr>(attr).getValue().eq(::llvm::APInt(64, 2)))));
}
IterCombAttr IterCombAttr::get(::mlir::MLIRContext *context, IterComb val) {
  ::mlir::IntegerType intType = ::mlir::IntegerType::get(context, 64);
  ::mlir::IntegerAttr baseAttr = ::mlir::IntegerAttr::get(intType, static_cast<uint64_t>(val));
  return ::llvm::cast<IterCombAttr>(baseAttr);
}
IterComb IterCombAttr::getValue() const {
  return static_cast<IterComb>(::mlir::IntegerAttr::getValue().getZExtValue());
}

} // namespace timbda
namespace timbda {

::llvm::StringRef stringifyPrim(Prim val) {
  switch (val) {
    case Prim::Add: return "add";
    case Prim::Sub: return "sub";
    case Prim::Mul: return "mul";
    case Prim::Div: return "div";
    case Prim::Neg: return "neg";
    case Prim::Pls: return "pls";
    case Prim::Gt: return "gt";
    case Prim::Lt: return "lt";
    case Prim::Geq: return "geq";
    case Prim::Leq: return "leq";
    case Prim::Neq: return "neq";
    case Prim::IsInt: return "isInt";
    case Prim::IsBool: return "isBool";
    case Prim::IsUnit: return "isUnit";
    case Prim::Cons: return "cons";
    case Prim::Cons2: return "cons2";
    case Prim::DotDot: return "dotdot";
    case Prim::ArrLen: return "arrLen";
  }
  return "";
}

::std::optional<Prim> symbolizePrim(::llvm::StringRef str) {
  return ::llvm::StringSwitch<::std::optional<Prim>>(str)
      .Case("add", Prim::Add)
      .Case("sub", Prim::Sub)
      .Case("mul", Prim::Mul)
      .Case("div", Prim::Div)
      .Case("neg", Prim::Neg)
      .Case("pls", Prim::Pls)
      .Case("gt", Prim::Gt)
      .Case("lt", Prim::Lt)
      .Case("geq", Prim::Geq)
      .Case("leq", Prim::Leq)
      .Case("neq", Prim::Neq)
      .Case("isInt", Prim::IsInt)
      .Case("isBool", Prim::IsBool)
      .Case("isUnit", Prim::IsUnit)
      .Case("cons", Prim::Cons)
      .Case("cons2", Prim::Cons2)
      .Case("dotdot", Prim::DotDot)
      .Case("arrLen", Prim::ArrLen)
      .Default(::std::nullopt);
}
::std::optional<Prim> symbolizePrim(uint64_t value) {
  switch (value) {
  case 0: return Prim::Add;
  case 1: return Prim::Sub;
  case 2: return Prim::Mul;
  case 3: return Prim::Div;
  case 4: return Prim::Neg;
  case 5: return Prim::Pls;
  case 6: return Prim::Gt;
  case 7: return Prim::Lt;
  case 8: return Prim::Geq;
  case 9: return Prim::Leq;
  case 10: return Prim::Neq;
  case 11: return Prim::IsInt;
  case 12: return Prim::IsBool;
  case 13: return Prim::IsUnit;
  case 14: return Prim::Cons;
  case 15: return Prim::Cons2;
  case 16: return Prim::DotDot;
  case 17: return Prim::ArrLen;
  default: return ::std::nullopt;
  }
}

bool PrimAttr::classof(::mlir::Attribute attr) {
  return (((::llvm::isa<::mlir::IntegerAttr>(attr))) && ((::llvm::cast<::mlir::IntegerAttr>(attr).getType().isSignlessInteger(64)))) && (((
    ::llvm::cast<::mlir::IntegerAttr>(attr).getValue().eq(::llvm::APInt(64, 0)))) || ((
    ::llvm::cast<::mlir::IntegerAttr>(attr).getValue().eq(::llvm::APInt(64, 1)))) || ((
    ::llvm::cast<::mlir::IntegerAttr>(attr).getValue().eq(::llvm::APInt(64, 2)))) || ((
    ::llvm::cast<::mlir::IntegerAttr>(attr).getValue().eq(::llvm::APInt(64, 3)))) || ((
    ::llvm::cast<::mlir::IntegerAttr>(attr).getValue().eq(::llvm::APInt(64, 4)))) || ((
    ::llvm::cast<::mlir::IntegerAttr>(attr).getValue().eq(::llvm::APInt(64, 5)))) || ((
    ::llvm::cast<::mlir::IntegerAttr>(attr).getValue().eq(::llvm::APInt(64, 6)))) || ((
    ::llvm::cast<::mlir::IntegerAttr>(attr).getValue().eq(::llvm::APInt(64, 7)))) || ((
    ::llvm::cast<::mlir::IntegerAttr>(attr).getValue().eq(::llvm::APInt(64, 8)))) || ((
    ::llvm::cast<::mlir::IntegerAttr>(attr).getValue().eq(::llvm::APInt(64, 9)))) || ((
    ::llvm::cast<::mlir::IntegerAttr>(attr).getValue().eq(::llvm::APInt(64, 10)))) || ((
    ::llvm::cast<::mlir::IntegerAttr>(attr).getValue().eq(::llvm::APInt(64, 11)))) || ((
    ::llvm::cast<::mlir::IntegerAttr>(attr).getValue().eq(::llvm::APInt(64, 12)))) || ((
    ::llvm::cast<::mlir::IntegerAttr>(attr).getValue().eq(::llvm::APInt(64, 13)))) || ((
    ::llvm::cast<::mlir::IntegerAttr>(attr).getValue().eq(::llvm::APInt(64, 14)))) || ((
    ::llvm::cast<::mlir::IntegerAttr>(attr).getValue().eq(::llvm::APInt(64, 15)))) || ((
    ::llvm::cast<::mlir::IntegerAttr>(attr).getValue().eq(::llvm::APInt(64, 16)))) || ((
    ::llvm::cast<::mlir::IntegerAttr>(attr).getValue().eq(::llvm::APInt(64, 17)))));
}
PrimAttr PrimAttr::get(::mlir::MLIRContext *context, Prim val) {
  ::mlir::IntegerType intType = ::mlir::IntegerType::get(context, 64);
  ::mlir::IntegerAttr baseAttr = ::mlir::IntegerAttr::get(intType, static_cast<uint64_t>(val));
  return ::llvm::cast<PrimAttr>(baseAttr);
}
Prim PrimAttr::getValue() const {
  return static_cast<Prim>(::mlir::IntegerAttr::getValue().getZExtValue());
}

} // namespace timbda
