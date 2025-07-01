{ dockerTools
, stdenv
, writeShellScriptBin
, buildEnv
, coreutils
, bash
, pkgs
, fdbPackages
, fdb ? fdbPackages.foundationdb71
}:

let
  fdbVersion = fdb.version;
  platform = stdenv.targetPlatform.qemuArch;

  entryPoint = writeShellScriptBin "entry-point.sh"
    ''
      # Preparing environment
      mkdir -p /var/foundationdb/logs
      mkdir -p /var/foundationdb/data

      FDB_PORT="''${FDB_PORT:=4500}"
      FDB_CLUSTER_FILE="/var/foundationdb/fdb.cluster"
      echo "Creating FDB cluster file..."
      echo "docker:dockerdb@127.0.0.1:$FDB_PORT" > $FDB_CLUSTER_FILE
      echo ""
      cat $FDB_CLUSTER_FILE

      echo "Starting FDB server on 0.0.0.0:$FDB_PORT"
      fdbcli -C $FDB_CLUSTER_FILE --exec "configure new single memory; status" &

      fdbserver -p 0.0.0.0:$FDB_PORT \
        -C $FDB_CLUSTER_FILE
        --datadir /var/foundationdb/data \
        --logdir /var/foundationdb/logs
    '';

  dockerImage = dockerTools.streamLayeredImage {
    name = "alekseysidorov/foundationdb";
    tag = "${fdbVersion}_${platform}";

    contents = [
      fdb
      # Certificates
      dockerTools.usrBinEnv
      dockerTools.binSh
      dockerTools.caCertificates
      dockerTools.fakeNss
      entryPoint
    ];

    config = {
      Cmd = [ "/bin/entry-point.sh" ];
      WorkingDir = "/";
    };
  };

  runDockerImage = dockerTools.buildImage {
    name = "alekseysidorov/foundationdb";
    tag = "${fdbVersion}_${platform}";

    copyToRoot = buildEnv {
      name = "image-root";
      paths = [
        coreutils
        bash
        fdb
        # Certificates
        dockerTools.usrBinEnv
        dockerTools.binSh
        dockerTools.caCertificates
        dockerTools.fakeNss
        entryPoint
      ];
      pathsToLink = [ "/bin" ];
    };

    config = {
      Cmd = [ "/bin/entry-point.sh" ];
      WorkingDir = "/";
    };
  };


  # Workaround: passthru doesn't work for docker images, so we have to use merge.
  extendedAttrs =
    let
      passthru = dockerImage.passthru // {
        fdbVersion = fdb.version;
      };
    in
    passthru // { inherit passthru; };
in
dockerImage // extendedAttrs
