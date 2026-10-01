#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<EOF
Usage:
  $(basename "$0") <apply|delete> <cni>

Supported CNIs:
  flannel

Examples:
  $(basename "$0") apply flannel
  $(basename "$0") delete flannel
EOF
}

if [[ $# -ne 2 ]]; then
    usage
    exit 1
fi

ACTION="$1"
CNI="$2"

# Node-to-node network; defaults to the VirtualBox host-only network and
# matches the address advertised in k8s-cluster.sh. Override via the environment.
NODE_NETWORK_REGEX="${NODE_NETWORK_REGEX:-^192\\.168\\.56\\.}"

case "$CNI" in
    flannel)
        MANIFEST="https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml"
        ;;
    *)
        echo "Error: Unsupported CNI '$CNI'"
        usage
        exit 1
        ;;
esac

# Pin flannel's VXLAN endpoint to the node network. Without --iface-regex flannel
# uses the default-route interface (on VirtualBox the NAT device, 10.0.2.15 -
# identical and non-routable across VMs), which black-holes cross-node pod traffic.
render_flannel() {
    local manifest repl="${NODE_NETWORK_REGEX//\\/\\\\}"
    manifest="$(curl -fsSL "$MANIFEST" |
        sed "s|^\( *\)- --kube-subnet-mgr\$|&\n\1- --iface-regex=${repl}|")"
    if ! grep -q -- "--iface-regex=" <<<"$manifest"; then
        echo "Error: could not inject --iface-regex into the flannel manifest" >&2
        exit 1
    fi
    printf '%s\n' "$manifest"
}

case "$ACTION" in
    apply)
        echo "Applying ${CNI} (interface regex: ${NODE_NETWORK_REGEX})..."
        render_flannel | kubectl apply -f -
        kubectl -n kube-flannel rollout status ds kube-flannel-ds --timeout=120s
        ;;
    delete)
        echo "Deleting ${CNI}..."
        kubectl delete -f "$MANIFEST"

        cat <<EOF

====================================================================
Run the following commands on ALL Kubernetes nodes:

sudo rm -f /etc/cni/net.d/10-flannel.conflist
sudo rm -f /opt/cni/bin/flannel
sudo systemctl restart kubelet

====================================================================
EOF
        ;;
    *)
        echo "Error: Invalid action '$ACTION'"
        usage
        exit 1
        ;;
esac
