#!/usr/bin/env bash

set -euo pipefail

NAMESPACE="monitoring"
GRAFANA_IP="192.168.56.2"
GRAFANA_ADMIN_PASSWORD="admin"

RELEASE_MONITORING="monitoring"
RELEASE_LOKI="loki"
RELEASE_PROMTAIL="promtail"
RELEASE_TEMPO="tempo"

usage() {
    cat <<EOF
Usage:
  $(basename "$0") apply
  $(basename "$0") delete

Commands:
  apply    Deploy Prometheus, Grafana, Alertmanager, Loki, Promtail, and Tempo
  delete   Remove the monitoring stack from the cluster

Grafana is exposed at http://${GRAFANA_IP} (admin / ${GRAFANA_ADMIN_PASSWORD})
EOF
    exit 1
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Error: '$1' is required but not installed."
        exit 1
    fi
}

require_cluster() {
    if ! kubectl cluster-info >/dev/null 2>&1; then
        echo "Error: Cannot reach the Kubernetes cluster. Configure kubectl and try again."
        exit 1
    fi
}

add_helm_repos() {
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
    helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null || true
    helm repo update
}

write_values_files() {
    local values_dir="$1"

    cat > "${values_dir}/kube-prometheus-stack.yaml" <<EOF
grafana:
  adminPassword: ${GRAFANA_ADMIN_PASSWORD}
  hostNetwork: true
  dnsPolicy: ClusterFirstWithHostNet
  nodeSelector:
    node-role.kubernetes.io/control-plane: ""
  tolerations:
    - key: node-role.kubernetes.io/control-plane
      operator: Exists
      effect: NoSchedule
  grafana.ini:
    server:
      http_port: 80
  service:
    type: ClusterIP
    port: 80
  additionalDataSources:
    - name: Loki
      type: loki
      access: proxy
      url: http://${RELEASE_LOKI}:3100
      isDefault: false
    - name: Tempo
      type: tempo
      access: proxy
      url: http://${RELEASE_TEMPO}:3100
      isDefault: false

prometheus:
  prometheusSpec:
    retention: 7d

alertmanager:
  alertmanagerSpec:
    retention: 120h
EOF

    cat > "${values_dir}/loki.yaml" <<'EOF'
deploymentMode: SingleBinary
gateway:
  enabled: false
chunksCache:
  enabled: false
resultsCache:
  enabled: false
lokiCanary:
  enabled: false
test:
  enabled: false
loki:
  auth_enabled: false
  commonConfig:
    replication_factor: 1
  storage:
    type: filesystem
  schemaConfig:
    configs:
      - from: "2024-04-01"
        store: tsdb
        object_store: filesystem
        schema: v13
        index:
          prefix: loki_index_
          period: 24h
singleBinary:
  replicas: 1
  persistence:
    enabled: false
  extraVolumes:
    - name: storage
      emptyDir: {}
  extraVolumeMounts:
    - name: storage
      mountPath: /var/loki
read:
  replicas: 0
write:
  replicas: 0
backend:
  replicas: 0
EOF

    cat > "${values_dir}/promtail.yaml" <<EOF
config:
  clients:
    - url: http://${RELEASE_LOKI}:3100/loki/api/v1/push
daemonset:
  enabled: true
EOF

    cat > "${values_dir}/tempo.yaml" <<'EOF'
tempo:
  storage:
    trace:
      backend: local
      local:
        path: /var/tempo/traces
  extraVolumeMounts:
    - name: storage
      mountPath: /var/tempo
extraVolumes:
  - name: storage
    emptyDir: {}
persistence:
  enabled: false
EOF
}

apply_monitoring() {
    require_command kubectl
    require_command helm
    require_cluster

    echo "Adding Helm repositories..."
    add_helm_repos

    echo "Creating namespace '${NAMESPACE}'..."
    kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

    local values_dir
    values_dir="$(mktemp -d)"
    trap 'rm -rf "${values_dir}"' RETURN

    write_values_files "${values_dir}"

    echo "Deploying Loki..."
    helm upgrade --install "${RELEASE_LOKI}" grafana/loki \
        --namespace "${NAMESPACE}" \
        --values "${values_dir}/loki.yaml" \
        --wait --timeout 10m

    echo "Deploying Promtail..."
    helm upgrade --install "${RELEASE_PROMTAIL}" grafana/promtail \
        --namespace "${NAMESPACE}" \
        --values "${values_dir}/promtail.yaml" \
        --wait --timeout 10m

    echo "Deploying Tempo..."
    helm upgrade --install "${RELEASE_TEMPO}" grafana/tempo \
        --namespace "${NAMESPACE}" \
        --values "${values_dir}/tempo.yaml" \
        --wait --timeout 10m

    echo "Deploying kube-prometheus-stack (Prometheus, Grafana, Alertmanager)..."
    helm upgrade --install "${RELEASE_MONITORING}" prometheus-community/kube-prometheus-stack \
        --namespace "${NAMESPACE}" \
        --values "${values_dir}/kube-prometheus-stack.yaml" \
        --wait --timeout 15m

    echo
    echo "Monitoring stack deployed successfully."
    echo
    kubectl get pods -n "${NAMESPACE}"
    echo
    cat <<EOF
Grafana:      http://${GRAFANA_IP}
Username:     admin
Password:     ${GRAFANA_ADMIN_PASSWORD}

Datasources configured in Grafana: Prometheus (default), Loki, Tempo
EOF
}

delete_monitoring() {
    require_command kubectl
    require_command helm
    require_cluster

    echo "Removing monitoring Helm releases..."
    helm uninstall "${RELEASE_MONITORING}" --namespace "${NAMESPACE}" 2>/dev/null || true
    helm uninstall "${RELEASE_TEMPO}" --namespace "${NAMESPACE}" 2>/dev/null || true
    helm uninstall "${RELEASE_PROMTAIL}" --namespace "${NAMESPACE}" 2>/dev/null || true
    helm uninstall "${RELEASE_LOKI}" --namespace "${NAMESPACE}" 2>/dev/null || true

    echo "Waiting for namespace '${NAMESPACE}' to terminate (if it exists)..."
    kubectl delete namespace "${NAMESPACE}" --ignore-not-found=true --wait=true --timeout=300s || {
        echo "Timeout waiting for namespace deletion."
        echo "You may need to investigate stuck finalizers:"
        echo "  kubectl get namespace ${NAMESPACE} -o yaml"
        exit 1
    }

    echo
    echo "Monitoring stack has been removed."
}

if [[ $# -ne 1 ]]; then
    usage
fi

case "$1" in
    apply)
        apply_monitoring
        ;;
    delete)
        delete_monitoring
        ;;
    *)
        echo "Invalid command: $1"
        usage
        ;;
esac
