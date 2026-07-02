#!/usr/bin/env bash

set -euo pipefail

# STOP KUBERNETES SERVICES
systemctl stop kubelet 2>/dev/null || true

# RESET KUBEADM
kubeadm reset -f

# REMOVE KUBERNETES CONFIGURATION
rm -rf /etc/kubernetes
rm -rf /var/lib/etcd
rm -rf /var/lib/kubelet
rm -rf /var/lib/cni
rm -rf /etc/cni/net.d
rm -rf ~/.kube

# CLEAN UP NETWORKING

# FLUSH IPTABLES RULES CREATED BY KUBERNETES
iptables -F || true
iptables -t nat -F || true
iptables -t mangle -F || true
iptables -X || true

# REMOVE COMMON NETWORK INTERFACES
ip link delete cni0 2>/dev/null || true
ip link delete flannel.1 2>/dev/null || true
ip link delete weave 2>/dev/null || true

# RESTART CONTAINER RUNTIME
if systemctl is-active --quiet containerd; then
    systemctl restart containerd
fi

if systemctl is-active --quiet docker; then
    systemctl restart docker
fi

