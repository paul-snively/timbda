include "hdr.td"
def : Pat<(TimbdaUnifyOp $lhs, $rhs), (TimbdaBindOp $lhs)>;
