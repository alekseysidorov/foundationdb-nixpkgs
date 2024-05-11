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
      # Setup nixpkgs
      pkgs = import nixpkgs {
        inherit system;
        overlays = [
          nixpkgs-cross-overlay.outputs.overlays.default
          (import ./.)
        ];
      };
      # Eval the treefmt modules from ./treefmt.nix
      treefmt = (treefmt-nix.lib.evalModule pkgs ./treefmt.nix).config.build;
    in
    {
      # for `nix fmt`
      formatter = treefmt.wrapper;
      # for `nix flake check`
      checks.formatting = treefmt.check self;
      # Overlay with the foundationdb packages.
      overlays.default = import ./.;
      
      packages = {
        foundationdb73 = pkgs.fdbPackages.foundationdb73;
      };
    });
}
