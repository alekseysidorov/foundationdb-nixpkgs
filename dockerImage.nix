{ pkgs
, dockerTools
, name ? "foundationdb"
, tag ? "latest"
}:

let
  port = "4689";
  clusterFile = pkgs.writeText "fdb.cluster" "test1:testdb1@127.0.0.1:${port}";

  entryPoint = pkgs.writeShellScriptBin "entry-point.sh"
    ''
      uname -a
      mkdir -p /var/foundationdb/logs
      mkdir -p /var/foundationdb/data

      fdbcli -C ${clusterFile} --exec "configure new single memory; status details" &
              
      fdbserver -p 0.0.0.0:${port} \
        --datadir /var/foundationdb/data -C ${clusterFile} \
        --logdir /var/foundationdb/logs
    '';

in
dockerTools.buildLayeredImage {
  inherit name tag;

  contents = with pkgs; [
    fdbPackages.foundationdb73
    # Certificates
    dockerTools.usrBinEnv
    dockerTools.binSh
    dockerTools.caCertificates
    dockerTools.fakeNss
    # Utilites like ldd and bash to help image debugging
    stdenv.cc.libc_bin
    coreutils
    bashInteractive
    nano
    entryPoint
  ];

  config = {
    Cmd = [ "/bin/entry-point.sh" ];
    WorkingDir = "/";
    Expose = port;
  };

  passthru = {
    inherit port clusterFile;
  };
}
