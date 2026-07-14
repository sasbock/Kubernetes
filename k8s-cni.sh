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
        # Pin flannel's VXLAN endpoint to the node-to-node network. Without this,
        # flannel auto-selects the default-route interface (on VirtualBox that is the
        # NAT device, 10.0.2.15 — identical and non-routable across VMs), which
        # black-holes all cross-node pod traffic. Match the network advertised in
        # k8s-cluster.sh (192.168.56.0/24).
        IFACE_REGEX='192\.168\.56\.'
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

        if [[ "$CNI" == "flannel" ]]; then
            echo "Pinning flannel to the node network interface (regex: ${IFACE_REGEX})..."
            kubectl -n kube-flannel patch ds kube-flannel-ds --type=json \
                -p="[{\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/args/-\",\"value\":\"--iface-regex=${IFACE_REGEX}\"}]"
            kubectl -n kube-flannel rollout restart ds kube-flannel-ds
            kubectl -n kube-flannel rollout status ds kube-flannel-ds --timeout=120s
        fi
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
