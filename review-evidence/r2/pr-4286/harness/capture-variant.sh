#!/usr/bin/env bash
set -euo pipefail
set -x

if [[ $# -ne 1 ]] || [[ $1 != baseline && $1 != fixed ]]; then
  echo "usage: $0 <baseline|fixed>" >&2
  exit 2
fi

variant=$1
export KUBECONFIG=/tmp/pr4286-r2-kubeconfig
KUBECTL=/tmp/pr4286-bin/kubectl
HELM=/tmp/pr4286-bin/helm
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
EVIDENCE=${EVIDENCE:-$(cd -- "${SCRIPT_DIR}/.." && pwd)}
NACOS=http://127.0.0.1:18848/nacos

mkdir -p "${EVIDENCE}/raw"

"${KUBECTL}" get pod -n higress-system -l app=higress-gateway -o json > "${EVIDENCE}/raw/${variant}-gateway-pod.json"
"${KUBECTL}" get pods -A -o json > "${EVIDENCE}/raw/${variant}-all-pods.json"
"${KUBECTL}" get pods -A -o wide
"${KUBECTL}" get configmap -n higress-system higress-config -o yaml > "${EVIDENCE}/raw/${variant}-higress-config.yaml"
"${KUBECTL}" logs -n higress-system deployment/higress-gateway > "${EVIDENCE}/raw/${variant}-gateway.log"
"${KUBECTL}" logs -n higress-system deployment/higress-controller -c higress-core > "${EVIDENCE}/raw/${variant}-controller.log"
"${KUBECTL}" logs -n pr4286-runtime deployment/pr4286-nacos > "${EVIDENCE}/raw/${variant}-nacos.log"

"${KUBECTL}" get pod -n higress-system -l app=higress-gateway -o jsonpath='{.items[0].status.containerStatuses[0].imageID}'
printf '\n'
"${KUBECTL}" exec -n higress-system deployment/higress-gateway -- sha256sum /var/lib/istio/envoy/golang-filter.so
"${KUBECTL}" exec -n higress-system deployment/higress-gateway -- /usr/local/bin/envoy --version
"${KUBECTL}" exec -n higress-system deployment/higress-gateway -- sh -c 'curl -fsS http://127.0.0.1:15000/stats' > "${EVIDENCE}/raw/${variant}-envoy-stats.txt"
grep -E 'golang-filter-mcp-(server|session)|http\.outbound_0\.0\.0\.0_80\.downstream_rq_total|panic_error' "${EVIDENCE}/raw/${variant}-envoy-stats.txt"

curl -fsS "${NACOS}/v1/ns/instance/list?serviceName=pr4286-backend&groupName=PR4286_GROUP" \
  > "${EVIDENCE}/raw/${variant}-nacos-instances.json"
curl -fsS "${NACOS}/v1/cs/configs?dataId=pr4286-backend-mcp-tools.json&group=PR4286_GROUP" \
  > "${EVIDENCE}/raw/${variant}-nacos-tool-config.json"
curl -fsS -X POST http://127.0.0.1:18080/pr4286/mcp \
  -H 'Host: pr4286.example.com' -H 'Content-Type: application/json' \
  --data-binary @"${SCRIPT_DIR}/cluster/mcp-tools-list.json" \
  > "${EVIDENCE}/raw/${variant}-tools-list-response.json"

"${HELM}" history pr4286 -n higress-system -o yaml > "${EVIDENCE}/raw/${variant}-helm-history.yaml"
"${HELM}" get all pr4286 -n higress-system > "${EVIDENCE}/raw/${variant}-helm-get-all.txt"
