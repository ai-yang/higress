#!/usr/bin/env bash

set -euo pipefail

variant="${1:?usage: run-requests.sh <baseline|fixed>}"
case "${variant}" in
  baseline|fixed) ;;
  *) echo "unsupported variant: ${variant}" >&2; exit 2 ;;
esac

: "${EVIDENCE_ROOT:?set EVIDENCE_ROOT to review-evidence/r3/pr-4231}"

curl_bin="${CURL:-curl}"
resolve_address="${CURL_RESOLVE_ADDR:-127.0.0.1}"
host="${PR4231_HOST:-pr4231.example}"
port="${PR4231_PORT:-18080}"
path="${PR4231_PATH:-/r3}"
result_dir="${EVIDENCE_ROOT}/results/${variant}"
mkdir -p "${result_dir}"

for sample in 1 2 3; do
  "${curl_bin}" \
    --silent \
    --show-error \
    --noproxy '*' \
    --resolve "${host}:${port}:${resolve_address}" \
    --connect-timeout 10 \
    --max-time 20 \
    --dump-header "${result_dir}/request-${sample}.headers" \
    --output "${result_dir}/request-${sample}.body" \
    --write-out "{\"sample\":${sample},\"http_code\":%{http_code},\"curl_exit_code\":%{exitcode},\"remote_ip\":\"%{remote_ip}\",\"remote_port\":%{remote_port},\"time_total_seconds\":%{time_total}}\\n" \
    "http://${host}:${port}${path}" \
    >"${result_dir}/request-${sample}.json"
done
