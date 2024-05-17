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
        in pkgsCross.callPackage ./dockerImage.nix { };

      dockerImages = {
        arm64 = mkDockerImage { config = "aarch64-unknown-linux-gnu"; };
        x86_64 = mkDockerImage { config = "x86_64-unknown-linux-gnu"; };
      };

            runDockerImage = dockerImage: pkgs.writeScriptBin "load-docker" ''
        docker=${pkgs.docker}/bin/docker
        docker load -i "${dockerImage}"
        docker run -it "${dockerImage.imageName}:${dockerImage.imageTag}"
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

        dockerImage_arm64 = runDockerImage dockerImages.arm64;
        dockerImage_x86_64 = runDockerImage dockerImages.x86_64;
      };
    });
}
