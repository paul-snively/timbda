include "hdr.td"
def NotIntMatch : NativeCodeCall<"::timbda::matchNotIntValue($_self, rewriter, $0)">;
def : Pat<(TimbdaPrimOp ConstantEnumCase<Timbda_PrimAttr, "isInt">,
           (variadic (NotIntMatch $x))),
          (TimbdaFailOp)>;
