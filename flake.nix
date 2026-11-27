{
  description = "Timbda-0 verified compiler; M-1 build-infra skeleton (PLAN.md step 0)";

  # All source pins mirror tools/pins/pins.toml (flake_input names must match);
  # CI asserts flake.lock == pins.toml via tools/pins/pins.py.
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/b349185bb79c7cf7ad8ea8c097931730bf473c71";
    # flake = false: these upstreams are source-only (no flake.nix) — we build them
    # with our own derivations (the Coq stack below); the inputs exist to lock revisions.
    mlir-wasm-dialect.url = "github:CMUAbstract/mlir-wasm-dialect/6be18d00a0c1472a4415f24deb9ba72101c8132e";
    mlir-wasm-dialect.flake = false;
    ctrees.url = "github:vellvm/ctrees/cabcf9bf24b0f459204a7da19ac01b7697ff04e3";
    ctrees.flake = false;
    interaction-trees.url = "github:DeepSpec/InteractionTrees/284d42248a3c5517cff9f582e335fcee2f6bdc1f";
    interaction-trees.flake = false;
    coq-ext-lib.url = "github:rocq-community/coq-ext-lib/c5cdb83d48786ca2680c6d817c19bb99f68d4ca3";
    coq-ext-lib.flake = false;
    # tag v1.21, not master: master needs rocq >= 9.2 (pins [formal.coinduction] note)
    coinduction.url = "github:damien-pous/coinduction/a88f0f4f170dcb9b24e3d470c76801a765423598";
    coinduction.flake = false;
    paco.url = "github:snu-sf/paco/d0561bf7f0a96cac486ba3bd8ca0b72ce01fb9cf";
    paco.flake = false;
    certirocq.url = "github:CertiRocq/CertiRocq/943b52ae654708130f241ccf8a50ecb95a7956e2";
    certirocq.flake = false;
    veriffi.url = "github:CertiRocq/VeriFFI/7e8cd8e7b631be066407f86c82ff60b6fc63ae0b";
    veriffi.flake = false;
    verse-semantics.url = "github:augustss/verse-semantics/d0eababfb7a5662f40bc7de45a596cb925445b8d";
    verse-semantics.flake = false;
  };

  outputs = { self, nixpkgs, ... }@inp:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: builtins.listToAttrs (map (system: {
        name = system;
        value = f system (import nixpkgs {
          inherit system;
          # Narrowed unfree gate (2026-11-25, M2 toolchain): CompCert only.
          # pins.toml [formal.compcert] pins CompCert 3.17 (coqPackages_9_1) as the
          # T6/T7 Lower.v library dep; its INRIA non-commercial license restricts use
          # to evaluation/research, so the dep is build-time only and nothing
          # from CompCert (neither ccomp nor its C output) is a flake artifact.
          # allowUnfreePredicate keeps that scope machine-checked instead of a
          # global allowUnfree: any future unfree package trips the eval.
          config.allowUnfreePredicate = pkg:
            builtins.elem (pkg.pname or (builtins.parseDrvName pkg.name).name)
              [ "compcert" ];
        });
      }) systems);
      pins = builtins.fromTOML (builtins.readFile ./tools/pins/pins.toml);

      # Entries that record a nixpkgs-provided version: assert them at eval time.
      pinVersionEntries = builtins.filter (e: e ? nixpkgs_attr && e ? version)
        (builtins.attrValues (pins.formal or {})
        ++ builtins.attrValues (pins.haskell or {})
        ++ builtins.attrValues (pins.tooling or {})
        ++ builtins.attrValues (pins.runtime or {}));

      srcInputNames = [ "mlir-wasm-dialect" "ctrees" "interaction-trees" "coq-ext-lib"
        "coinduction" "paco" "certirocq" "veriffi" "verse-semantics" ];

      # ───────────────────────────────────────────────────────────────────────────
      # The Coq/Rocq stack (PLAN.md sec. 6 "Nix-native Rocq, opam secondary").  This
      # is what closed DEV-3, the transitional host opam switch: the kernel now builds
      # from these pins with nothing but nix on the host.
      #
      # nixpkgs' rocq 9.1 layout (read off pkgs.rocqPackages.rocq-core, its setupHook
      # and the findlib hook; confirmed by the M-2 probe builds, 2026-11):
      #   .vo theories  -> $out/lib/coq/9.1/user-contrib/<LogicalName>/
      #                    rocq-core's hook exports ROCQPATH for those dirs; dune 3.21's
      #                    coq-mode theory DB scans COQPATH instead -> our own setupHook
      #                    carries the same dirs into COQPATH.
      #   OCaml plugins -> $out/lib/ocaml/4.14.4/site-lib/<findlib pkg> (rocq-coinduction's
      #                    reification plugin is loaded from there; findlib exports OCAMLPATH).
      #
      # Build-mode rule for the whole stack: `(using coq 0.7)`.  coq lang >= 0.8 makes
      # dune compile with `coqc -boot`, which switches off rocq 9.1's implicit loadpath;
      # since nixpkgs ships the Stdlib as a *package* (rocqPackages.stdlib) rather than as
      # rocq-core theories, `From Stdlib Require ...` and bare `ZArith`/`BinPos` then fail.
      # coq lang 0.7 is dune's "implicit bootstrap": no -boot, rocq keeps its loadpath.
      # ───────────────────────────────────────────────────────────────────────────
      coqStack = pkgs:
        let
          rocq-core = pkgs.rocqPackages.rocq-core;
          rocq-stdlib = pkgs.rocqPackages.stdlib;
          ocamlP = rocq-core.ocamlPackages;
          # ocaml + findlib are what put findlib packages on OCAMLPATH (findlib's setup hook
          # exports $pkg/lib/ocaml/<ocaml version>/site-lib): without them a Coinduction
          # `Require` dies with "Findlib error: rocq-coinduction.plugin not found".
          ocamlForRocq = [ ocamlP.ocaml ocamlP.findlib ];
          rocqV = rocq-core.rocq-version;                  # "9.1"
          userContrib = "lib/coq/${rocqV}/user-contrib";

          coqPathHook = pkgs.writeText "timbda-coqpath-hook.sh" ''
            timbdaAddCoqPath () {
              if test -d "''$1/${userContrib}"; then
                export COQPATH="''${COQPATH-}''${COQPATH:+:}''$1/${userContrib}/"
              fi
            }
            addEnvHooks "$targetOffset" timbdaAddCoqPath
          '';

          # dune's coq mode looks for coqc/coqdep/coqdoc; nixpkgs ships only `rocq`
          # (`rocq c`, `rocq dep`, `rocq doc` are the same binaries).
          rocq-shims = pkgs.runCommand "rocq-shims" { } ''
            mkdir -p $out/bin
            cat > $out/bin/coqc  <<EOF
            #!/bin/sh
            exec ${rocq-core}/bin/rocq c "\$@"
            EOF
            cat > $out/bin/coqdep <<EOF
            #!/bin/sh
            exec ${rocq-core}/bin/rocq dep "\$@"
            EOF
            cat > $out/bin/coqdoc <<EOF
            #!/bin/sh
            exec ${rocq-core}/bin/rocq doc "\$@"
            EOF
            chmod +x $out/bin/*
          '';

          # One builder for both build flavours we meet in the pinned Coq stack:
          # dune projects (coq.theory stanzas) and coq_makefile projects (Makefile).
          mkRocqLib = { pname, version ? "0", src
                      , useDune ? false, theoryName ? null
                      , buildCmd ? "make", installCmd ? "make install"
                      , buildInputs ? [ ], postPatch ? null, meta ? { } }:
            pkgs.stdenv.mkDerivation ({
              inherit pname version src meta;
              setupHook = coqPathHook;
              nativeBuildInputs = [ pkgs.which ocamlP.ocaml ocamlP.findlib ]
                ++ pkgs.lib.optionals useDune [ pkgs.dune rocq-shims ];
              buildInputs = [ rocq-core rocq-stdlib ] ++ buildInputs;
              propagatedBuildInputs = [ rocq-core rocq-stdlib ] ++ buildInputs;
              buildPhase =
                if useDune then ''
                  runHook preBuild
                  export COQPATH="$ROCQPATH''${COQPATH:+:}$COQPATH"
                  dune build ./theories
                  runHook postBuild
                '' else ''
                  runHook preBuild
                  ${buildCmd}
                  runHook postBuild
                '';
              installPhase =
                if useDune then ''
                  runHook preInstall
                  mkdir -p $out/${userContrib}/${theoryName}
                  cp -r --no-preserve=mode _build/default/theories/. \
                        $out/${userContrib}/${theoryName}/
                  runHook postInstall
                '' else ''
                  runHook preInstall
                  # COQLIBINSTALL / COQPLUGININSTALL are the coq_makefile install knobs
                  # nixpkgs' own mkRocqDerivation passes (pkgs/build-support/rocq).
                  ${installCmd} COQLIBINSTALL=$out/${userContrib} \
                                 COQDOCINSTALL=$out/share/coq/${rocqV}/user-contrib \
                                 COQPLUGININSTALL=$OCAMLFIND_DESTDIR
                  # some meta-packages install under site-coq*/...: flatten into user-contrib
                  if [ -d "$OCAMLFIND_DESTDIR/coq" ]; then
                    mkdir -p $out/lib/coq
                    cp -r $OCAMLFIND_DESTDIR/coq/. $out/lib/coq/${rocqV}/ 2>/dev/null || true
                  fi
                  runHook postInstall
                '';
            } // (pkgs.lib.optionalAttrs (postPatch != null) { inherit postPatch; }));

          coq-ext-lib = mkRocqLib {
            pname = "coq-ext-lib"; version = "0.13.0-dev";
            src = inp.coq-ext-lib; useDune = true; theoryName = "ExtLib";
            postPatch = ''
              substituteInPlace dune-project --replace 'using coq 0.8' 'using coq 0.7'
            '';
          };

          # paco: a coq_makefile project whose Makefile still invokes the retired
          # `coq_makefile` binary; rocq 9.1 renamed it to `rocq makefile`.
          paco = mkRocqLib {
            pname = "coq-paco"; version = "4.4-dev"; src = inp.paco;
            postPatch = ''
              substituteInPlace src/Makefile --replace 'coq_makefile -f' 'rocq makefile -f'
            '';
            buildCmd = "make -C src all";
            installCmd = "make -C src -f Makefile.coq install";
          };

          # coinduction 1.21: its Makefile already drives `rocq makefile`; builds the
          # reification plugin (findlib package rocq-coinduction -> plugin.cmxs).
          rocq-coinduction = mkRocqLib {
            pname = "rocq-coinduction"; version = "1.21"; src = inp.coinduction;
          };

          coq-itree = mkRocqLib {
            pname = "coq-itree"; version = "5.2.1-dev";
            src = inp.interaction-trees; useDune = true; theoryName = "ITree";
            # `dune build ./theories` (not `dune build`): the repo's extraction and
            # test stanzas are not part of what the Timbda kernel needs.
            buildInputs = [ coq-ext-lib paco pkgs.rocqPackages.relation-algebra
              pkgs.coqPackages.equations ];
          };

          rocq-ctree = mkRocqLib {
            pname = "rocq-ctree"; version = "2.0-dev";
            src = inp.ctrees; useDune = true; theoryName = "CTree";
            buildInputs = [ coq-ext-lib rocq-coinduction coq-itree
              pkgs.rocqPackages.relation-algebra pkgs.coqPackages.equations ];
          };

          # CompCert 3.17, nixpkgs-provided, from the coqPackages_9_1 namespace.
          # Measured 2026-11-25: the TOP-LEVEL pkgs.compcert is wired from
          # coqPackages_9_0 (all-packages.nix `inherit (coqPackages_9_0) compcert`),
          # i.e. its .vo are compiled by prover 9.0 and land in lib/coq/9.0/
          # user-contrib (drv evidence: -coqdevdir $lib/lib/coq/9.0/...); .vo files
          # are prover-version-locked, so that variant is unusable in this flake's
          # rocq 9.1.1 stack - and building it pulls a from-scratch stdlib 9.0
          # rebuild that ate the gate's memory floor.  coqPackages_9_1.compcert is
          # the 9.1-series build of the same pinned 3.17 (nixpkgs applies the Coq
          # 9.1.1 compat patch); version-consistency now asserts pins.toml
          # [formal.compcert] against exactly this attribute.
          # .vo tree: lib output, user-contrib/compcert/{lib,common,backend,
          # cfrontend,...}; the upstream Makefile compiles each source dir
          # with `-R <dir> compcert.<dir>` so the .vo files record fully-qualified
          # dependencies, and consumers need only the single root mapping:
          # `Require Import compcert.common.AST compcert.cfrontend.Clight.` verified
          # against a minimal tree probe on rocq 9.1.1 (2026-11-25), matching the
          # README upstream installs next to the .vo tree.
          compcert = pkgs.coqPackages_9_1.compcert;
        in
        {
          inherit rocq-core rocq-stdlib rocq-shims coqPathHook userContrib ocamlForRocq;
          inherit coq-ext-lib paco rocq-coinduction coq-itree rocq-ctree compcert;
          # everything the kernel's `From X Require` lines resolve against, plus
          # CompCert for the T6/T7 Lower.v work (no coq/*.v imports it yet - it is
          # the build-time library dep pins.toml records, not a shipped artifact)
          rocqDeps = [ rocq-core rocq-stdlib coq-ext-lib paco rocq-coinduction coq-itree
            rocq-ctree pkgs.rocqPackages.relation-algebra pkgs.coqPackages.equations
            compcert ];
        };
    in
    {
      packages = forAllSystems (system: pkgs:
        let
          stack = coqStack pkgs;
          libNames = {
            "timbda-extlib" = stack.coq-ext-lib;
            "timbda-paco" = stack.paco;
            "timbda-coinduction" = stack.rocq-coinduction;
            "timbda-itrees" = stack.coq-itree;
            "timbda-ctrees" = stack.rocq-ctree;
            # nixpkgs' compcert under our pin: a buildable name so the T6 dep can
            # be materialized/attested standalone before any Lower.v exists.
            "timbda-compcert" = stack.compcert;
          };
          # Where the kernel package's .vo trees land, for corners that `Require Import
          # Timbda.*` without going through dune (the two corpus corners).
          kernelTheoryDir =
            "${self.packages.${system}.timbda-kernel}/${stack.userContrib}";

          # What a corpus corner reads out of this repo, taken from the two buildPhases below and
          # nothing else: corpus.py, driver.ml, extract.v, and the corpus spec file.  The kernel's .vo
          # trees arrive through `timbda-kernel` in buildInputs, not from this tree.  Narrowing `src`
          # to exactly that is what keeps a documentation-only commit from rehashing both corner
          # derivations and making the gate re-run rocq over a generated ~700-line corner for no proof
          # change (measured 2026-11-26: a docs-only edit changed the corner drv hashes, and the
          # differential lane rebuilt with them).  Directories pass the filter so their allowed files
          # are reachable; cleanSourceFilter first is what drops .git/.jj/_build/result.
          cornerSrc = pkgs.lib.cleanSourceWith {
            src = ./.;
            # nix hands a `filter` the store path it is copying (`/nix/store/<hash>-source/tools/...`),
            # not a path relative to `src` - measured on this flake with nix 2.35.3, where a relative
            # pattern matched every directory and no file.  Match on suffixes instead.  cleanSourceFilter
            # first is what drops .git/.jj/_build/result.
            filter = path: type: pkgs.lib.cleanSourceFilter path type && (
              type == "directory"
              || pkgs.lib.hasSuffix "/tools/corpus/corpus.py" path
              || pkgs.lib.hasSuffix "/tools/corpus/driver.ml" path
              || pkgs.lib.hasSuffix "/tools/extract/extract.v" path
              || pkgs.lib.hasInfix "/tests/corpus/" path
            );
          };

          mkCorpusCoqCorner = { cornerName, specFile }: pkgs.stdenv.mkDerivation {
            pname = cornerName;
            version = "0.1.0";
            src = cornerSrc;
            nativeBuildInputs = [ pkgs.python3 ] ++ stack.ocamlForRocq;
            buildInputs = [ self.packages.${system}.timbda-kernel ] ++ stack.rocqDeps;
            phases = [ "buildPhase" "installPhase" ];
            buildPhase = ''
              set +e
              # The kernel package installs its .vo trees under userContrib; rocq finds
              # them through ROCQPATH, which its own setup hook fills in for the rocqDeps
              # but not for timbda-kernel (a plain mkDerivation), so name it here.
              export ROCQPATH="${kernelTheoryDir}''${ROCQPATH:+:}$ROCQPATH"
              # The Coq corner: corpus.py generates a file of `reflexivity` assertions
              # about Coq's own evaluator (Timbda.Eval.norm / head_redex), and rocq
              # either compiles that file or it does not.  `Print corner_cases.` inside
              # the generated file prints the Coq-side case count for the cross-check.
              # Every step's status lands in status.txt: an empty corpus file or a
              # silently-missing tool must not be able to produce a vacuous "exit 0"
              # (that is exactly how this corner first fooled us - an empty corner.v
              # compiles happily).
              cp $src/tools/corpus/corpus.py .
              python3 corpus.py --count $src/${specFile} > corpus-count.txt
              reader_rc=$?
              python3 corpus.py --count-cands $src/${specFile} > corpus-cands.txt
              cands_rc=$?
              python3 corpus.py --emit-coq $src/${specFile} > corner.v
              rocq compile corner.v > coq-corner.log 2>&1
              rocq_rc=$?
              grep -n -A6 "Error" coq-corner.log
              {
                echo "reader_rc=$reader_rc"
                echo "cands_rc=$cands_rc"
                echo "reader_cases=$(cat corpus-count.txt)"
                echo "reader_cands=$(cat corpus-cands.txt)"
                echo "corner_lines=$(wc -l < corner.v)"
                echo "rocq_rc=$rocq_rc"
                echo "marker=$(grep -E "corner_cases = [0-9]+" coq-corner.log | head -1)"
                echo "cands_marker=$(grep -E "corner_cands = [0-9]+" coq-corner.log | head -1)"
              } > status.txt
              cat status.txt
              # The corner must fail on its own bad status, not only inside
              # checks.corpus-differential: on 2026-11-19 the extracted corner derived
              # "successfully" with ocamlc_rc=2 / driver_rc=127, because nothing here read
              # the status it had just written.  A derivation whose phases ignored rc is a
              # vacuous success (DESIGN-NOTES sec. 8.3), so gate here as well as in the check.
              test "$reader_rc" = 0 || { echo "FAIL: corpus reader (corpus.py --count) exited $reader_rc"; exit 1; }
              test "$cands_rc" = 0 || { echo "FAIL: corpus reader (corpus.py --count-cands) exited $cands_rc"; exit 1; }
              test "$rocq_rc" = 0 || { echo "FAIL: rocq compile of the generated corner exited $rocq_rc, see coq-corner.log"; exit 1; }
              test "$(wc -l < corner.v)" -gt 100 || { echo "FAIL: generated corner is not a substantial file"; exit 1; }
            '';
            installPhase = ''
              mkdir -p $out
              cp corner.v $out/corner-generated.v
              cp coq-corner.log status.txt $out/
              grep -oE "corner_cases = [0-9]+" coq-corner.log | head -1 |
                cut -d" " -f3 > $out/case-count
              grep -oE "corner_cands = [0-9]+" coq-corner.log | head -1 |
                cut -d" " -f3 > $out/cands-count
            '';
          };

          # The extracted-evaluator corner: tools/extract/extract.v runs `Extraction` on
          # the *installed* kernel package, and tools/corpus/driver.ml - an independent
          # reader of the same corpus - runs the extracted OCaml evaluator on every case.
          mkCorpusOcamlCorner = { cornerName, specFile }: pkgs.stdenv.mkDerivation {
            pname = cornerName;
            version = "0.1.0";
            src = cornerSrc;
            nativeBuildInputs = [ stack.rocq-core ] ++ stack.ocamlForRocq;
            buildInputs = [ self.packages.${system}.timbda-kernel ] ++ stack.rocqDeps;
            phases = [ "buildPhase" "installPhase" ];
            buildPhase = ''
              set +e
              export ROCQPATH="${kernelTheoryDir}''${ROCQPATH:+:}$ROCQPATH"
              cp $src/tools/extract/extract.v .
              cp $src/tools/corpus/driver.ml .
              rocq compile extract.v > extract.log 2>&1
              extract_rc=$?
              grep -n -e "Error" -e "Closed under the global context" -e "Axioms:" extract.log
              # `Extraction "timbda_eval.ml"` also emits timbda_eval.mli; compiling the
              # interface first means the driver is type-checked against the extracted
              # signature, not just against whatever constructors happen to be visible.
              ocamlc -c timbda_eval.mli > ocamlc.log 2>&1
              mli_rc=$?
              ocamlc -o corpus-run timbda_eval.ml driver.ml >> ocamlc.log 2>&1
              ocamlc_rc=$?
              ./corpus-run $src/${specFile} > corpus-run.log 2>&1
              driver_rc=$?
              grep -n "^FAIL" corpus-run.log
              {
                echo "extract_rc=$extract_rc"
                echo "extracted_lines=$(wc -l < timbda_eval.ml)"
                echo "mli_rc=$mli_rc"
                echo "ocamlc_rc=$ocamlc_rc"
                echo "driver_rc=$driver_rc"
                echo "summary=$(grep -E "^corpus corner: [0-9]+ cases" corpus-run.log | head -1)"
                echo "cands_summary=$(grep -E "^cands corner: [0-9]+ groups" corpus-run.log | head -1)"
              } > status.txt
              cat status.txt
              tail -3 corpus-run.log
              # Same rule as the Coq corner: the phases must gate on the rc they recorded,
              # otherwise `nix build .#…ocaml-corner` reports success on a corner that never
              # compiled or never ran (measured on 2026-11-19: ocamlc_rc=2, driver_rc=127).
              test "$extract_rc" = 0 || { echo "FAIL: rocq compile of tools/extract/extract.v exited $extract_rc"; exit 1; }
              test -f timbda_eval.ml || { echo "FAIL: Extraction produced no timbda_eval.ml"; exit 1; }
              test "$(wc -l < timbda_eval.ml)" -gt 200 || { echo "FAIL: extracted evaluator is not a substantial file"; exit 1; }
              test "$mli_rc" = 0 || { echo "FAIL: ocamlc of timbda_eval.mli exited $mli_rc"; exit 1; }
              test "$ocamlc_rc" = 0 || { echo "FAIL: ocamlc of the driver exited $ocamlc_rc, see ocamlc.log"; exit 1; }
              test "$driver_rc" = 0 || { echo "FAIL: the corpus driver exited $driver_rc, see corpus-run.log"; exit 1; }
            '';
            installPhase = ''
              mkdir -p $out
              cp extract.log ocamlc.log corpus-run.log status.txt $out/
              cp $src/tools/corpus/driver.ml $out/driver.ml
              if test -f timbda_eval.ml; then
                cp timbda_eval.ml $out/
                test -f timbda_eval.mli && cp timbda_eval.mli $out/ || true
              fi
              grep -oE "corpus corner: [0-9]+ cases" corpus-run.log | head -1 |
                cut -d" " -f3 > $out/case-count
              grep -oE "cands corner: [0-9]+ groups" corpus-run.log | head -1 |
                cut -d" " -f3 > $out/cands-count
            '';
          };

        in
        {
          # The M0 Gallina kernel: coq/*.v + coq/tests/KernelTest.v.
          # The build doubles as the `Admitted` / axiom audit (docs/RULES-AUDIT.md sec. 6):
          # Print Assumptions runs at build time inside dune's output, so the audit is
          # build evidence, not a claim in a doc.
          timbda-kernel = pkgs.stdenv.mkDerivation {
            pname = "timbda-kernel";
            version = "0.1.0";
            src = ./coq;
            nativeBuildInputs = [ stack.rocq-shims pkgs.dune pkgs.which
              stack.rocq-core.ocamlPackages.ocaml stack.rocq-core.ocamlPackages.findlib ];
            buildInputs = stack.rocqDeps;
            buildPhase = ''
              set -o pipefail
              export COQPATH="$ROCQPATH''${COQPATH:+:}$COQPATH"
              dune build 2>&1 | tee build.log

              echo "--- axiom audit (Print Assumptions, coq/tests/KernelTest.v) ---"
              test -f _build/default/tests/KernelTest.vo \
                || { echo "FAIL kernel tests did not compile"; exit 1; }
              # M2 (2026-11-23): the T4 checker theory, its eval-side leg and the corpus-mirror
              # tests stand in the same gate as the M0 tests - a kernel build that silently skipped
              # any of them is not a pass (tools/build/coq-build.sh EXPECTED_VO mirror).
              test -f _build/default/Checks.vo \
                || { echo "FAIL the T4 checker theory did not compile"; exit 1; }
              test -f _build/default/ChecksEval.vo \
                || { echo "FAIL the T4 eval-side leg did not compile"; exit 1; }
              test -f _build/default/tests/ChecksTest.vo \
                || { echo "FAIL the M2 checker tests did not compile"; exit 1; }
              # M2 (2026-11-25): Lower.v is the T7 carrier; a build without it is
              # the same vacuity this list has always guarded against.
              test -f _build/default/Lower.vo \
                || { echo "FAIL the Lower.v (T7) theory did not compile"; exit 1; }
              # M1 item 1 (2026-11-25): RewRules.v is the generated rule surface;
              # the kernel must compile against the generated ctors, not a
              # hand-glued copy (docs/PLAN.md § 5.0).
              test -f _build/default/RewRules.vo \
                || { echo "FAIL the generated rule surface (RewRules.v) did not compile"; exit 1; }
              # M1 item 1 completion: the eval-side RuleID/selected_rows and the
              # soundness registry are generated files too; Eval.v now Requires
              # RuleAst, so a build without them cannot even reach Eval.vo.
              test -f _build/default/RuleAst.vo \
                || { echo "FAIL the generated eval-side AST (RuleAst.v) did not compile"; exit 1; }
              test -f _build/default/CheckerManifest.vo \
                || { echo "FAIL the generated soundness registry (CheckerManifest.v) did not compile"; exit 1; }
              if grep -n "Admitted" build.log; then
                echo "FAIL Admitted appeared in build output"; exit 1
              fi
              axioms=$(grep -oE "^[A-Za-z][A-Za-z0-9_.]* :" build.log | sort -u)
              n=$(printf '%s\n' "$axioms" | grep -c .)
              echo "axioms referenced ($n): $axioms"
              test "$n" = 1 || { echo "FAIL expected exactly one axiom"; exit 1; }
              test "$axioms" = "Eqdep.Eq_rect_eq.eq_rect_eq :" \
                || { echo "FAIL unexpected axiom set"; exit 1; }
              echo "OK kernel builds, single axiom eq_rect_eq"
              # T6 cone audit (2026-11-25, docs/PLAN.md decision 10a, docs/DESIGN-NOTES.md
              # sec. 13.14): the CompCert-facing cone (coq/Realize.v onward) is audited in
              # its own scope, not smuggled into the kernel sweep above (no file of the
              # Realize family carries a Print Assumptions line - the headers forbid it).
              # Since the increment-C fan-in split (2026-11-26, decision 12) the family is
              # the Realize hub plus the leaves RealizeBridges/RealizeDiv/RealizeCorners
              # composing in RealizeCompose; checking the two roots covers all of them
              # transitively.  As of M2 increment D1 (2026-11-26) the root list also
              # carries Timbda.Compile: measured before wiring, `rocq check` prints for
              # it exactly the pinned 13 axioms below - the fold path adds none, and no
              # Compile-family file carries a Print Assumptions line (same header rule).  rocqchk re-checks the whole transitive cone; the CONTEXT
              # SUMMARY's axiom block must match the pinned list verbatim, and the
              # type-in-type / unsafe-(co)fixpoint / assumed-positivity sections must all
              # stay <none>.
              test -f _build/default/Realize.vo \
                || { echo "FAIL the T6 realization theory (Realize.v) did not compile"; exit 1; }
              test -f _build/default/RealizeCompose.vo \
                || { echo "FAIL the T6 composition leaf (RealizeCompose.v) did not compile"; exit 1; }
              # M2 increment D1 (2026-11-26, docs/COMPILE-STRATEGY.md sec. 8): Compile.v is
              # the CertiRocq->C wiring leaf (fold-specialized hylomorphism, decision 14);
              # it and its test lane stand in this gate like the Realize family does.
              test -f _build/default/Compile.vo \
                || { echo "FAIL the M2 compile leaf (Compile.v) did not compile"; exit 1; }
              test -f _build/default/tests/CompileTest.vo \
                || { echo "FAIL the M2 compile test lane did not compile"; exit 1; }
              rocq check -silent -o -Q _build/default Timbda Timbda.Realize Timbda.RealizeCompose Timbda.Compile > cone.log 2>&1
              test "$?" = 0 || { echo "FAIL rocq check on Timbda.Realize/Timbda.RealizeCompose/Timbda.Compile"; tail -40 cone.log; exit 1; }
              if grep -n "Admitted" cone.log; then
                echo "FAIL Admitted appeared in the cone check"; exit 1
              fi
              for marker in \
                "type-in-type: <none>" \
                "unsafe (co)fixpoints: <none>" \
                "positivity is assumed: <none>"; do
                grep -qF "$marker" cone.log \
                  || { echo "FAIL cone summary lacks the empty '$marker' section"; exit 1; }
              done
              cone_axioms=$(awk '/^\* Axioms:/{f=1;next} /^\*/{f=0} f && NF {print $1}' cone.log | sort -u)
              expected_cone=$(printf '%s\n' \
                Stdlib.Reals.ClassicalDedekindReals.sig_not_dec \
                Stdlib.Reals.ClassicalDedekindReals.sig_forall_dec \
                Stdlib.Logic.FunctionalExtensionality.functional_extensionality_dep \
                Stdlib.Logic.Classical_Prop.classic \
                Stdlib.Logic.ProofIrrelevance.proof_irrelevance \
                Stdlib.Logic.Eqdep.Eq_rect_eq.eq_rect_eq \
                Stdlib.Sets.Ensembles.Extensionality_Ensembles \
                compcert.common.Events.inline_assembly_sem \
                compcert.common.Events.inline_assembly_properties \
                compcert.common.Events.external_functions_sem \
                compcert.common.Events.external_functions_properties \
                compcert.lib.Axioms.proof_irr \
                compcert.x86_64.Archi.win64 | sort -u)
              test "$cone_axioms" = "$expected_cone" \
                || { echo "FAIL unexpected cone axiom set"; echo "got:"; echo "$cone_axioms"; exit 1; }
              echo "OK cone audited, $(printf '%s\n' "$expected_cone" | grep -c .) pinned axioms"
            '';
            installPhase = ''
              mkdir -p $out/${stack.userContrib}/Timbda $out/${stack.userContrib}/TimbdaTests
              cp -r --no-preserve=mode _build/default/. $out/${stack.userContrib}/Timbda/
              rm -rf $out/${stack.userContrib}/Timbda/tests $out/${stack.userContrib}/Timbda/.dune
              cp -r --no-preserve=mode _build/default/tests/. \
                     $out/${stack.userContrib}/TimbdaTests/
              find $out \( -name "*.aux" -o -name "*.theory.d" \) -delete
            '';
          };

          # ---- tblgen-rocq: the Coq-side generator (PLAN sec. 2, M1 item 1) -----
          # Built on nixpkgs llvmPackages_23 - the [formal.mlir_gen] pin
          # (version-consistency checks it; docs/DESIGN-NOTES.md sec. 13.10).
          # That distribution ships no MLIR TableGen *library*, so the backend
          # parses through the classic llvm::TableGen API; bazel keeps compiling
          # the dialect C++/DRR with mlir-tblgen and generated text is the only
          # cross-graph interface (PLAN sec. 6).
          timbda-tblgen-rocq = pkgs.stdenv.mkDerivation {
            pname = "timbda-tblgen-rocq";
            version = "0.1.0";
            src = ./.;
            nativeBuildInputs = [ pkgs.stdenv.cc
              pkgs.llvmPackages_23.llvm.dev pkgs.llvmPackages_23.mlir.dev
              pkgs.llvmPackages_23.llvm.lib ];
            phases = [ "buildPhase" "installPhase" ];
            LLVM_INC = "${pkgs.llvmPackages_23.llvm.dev}/include";
            MLIR_INC = "${pkgs.llvmPackages_23.mlir.dev}/include";
            buildPhase = ''
              set -e
              c++ $src/dialect/tblgen-rocq/TimbdaRocqGen.cpp -std=c++17 \
                -I $LLVM_INC -I $MLIR_INC \
                -L${pkgs.llvmPackages_23.llvm.lib}/lib \
                -lLLVMTableGen -lLLVMSupport -lLLVMDemangle -lz -lpthread -ldl \
                -o tblgen-rocq-bin
              chmod +w tblgen-rocq-bin
            '';
            installPhase = ''
              mkdir -p $out/bin $out/libexec
              cp tblgen-rocq-bin $out/libexec/
              # plain sed (substituteAll's arg conventions tripped us: options
              # after the positionals get parsed as input files - measured).
              sed -e "s|@MLIR_INC@|$MLIR_INC|g" -e "s|@LLVM_INC@|$LLVM_INC|g" \
                $src/dialect/tblgen-rocq/tblgen-rocq.sh > $out/bin/tblgen-rocq
              chmod +x $out/bin/tblgen-rocq
            '';
          };

          # ---- differential corpus corners (M0 tail; docs/PLAN.md sec. 6) ----------
          # Each spec file gets two independent readers and two evaluators.  Every
          # corner always builds and writes a verdict line into its log, so a
          # disagreement stays readable; the checks.corpus-* gates fail when a spec's
          # two corners do not agree.  Harness scaffolding lives in tools/ + tests/,
          # never in coq/, so the kernel gate above is untouched by it
          # (tools/corpus/README.md sec. 5).  The builders are parameterised by spec
          # file (2026-11-22, the M2 wiring - tools/corpus/README.md sec. 8):
          # m0.texpr keeps its corners, names, build script and gate verbatim (the
          # shell text below is character-identical to the pre-wiring version apart
          # from the m0.texpr path becoming ${specFile} and pname becoming a
          # parameter), and m2-det.texpr gets the identical machinery as a second
          # corner pair under -m2 names.
          # The four corners, spelled out: the m0 pair keeps the pre-wiring attribute
          # names, so every documented target (`.#packages.…-corpus-coq-corner`, the
          # gate, the DESIGN-NOTES measurements) stays addressable unchanged.
          timbda-corpus-coq-corner = mkCorpusCoqCorner {
            cornerName = "timbda-corpus-coq-corner";
            specFile = "tests/corpus/m0.texpr";
          };
          timbda-corpus-ocaml-corner = mkCorpusOcamlCorner {
            cornerName = "timbda-corpus-ocaml-corner";
            specFile = "tests/corpus/m0.texpr";
          };
          # The M2 pair (tools/corpus/README.md sec. 8): same readers, same evaluators,
          # same anti-vacuity tests, spec file tests/corpus/m2-det.texpr.
          timbda-corpus-coq-corner-m2 = mkCorpusCoqCorner {
            cornerName = "timbda-corpus-coq-corner-m2";
            specFile = "tests/corpus/m2-det.texpr";
          };
          timbda-corpus-ocaml-corner-m2 = mkCorpusOcamlCorner {
            cornerName = "timbda-corpus-ocaml-corner-m2";
            specFile = "tests/corpus/m2-det.texpr";
          };

          # Locks every pinned upstream on day one (PLAN sec. 6): a cheap derivation
          # that just exposes the fetched source trees.
          timbda-pin-sources = pkgs.runCommand "timbda-pin-sources" { }
            (''
                mkdir -p $out
              ''
              + nixpkgs.lib.concatMapStrings (name:
                  ''
                    ln -s ${inp."${name}".outPath} $out/${name}
                  ''
                ) srcInputNames);
        } // libNames);

      devShells = forAllSystems (system: pkgs:
        let
          stack = coqStack pkgs;
          # DEV-3 closure: the whole Coq dependency cone now comes from the flake, so
          # `cd coq && dune build` needs no host opam switch.  rocq's setupHook publishes
          # the installed theories on ROCQPATH; dune 3.21's coq-mode theory DB reads COQPATH,
          # so mirror it exactly as our derivations do in their buildPhase.
          coqShellHook = ''
            export COQPATH="$ROCQPATH''${COQPATH:+:}$COQPATH"
            echo "timbda rocq shell: $(rocq --version | head -1); build with: cd coq && dune build"
          '';
          coqShellTools = [ pkgs.dune pkgs.which stack.rocq-shims ] ++ stack.ocamlForRocq;
        in
        {
          # Formalisation shell (the DEV-3 opam-switch replacement): rocq plus every pinned
          # library and the language server editors talk to.
          rocq = pkgs.mkShell {
            packages = [ pkgs.rocqPackages.vsrocq-language-server pkgs.git pkgs.python3 ]
              ++ coqShellTools ++ stack.rocqDeps;
            shellHook = coqShellHook;
          };

          # Compiler side (Bazel / hermetic-llvm leg arrives at M-2, PLAN sec. 6.2);
          # tblgen-rocq rides along: the nix-side generator of PLAN sec. 6.
          cpp = pkgs.mkShell {
            packages = [ pkgs.bazelisk pkgs.git pkgs.python3
              self.packages.${system}.timbda-tblgen-rocq ];
          };

          # Reference semantics / differential harness side (M-0 tail).
          hs = pkgs.mkShell {
            packages = [ pkgs.haskell.compiler.ghc912 pkgs.cabal-install pkgs.git pkgs.python3 ];
          };

          # Everything at once (the canonical shell of docs/DESIGN-NOTES.md sec. 4).
          all = pkgs.mkShell {
            packages = with pkgs; [ bazelisk git python3 haskell.compiler.ghc912 cabal-install
              rocqPackages.vsrocq-language-server ]
              ++ [ self.packages.${system}.timbda-tblgen-rocq ]
              ++ coqShellTools ++ stack.rocqDeps;
            shellHook = coqShellHook;
          };
        });

      checks = forAllSystems (system: pkgs:
        let
          stack = coqStack pkgs;
          cornerCoq = self.packages.${system}.timbda-corpus-coq-corner;
          cornerOcaml = self.packages.${system}.timbda-corpus-ocaml-corner;
          cornerCoqM2 = self.packages.${system}.timbda-corpus-coq-corner-m2;
          cornerOcamlM2 = self.packages.${system}.timbda-corpus-ocaml-corner-m2;
          # One gate builder per spec file.  The shell body below is the
          # pre-wiring corpus-differential text line-for-line (same status
          # fields, same anti-vacuity tests, same report layout): only the
          # derivation name, the report's corpus label, and the two corner
          # paths became arguments, named exactly like the let bindings they
          # shadow.  The m0 instantiation therefore builds the same check
          # derivation name it built before the wiring (the DESIGN-NOTES sec.
          # 12 measurements stay comparable); the m2 instantiation runs the
          # identical comparison over tests/corpus/m2-det.texpr
          # (tools/corpus/README.md sec. 8).
          corpusDifferentialFor = { checkName, specFile, cornerCoq, cornerOcaml }:
            pkgs.runCommand checkName { }
            (''
                set -e
                mkdir -p $out
                st_coq=${cornerCoq}/status.txt
                st_ml=${cornerOcaml}/status.txt
                test -f "$st_coq" || { echo "FAIL: no status.txt from the Coq corner" >&2; exit 1; }
                test -f "$st_ml"  || { echo "FAIL: no status.txt from the extracted corner" >&2; exit 1; }

                field () { grep -m1 "^$2=" "$1" | cut -d= -f2-; }
                reader_rc=$(field "$st_coq" reader_rc)
                cands_rc=$(field "$st_coq" cands_rc)
                reader_cases=$(field "$st_coq" reader_cases)
                reader_cands=$(field "$st_coq" reader_cands)
                corner_lines=$(field "$st_coq" corner_lines)
                rocq_rc=$(field "$st_coq" rocq_rc)
                extract_rc=$(field "$st_ml" extract_rc)
                extracted_lines=$(field "$st_ml" extracted_lines)
                mli_rc=$(field "$st_ml" mli_rc)
                ocamlc_rc=$(field "$st_ml" ocamlc_rc)
                driver_rc=$(field "$st_ml" driver_rc)

                fail () { echo "FAIL: $1" >&2; exit 1; }
                test "$reader_rc" = 0  || fail "corpus reader exited $reader_rc"
                test "$cands_rc" = 0   || fail "cands reader exited $cands_rc"
                test "$rocq_rc" = 0    || fail "the generated Coq corner did not compile (rocq exit $rocq_rc)"
                test "$extract_rc" = 0 || fail "Extraction failed (rocq exit $extract_rc)"
                test "$mli_rc" = 0     || fail "the extracted signature (timbda_eval.mli) did not compile (exit $mli_rc)"
                test "$ocamlc_rc" = 0  || fail "the extracted evaluator + driver did not compile (ocamlc exit $ocamlc_rc)"
                test "$driver_rc" = 0  || fail "the corpus driver reported a case mismatch (exit $driver_rc)"

                # Anti-vacuity: an empty corpus, an empty generated corner or a truncated
                # extraction must not be able to produce a green build (that is how the
                # first version of these corners "passed" while running nothing).
                test "$reader_cases" -gt 0     || fail "the corpus reader saw 0 cases"
                test "$reader_cands" -gt 0     || fail "the corpus declares no candidate-bag cases"
                test "$corner_lines" -gt 100   || fail "the generated Coq corner has only $corner_lines lines"
                test "$extracted_lines" -gt 200 || fail "Extraction produced only $extracted_lines lines of OCaml"

                n_coq=$(cat ${cornerCoq}/case-count  || true)
                n_ocaml=$(cat ${cornerOcaml}/case-count || true)
                test -n "$n_coq"   || fail "Coq corner printed no case count"
                test -n "$n_ocaml" || fail "extracted corner printed no case count"
                test "$n_coq" = "$reader_cases" || fail "Coq corner checked $n_coq cases, corpus declares $reader_cases"
                test "$n_ocaml" = "$reader_cases" || fail "extracted corner ran $n_ocaml cases, corpus declares $reader_cases"

                # The candidate-bag layer is counted separately on purpose: a corner that
                # silently dropped the `cands` assertions would still satisfy the case count.
                k_coq=$(cat ${cornerCoq}/cands-count || true)
                k_ocaml=$(cat ${cornerOcaml}/cands-count || true)
                test -n "$k_coq"   || fail "Coq corner printed no candidate-bag count"
                test -n "$k_ocaml" || fail "extracted corner printed no candidate-bag count"
                test "$k_coq" = "$reader_cands"   || fail "Coq corner discharged $k_coq cand_bag claims, corpus declares $reader_cands"
                test "$k_ocaml" = "$reader_cands" || fail "extracted corner ran $k_ocaml cand_bag claims, corpus declares $reader_cands"

                summary=$(grep -m1 "^corpus corner:" ${cornerOcaml}/corpus-run.log || true)
                case "$summary" in
                  *"all agree with the extracted evaluator"*) ;;
                  *) fail "extracted corner verdict line is: $summary" ;;
                esac
                cands_summary=$(grep -m1 "^cands corner:" ${cornerOcaml}/corpus-run.log || true)
                case "$cands_summary" in
                  *"all agree with cand_bag"*) ;;
                  *) fail "extracted corner candidate-bag line is: $cands_summary" ;;
                esac

                {
                  echo "timbda differential corpus check (docs/PLAN.md sec. 6)"
                  echo "  corpus:            ${specFile}  ($reader_cases cases, $reader_cands with a candidate bag)"
                  echo "  Coq corner:        $n_coq cases / $k_coq cand_bag claims, generated by corpus.py, all discharged by rocq"
                  echo "  extracted corner:  $n_ocaml cases / $k_ocaml cand_bag claims against timbda_eval.ml ($extracted_lines lines, Extraction'd from the same Gallina evaluator)"
                  echo "  generated corner:  $corner_lines lines of .v"
                  echo "  axiom footprint of the extracted evaluator:"
                  grep -n -e "Closed under the global context" -e "Axioms:" ${cornerOcaml}/extract.log || true
                  echo "  extracted corner line: $summary"
                  echo "  extracted corner cands line: $cands_summary"
                } > $out/report.txt
                cp "$st_coq" $out/coq-corner-status.txt
                cp "$st_ml"  $out/ocaml-corner-status.txt
                cp ${cornerCoq}/coq-corner.log $out/coq-corner.log
                cp ${cornerOcaml}/corpus-run.log $out/corpus-run.log
                echo "ok: $reader_cases corpus cases (incl. $reader_cands candidate bags) agree across corners (Gallina native vs extracted OCaml)"
              '');
        in
        {
          # Half of the pin-consistency story: pins.toml vs the nixpkgs-provided versions
          # (the flake.lock / MODULE.bazel half is tools/pins/pins.py).
          version-consistency = pkgs.runCommand "timbda-version-consistency" { }
            (''
                set -e
              ''
              + nixpkgs.lib.concatMapStrings (e:
                  let
                    got = (nixpkgs.lib.attrByPath
                      (nixpkgs.lib.splitString "." e.nixpkgs_attr)
                      { version = "<missing>"; } pkgs).version;
                  in ''
                    test "${e.version}" = "${got}" || { echo "VERSION MISMATCH ${e.nixpkgs_attr}: pins.toml=${e.version} nixpkgs=${got}" >&2; exit 1; }
                  ''
                ) pinVersionEntries
              + ''
                echo "timbda version-consistency ok (${builtins.toString (builtins.length pinVersionEntries)} pinned tool versions match)"
                touch $out
              '');

          # The kernel + its Print Assumptions audit.
          coq-kernel-tests = self.packages.${system}.timbda-kernel;

          # The differential claim itself: one corpus file, two independent readers, two
          # evaluators (Gallina native, and the OCaml that `Extraction` produced from the
          # same Gallina function).  Both corners must accept every case, and the case
          # counts each corner sees must match - otherwise "the corpus is the spec" would
          # just mean "both corners inherit the same reader".
          # The m0 gate, spelled out: the derivation name, spec file and corner
          # pair it always had - corpusDifferentialFor changed the corners' and
          # the check's *text* (a parameterised function now builds it), which
          # rebuilds the derivations but changes no compared quantity.
          corpus-differential = corpusDifferentialFor {
            checkName = "timbda-corpus-differential";
            specFile = "tests/corpus/m0.texpr";
            cornerCoq = cornerCoq;
            cornerOcaml = cornerOcaml;
          };
          # The M2 gate (tools/corpus/README.md sec. 8): the same builder over
          # the m2 corner pair.  A FAIL there is a finding about the m2 claims,
          # never an m0 regression - the two checks share logic, not corpus or
          # corners.
          corpus-m2-differential = corpusDifferentialFor {
            checkName = "timbda-corpus-m2-differential";
            specFile = "tests/corpus/m2-det.texpr";
            cornerCoq = cornerCoqM2;
            cornerOcaml = cornerOcamlM2;
          };

          # Every logical library the kernel Require-s resolves on the nix stack,
          # including the coinduction reification plugin (loaded via findlib/OCAMLPATH).
          coq-load-chain = pkgs.stdenv.mkDerivation {
            pname = "timbda-coq-load-chain";
            version = "0.0.0";
            src = pkgs.writeText "load_chain.v" ''
              From Coinduction Require Import all.
              From ITree Require Import Basics Indexed.Sum Core.Subevent.
              From CTree Require Import Eq.
              From ExtLib Require Import Data.List.
              From RelationAlgebra Require Import rel.
              From Stdlib Require Import ZArith.
              Definition load_chain := 1.
            '';
            nativeBuildInputs = [ stack.rocq-core.ocamlPackages.ocaml
              stack.rocq-core.ocamlPackages.findlib pkgs.which ];
            buildInputs = stack.rocqDeps;
            phases = [ "buildPhase" "installPhase" ];
            buildPhase = ''
              # rocq 9.1 forbids '-' in module identifiers, so the file is load_chain.v
              cp $src load_chain.v
              export COQPATH="$ROCQPATH''${COQPATH:+:}$COQPATH"
              rocq compile load_chain.v
            '';
            installPhase = ''mkdir -p $out && cp load_chain.vo $out/'';
          };

          # Differential harness seed (M-0 tail wires the extracted evaluator to it).
          # mkDerivation (not runCommand): we need the src tree unpacked into a writable
          # build dir, since run.sh compiles in place with ghc.
          golden-test = pkgs.stdenv.mkDerivation {
            pname = "timbda-golden-test";
            version = "0.0.0";
            src = ./tests/golden;
            nativeBuildInputs = [ pkgs.haskell.compiler.ghc912 ];
            buildPhase = "sh run.sh";
            installPhase = ''
              mkdir -p $out
              cp actual.out $out/golden.out
              cp golden.expected $out/
            '';
          };

          # --- M1 lanes (decision 9 § 5.0 items 3-4, landed 2026-11-25) -----
          # The coverage audit as a gate lane: tools/rules-audit.py diffs the
          # TimbdaRule records <-> coq/Rewriting.v ctors + Eval.v selected_rows
          # <-> RewSound_* presence in Denotation.v <-> TimbdaPatterns.td DRR
          # defs <-> docs/RULES-AUDIT.md, plus the row/status/category
          # arithmetic.  Its "exit 0 = all green" is now gate evidence, not a
          # local ritual (docs/PLAN.md § 5 M1 item 3).
          rules-audit = pkgs.stdenv.mkDerivation {
            pname = "timbda-rules-audit";
            version = "0.1.0";
            src = ./.;
            nativeBuildInputs = [ pkgs.python3 ];
            phases = [ "buildPhase" "installPhase" ];
            buildPhase = ''
              set -e
              rc=0
              cd $src
              python3 tools/rules-audit.py > $NIX_BUILD_TOP/rules-audit.log 2>&1 || rc=$?
              test "$rc" = 0 || { echo "FAIL rules-audit rc=$rc"; cat $NIX_BUILD_TOP/rules-audit.log; exit 1; }
              grep -q '^RESULT: PASS' $NIX_BUILD_TOP/rules-audit.log \
                || { echo "FAIL audit printed no PASS marker"; cat $NIX_BUILD_TOP/rules-audit.log; exit 1; }
            '';
            installPhase = ''
              mkdir -p $out
              cp $NIX_BUILD_TOP/rules-audit.log $out/
              grep '^RESULT: PASS' $NIX_BUILD_TOP/rules-audit.log > $out/status.txt
            '';
          };

          # tblgen-rocq golden (docs/PLAN.md § 5.0 item 1): regenerate
          # coq/RewRules.v, coq/RuleAst.v and coq/CheckerManifest.v from the
          # committed records and byte-diff each against its committed artifact
          # - "generated, not hand-glued" as gate evidence.  A second
          # regeneration must be byte-identical to the first (the generator is
          # deterministic), the counts must match the audit's (35 ctors, 27
          # RuleIDs, 35 manifest entries), and the unimplemented mode must
          # refuse (rc=2) rather than emit a skeleton.
          tblgen-rocq-golden = pkgs.stdenv.mkDerivation {
            pname = "timbda-tblgen-rocq-golden";
            version = "0.1.0";
            src = ./.;
            nativeBuildInputs = [ self.packages.${system}.timbda-tblgen-rocq ];
            phases = [ "buildPhase" "installPhase" ];
            buildPhase = ''
              set -e
              for mode in rules ast checker; do
                tblgen-rocq -gen-rocq-$mode $src/dialect/Timbda.td -o regen1-$mode.v
                tblgen-rocq -gen-rocq-$mode $src/dialect/Timbda.td -o regen2-$mode.v
                cmp regen1-$mode.v regen2-$mode.v \
                  || { echo "FAIL -gen-rocq-$mode regeneration is not byte-identical (nondeterministic backend)"; exit 1; }
              done
              cmp regen1-rules.v $src/coq/RewRules.v \
                || { echo "FAIL committed coq/RewRules.v differs from regeneration; run: tblgen-rocq -gen-rocq-rules dialect/Timbda.td -o coq/RewRules.v"; exit 1; }
              cmp regen1-ast.v $src/coq/RuleAst.v \
                || { echo "FAIL committed coq/RuleAst.v differs from regeneration; run: tblgen-rocq -gen-rocq-ast dialect/Timbda.td -o coq/RuleAst.v"; exit 1; }
              cmp regen1-checker.v $src/coq/CheckerManifest.v \
                || { echo "FAIL committed coq/CheckerManifest.v differs from regeneration; run: tblgen-rocq -gen-rocq-checker dialect/Timbda.td -o coq/CheckerManifest.v"; exit 1; }
              n=$(grep -c '^| Rew' regen1-rules.v)
              test "$n" = 35 || { echo "FAIL generated ctor count $n != 35"; exit 1; }
              m=$(grep -o 'R_[A-Za-z0-9]*' regen1-ast.v | sort -u | wc -l)
              test "$m" = 27 || { echo "FAIL generated RuleID count $m != 27"; exit 1; }
              k=$(grep -c '("Rew' regen1-checker.v)
              test "$k" = 35 || { echo "FAIL manifest entry count $k != 35"; exit 1; }
              rc=0
              tblgen-rocq -gen-rocq-externs $src/dialect/Timbda.td -o no1.v || rc=$?
              test "$rc" = 2 || { echo "FAIL -gen-rocq-externs did not refuse with rc=2"; exit 1; }
              test ! -e no1.v || { echo "FAIL refusing mode wrote an output"; exit 1; }
              echo "ok: coq/RewRules.v, coq/RuleAst.v and coq/CheckerManifest.v byte-identical to regeneration ($n ctors, $m RuleIDs, $k manifest entries); -gen-rocq-externs refused"
            '';
            installPhase = ''
              mkdir -p $out
              cp regen1-rules.v $out/RewRules.v
              cp regen1-ast.v $out/RuleAst.v
              cp regen1-checker.v $out/CheckerManifest.v
              echo "ok: tblgen-rocq-golden lane green (deterministic regeneration, byte-equal artifacts, honest refusals)" > $out/status.txt
            '';
          };

          # ---- dialect-lit tests (docs/PLAN.md § 5.0 item 2) ------------------
          # lit (nixpkgs) + FileCheck (the [formal.mlir_gen] pin) run tests/lit:
          # the 23 generated pdll skeletons (one per DRR ctor row, -gen-pdll-tests),
          # the handwritten populate-shape test, and the canonicalize skeleton that
          # reports UNSUPPORTED until a timbda-aware opt binary exists (M2) - an
          # honest skip, not a fake pass.  The lane also regenerates the skeletons
          # twice, byte-diffs them against the committed files (the same
          # "generated, not hand-glued" claim as tblgen-rocq-golden), and refuses
          # without the sha256-attested bazel evidence as test input.
          dialect-lit-tests = pkgs.stdenv.mkDerivation {
            pname = "timbda-dialect-lit-tests";
            version = "0.1.0";
            src = ./.;
            nativeBuildInputs = [ self.packages.${system}.timbda-tblgen-rocq
              pkgs.lit pkgs.llvmPackages_23.llvm ];
            phases = [ "buildPhase" "installPhase" ];
            buildPhase = ''
              set -e
              INC=$src/tools/build/bazel-evidence/TimbdaCanonicalization.cpp.inc
              test -f "$INC" \
                || { echo "FAIL no committed bazel evidence; run: nix develop .#cpp -c tools/build/bazel-lane.sh"; exit 1; }
              rm -rf regen1 regen2
              tblgen-rocq -gen-pdll-tests $src/dialect/Timbda.td -o regen1
              tblgen-rocq -gen-pdll-tests $src/dialect/Timbda.td -o regen2
              diff -r regen1 regen2 \
                || { echo "FAIL -gen-pdll-tests regeneration is not byte-identical"; exit 1; }
              m=$(ls regen1/*.check | wc -l)
              test "$m" = 23 || { echo "FAIL regenerated pdll skeletons $m != 23"; exit 1; }
              n=$(ls $src/tests/lit/pdll/*.check | wc -l)
              test "$n" = 23 || { echo "FAIL committed pdll skeletons $n != 23"; exit 1; }
              for f in $src/tests/lit/pdll/*.check; do
                cmp "$f" "regen1/$(basename "$f")" \
                  || { echo "FAIL committed $(basename "$f") differs from regeneration; run: tblgen-rocq -gen-pdll-tests dialect/Timbda.td -o tests/lit/pdll"; exit 1; }
              done
              export TIMBDA_DRR_INC=$INC
              rc=0
              lit $src/tests/lit -a > lit.log 2>&1 || rc=$?
              test "$rc" = 0 || { echo "FAIL lit exited $rc"; cat lit.log; exit 1; }
              grep -E "Passed|Failed|Unsupported|Unresolved" lit.log || true
              grep -qE "Passed +: 24" lit.log \
                || { echo "FAIL lit passed-count != 24 (23 pdll skeletons + populate shape test)"; cat lit.log; exit 1; }
              grep -qE "Unsupported: +1" lit.log \
                || { echo "FAIL lit unsupported-count != 1 (canonicalize/prim-fold skeleton, M2-bound)"; cat lit.log; exit 1; }
              if grep -qiE "failed|unresolved" lit.log; then
                echo "FAIL lit reported failures/unresolved tests"; cat lit.log; exit 1
              fi
              echo "ok: dialect-lit-tests green ($m generated skeletons byte-equal to committed; lit 24 passed / 1 honest unsupported)"
            '';
            installPhase = ''
              mkdir -p $out
              cp lit.log $out/
              cp -r regen1 $out/regen-skeletons
              echo "ok: dialect-lit-tests lane green (deterministic pdll skeletons, 24 lit passes, 1 registered unsupported)" > $out/status.txt
            '';
          };

          # bazel attestation, per § 6's "bazel builds, nix checks consume as
          # prebuilt": tools/build/bazel-lane.sh (bazelisk + hermetic-llvm from
          # MODULE.bazel) records the dialect build/test result in
          # tools/build/bazel-lane-status.txt; this check refuses the evidence
          # unless (a) it reports rc=0 with a PASSED dialect-test summary, (b)
          # its recorded bazel version equals the pinned .bazelversion, and (c)
          # `sha256sum -c` over its source-hash block matches THIS tree's
          # dialect/pin inputs - a stale status against a changed dialect is a
          # red gate, never a pass (docs/PLAN.md § 5 M1 item 4).
          bazel-native-tests = pkgs.stdenv.mkDerivation {
            pname = "timbda-bazel-native-tests";
            version = "0.1.0";
            src = ./.;
            phases = [ "buildPhase" "installPhase" ];
            buildPhase = ''
              set -e
              ST=$src/tools/build/bazel-lane-status.txt
              test -f "$ST" \
                || { echo "FAIL no bazel-lane status; run: nix develop .#cpp -c tools/build/bazel-lane.sh"; exit 1; }
              grep -q '^bazel_rc=0$' "$ST" || { echo "FAIL status does not record rc=0"; exit 1; }
              grep '^test_summary=' "$ST" | grep -q 'PASSED' \
                || { echo "FAIL status carries no PASSED dialect-test summary"; exit 1; }
              if grep '^test_summary=' "$ST" | grep -qE 'FAILED|TIMEOUT'; then
                echo "FAIL dialect test summary records a failure"; exit 1
              fi
              grep -q '^build_targets=.*timbda_dialect_test' "$ST" \
                || { echo "FAIL lane target set incomplete"; exit 1; }
              BV=$(grep -m1 '^bazel_version=' "$ST" | cut -d= -f2-)
              test "$BV" = "bazel $(cat $src/.bazelversion)" \
                || { echo "FAIL recorded bazel_version='$BV' != .bazelversion"; exit 1; }
              awk '/^=== source hashes ===$/{f=1;next} f' "$ST" > $NIX_BUILD_TOP/hashes.txt
              test -s $NIX_BUILD_TOP/hashes.txt || { echo "FAIL status carries no source-hash block"; exit 1; }
              cd $src
              sha256sum -c $NIX_BUILD_TOP/hashes.txt
              echo "ok: bazel evidence bound to this exact tree ($(wc -l < $NIX_BUILD_TOP/hashes.txt) hashed inputs)"
            '';
            installPhase = ''
              mkdir -p $out
              cp $src/tools/build/bazel-lane-status.txt $out/
              cp $NIX_BUILD_TOP/hashes.txt $out/
              echo "ok: bazel-native-tests lane green ($(grep -m1 '^bazel_version=' $src/tools/build/bazel-lane-status.txt | cut -d= -f2-), dialect test PASSED, evidence sha256-bound)" > $out/status.txt
            '';
          };
        });
    };
}
