final: prev: {
  foundationdb = prev.callPackage ./pkgs/foundationdb/package.nix { };
  fdbexplorer = final.callPackage ./pkgs/fdbexplorer.nix { };
}
