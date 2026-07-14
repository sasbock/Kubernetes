#!/usr/bin/env bash

set -euo pipefail

METALLB_VERSION="v0.14.9"
MANIFEST_URL="https://raw.githubusercontent.com/metallb/metallb/${METALLB_VERSION}/config/manifests/metallb-native.yaml"
NAMESPACE="metallb-system"

# Address pool handed out to LoadBalancer services. Must be free addresses on
# the node network (192.168.56.0/24, see k8s-cluster.sh) and outside the
# node/host range reserved in k8s-setup.sh (.2-.9).
IP_POOL_RANGE="192.168.56.240-192.168.56.250"

usage() {
    cat <<EOF
Usage:
  $(basename "$0") apply
  $(basename "$0") delete

Commands:
  apply    Deploy MetalLB (L2 mode) and configure the address pool
  delete   Remove MetalLB and its configuration

MetalLB assigns external IPs from ${IP_POOL_RANGE} to LoadBalancer services.
EOF
    exit 1
}

apply_config() {
    # The MetalLB validating webhook may take a moment to become reachable after
    # the controller starts; retry applying the CRs until it accepts them.
    local attempt=0
    until kubectl apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: ${NAMESPACE}
spec:
  addresses:
    - ${IP_POOL_RANGE}
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default-l2
  namespace: ${NAMESPACE}
spec:
  ipAddressPools:
    - default-pool
EOF
    do
        attempt=$((attempt + 1))
        if (( attempt >= 20 )); then
            echo "Error: MetalLB webhook did not accept the configuration in time."
            exit 1
        fi
        echo "Waiting for MetalLB webhook to become ready (attempt ${attempt})..."
        sleep 3
    done
}

if [[ $# -ne 1 ]]; then
    usage
fi

case "$1" in
    apply)
        echo "Deploying MetalLB ${METALLB_VERSION}..."
        kubectl apply -f "${MANIFEST_URL}"

        echo "Waiting for MetalLB to become available..."
        kubectl -n "${NAMESPACE}" rollout status deployment/controller --timeout=180s
        kubectl -n "${NAMESPACE}" rollout status daemonset/speaker --timeout=180s

        echo "Configuring address pool (${IP_POOL_RANGE})..."
        apply_config

        echo
        echo "MetalLB deployed successfully."
        kubectl -n "${NAMESPACE}" get pods
        ;;

    delete)
        echo "Removing MetalLB configuration..."
        kubectl -n "${NAMESPACE}" delete l2advertisement default-l2 --ignore-not-found=true
        kubectl -n "${NAMESPACE}" delete ipaddresspool default-pool --ignore-not-found=true

        echo "Removing MetalLB..."
        kubectl delete -f "${MANIFEST_URL}" --ignore-not-found=true

        echo
        echo "MetalLB has been removed."
        ;;

    *)
        echo "Invalid command: $1"
        usage
        ;;
esac
