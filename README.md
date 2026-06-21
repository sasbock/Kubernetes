# Kubernetes Cluster Setup

This repository provides scripts and guidance for setting up Kubernetes clusters and deploying applications on them. Use it to prepare cluster nodes, initialize a control plane, join worker nodes, and run workloads once the cluster is ready.

## Overview

The workflow is split into two phases:

1. **Cluster setup** — Prepare each node (master or worker) with the required packages, networking, and Kubernetes components.
2. **Application deployment** — After the cluster is running, use `kubectl` to deploy and manage applications on top of it.

## Prerequisites

- One machine for the control plane (master) and one or more worker nodes.
- Supported Linux distributions:
  - **RPM-based:** RHEL, CentOS, Fedora, Rocky Linux, AlmaLinux
  - **Debian-based:** Debian, Ubuntu
- Root or sudo access on each node.
- Network connectivity between nodes.

### Default network layout

The setup scripts configure the following hostnames and IP addresses in `/etc/hosts`:

| Hostname       | IP Address     |
|----------------|----------------|
| `k8s-master`   | 192.168.0.201  |
| `k8s-worker-01`| 192.168.0.202  |
| `k8s-worker-02`| 192.168.0.203  |
| `k8s-worker-03`| 192.168.0.204  |

Adjust these values in `k8s-setup.sh` if your environment uses different addresses.

## Quick start

### 1. Prepare each node

Run the setup script on every node, passing the role for that machine:

```bash
sudo ./k8s-setup.sh master
```

On worker nodes, use a numbered worker identifier:

```bash
sudo ./k8s-setup.sh worker-01
sudo ./k8s-setup.sh worker-02
sudo ./k8s-setup.sh worker-03
```

The script performs the following on each node:

- Sets the hostname (`k8s-master`, `k8s-worker-01`, etc.)
- Configures `/etc/hosts` with cluster node entries
- Disables swap
- Adds the Kubernetes 1.36 package repository
- Installs `kubelet`, `kubeadm`, `kubectl`, and `containerd`
- Configures containerd with systemd cgroups
- Loads required kernel modules and sysctl settings
- Opens firewall ports `6443` and `10250`

On the master node, the script also pulls the images required by `kubeadm`.

### 2. Initialize the cluster

On the **master** node only, run:

```bash
sudo ./k8s-start-cluster.sh
```

This script:

- Initializes the cluster with `kubeadm` using pod network CIDR `10.244.0.0/16`
- Installs the [Flannel](https://github.com/flannel-io/flannel) CNI plugin for pod networking

After initialization, `kubeadm` prints a `kubeadm join` command. Run that command on each worker node to add it to the cluster.

### 3. Verify the cluster

On the master node:

```bash
kubectl get nodes
```

All nodes should report a `Ready` status once workers have joined and Flannel is running.

## Deploying applications

With a healthy cluster, deploy applications using standard Kubernetes manifests or Helm charts:

```bash
kubectl apply -f your-app.yaml
kubectl get pods
kubectl get services
```

Common next steps include:

- Creating Deployments and Services for your applications
- Exposing workloads with Ingress controllers or LoadBalancer services
- Managing configuration with ConfigMaps and Secrets
- Scaling replicas with `kubectl scale`

## Scripts reference

| Script                 | Purpose                                              |
|------------------------|------------------------------------------------------|
| `k8s-setup.sh`         | Prepare a node as master or worker                   |
| `k8s-start-cluster.sh` | Initialize the control plane and install Flannel     |

## Troubleshooting

- **Nodes not Ready:** Confirm Flannel pods are running (`kubectl get pods -n kube-flannel`) and that workers joined successfully.
- **Swap errors:** The setup script disables swap; reboot if swap was re-enabled.
- **Firewall issues:** Ensure ports `6443` (API server) and `10250` (kubelet) are open on all nodes.

## License

See the repository for license details.
