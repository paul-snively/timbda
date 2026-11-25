# timbda dialect lit config (M1 item 2, docs/PLAN.md sec. 5.0).
# Consumed by the checks.dialect-lit-tests gate lane (nixpkgs `lit` +
# FileCheck from the llvmPackages_23 pin); see tools/build/nix-gate.sh.
#
# Substitutions:
#   %timbda_drr_inc  the bazel mlir-tblgen -gen-rewriters output for
#                    dialect/TimbdaPatterns.td.  The gate refuses without it
#                    (stale/missing prebuilt evidence is a red gate, never a
#                    silent skip - same discipline as checks.bazel-native-tests).
#   %timbda_opt      a timbda-aware mlir-opt binary.  There is none yet (the
#                    Lower.v/T7 + opt tool wiring is M2 work), so the
#                    canonicalize/ skeletons carry REQUIRES: timbda-opt and
#                    report UNSUPPORTED - an honest skip, not a fake pass.

import os
import tempfile

import lit.formats

config.name = "timbda-dialect"
config.suffixes = [".check", ".mlir"]
config.excludes = ["lit.cfg.py"]
config.test_format = lit.formats.ShTest(execute_external=True)

# ShTest writes its script + Output/ scratch next to test.getExecPath(),
# which defaults to the source tree.  The gate runs lit against the nix store
# copy - read-only - so the exec root must live elsewhere (measured: a
# PermissionError on .../tests/lit/pdll/Output surfaced as UNRESOLVED).
# Scratch in a fresh temp dir also keeps the source tree clean for jj/git.
config.test_exec_root = tempfile.mkdtemp(prefix="timbda-lit-exec-")

drr_inc = os.environ.get("TIMBDA_DRR_INC")
if not drr_inc:
    lit_config.fatal(
        "TIMBDA_DRR_INC must point at the bazel-generated "
        "dialect/TimbdaCanonicalization.cpp.inc (run: nix develop .#cpp -c "
        "tools/build/bazel-lane.sh; the gate lane sets it)"
    )
config.substitutions.append(("%timbda_drr_inc", drr_inc))

timbda_opt = os.environ.get("TIMBDA_OPT")
if timbda_opt:
    config.available_features.add("timbda-opt")
    config.substitutions.append(("%timbda_opt", timbda_opt))
