{ pkgs
, fetchpatch
}:

{
  foundationdb73 = pkgs.callPackage ./cmake.nix {
    version = "7.3.40";
    hash = "sha256-ijXQjl2+GXzEbJM4O/rx3nSlLUWFHDJ+kFHk/aDB6Us=";

    patches = [
      ./patches/disable-flowbench.patch
      ./patches/don-t-use-static-boost-libs.patch
      ./patches/disable-c-binding-tests.patch
      # # GetMsgpack: add 4+ versions of upstream
      # # https://github.com/apple/foundationdb/pull/10935
      (fetchpatch {
        url = "https://github.com/apple/foundationdb/commit/c35a23d3f6b65698c3b888d76de2d93a725bff9c.patch";
        hash = "sha256-bneRoZvCzJp0Hp/G0SzAyUyuDrWErSpzv+ickZQJR5w=";
      })

      # ./patches/fix-open-with-O_CREAT.patch
    ];
  };
}
