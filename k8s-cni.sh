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

case "$ACTION" in
    apply)
        echo "Applying ${CNI}..."
        kubectl apply -f "$MANIFEST"
        ;;
    delete)
        echo "Deleting ${CNI}..."
        kubectl delete -f "$MANIFEST"

        cat <<EOF

====================================================================
Run the following commands on ALL Kubernetes nodes:

sudo rm -f /etc/cni/net.d/10-flannel.conflist
sudo rm -f /opt/cni/bin/flannel

====================================================================
EOF
        ;;
    *)
        echo "Error: Invalid action '$ACTION'"
        usage
        exit 1
        ;;
esac
