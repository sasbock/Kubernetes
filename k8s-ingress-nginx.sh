#!/usr/bin/env bash

set -euo pipefail

MANIFEST_URL="https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml"
NAMESPACE="ingress-nginx"

usage() {
    cat <<EOF
Usage:
  $(basename "$0") apply
  $(basename "$0") delete

Commands:
  apply    Deploy the ingress-nginx controller
  delete   Remove the ingress-nginx controller and clean up resources
EOF
    exit 1
}

if [[ $# -ne 1 ]]; then
    usage
fi

case "$1" in
    apply)
        echo "Deploying ingress-nginx controller..."
        kubectl apply -f "${MANIFEST_URL}"

        echo "Waiting for deployment to become available..."
        kubectl rollout status deployment/ingress-nginx-controller \
            -n "${NAMESPACE}" \
            --timeout=300s

        echo
        echo "Ingress NGINX controller deployed successfully."
        kubectl get pods -n "${NAMESPACE}"
        ;;

    delete)
        echo "Removing ingress-nginx controller..."
        kubectl delete -f "${MANIFEST_URL}" --ignore-not-found=true

        echo "Waiting for namespace '${NAMESPACE}' to terminate (if it exists)..."

        if kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
            timeout=120
            elapsed=0

            while kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; do
                if (( elapsed >= timeout )); then
                    echo "Timeout waiting for namespace deletion."
                    echo "You may need to investigate stuck finalizers:"
                    echo "  kubectl get namespace ${NAMESPACE} -o yaml"
                    exit 1
                fi

                sleep 2
                elapsed=$((elapsed + 2))
            done
        fi

        # Remove any leftover IngressClass if present.
        kubectl delete ingressclass nginx --ignore-not-found=true

        echo
        echo "Ingress NGINX controller has been removed."
        ;;

    *)
        echo "Invalid command: $1"
        usage
        ;;
esac
