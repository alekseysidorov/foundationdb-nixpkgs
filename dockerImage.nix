{
  dockerTools,
  writeShellScriptBin,
  coreutils,
  hostname,
  bash,
  foundationdb,
}:

let
  entryPoint = writeShellScriptBin "entry-point.sh" ''
    set -Eeuo pipefail
    set -m  # enable job control so we can use `fg` at the end

    FDB_PORT="''${FDB_PORT:=4500}"
    FDB_NETWORKING_MODE="''${FDB_NETWORKING_MODE:=container}"
    FDB_PROCESS_CLASS="''${FDB_PROCESS_CLASS:=unset}"
    FDB_CLUSTER_FILE="''${FDB_CLUSTER_FILE:=/var/foundationdb/fdb.cluster}"

    mkdir -p /var/foundationdb/logs
    mkdir -p /var/foundationdb/data
    mkdir -p "$(dirname "$FDB_CLUSTER_FILE")"

    # Determine the public IP address.
    # Supports override via FDB_PUBLIC_IP env var (e.g. Kubernetes Downward API).
    if [[ -z "''${FDB_PUBLIC_IP:-}" ]]; then
      if [[ "$FDB_NETWORKING_MODE" == "host" ]]; then
        FDB_PUBLIC_IP="127.0.0.1"
      else
        # Use hostname -I to get the host's IP address.
        FDB_PUBLIC_IP="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
        FDB_PUBLIC_IP="''${FDB_PUBLIC_IP:-127.0.0.1}"
      fi
    fi

    # IPv6 addresses need square brackets in the cluster-file and listen address.
    if [[ "$FDB_PUBLIC_IP" == *:* ]]; then
      PUBLIC_ADDR="[$FDB_PUBLIC_IP]:$FDB_PORT"
      LISTEN_ADDR="[::]:$FDB_PORT"
    else
      PUBLIC_ADDR="$FDB_PUBLIC_IP:$FDB_PORT"
      LISTEN_ADDR="0.0.0.0:$FDB_PORT"
    fi

    echo "Creating FDB cluster file at $FDB_CLUSTER_FILE ..."
    echo "docker:dockerdb@$PUBLIC_ADDR" > "$FDB_CLUSTER_FILE"
    cat "$FDB_CLUSTER_FILE"

    echo "Starting FDB server (listen: $LISTEN_ADDR, public: $PUBLIC_ADDR) ..."
    fdbserver \
      --listen-address  "$LISTEN_ADDR" \
      --public-address  "$PUBLIC_ADDR" \
      --locality-zoneid="$HOSTNAME" \
      --locality-machineid="$HOSTNAME" \
      --class           "$FDB_PROCESS_CLASS" \
      --knob_disable_posix_kernel_aio=1 \
      -C                "$FDB_CLUSTER_FILE" \
      --datadir         /var/foundationdb/data \
      --logdir          /var/foundationdb/logs &

    echo "Waiting for FDB server to start (5s) ..."
    sleep 5

    echo "Configuring FDB cluster ..."
    fdbcli -C "$FDB_CLUSTER_FILE" --exec "configure new single memory; status"

    # Bring fdbserver back to foreground so it becomes PID 1's child and the
    # container stays alive until the server exits.
    fg %1
  '';

  dockerImage = dockerTools.buildLayeredImage {
    name = "alekseysidorov/foundationdb";
    created = "2025-07-02";

    maxLayers = 16;
    contents = [
      # Certificates
      dockerTools.usrBinEnv
      dockerTools.binSh
      dockerTools.caCertificates
      dockerTools.fakeNss

      bash
      coreutils
      hostname # for hostname -I (public IP detection)

      foundationdb
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
        fdbVersion = foundationdb.version;
      };
    in
    passthru // { inherit passthru; };
in
dockerImage // extendedAttrs
