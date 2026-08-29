#!/usr/bin/env bash

set -euo pipefail

: "${KUBECTL:?set KUBECTL to the kubectl v1.34.0 binary}"
: "${HELM:?set HELM to the Helm v3.14.4 binary}"
: "${KUBECONFIG:?set KUBECONFIG to the disposable kind kubeconfig}"
: "${HIGRESS_SOURCE_ROOT:?set HIGRESS_SOURCE_ROOT to the fixed source checkout}"

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
evidence_root="${EVIDENCE_ROOT:-$(cd -- "${script_dir}/.." && pwd)}"

"${HELM}" upgrade higress "${HIGRESS_SOURCE_ROOT}/helm/core" \
  --namespace higress-system \
  --kubeconfig "${KUBECONFIG}" \
  --values "${evidence_root}/manifests/helm-values-fixed.yaml" \
  --wait \
  --timeout 10m
"${KUBECTL}" --kubeconfig "${KUBECONFIG}" -n higress-system rollout status \
  deployment/higress-controller --timeout=5m
"${KUBECTL}" --kubeconfig "${KUBECONFIG}" -n higress-system exec \
  deployment/higress-controller -c higress-core -- \
  /usr/local/bin/higress version -o json
