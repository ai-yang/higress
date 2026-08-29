#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $0 <baseline|fixed> <expected-final-quota> <wasm-path>" >&2
  exit 2
fi

variant=$1
expected_final_quota=$2
wasm_path=$3

case "${variant}" in
  baseline|fixed) ;;
  *)
    echo "unsupported variant: ${variant}" >&2
    exit 2
    ;;
esac

: "${EVIDENCE_ROOT:?set EVIDENCE_ROOT to review-evidence/r3/pr-4232}"
: "${HIGRESS_GATEWAY_IMAGE:?set the pinned Higress gateway image}"
: "${REDIS_IMAGE:?set the pinned Redis image}"

if [[ ! -f "${wasm_path}" ]]; then
  echo "Wasm artifact does not exist: ${wasm_path}" >&2
  exit 2
fi

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
result_dir="${EVIDENCE_ROOT}/results/${variant}"
log_dir="${EVIDENCE_ROOT}/logs/${variant}/runtime"
project_name=${COMPOSE_PROJECT_NAME:-higress-pr4232-r3}
envoy_port=${ENVOY_PORT:-12032}
admin_port=${ENVOY_ADMIN_PORT:-19032}
expected_body='{"id":"chatcmpl-pr4232","object":"chat.completion","usage":{"prompt_tokens":11,"completion_tokens":7,"total_tokens":18}}'

mkdir -p "${result_dir}" "${log_dir}"
find "${result_dir}" "${log_dir}" -mindepth 1 -maxdepth 1 -type f -delete

compose() {
  HIGRESS_GATEWAY_IMAGE="${HIGRESS_GATEWAY_IMAGE}" \
    REDIS_IMAGE="${REDIS_IMAGE}" \
    WASM_PATH="${wasm_path}" \
    ENVOY_PORT="${envoy_port}" \
    ENVOY_ADMIN_PORT="${admin_port}" \
    docker compose -p "${project_name}" -f "${script_dir}/compose.yaml" "$@"
}

cleanup() {
  compose down --volumes --remove-orphans >"${log_dir}/compose-down.log" 2>&1 || true
}
trap cleanup EXIT

cleanup
compose up -d >"${log_dir}/compose-up.log" 2>&1

curl --fail --silent --show-error \
  --retry 30 --retry-delay 1 --retry-connrefused --retry-all-errors \
  "http://127.0.0.1:${admin_port}/ready" >"${log_dir}/ready.txt"

compose exec -T redis redis-cli PING >"${log_dir}/redis-ping.txt"

for round in 1 2 3; do
  compose exec -T redis redis-cli SET chat_quota:consumer1 100 \
    >"${result_dir}/round-${round}-redis-set.txt"

  before=$(compose exec -T redis redis-cli GET chat_quota:consumer1 | tr -d '\r')
  printf '%s\n' "${before}" >"${result_dir}/round-${round}-redis-before.txt"

  curl --fail-with-body --silent --show-error \
    --dump-header "${result_dir}/round-${round}-response.headers" \
    --output "${result_dir}/round-${round}-response.body" \
    --write-out '{"http_code":%{http_code},"time_total":%{time_total},"time_starttransfer":%{time_starttransfer},"size_download":%{size_download}}\n' \
    --header 'content-type: application/json' \
    --header 'x-mse-consumer: consumer1' \
    --header "x-verification-round: ${variant}-${round}" \
    --user-agent 'pr4232-evidence-harness/1' \
    --data-binary "@${script_dir}/request.json" \
    "http://127.0.0.1:${envoy_port}/v1/chat/completions" \
    >"${result_dir}/round-${round}-curl.json"

  after=''
  for _ in $(seq 1 50); do
    after=$(compose exec -T redis redis-cli GET chat_quota:consumer1 | tr -d '\r')
    if [[ "${after}" == "${expected_final_quota}" ]]; then
      break
    fi
    sleep 0.1
  done
  printf '%s\n' "${after}" >"${result_dir}/round-${round}-redis-after.txt"

  actual_body=$(<"${result_dir}/round-${round}-response.body")
  if [[ "${actual_body}" != "${expected_body}" ]]; then
    echo "${variant} round ${round}: response body mismatch" >&2
    exit 1
  fi
  if [[ "${before}" != '100' || "${after}" != "${expected_final_quota}" ]]; then
    echo "${variant} round ${round}: quota ${before} -> ${after}, expected 100 -> ${expected_final_quota}" >&2
    exit 1
  fi

  (
    cd "${result_dir}"
    sha256sum "round-${round}-response.body"
  ) >"${result_dir}/round-${round}-response.sha256"
done

# Allow asynchronous Redis and log callbacks to settle before snapshots.
sleep 1

compose logs --no-color envoy >"${log_dir}/envoy.log" 2>&1
compose logs --no-color chunked-mock >"${log_dir}/chunked-mock.log" 2>&1
compose logs --no-color redis >"${log_dir}/redis.log" 2>&1
curl --fail --silent --show-error \
  "http://127.0.0.1:${admin_port}/config_dump" >"${log_dir}/envoy-config-dump.json"
curl --fail --silent --show-error \
  "http://127.0.0.1:${admin_port}/stats?format=json" >"${log_dir}/envoy-stats.json"

cleanup
trap - EXIT

for port in "${envoy_port}" "${admin_port}"; do
  if curl --silent --max-time 1 "http://127.0.0.1:${port}/" >/dev/null 2>&1; then
    echo "port ${port} is still reachable after cleanup" >&2
    exit 1
  fi
done

printf '%s: 3/3 rounds passed, quota 100 -> %s\n' \
  "${variant}" "${expected_final_quota}"
