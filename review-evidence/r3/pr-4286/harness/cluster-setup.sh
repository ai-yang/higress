#!/usr/bin/env bash
set -euo pipefail
set -x

export KUBECONFIG=/tmp/pr4286-r3-kubeconfig
KIND=/tmp/pr4286-bin/kind
KUBECTL=/tmp/pr4286-bin/kubectl
HELM=/tmp/pr4286-bin/helm
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
EVIDENCE=${EVIDENCE:-$(cd -- "${SCRIPT_DIR}/.." && pwd)}
: "${REPO:?set REPO to the fixed Higress checkout}"

mkdir -p "${EVIDENCE}/raw"

"${KIND}" create cluster --name pr4286-r3 \
  --image docker.m.daocloud.io/kindest/node:v1.25.3 \
  --config "${SCRIPT_DIR}/cluster/kind-config.yaml" \
  --kubeconfig "${KUBECONFIG}"

"${KIND}" load docker-image \
  higress-registry.cn-hangzhou.cr.aliyuncs.com/higress/gateway:pr4286-r3-baseline-409b3ed2 \
  higress-registry.cn-hangzhou.cr.aliyuncs.com/higress/gateway:pr4286-r3-fixed-81c547a2 \
  higress-registry.cn-hangzhou.cr.aliyuncs.com/higress/higress:latest \
  higress-registry.cn-hangzhou.cr.aliyuncs.com/higress/pilot:de2c9628294f51b13c4a70b3a862b4372890797a \
  docker.m.daocloud.io/nacos/nacos-server:v2.3.2-slim \
  docker.m.daocloud.io/hashicorp/http-echo:1.0.0 \
  --name pr4286-r3

"${HELM}" template pr4286 "${REPO}/helm/core" --namespace higress-system \
  --values "${SCRIPT_DIR}/cluster/helm-values-baseline.yaml" > "${EVIDENCE}/raw/helm-rendered-baseline.yaml"
"${HELM}" template pr4286 "${REPO}/helm/core" --namespace higress-system \
  --values "${SCRIPT_DIR}/cluster/helm-values-fixed.yaml" > "${EVIDENCE}/raw/helm-rendered-fixed.yaml"

"${HELM}" upgrade --install pr4286 "${REPO}/helm/core" \
  --namespace higress-system --create-namespace \
  --values "${SCRIPT_DIR}/cluster/helm-values-baseline.yaml" \
  --wait --timeout 5m

"${KUBECTL}" apply -f "${SCRIPT_DIR}/cluster/runtime-fixtures.yaml"
"${KUBECTL}" rollout status deployment/pr4286-nacos -n pr4286-runtime --timeout=5m
"${KUBECTL}" rollout status deployment/pr4286-backend-0 -n pr4286-runtime --timeout=2m
"${KUBECTL}" rollout status deployment/pr4286-backend-1 -n pr4286-runtime --timeout=2m
"${KUBECTL}" apply -f "${SCRIPT_DIR}/cluster/ingress-route.yaml"
"${KUBECTL}" patch configmap higress-config -n higress-system \
  --type merge --patch-file "${SCRIPT_DIR}/cluster/higress-config-patch.yaml"
"${KUBECTL}" rollout status deployment/higress-controller -n higress-system --timeout=3m
"${KUBECTL}" rollout status deployment/higress-gateway -n higress-system --timeout=3m
"${KUBECTL}" get nodes -o wide
"${KUBECTL}" get pods -A -o wide
