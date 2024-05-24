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

      mkDockerImage = { platform, imageName ? "foundationdb", imageTag ? "latest" }:
        let
          # Setup pkgs for cross compilation
          pkgsCross = pkgs.mkCrossPkgs {
            src = nixpkgs;
            localSystem = system;
            crossSystem.config = "${platform}-unknown-linux-gnu";
            overlays = [
              localOverlay
            ];
          };
        in
        pkgsCross.callPackage ./dockerImage.nix {
          tag = "${imageTag}_${platform}";
          name = imageName;
        };
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
          # FoundationDB configuration for local launch.
          FDB_CLUSTER_FILE = "${pkgs.writeText "fdb.cluster" "test1:testdb1@127.0.0.1:4689"}";
        };
      };

      packages = {
        foundationdb73 = pkgs.fdbPackages.foundationdb73;

        dockerImage =
          let
            imageName = "alekseysidorov/foundationdb";
            imageTag = "latest";
            dockerImages = {
              aarch64 = mkDockerImage { inherit imageName imageTag; platform = "aarch64"; };
              x86_64 = mkDockerImage { inherit imageName imageTag; platform = "x86_64"; };
            };
          in
          pkgs.writeShellApplication {
            name = "run-docker-image";
            runtimeInputs = with pkgs; [ docker skopeo ];

            text = ''
              set -x

              docker load --input ${dockerImages.aarch64}
              docker load --input ${dockerImages.x86_64}
              docker run -it ${imageName}:${imageTag}_aarch64
            '';
          };
      };
    });
}
