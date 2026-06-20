#!/bin/bash

# CONFIGURE MACHINE NAME: MASTER/WORKER
hostnamectl hostname k8s-worker-01

# CONFIGURE HOST NAMES/IP ADDRESSES
while IFS= read -r line; do
  grep -Fxq "$line" /etc/hosts || echo "$line" >> /etc/hosts
done << 'EOF'
192.168.0.201	k8s-master
192.168.0.202	k8s-worker-01
192.168.0.203	k8s-worker-02
192.168.0.204	k8s-worker-03
EOF

# DISABLE SWAPPING
swapoff -a
sed -i '/^[[:space:]]*#/! s/^\([[:space:]]*[^[:space:]].*[[:space:]]swap[[:space:]].*\)$/# \1/' /etc/fstab
# probably not necessary: systemctl daemon-reload

# CONFIGURE KUBERNETES 1.36 RPM REPOSITORY
cat <<'EOF' > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.36/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.36/rpm/repodata/repomd.xml.key
EOF

# INSTALL KUBERNETES AND CONTAINER DAEMON
dnf install -y net-tools epel-release kubelet kubeadm kubectl
dnf install -y containerd

containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl enable --now containerd

# ENABLE AND START KUBELET
systemctl enable --now kubelet

# ENABLE KERNEL MODULES
cat <<'EOF' > /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# CONFIGURE NETWORKING AND FIREWALL
cat <<'EOF' > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
net.ipv4.ip_forward=1
EOF

firewall-cmd --permanent --add-port=10250/tcp
# TODO: Add NodePort Services (if required)
firewall-cmd --reload
