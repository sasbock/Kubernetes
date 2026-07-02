#!/bin/bash

kubeadm init \
  --apiserver-advertise-address=192.168.56.10 \
  --control-plane-endpoint=192.168.56.10:6443 \
  --pod-network-cidr=10.244.0.0/16

kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
