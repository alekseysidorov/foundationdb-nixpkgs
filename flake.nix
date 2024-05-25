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

      runDockerImage = dockerImage:
        pkgs.writeShellApplication {
          name = "run-docker-image";
          runtimeInputs = with pkgs; [ docker ];
          text = ''
            docker load --input ${dockerImage}
            docker run -it ${dockerImage.imageName}:${dockerImage.imageTag}
          '';
        };
    in
    rec {
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

        # FoundationDB configuration for local launch.
        env.FDB_CLUSTER_FILE = packages.pushDockerImage.clusterFile;
      };

      packages =
        let
          imageName = "alekseysidorov/foundationdb";
          imageTag = "7.42";

          dockerImages = {
            aarch64 = mkDockerImage {
              inherit imageName imageTag;
              platform = "aarch64";
            };
            x86_64 = mkDockerImage {
              inherit imageName imageTag;
              platform = "x86_64";
            };
          };
        in
        {
          foundationdb73 = pkgs.fdbPackages.foundationdb73;

          dockerImage_aarch64 = runDockerImage dockerImages.aarch64;
          dockerImage_x86_64 = runDockerImage dockerImages.x86_64;

          pushDockerImage = pkgs.writeShellApplication {
            name = "push-docker-image";
            runtimeInputs = with pkgs; [ docker ];

            passthru.clusterFile = dockerImages.aarch64.clusterFile;

            text = ''
              set -x

              docker load --input ${dockerImages.aarch64}
              docker load --input ${dockerImages.x86_64}

              docker push ${dockerImages.aarch64.imageName}:${dockerImages.aarch64.imageTag}
              docker push ${dockerImages.x86_64.imageName}:${dockerImages.x86_64.imageTag}

              docker manifest create ${imageName}:${imageTag} \
                --amend ${dockerImages.aarch64.imageName}:${dockerImages.aarch64.imageTag} \
                --amend ${dockerImages.x86_64.imageName}:${dockerImages.x86_64.imageTag}
              docker manifest push ${imageName}:${imageTag}

              # Publish also as latest
              docker manifest create ${imageName}:latest \
                --amend ${dockerImages.aarch64.imageName}:${dockerImages.aarch64.imageTag} \
                --amend ${dockerImages.x86_64.imageName}:${dockerImages.x86_64.imageTag}
              docker manifest push ${imageName}:latest
            '';
          };
        };
    });
}
