#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <baseline|fixed> <wasm-path>" >&2
  exit 2
fi

variant=$1
wasm_path=$2
case "${variant}" in
  baseline|fixed) ;;
  *) echo "unsupported variant: ${variant}" >&2; exit 2 ;;
esac

: "${EVIDENCE_ROOT:?set EVIDENCE_ROOT to review-evidence/r3/pr-4288}"
: "${HIGRESS_GATEWAY_IMAGE:?set the pinned gateway image}"
: "${MOCK_IMAGE:?set the pinned mock image}"

if [[ ! -f "${wasm_path}" ]]; then
  echo "Wasm artifact does not exist: ${wasm_path}" >&2
  exit 2
fi

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
result_dir="${EVIDENCE_ROOT}/results/${variant}"
log_dir="${EVIDENCE_ROOT}/logs/${variant}/runtime"
project_name=${COMPOSE_PROJECT_NAME:-higress-pr4288-r3}
envoy_port=${ENVOY_PORT:-11088}
admin_port=${ENVOY_ADMIN_PORT:-19988}

mkdir -p "${result_dir}" "${log_dir}"
find "${result_dir}" "${log_dir}" -mindepth 1 -maxdepth 1 -type f -delete

compose() {
  HIGRESS_GATEWAY_IMAGE="${HIGRESS_GATEWAY_IMAGE}" \
    MOCK_IMAGE="${MOCK_IMAGE}" \
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

for round in 1 2 3; do
  curl --fail-with-body --silent --show-error \
    --dump-header "${result_dir}/round-${round}-response.headers" \
    --output "${result_dir}/round-${round}-response.json" \
    --write-out '{"http_code":%{http_code},"time_total":%{time_total},"size_download":%{size_download}}\n' \
    --header 'content-type: application/json' \
    --header "x-request-id: pr4288-r3-${variant}-${round}" \
    --header "x-verification-iteration: ${round}" \
    --user-agent 'pr4288-evidence-harness/1' \
    --data-binary "@${script_dir}/request.json" \
    "http://127.0.0.1:${envoy_port}/v1/chat/completions" \
    >"${result_dir}/round-${round}-curl.json"

  if [[ "${variant}" == baseline ]]; then
    "${script_dir}/assert_baseline_response.py" \
      "${result_dir}/round-${round}-response.json" \
      "${script_dir}/gemini-response.json" \
      >"${result_dir}/round-${round}-baseline-assertion.txt"
    set +e
    "${script_dir}/assert_fixed_response.py" \
      "${result_dir}/round-${round}-response.json" \
      >/dev/null 2>&1
    assertion_status=$?
    set -e
    if [[ "${assertion_status}" -eq 0 ]]; then
      echo "baseline round ${round} unexpectedly passed fixed assertion" >&2
      exit 1
    fi
    printf 'expected OpenAI assertion failure: baseline response has no choices\nexpected_failure_exit=%s\n' \
      "${assertion_status}" \
      >"${result_dir}/round-${round}-openai-assertion.txt"
  else
    "${script_dir}/assert_fixed_response.py" \
      "${result_dir}/round-${round}-response.json" \
      >"${result_dir}/round-${round}-openai-assertion.txt"
  fi

  (
    cd "${result_dir}"
    sha256sum "round-${round}-response.json"
  ) >"${result_dir}/round-${round}-response.sha256"
done

sleep 1
curl --fail --silent --show-error \
  "http://127.0.0.1:${admin_port}/config_dump" >"${log_dir}/envoy-config-dump.json"
curl --fail --silent --show-error \
  "http://127.0.0.1:${admin_port}/stats?format=json" >"${log_dir}/envoy-stats.json"
compose logs --no-color envoy >"${log_dir}/envoy.log" 2>&1
compose logs --no-color mock-gemini >"${log_dir}/mock.log" 2>&1

cleanup
trap - EXIT
for port in "${envoy_port}" "${admin_port}"; do
  if curl --silent --max-time 1 "http://127.0.0.1:${port}/" >/dev/null 2>&1; then
    echo "port ${port} is still reachable after cleanup" >&2
    exit 1
  fi
done

printf '%s: 3/3 runtime rounds passed\n' "${variant}"
