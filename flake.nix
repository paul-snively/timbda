{
  description = "Timbda-0 verified compiler; M-1 build-infra skeleton (PLAN.md step 0)";

  # All source pins mirror tools/pins/pins.toml (flake_input names must match);
  # CI asserts flake.lock == pins.toml via tools/pins/pins.py.
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/b349185bb79c7cf7ad8ea8c097931730bf473c71";
    # flake = false: these upstreams are source-only (no flake.nix) — we build
    # them with our own derivations, the inputs exist to lock the revisions.
    mlir-wasm-dialect.url = "github:CMUAbstract/mlir-wasm-dialect/6be18d00a0c1472a4415f24deb9ba72101c8132e";
    mlir-wasm-dialect.flake = false;
    ctrees.url = "github:vellvm/ctrees/cabcf9bf24b0f459204a7da19ac01b7697ff04e3";
    ctrees.flake = false;
    interaction-trees.url = "github:DeepSpec/InteractionTrees/284d42248a3c5517cff9f582e335fcee2f6bdc1f";
    interaction-trees.flake = false;
    coq-ext-lib.url = "github:rocq-community/coq-ext-lib/c5cdb83d48786ca2680c6d817c19bb99f68d4ca3";
    coq-ext-lib.flake = false;
    coinduction.url = "github:damien-pous/coinduction/07d2a09f9cb971209683298e9f5b3f5031d98b3f";
    coinduction.flake = false;
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
        "coinduction" "certirocq" "veriffi" "verse-semantics" ];
    in
    {
      packages = forAllSystems (system: pkgs:
        let
          rocqPackages = pkgs.rocqPackages;
        in
        {
          # Trivial Rocq kernel stub (M-1): compiles with the pinned rocq.
          timbda-kernel = pkgs.stdenv.mkDerivation {
            pname = "timbda-kernel-stub";
            version = "0.0.0";
            src = ./coq;
            nativeBuildInputs = [ rocqPackages.rocq-core ];
            buildPhase = "rocq compile KernelStub.v";
            installPhase = ''
              mkdir -p $out/lib/rocq
              cp KernelStub.vo KernelStub.vok KernelStub.vos KernelStub.glob $out/lib/rocq/
            '';
          };

          # Locks every pinned source repo on day one (PLAN sec. 6 "lock day one"):
          # a cheap derivation that just exposes the fetched source trees.
          # (Note: '' strings don't process \n — line breaks here are real.)
          pin-sources = pkgs.runCommand "timbda-pin-sources" { }
            (''
                mkdir -p $out
              ''
              + nixpkgs.lib.concatMapStrings (name:
                  ''
                    ln -s ${inp."${name}".outPath} $out/${name}
                  ''
                ) srcInputNames);
        });

      devShells = forAllSystems (system: pkgs: {
        # NOTE: no rocqPackages.withPackages in nixos-26.05 (probe, 2026-11);
        # PLAN's withPackages idiom re-probes at M-2 when real kernel deps land.
        cpp = pkgs.mkShell { packages = [ pkgs.bazelisk pkgs.git pkgs.python3 ]; };
        rocq = pkgs.mkShell {
          packages = [
            pkgs.rocqPackages.rocq-core
            pkgs.rocqPackages.stdpp
            pkgs.coqPackages.equations
            pkgs.rocqPackages.vsrocq-language-server
          ];
        };
        hs = pkgs.mkShell {
          packages = [ pkgs.haskell.compiler.ghc912 pkgs.cabal-install ];
        };
        all = pkgs.mkShell {
          packages = with pkgs; [
            bazelisk git python3
            rocqPackages.rocq-core rocqPackages.stdpp coqPackages.equations
            rocqPackages.vsrocq-language-server
            haskell.compiler.ghc912 cabal-install
            wasmtime lit
          ];
        };
      });

      checks = forAllSystems (system: pkgs: {
          # nixpkgs-provided tool versions == pin table (the other half of the
          # consistency check lives in tools/pins/pins.py).
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

          coq-kernel-tests = self.packages.${system}.timbda-kernel;

          # mkDerivation (not runCommand): we need the src tree unpacked into a
          # writable build dir, since run.sh compiles in place with ghc.
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
