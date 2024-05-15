{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-cross-overlay.url = "github:alekseysidorov/nixpkgs-cross-overlay";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    { self
    , nixpkgs
    , nixpkgs-cross-overlay
    , flake-utils
    , treefmt-nix
    }: flake-utils.lib.eachDefaultSystem (system:
    let
      localOverlay = (import ./.);

      # Setup nixpkgs
      pkgs = import nixpkgs {
        inherit system;
        overlays = [
          nixpkgs-cross-overlay.outputs.overlays.default
          localOverlay
        ];
      };

      # Eval the treefmt modules from ./treefmt.nix
      treefmt = (treefmt-nix.lib.evalModule pkgs ./treefmt.nix).config.build;

      # FoundationDB configuration for local launch.
      fdb = rec {
        port = "4689";
        cluster = pkgs.writeText "fdb.cluster" "test1:testdb1@127.0.0.1:${port}";
      };

      mkDockerImage = crossSystem:
        let
          # Setup pkgs for cross compilation
          pkgsCross = pkgs.mkCrossPkgs {
            src = nixpkgs;
            inherit crossSystem;
            localSystem = system;
            overlays = [
              localOverlay
            ];
          };
          dockerTools = pkgsCross.pkgsBuildHost.dockerTools;

          entryPoint = pkgsCross.writeShellScriptBin "entry-point.sh"
            ''
              mkdir -p /var/foundationdb/logs
              mkdir -p /var/foundationdb/data

              fdbcli -C ${fdb.cluster} --exec "configure new single memory; status details" &
              fdbserver -p 0.0.0.0:${fdb.port} \
                --datadir /var/foundationdb/data -C ${fdb.cluster} \
                --logdir /var/foundationdb/logs
            '';
        in
        dockerTools.buildLayeredImage {
          name = "foundationdb";
          tag = "latest";

          contents = with pkgsCross; [
            fdbPackages.foundationdb73
            # Certificates
            dockerTools.usrBinEnv
            dockerTools.binSh
            dockerTools.caCertificates
            dockerTools.fakeNss
            # Utilites like ldd and bash to help image debugging
            stdenv.cc.libc_bin
            coreutils
            bashInteractive
            nano
            entryPoint
          ];

          config = {
            Cmd = [ "/bin/entry-point.sh" ];
            WorkingDir = "/";
            Expose = fdb.port;
          };
        };

      loadDockerImage = { dockerImage }: pkgs.writeScriptBin "load-docker" ''
        docker=${pkgs.docker}/bin/docker
        docker load -i "${dockerImage}"
      '';
    in
    {
      # for `nix fmt`
      formatter = treefmt.wrapper;
      # for `nix flake check`
      checks.formatting = treefmt.check self;
      # Overlay with the foundationdb packages.
      overlays.default = localOverlay;

      devShells.default = pkgs.mkShell {
        buildInputs = with pkgs; [
          fdbPackages.foundationdb73
        ];

        env = {
          FDB_CLUSTER_FILE = "${fdb.cluster}";
        };
      };

      packages = {
        foundationdb73 = pkgs.fdbPackages.foundationdb73;
        dockerImage_aarch64 = loadDockerImage {
          dockerImage = mkDockerImage { config = "aarch64-unknown-linux-gnu"; };
        };
        dockerImage_x86_64 = mkDockerImage { config = "x86_64-unknown-linux-gnu"; };
      };
    });
}
