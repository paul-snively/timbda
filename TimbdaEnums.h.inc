/*===- TableGen'erated file -------------------------------------*- C++ -*-===*\
|*                                                                            *|
|* Enum Utility Declarations                                                  *|
|*                                                                            *|
|* Automatically generated file, do not edit!                                 *|
|* From: Timbda.td                                                            *|
|*                                                                            *|
\*===----------------------------------------------------------------------===*/

namespace timbda {

// iter composition (coq/Syntax.v `IterComb`)
enum class IterComb : uint64_t {
  All = 0,
  If = 1,
  For = 2,
};

::std::optional<IterComb> symbolizeIterComb(uint64_t);
::llvm::StringRef stringifyIterComb(IterComb);
::std::optional<IterComb> symbolizeIterComb(::llvm::StringRef);
inline constexpr unsigned getMaxEnumValForIterComb() {
  return 2;
}


inline ::llvm::StringRef stringifyEnum(IterComb enumValue) {
  return stringifyIterComb(enumValue);
}

template <typename EnumType>
::std::optional<EnumType> symbolizeEnum(::llvm::StringRef);

template <>
inline ::std::optional<IterComb> symbolizeEnum<IterComb>(::llvm::StringRef str) {
  return symbolizeIterComb(str);
}

class IterCombAttr : public ::mlir::IntegerAttr {
public:
  using ValueType = IterComb;
  using ::mlir::IntegerAttr::IntegerAttr;
  static bool classof(::mlir::Attribute attr);
  static IterCombAttr get(::mlir::MLIRContext *context, IterComb val);
  IterComb getValue() const;
};

} // namespace timbda

namespace mlir {
template <typename T, typename>
struct FieldParser;

template<>
struct FieldParser<::timbda::IterComb, ::timbda::IterComb> {
  template <typename ParserT>
  static FailureOr<::timbda::IterComb> parse(ParserT &parser) {
    // Parse the keyword/string containing the enum.
    std::string enumKeyword;
    auto loc = parser.getCurrentLocation();
    if (failed(parser.parseOptionalKeywordOrString(&enumKeyword)))
      return parser.emitError(loc, "expected keyword for iter composition (coq/Syntax.v `IterComb`)");

    // Symbolize the keyword.
    if (::std::optional<::timbda::IterComb> attr = ::timbda::symbolizeEnum<::timbda::IterComb>(enumKeyword))
      return *attr;
    return parser.emitError(loc, "expected one of [all, if, for] for iter composition (coq/Syntax.v `IterComb`), got: ") << enumKeyword;
  }
};

/// Support for std::optional, useful in attribute/type definition where the enum is
/// used as:
///
///    let parameters = (ins OptionalParameter<"std::optional<TheEnumName>">:$value);
template<>
struct FieldParser<std::optional<::timbda::IterComb>, std::optional<::timbda::IterComb>> {
  template <typename ParserT>
  static FailureOr<std::optional<::timbda::IterComb>> parse(ParserT &parser) {
    // Parse the keyword/string containing the enum.
    std::string enumKeyword;
    auto loc = parser.getCurrentLocation();
    if (failed(parser.parseOptionalKeywordOrString(&enumKeyword, {"all", "if", "for"})))
      return std::optional<::timbda::IterComb>{};

    // Symbolize the keyword.
    if (::std::optional<::timbda::IterComb> attr = ::timbda::symbolizeEnum<::timbda::IterComb>(enumKeyword))
      return attr;
    return parser.emitError(loc, "expected one of [all, if, for] for iter composition (coq/Syntax.v `IterComb`), got: ") << enumKeyword;
  }
};
} // namespace mlir

namespace llvm {
inline ::llvm::raw_ostream &operator<<(::llvm::raw_ostream &p, ::timbda::IterComb value) {
  auto valueStr = stringifyEnum(value);
  return p << valueStr;
}
} // namespace llvm

namespace llvm {
template<> struct DenseMapInfo<::timbda::IterComb> {
  using StorageInfo = ::llvm::DenseMapInfo<uint64_t>;

  static unsigned getHashValue(const ::timbda::IterComb &val) {
    return StorageInfo::getHashValue(static_cast<uint64_t>(val));
  }

  static bool isEqual(const ::timbda::IterComb &lhs, const ::timbda::IterComb &rhs) {
    return lhs == rhs;
  }
};
}

namespace timbda {

// verse primops (coq/Syntax.v `Prim`)
enum class Prim : uint64_t {
  Add = 0,
  Sub = 1,
  Mul = 2,
  Div = 3,
  Neg = 4,
  Pls = 5,
  Gt = 6,
  Lt = 7,
  Geq = 8,
  Leq = 9,
  Neq = 10,
  IsInt = 11,
  IsBool = 12,
  IsUnit = 13,
  Cons = 14,
  Cons2 = 15,
  DotDot = 16,
  ArrLen = 17,
};

::std::optional<Prim> symbolizePrim(uint64_t);
::llvm::StringRef stringifyPrim(Prim);
::std::optional<Prim> symbolizePrim(::llvm::StringRef);
inline constexpr unsigned getMaxEnumValForPrim() {
  return 17;
}


inline ::llvm::StringRef stringifyEnum(Prim enumValue) {
  return stringifyPrim(enumValue);
}

template <typename EnumType>
::std::optional<EnumType> symbolizeEnum(::llvm::StringRef);

template <>
inline ::std::optional<Prim> symbolizeEnum<Prim>(::llvm::StringRef str) {
  return symbolizePrim(str);
}

class PrimAttr : public ::mlir::IntegerAttr {
public:
  using ValueType = Prim;
  using ::mlir::IntegerAttr::IntegerAttr;
  static bool classof(::mlir::Attribute attr);
  static PrimAttr get(::mlir::MLIRContext *context, Prim val);
  Prim getValue() const;
};

} // namespace timbda

namespace mlir {
template <typename T, typename>
struct FieldParser;

template<>
struct FieldParser<::timbda::Prim, ::timbda::Prim> {
  template <typename ParserT>
  static FailureOr<::timbda::Prim> parse(ParserT &parser) {
    // Parse the keyword/string containing the enum.
    std::string enumKeyword;
    auto loc = parser.getCurrentLocation();
    if (failed(parser.parseOptionalKeywordOrString(&enumKeyword)))
      return parser.emitError(loc, "expected keyword for verse primops (coq/Syntax.v `Prim`)");

    // Symbolize the keyword.
    if (::std::optional<::timbda::Prim> attr = ::timbda::symbolizeEnum<::timbda::Prim>(enumKeyword))
      return *attr;
    return parser.emitError(loc, "expected one of [add, sub, mul, div, neg, pls, gt, lt, geq, leq, neq, isInt, isBool, isUnit, cons, cons2, dotdot, arrLen] for verse primops (coq/Syntax.v `Prim`), got: ") << enumKeyword;
  }
};

/// Support for std::optional, useful in attribute/type definition where the enum is
/// used as:
///
///    let parameters = (ins OptionalParameter<"std::optional<TheEnumName>">:$value);
template<>
struct FieldParser<std::optional<::timbda::Prim>, std::optional<::timbda::Prim>> {
  template <typename ParserT>
  static FailureOr<std::optional<::timbda::Prim>> parse(ParserT &parser) {
    // Parse the keyword/string containing the enum.
    std::string enumKeyword;
    auto loc = parser.getCurrentLocation();
    if (failed(parser.parseOptionalKeywordOrString(&enumKeyword, {"add", "sub", "mul", "div", "neg", "pls", "gt", "lt", "geq", "leq", "neq", "isInt", "isBool", "isUnit", "cons", "cons2", "dotdot", "arrLen"})))
      return std::optional<::timbda::Prim>{};

    // Symbolize the keyword.
    if (::std::optional<::timbda::Prim> attr = ::timbda::symbolizeEnum<::timbda::Prim>(enumKeyword))
      return attr;
    return parser.emitError(loc, "expected one of [add, sub, mul, div, neg, pls, gt, lt, geq, leq, neq, isInt, isBool, isUnit, cons, cons2, dotdot, arrLen] for verse primops (coq/Syntax.v `Prim`), got: ") << enumKeyword;
  }
};
} // namespace mlir

namespace llvm {
inline ::llvm::raw_ostream &operator<<(::llvm::raw_ostream &p, ::timbda::Prim value) {
  auto valueStr = stringifyEnum(value);
  return p << valueStr;
}
} // namespace llvm

namespace llvm {
template<> struct DenseMapInfo<::timbda::Prim> {
  using StorageInfo = ::llvm::DenseMapInfo<uint64_t>;

  static unsigned getHashValue(const ::timbda::Prim &val) {
    return StorageInfo::getHashValue(static_cast<uint64_t>(val));
  }

  static bool isEqual(const ::timbda::Prim &lhs, const ::timbda::Prim &rhs) {
    return lhs == rhs;
  }
};
}

