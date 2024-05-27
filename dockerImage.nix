{ pkgs
, dockerTools
}:

let
  fdbVersion = pkgs.fdbPackages.foundationdb73.version;
  platform = pkgs.stdenv.targetPlatform.qemuArch;

  port = "4689";
  clusterFile = pkgs.writeText "fdb.cluster" "test1:testdb1@127.0.0.1:${port}";

  entryPoint = pkgs.writeShellScriptBin "entry-point.sh"
    ''
      uname -a
      mkdir -p /var/foundationdb/logs
      mkdir -p /var/foundationdb/data

      echo "Starting FDB server on 0.0.0.0:${port}"
      fdbcli -C ${clusterFile} --exec "configure new single memory; status" &
              
      fdbserver -p 0.0.0.0:${port} \
        --datadir /var/foundationdb/data -C ${clusterFile} \
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
      Expose = port;
    };
  };

  # Workaround: passthru doesn't work for docker images, so we have to use merge.
  extendedAttrs =
    let
      passthru = dockerImage.passthru // {
        inherit port clusterFile platform;
        fdbVersion = pkgs.fdbPackages.foundationdb73.version;
      };
    in
    passthru // { inherit passthru; };
in
dockerImage // extendedAttrs
