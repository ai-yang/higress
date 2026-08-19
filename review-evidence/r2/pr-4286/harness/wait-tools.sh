#!/usr/bin/env bash
set -euo pipefail
set -x

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <variant>" >&2
  exit 2
fi

variant=$1
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
EVIDENCE=${EVIDENCE:-$(cd -- "${SCRIPT_DIR}/.." && pwd)}
response_file="${EVIDENCE}/raw/${variant}-tools-ready-response.json"

mkdir -p "${EVIDENCE}/raw"

for attempt in $(seq 1 60); do
  if curl -fsS -X POST http://127.0.0.1:18080/pr4286/mcp \
      -H 'Host: pr4286.example.com' \
      -H 'Content-Type: application/json' \
      --data-binary @"${SCRIPT_DIR}/cluster/mcp-tools-list.json" \
      > "${response_file}" \
      && grep -q 'PR4286_GROUP_pr4286-backend_identity' "${response_file}"; then
    cat "${response_file}"
    exit 0
  fi
  sleep 2
done

cat "${response_file}" >&2 || true
exit 1
