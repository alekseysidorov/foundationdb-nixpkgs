{ gccStdenv
, llvmPackages
, stdenv
, lib
, fetchFromGitHub
, fetchpatch

, cmake
, ninja
, python3
, mono
, openssl
, boost178
, pkg-config
, msgpack-cxx
, toml11
, jemalloc
, darwin
, writeShellScriptBin
} @args:

let
  cmakeBuild = import ./cmake.nix args;
in
{
  foundationdb73 = cmakeBuild {
    version = "7.3.28";
    hash = "sha256-CNJ4w1ECadj2KtcfbBPBQpXQeq9BAiw54hUgRTWPFzY=";
    boost = boost178;
    ssl = openssl;

    patches = [
      ./patches/disable-flowbench.patch
      ./patches/don-t-run-tests-requiring-doctest.patch
      ./patches/don-t-use-static-boost-libs.patch
      ./patches/fix-open-with-O_CREAT.patch
      # GetMsgpack: add 4+ versions of upstream
      # https://github.com/apple/foundationdb/pull/10935
      (fetchpatch {
        url = "https://github.com/apple/foundationdb/commit/c35a23d3f6b65698c3b888d76de2d93a725bff9c.patch";
        hash = "sha256-bneRoZvCzJp0Hp/G0SzAyUyuDrWErSpzv+ickZQJR5w=";
      })
    ];
  };
}
