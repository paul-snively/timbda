include "hdr.td"
def IntRhs : NativeCodeCall<"::timbda::identityValue(rewriter, $0)">;
def : Pat<(TimbdaPrimOp ConstantEnumCase<Timbda_PrimAttr, "add">,
           (variadic (TimbdaIntOp AnyIntegerAttr:$x), (TimbdaIntOp AnyIntegerAttr:$y))),
          (IntRhs $y)>;
