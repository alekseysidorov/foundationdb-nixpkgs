{ pkgs
, dockerTools
}:

let
  fdbVersion = pkgs.fdbPackages.foundationdb73.version;
  platform = pkgs.stdenv.targetPlatform.qemuArch;

  entryPoint = pkgs.writeShellScriptBin "entry-point.sh"
    ''
      # Preparing environment
      mkdir -p /var/foundationdb/logs
      mkdir -p /var/foundationdb/data
      
      FDB_PORT="''${FDB_PORT:=4500}"
      FDB_CLUSTER_FILE="/var/foundationdb/fdb.cluster"
      echo "Creating FDB cluster file..."
      echo "test1:testdb1@127.0.0.1:$FDB_PORT" > $FDB_CLUSTER_FILE

      echo ""
      cat $FDB_CLUSTER_FILE
      
      echo "Starting FDB server on 0.0.0.0:$FDB_PORT"
      fdbcli -C $FDB_CLUSTER_FILE --exec "configure new single memory; status" &
              
      fdbserver -p 0.0.0.0:$FDB_PORT \
        -C $FDB_CLUSTER_FILE
        --datadir /var/foundationdb/data \
        --logdir /var/foundationdb/logs
    '';

  dockerImage = dockerTools.buildLayeredImage {
    name = "alekseysidorov/foundationdb";
    tag = "${fdbVersion}_${platform}";


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
    };
  };

  # Workaround: passthru doesn't work for docker images, so we have to use merge.
  extendedAttrs =
    let
      passthru = dockerImage.passthru // {
        fdbVersion = pkgs.fdbPackages.foundationdb73.version;
      };
    in
    passthru // { inherit passthru; };
in
dockerImage // extendedAttrs
