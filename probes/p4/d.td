include "hdr.td"
def HnfMatch : NativeCodeCall<"::timbda::matchHnfValue($_self, rewriter, $0)">;
def SeqRhs : NativeCodeCall<"::timbda::seqRewrite(rewriter, $0)">;
def : Pat<(TimbdaBindOp (HnfMatch $init)), (SeqRhs $init)>;
