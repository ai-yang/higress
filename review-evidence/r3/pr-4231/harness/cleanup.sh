#!/usr/bin/env bash

set -euo pipefail

: "${KIND:?set KIND to the kind v0.17.0 binary}"

cluster_name="${CLUSTER_NAME:-higress-pr4231-r3}"

"${KIND}" delete cluster --name "${cluster_name}"
"${KIND}" get clusters
docker ps -a --filter "name=${cluster_name}"
if command -v ss >/dev/null 2>&1; then
  if ss -ltn | grep -Eq ':(18080|18443)[[:space:]]'; then
    echo "cleanup verification failed: a mapped port is still listening" >&2
    exit 1
  fi
fi
echo "cleanup verification: PASS"
