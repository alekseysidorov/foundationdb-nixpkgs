{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-old.url = "github:NixOS/nixpkgs/nixos-24.05";

    treefmt-nix.url = "github:numtide/treefmt-nix";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-old,
      flake-utils,
      treefmt-nix,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        localOverlay = (import ./.);

        # Setup nixpkgs
        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            localOverlay
          ];
        };

        # Eval the treefmt modules from ./treefmt.nix
        treefmt = (treefmt-nix.lib.evalModule pkgs ./treefmt.nix).config.build;

        mkDockerImage =
          { platform, foundationdb }:
          let
            pkgsOld = import nixpkgs-old {
              inherit system;
            };

            # Setup pkgs for cross compilation
            pkgsCross = import nixpkgs {
              inherit system;
              crossSystem.config = "${platform}-unknown-linux-gnu";
              overlays = [
                localOverlay
                (final: prev: {
                  # Use old fakeroot without "symbol not found in flat namespace '_fstat$INODE64'" bug.
                  # TODO fix this bug in upstream fakeroot.
                  fakeroot = pkgsOld.fakeroot;
                })
              ];
            };
          in
          pkgsCross.callPackage ./dockerImage.nix { inherit foundationdb; };

        runDockerImage =
          dockerImage:
          pkgs.writeShellApplication {
            name = "run-docker-image";
            runtimeInputs = with pkgs; [ docker ];
            text = ''
              docker load --input ${dockerImage}
              docker run -it ${dockerImage.imageName}:${dockerImage.imageTag}
            '';
          };

        pushDockerImage =
          {
            dockerImage,
            revision ? null,
          }:
          let
            # Export variables that are the same for each image.
            fdbVersion = dockerImage.aarch64.fdbVersion;
            imageName = dockerImage.aarch64.imageName;
            imageTag = if revision == null then "${fdbVersion}" else "${fdbVersion}-${revision}";
          in
          pkgs.writeShellApplication {
            name = "push-docker-image";
            runtimeInputs = with pkgs; [ docker ];

            text = ''
              docker load --input ${dockerImage.aarch64}
              docker load --input ${dockerImage.x86_64}

              docker push ${dockerImage.aarch64.imageName}:${dockerImage.aarch64.imageTag}
              docker push ${dockerImage.x86_64.imageName}:${dockerImage.x86_64.imageTag}

              docker manifest create ${imageName}:${imageTag} \
                --amend ${dockerImage.aarch64.imageName}:${dockerImage.aarch64.imageTag} \
                --amend ${dockerImage.x86_64.imageName}:${dockerImage.x86_64.imageTag}
              docker manifest push ${imageName}:${imageTag}
            '';
          };

        dockerImages = {
          foundationdb71 = {
            aarch64 = mkDockerImage {
              platform = "aarch64";
              foundationdb = "foundationdb71";
            };
            x86_64 = mkDockerImage {
              platform = "x86_64";
              foundationdb = "foundationdb71";
            };
          };

          foundationdb73 = {
            aarch64 = mkDockerImage {
              platform = "aarch64";
              foundationdb = "foundationdb73";
            };
            x86_64 = mkDockerImage {
              platform = "x86_64";
              foundationdb = "foundationdb73";
            };
          };
        };
      in
      {
        # for `nix fmt`
        formatter = treefmt.wrapper;
        # for `nix flake check`
        checks.formatting = treefmt.check self;

        devShells = with pkgs; rec {
          foundationdb71 = mkShell {
            nativeBuildInputs = [
              fdbPackages.foundationdb71
            ];
          };
          foundationdb73 = mkShell {
            nativeBuildInputs = [
              fdbPackages.foundationdb73
            ];
          };
          default = mkShell {
            nativeBuildInputs = [
              fdbPackages.foundationdb73
              typos-lsp
            ];
          };
        };

        packages = {
          foundationdb73 = pkgs.fdbPackages.foundationdb73;
          foundationdb71 = pkgs.fdbPackages.foundationdb71;
          fdbexplorer = pkgs.fdbexplorer;

          docker-image-foundationdb71-aarch64 = runDockerImage dockerImages.foundationdb71.aarch64;
          docker-image-foundationdb71-x86_64 = runDockerImage dockerImages.foundationdb71.x86_64;
          docker-image-foundationdb73-aarch64 = runDockerImage dockerImages.foundationdb73.aarch64;
          docker-image-foundationdb73-x86_64 = runDockerImage dockerImages.foundationdb73.x86_64;

          push-docker-image-foundationdb71 = pushDockerImage {
            dockerImage = dockerImages.foundationdb71;
            revision = "2";
          };
          push-docker-image-foundationdb73 = pushDockerImage {
            dockerImage = dockerImages.foundationdb73;
            revision = "2";
          };
        };

        apps = {
          fdbexplorer = flake-utils.lib.mkApp {
            drv = self.packages.${system}.fdbexplorer;
          };
        };
      }
    )
    # System independent modules.
    // {
      # The usual flake attributes can be defined here, including system-
      # agnostic ones like nixosModule and system-enumerating ones, although
      # those are more easily expressed in perSystem.
      overlays.default = import ./.;
    };
}
