final: prev: {
  fdbPackages = prev.callPackage ./pkgs/foundationdb { };
  fdbexplorer = prev.callPackage ./pkgs/fdbexplorer.nix { };
}
