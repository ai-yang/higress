#!/usr/bin/env bash

set -euo pipefail

: "${KIND:?set KIND to the kind v0.17.0 binary}"
: "${KUBECTL:?set KUBECTL to the kubectl v1.34.0 binary}"
: "${HELM:?set HELM to the Helm v3.14.4 binary}"
: "${KUBECONFIG:?set KUBECONFIG to a disposable kubeconfig path}"
: "${HIGRESS_SOURCE_ROOT:?set HIGRESS_SOURCE_ROOT to the fixed source checkout}"
: "${RUNTIME_DIR:?set RUNTIME_DIR to a disposable directory with at least 2 GiB free}"

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
evidence_root="${EVIDENCE_ROOT:-$(cd -- "${script_dir}/.." && pwd)}"
cluster_name="${CLUSTER_NAME:-higress-pr4231-r3}"
node_name="${cluster_name}-control-plane"
kind_image="kindest/node:v1.34.0@sha256:7416a61b42b1662ca6ca89f02028ac133a309a2a30ba309614e8ec94d976dc5a"
gateway_api_manifest="https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.0/standard-install.yaml"
archive="${RUNTIME_DIR}/runtime-images.tar"

runtime_images=(
  higress-registry.cn-hangzhou.cr.aliyuncs.com/higress/higress:pr4231-r3-baseline-409b3ed2
  higress-registry.cn-hangzhou.cr.aliyuncs.com/higress/higress:pr4231-r3-fixed-7cc8cde4
  higress-registry.cn-hangzhou.cr.aliyuncs.com/higress/gateway:v2.2.4
  higress-registry.cn-hangzhou.cr.aliyuncs.com/higress/pilot:v2.2.4
  docker.m.daocloud.io/hashicorp/http-echo:1.0.0
)

mkdir -p "${RUNTIME_DIR}"
"${KIND}" create cluster \
  --name "${cluster_name}" \
  --image "${kind_image}" \
  --config "${evidence_root}/manifests/kind-config.yaml" \
  --kubeconfig "${KUBECONFIG}"

# kind v0.17.0 cannot detect the snapshotter used by the v1.34.0 node.
# Importing the exact Docker archive through containerd is the deterministic fallback.
docker save --output "${archive}" "${runtime_images[@]}"
docker cp "${archive}" "${node_name}:/runtime-images.tar"
docker exec "${node_name}" ctr -n k8s.io images import /runtime-images.tar
docker exec "${node_name}" rm -f /runtime-images.tar

"${KUBECTL}" --kubeconfig "${KUBECONFIG}" apply -f "${gateway_api_manifest}"
"${HELM}" install higress "${HIGRESS_SOURCE_ROOT}/helm/core" \
  --namespace higress-system \
  --create-namespace \
  --kubeconfig "${KUBECONFIG}" \
  --values "${evidence_root}/manifests/helm-values-baseline.yaml" \
  --wait \
  --timeout 10m
"${KUBECTL}" --kubeconfig "${KUBECONFIG}" apply \
  -f "${evidence_root}/manifests/runtime-fixtures.yaml"
"${KUBECTL}" --kubeconfig "${KUBECONFIG}" -n higress-system rollout status \
  deployment/higress-controller --timeout=5m
"${KUBECTL}" --kubeconfig "${KUBECONFIG}" -n higress-system rollout status \
  deployment/higress-gateway --timeout=5m
"${KUBECTL}" --kubeconfig "${KUBECONFIG}" -n higress-system rollout status \
  deployment/pr4231-echo --timeout=5m
"${KUBECTL}" --kubeconfig "${KUBECONFIG}" get pods -A -o wide
