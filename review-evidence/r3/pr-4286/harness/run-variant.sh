#!/usr/bin/env bash
set -euo pipefail
set -x

if [[ $# -ne 2 ]] || [[ $1 != baseline && $1 != fixed ]]; then
  echo "usage: $0 <baseline|fixed> <expected-unique-backends>" >&2
  exit 2
fi

variant=$1
expected_unique=$2
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

bash "${SCRIPT_DIR}/wait-tools.sh" "${variant}"
for round in 1 2 3; do
  bash "${SCRIPT_DIR}/run-requests.sh" \
    "${variant}" "${round}" 100 "${expected_unique}"
done
