#!/usr/bin/env bash

set -euo pipefail

variant="${1:?usage: capture-variant.sh <baseline|fixed>}"
case "${variant}" in
  baseline|fixed) ;;
  *) echo "unsupported variant: ${variant}" >&2; exit 2 ;;
esac

: "${KUBECTL:?set KUBECTL to the kubectl v1.34.0 binary}"
: "${KUBECONFIG:?set KUBECONFIG to the disposable kind kubeconfig}"
: "${EVIDENCE_ROOT:?set EVIDENCE_ROOT to review-evidence/r3/pr-4231}"

log_dir="${EVIDENCE_ROOT}/logs/${variant}"
mkdir -p "${log_dir}"

kube() {
  "${KUBECTL}" --kubeconfig "${KUBECONFIG}" "$@"
}

kube version -o yaml >"${log_dir}/kubernetes-version.yaml"
kube get nodes -o wide >"${log_dir}/nodes.txt"
kube get pods -A -o wide >"${log_dir}/pods.txt"
kube -n higress-system get deploy,pod,svc,endpoints -o yaml >"${log_dir}/workloads.yaml"
kube -n higress-system get gateway higress-gateway -o yaml >"${log_dir}/gateway.yaml"
kube -n higress-system get httproute pr4231-higress-service -o yaml >"${log_dir}/httproute.yaml"
kube -n higress-system get mcpbridge default -o yaml >"${log_dir}/mcpbridge.yaml"
kube get gatewayclass higress -o yaml >"${log_dir}/gatewayclass.yaml"
kube -n higress-system logs deployment/higress-controller -c higress-core --timestamps >"${log_dir}/controller.log"
kube -n higress-system logs deployment/higress-controller -c discovery --timestamps >"${log_dir}/pilot.log"
kube -n higress-system logs deployment/higress-gateway --timestamps >"${log_dir}/gateway.log"
kube -n higress-system exec deployment/higress-controller -c higress-core -- \
  /usr/local/bin/higress version -o json >"${log_dir}/controller-version.json"
kube -n higress-system exec deployment/higress-gateway -- \
  curl --silent --show-error http://127.0.0.1:15000/clusters?format=json \
  >"${log_dir}/envoy-clusters.json"
kube -n higress-system exec deployment/higress-gateway -- \
  curl --silent --show-error \
  'http://127.0.0.1:15000/config_dump?resource=dynamic_route_configs' \
  >"${log_dir}/envoy-routes.json"
kube -n higress-system exec deployment/higress-gateway -- \
  curl --silent --show-error http://127.0.0.1:15000/stats?format=json \
  >"${log_dir}/envoy-stats.json"
kube -n higress-system exec deployment/higress-gateway -- \
  curl --silent --show-error --dump-header - \
  http://pr4231-echo.higress-system.svc.cluster.local:5678/ \
  >"${log_dir}/direct-backend-response.txt"
