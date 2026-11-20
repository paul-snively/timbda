include "hdr.td"
def : Pat<(TimbdaUnifyOp $lhs, $rhs),
          (TimbdaPrimOp ConstantEnumCase<Timbda_PrimAttr, "isInt">, (variadic $lhs, $rhs))>;
