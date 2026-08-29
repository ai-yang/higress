#!/usr/bin/env bash
set -euo pipefail
set -x

export KUBECONFIG=/tmp/pr4286-r3-kubeconfig
HELM=/tmp/pr4286-bin/helm
KUBECTL=/tmp/pr4286-bin/kubectl
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
EVIDENCE=${EVIDENCE:-$(cd -- "${SCRIPT_DIR}/.." && pwd)}
: "${REPO:?set REPO to the fixed Higress checkout}"

"${HELM}" upgrade pr4286 "${REPO}/helm/core" \
  --namespace higress-system \
  --values "${SCRIPT_DIR}/cluster/helm-values-fixed.yaml" \
  --wait --timeout 5m
"${KUBECTL}" rollout status deployment/higress-gateway -n higress-system --timeout=3m
"${KUBECTL}" get pods -n higress-system -o wide
