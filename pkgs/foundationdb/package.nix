{
  stdenv,
  fetchFromGitHub,
  lib,
  fetchpatch,
  cmake,
  ninja,
  python3,
  openjdk,
  mono,
  openssl,
  boost186,
  pkg-config,
  msgpack-cxx,
  toml11,
  jemalloc,
  doctest,
  zlib,
}:
let
  boost = boost186;
  # Only even numbered versions compile on aarch64; odd numbered versions have avx enabled.
  avxEnabled =
    version:
    let
      isOdd = n: lib.trivial.mod n 2 != 0;
      patch = lib.toInt (lib.versions.patch version);
    in
    isOdd patch;

  dylib_suffix = stdenv.hostPlatform.extensions.sharedLibrary;
  # LTO requires llvm-ar/gcc-ar to be present in PATH, which the nixpkgs
  # clang-wrapper does not expose. Disable on Darwin and during cross-compilation;
  # in both cases the regular `ar` wrapper is used instead.
  useLto = !stdenv.isDarwin && stdenv.buildPlatform == stdenv.hostPlatform;
  # Gold linker is Linux-only, part of GNU binutils, and only worthwhile alongside LTO.
  # With Clang the default linker (lld) is used instead.
  useGold = useLto && stdenv.cc.isGNU;
in
stdenv.mkDerivation rec {
  pname = "foundationdb";
  version = "7.3.68";

  src = fetchFromGitHub {
    owner = "apple";
    repo = "foundationdb";
    tag = version;
    hash = "sha256-OaV7YyBggeX3vrnI2EYwlWdIGRHOAeP5OZN0Rmd/dnw=";
  };

  patches = [
    ./disable-flowbench.patch
    ./don-t-use-static-boost-libs.patch
    # <https://github.com/apple/foundationdb/pull/12373>
    ./fix-toml11-4.0.patch
    # GetMsgpack: add 4+ versions of upstream
    # https://github.com/apple/foundationdb/pull/10935
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

  hardeningDisable = [ "fortify" ];

  postPatch = ''
    # allow using any msgpack-cxx version
    substituteInPlace cmake/GetMsgpack.cmake \
      --replace-warn 'find_package(msgpack-cxx 6 QUIET CONFIG)' 'find_package(msgpack-cxx QUIET CONFIG)'

    # Use our doctest package
    substituteInPlace bindings/c/test/unit/third_party/CMakeLists.txt \
      --replace-fail '/opt/doctest_proj_2.4.8' '${doctest}/include'

    # fmt 8.1.1 (bundled in contrib/) enables `consteval` for Clang >= 11
    # and GCC >= 10. However Clang 21+ (used via nixpkgs LLVM toolchain) has
    # stricter constant-expression evaluation that rejects fmt's
    # format_string_checker pointer arithmetic. Simply redefine FMT_CONSTEVAL
    # to empty so that format-string validation falls back to runtime checks.
    substituteInPlace contrib/fmt-8.1.1/include/fmt/core.h \
      --replace-fail \
        '#    define FMT_CONSTEVAL consteval' \
        '#    define FMT_CONSTEVAL /* disabled: broken with Clang 21+ */'

    # implib-gen.py calls bare 'readelf'; on Darwin the stdenv binutils is
    # Apple cctools which has no readelf (ELF is Linux-only). Bake in the
    # full path to GNU readelf from the cross-targeting binutils-unwrapped
    # (stdenv.cc.bintools.bintools) so the script works on all build platforms.
    substituteInPlace contrib/Implib.so/implib-gen.py \
      --replace-fail \
        'run(["readelf"' \
        'run(["${stdenv.cc.bintools.bintools}/bin/readelf"'

    # Upstream upgraded to Boost 1.86 with no code changes; see:
    # <https://github.com/apple/foundationdb/pull/11788>
    substituteInPlace cmake/CompileBoost.cmake \
      --replace-fail 'find_package(Boost 1.78.0 EXACT ' 'find_package(Boost '
  '';

  buildInputs = [
    boost
    jemalloc
    msgpack-cxx
    openssl
    toml11
    zlib
  ];

  checkInputs = [ doctest ];

  nativeBuildInputs = [
    cmake
    mono
    ninja
    openjdk
    pkg-config
    python3
  ];

  separateDebugInfo = true;

  cmakeFlags = [
    "-DFDB_RELEASE=TRUE"

    # Disable CMake warnings for project developers.
    "-Wno-dev"

    # CMake Error at fdbserver/CMakeLists.txt:332 (find_library):
    # >   Could not find lz4_STATIC_LIBRARIES using the following names: liblz4.a
    "-DSSD_ROCKSDB_EXPERIMENTAL=FALSE"

    "-DBUILD_DOCUMENTATION=FALSE"

    # Disable the default static linking to libc++, libstdc++ and libgcc.
    #
    # This leads to various, non-obvious problems as our dependencies bring in
    # their own copies of these libraries.
    "-DSTATIC_LINK_LIBCXX=FALSE"

    # LTO brings up overall build time, but results in much smaller
    # binaries for all users and the cache.
    (if useLto then "-DUSE_LTO=ON" else "-DUSE_LTO=OFF")

    # Gold helps alleviate the link time, especially when LTO is
    # enabled. But even then, it still takes a majority of the time.
    (if useGold then "-DUSE_LD=GOLD" else "-DUSE_LD=DEFAULT")

    # FIXME: why can't openssl be found automatically?
    "-DOPENSSL_USE_STATIC_LIBS=FALSE"
    "-DOPENSSL_CRYPTO_LIBRARY=${openssl.out}/lib/libcrypto${dylib_suffix}"
    "-DOPENSSL_SSL_LIBRARY=${openssl.out}/lib/libssl${dylib_suffix}"
  ];

  # the install phase for cmake is pretty wonky right now since it's not designed to
  # coherently install packages as most linux distros expect -- it's designed to build
  # packaged artifacts that are shipped in RPMs, etc. we need to add some extra code to
  # cmake upstream to fix this, and if we do, i think most of this can go away.
  postInstall = ''
    mv $out/sbin/fdbmonitor $out/bin/fdbmonitor
    mkdir $out/libexec && mv $out/usr/lib/foundationdb/backup_agent/backup_agent $out/libexec/backup_agent
    mv $out/sbin/fdbserver $out/bin/fdbserver

    rm -rf $out/etc $out/lib/foundationdb $out/lib/systemd $out/log $out/sbin $out/usr $out/var

    # move results into multi outputs
    mkdir -p $dev $lib
    mv $out/include $dev/include
    mv $out/lib $lib/lib

    # python bindings
    # NB: use the original setup.py.in, so we can substitute VERSION correctly
    cp ../LICENSE ./bindings/python
    substitute ../bindings/python/setup.py.in ./bindings/python/setup.py \
      --replace 'VERSION' "${version}"
    rm -f ./bindings/python/setup.py.* ./bindings/python/CMakeLists.txt
    rm -f ./bindings/python/fdb/*.pth # remove useless files
    rm -f ./bindings/python/*.rst ./bindings/python/*.mk

    cp -R ./bindings/python/                          tmp-pythonsrc/
    tar -zcf $pythonsrc --transform s/tmp-pythonsrc/python-foundationdb/ ./tmp-pythonsrc/

    # java bindings
    mkdir -p $lib/share/java
    mv lib/fdb-java-*.jar $lib/share/java/fdb-java.jar
  '';

  outputs = [
    "out"
    "dev"
    "lib"
    "pythonsrc"
  ];

  meta = {
    description = "Open source, distributed, transactional key-value store";
    homepage = "https://www.foundationdb.org";
    license = lib.licenses.asl20;
    platforms = [
      "x86_64-linux"
      "x86_64-darwin"
    ]
    ++ lib.optionals (!(avxEnabled version)) [
      "aarch64-linux"
      "aarch64-darwin"
    ];

    maintainers = with lib.maintainers; [
      thoughtpolice
      lostnet
      alekseysidorov
    ];
  };
}
