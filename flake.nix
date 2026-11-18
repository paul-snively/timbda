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
