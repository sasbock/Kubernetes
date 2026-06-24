#!/bin/bash

# Validate number of arguments
if [[ $# -ne 1 ]]; then
	echo "Usage: $0 <master|worker-n>"
	echo "  master"
	echo "  worker-<n>   where <n> is a non-negative integer"
	exit 1
fi

ROLE="$1"

# Validate argument format
if [[ "$ROLE" != "master" && ! "$ROLE" =~ ^worker-[0-9]+$ ]]; then
	echo "Error: Invalid parameter '$ROLE'"
	echo "Usage: $0 <master|worker-n>"
	echo "  master"
	echo "  worker-<n>   where <n> is a non-negative integer"
	exit 1
fi

if grep -qiE 'rhel|centos|fedora|rocky|almalinux' /etc/os-release; then
	DISTRIBUTION=rpm
elif grep -qiE 'debian|ubuntu' /etc/os-release; then
	DISTRIBUTION=deb
else
	echo "Unsupported distribution"
	exit 1
fi

# CONFIGURE MACHINE NAME: MASTER/WORKER
hostnamectl hostname k8s-$ROLE

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

# CONFIGURE KUBERNETES 1.36 REPOSITORY
case "$DISTRIBUTION" in
rpm)
	cat <<-EOF > /etc/yum.repos.d/kubernetes.repo
	[kubernetes]
	name=Kubernetes
	baseurl=https://pkgs.k8s.io/core:/stable:/v1.36/rpm/
	enabled=1
	gpgcheck=1
	gpgkey=https://pkgs.k8s.io/core:/stable:/v1.36/rpm/repodata/repomd.xml.key
	EOF
        ;;
deb)
	mkdir -p /etc/apt/keyrings
	curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.36/deb/Release.key | gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
	cat <<-EOF > /etc/apt/sources.list.d/kubernetes.list
	deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.36/deb/ /
	EOF
        ;;
esac

# INSTALL KUBERNETES AND CONTAINER DAEMON
case "$DISTRIBUTION" in
rpm)
	dnf install -y --skip-broken net-tools epel-release 
	dnf install -y kubelet kubeadm kubectl containerd
	;;
deb)
	apt update
	apt install -y net-tools kubelet kubeadm kubectl containerd
	;;
esac

mkdir -p /etc/containerd/
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

sysctl --system > /dev/null

case "$DISTRIBUTION" in
rpm)
	systemctl enable --now firewalld
	firewall-cmd --permanent --add-port=6443/tcp
	firewall-cmd --permanent --add-port=10250/tcp
	firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -s 10.244.0.0/16 -j ACCEPT
	firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -s 10.96.0.0/12 -j ACCEPT
	firewall-cmd --permanent --add-port=8472/udp
	firewall-cmd --permanent --zone=trusted --add-interface=flannel.1
	firewall-cmd --permanent --zone=trusted --add-interface=cni0
	firewall-cmd --reload
	;;
deb)
	update-alternatives --set iptables /usr/sbin/iptables-legacy
	update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
	systemctl enable --now ufw
	ufw --force enable
	ufw allow ssh
	ufw allow 6443/tcp
	ufw allow 10250/tcp
	ufw allow from 10.244.0.0/16
	ufw allow to 10.244.0.0/16
	ufw allow from 10.96.0.0/12
	ufw allow to 10.96.0.0/12
	ufw allow 8472/udp
	ufw reload
	;;
esac

# INITIALIZE CONTROL PLANE
case "$ROLE" in
master)
	kubeadm config images pull
	;;
esac
