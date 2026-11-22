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
        value = f system (import nixpkgs { inherit system; });
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
        in
        {
          inherit rocq-core rocq-stdlib rocq-shims coqPathHook userContrib ocamlForRocq;
          inherit coq-ext-lib paco rocq-coinduction coq-itree rocq-ctree;
          # everything the kernel's `From X Require` lines resolve against
          rocqDeps = [ rocq-core rocq-stdlib coq-ext-lib paco rocq-coinduction coq-itree
            rocq-ctree pkgs.rocqPackages.relation-algebra pkgs.coqPackages.equations ];
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
          };
          # Where the kernel package's .vo trees land, for corners that `Require Import
          # Timbda.*` without going through dune (the two corpus corners).
          kernelTheoryDir =
            "${self.packages.${system}.timbda-kernel}/${stack.userContrib}";

          mkCorpusCoqCorner = { cornerName, specFile }: pkgs.stdenv.mkDerivation {
            pname = cornerName;
            version = "0.1.0";
            src = ./.;
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
            src = ./.;
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

          # Compiler side (Bazel / hermetic-llvm leg arrives at M-2, PLAN sec. 6.2).
          cpp = pkgs.mkShell { packages = [ pkgs.bazelisk pkgs.git pkgs.python3 ]; };

          # Reference semantics / differential harness side (M-0 tail).
          hs = pkgs.mkShell {
            packages = [ pkgs.haskell.compiler.ghc912 pkgs.cabal-install pkgs.git pkgs.python3 ];
          };

          # Everything at once (the canonical shell of docs/DESIGN-NOTES.md sec. 4).
          all = pkgs.mkShell {
            packages = with pkgs; [ bazelisk git python3 haskell.compiler.ghc912 cabal-install
              rocqPackages.vsrocq-language-server ]
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
        });
    };
}
