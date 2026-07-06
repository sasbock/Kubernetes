#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<EOF
Usage:
  sudo $(basename "$0") <create|delete>

Examples:
  sudo $(basename "$0") create
  sudo $(basename "$0") delete
EOF
}

# Must be run as root
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root (use sudo)."
    exit 1
fi

if [[ $# -ne 1 ]]; then
    usage
    exit 1
fi

ACTION="$1"

case "$ACTION" in
    create)
        echo "Initializing Kubernetes cluster..."
        kubeadm init \
          --apiserver-advertise-address=192.168.56.2 \
          --control-plane-endpoint=192.168.56.2:6443 \
          --pod-network-cidr=10.244.0.0/16
        ;;

    delete)
        echo "Resetting Kubernetes cluster..."

        systemctl stop kubelet 2>/dev/null || true

        kubeadm reset -f || true

        rm -rf /etc/kubernetes
        rm -rf /var/lib/etcd
        rm -rf /var/lib/kubelet
        rm -rf /var/lib/cni
        rm -rf /etc/cni/net.d
        rm -rf /root/.kube
        rm -rf ~/.kube

        iptables -F || true
        iptables -t nat -F || true
        iptables -t mangle -F || true
        iptables -X || true

        ip link delete cni0 2>/dev/null || true
        ip link delete flannel.1 2>/dev/null || true
        ip link delete weave 2>/dev/null || true

        echo "Restarting container runtime..."

        if systemctl is-active --quiet containerd; then
            systemctl restart containerd
        fi

        if systemctl is-active --quiet docker; then
            systemctl restart docker
        fi

        echo "Kubernetes cluster removed successfully."
        ;;

    *)
        echo "Error: Invalid action '$ACTION'"
        usage
        exit 1
        ;;
esac
