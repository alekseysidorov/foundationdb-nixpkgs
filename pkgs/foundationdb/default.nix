{ pkgs
, fetchpatch
}:

rec {
  latest = foundationdb73;

  foundationdb73 = pkgs.callPackage ./cmake.nix {
    version = "7.3.63";
    hash = "sha256-fUyxV6oZdJOh0mv+uWz4hiNqyQHDR6hekTLS62XlPM8=";

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
      # Add a dependency that prevents bindingtester to run before the python bindings are generated
      # https://github.com/apple/foundationdb/pull/11859
      (fetchpatch {
        url = "https://github.com/apple/foundationdb/commit/8d04c97a74c6b83dd8aa6ff5af67587044c2a572.patch";
        hash = "sha256-ZLIcmcfirm1+96DtTIr53HfM5z38uTLZrRNHAmZL6rc=";
      })
    ];
  };

  foundationdb71 = pkgs.callPackage ./cmake.nix {
    version = "7.1.61";
    hash = "sha256-D+jlhhAmTZx2n84L+TxiVjiSXP5aWeZDbosEp4m2xas=";

    patches = [
      ./patches/disable-flowbench.patch
      ./patches/don-t-use-static-boost-libs.patch
      ./patches/don-t-run-tests-requiring-doctest.patch
      # # GetMsgpack: add 4+ versions of upstream
      # # https://github.com/apple/foundationdb/pull/10935
      (fetchpatch {
        url = "https://github.com/apple/foundationdb/commit/c35a23d3f6b65698c3b888d76de2d93a725bff9c.patch";
        hash = "sha256-bneRoZvCzJp0Hp/G0SzAyUyuDrWErSpzv+ickZQJR5w=";
      })
    ];
  };
}
