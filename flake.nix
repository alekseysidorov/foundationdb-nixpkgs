{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    nixpkgs-cross-overlay = {
      url = "github:alekseysidorov/nixpkgs-cross-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
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

      mkDockerImage = { platform, imageName ? "foundationdb" }:
        let
          # Setup pkgs for cross compilation
          pkgsCross = import nixpkgs {
            inherit system;
            crossSystem.config = "${platform}-unknown-linux-gnu";
            overlays = [
              nixpkgs-cross-overlay.outputs.overlays.default
              localOverlay
            ];
          };
        in
        pkgsCross.callPackage ./dockerImage.nix { };

      runDockerImage = dockerImage:
        pkgs.writeShellApplication {
          name = "run-docker-image";
          runtimeInputs = with pkgs; [ docker ];
          text = ''
            docker load --input ${dockerImage}
            docker run -it ${dockerImage.imageName}:${dockerImage.imageTag}
          '';
        };

      dockerImages = {
        aarch64 = mkDockerImage {
          platform = "aarch64";
        };
        x86_64 = mkDockerImage {
          platform = "x86_64";
        };

        # Export variables that are the same for each image.
        clusterFile = dockerImages.aarch64.clusterFile;
        imageName = dockerImages.aarch64.imageName;
        fdbVersion = dockerImages.aarch64.fdbVersion;
      };
    in
    {
      # for `nix fmt`
      formatter = treefmt.wrapper;
      # for `nix flake check`
      checks.formatting = treefmt.check self;
      # Overlay with the foundationdb packages.
      overlays.default = localOverlay;

      devShells = with pkgs; rec {
        foundationdb71 = mkShell {
          nativeBuildInputs = [
            fdbPackages.foundationdb71
          ];
        };
        foundationdb73 = mkShell {
          nativeBuildInputs = [
            fdbexplorer
            fdbPackages.foundationdb73
          ];
        };
        default = foundationdb73;
      };

      packages = {
        foundationdb73 = pkgs.fdbPackages.foundationdb73;
        foundationdb71 = pkgs.fdbPackages.foundationdb71;

        dockerImage_aarch64 = runDockerImage dockerImages.aarch64;
        dockerImage_x86_64 = runDockerImage dockerImages.x86_64;

        pushDockerImage = pkgs.writeShellApplication {
          name = "push-docker-image";
          runtimeInputs = with pkgs; [ docker ];

          text = ''
            set -x

            docker load --input ${dockerImages.aarch64}
            docker load --input ${dockerImages.x86_64}

            docker push ${dockerImages.aarch64.imageName}:${dockerImages.aarch64.imageTag}
            docker push ${dockerImages.x86_64.imageName}:${dockerImages.x86_64.imageTag}

            docker manifest create ${dockerImages.imageName}:${dockerImages.fdbVersion} \
              --amend ${dockerImages.aarch64.imageName}:${dockerImages.aarch64.imageTag} \
              --amend ${dockerImages.x86_64.imageName}:${dockerImages.x86_64.imageTag}
            docker manifest push ${dockerImages.imageName}:${dockerImages.fdbVersion}

            # Publish also as latest
            docker manifest create ${dockerImages.imageName}:latest \
              --amend ${dockerImages.aarch64.imageName}:${dockerImages.aarch64.imageTag} \
              --amend ${dockerImages.x86_64.imageName}:${dockerImages.x86_64.imageTag}
            docker manifest push ${dockerImages.imageName}:latest
          '';
        };
      };
    });
}
