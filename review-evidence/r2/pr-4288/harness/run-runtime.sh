#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly EVIDENCE_DIR=${EVIDENCE_DIR:-${SCRIPT_DIR}}
readonly PROJECT=higress-pr4288-r2-runtime
export HIGRESS_GATEWAY_IMAGE='higress-registry.cn-hangzhou.cr.aliyuncs.com/higress/gateway@sha256:93e4da97560d00871299e67163df4f1801732aeea4934a9cea841f9e7b4a26e8'
export MOCK_IMAGE='nginx@sha256:65645c7bb6a0661892a8b03b89d0743208a18dd2f3f17a54ef4b76fb8e2f2a10'
export WASM_PATH="$EVIDENCE_DIR/ai-proxy-fixed.wasm"

cd "$EVIDENCE_DIR"
exec > >(tee "$EVIDENCE_DIR/runtime-run.txt") 2>&1

compose() {
  docker compose -p "$PROJECT" "$@"
}

cleanup() {
  set +e
  compose down --volumes --remove-orphans
}
trap cleanup EXIT

compose down --volumes --remove-orphans
uname -a | tee "$EVIDENCE_DIR/uname.txt"
docker version --format 'Docker server {{.Server.Version}}' \
  | tee "$EVIDENCE_DIR/docker-version.txt"
docker compose version | tee "$EVIDENCE_DIR/compose-version.txt"
docker image inspect "$HIGRESS_GATEWAY_IMAGE" \
  --format 'gateway_id={{.Id}} gateway_repo_digests={{json .RepoDigests}}' \
  | tee "$EVIDENCE_DIR/gateway-image.txt"
docker image inspect "$MOCK_IMAGE" \
  --format 'mock_id={{.Id}} mock_repo_digests={{json .RepoDigests}}' \
  | tee "$EVIDENCE_DIR/mock-image.txt"

export WASM_PATH="$EVIDENCE_DIR/ai-proxy-baseline.wasm"
compose config | tee "$EVIDENCE_DIR/compose-resolved-baseline.yaml"
compose up -d
curl --retry 30 --retry-delay 1 --retry-connrefused --retry-all-errors --fail \
  http://127.0.0.1:19988/ready \
  | tee "$EVIDENCE_DIR/baseline-ready.txt"

baseline_codes=()
for i in 1 2 3; do
  code=$(curl --silent --show-error \
    --header 'Content-Type: application/json' \
    --header "X-Request-ID: pr4288-r2-baseline-$i" \
    --header "X-Verification-Iteration: $i" \
    --data-binary @request.json \
    --dump-header "baseline-headers-$i.txt" \
    --output "baseline-body-$i.bin" \
    --write-out '%{http_code}' \
    http://127.0.0.1:11088/v1/chat/completions)
  baseline_codes+=("$code")
  [[ $code == 200 ]]
  python3 assert_baseline_response.py \
    "baseline-body-$i.bin" gemini-response.json
  set +e
  python3 assert_fixed_response.py "baseline-body-$i.bin" \
    >"baseline-openai-assert-$i.txt" 2>&1
  assertion_status=$?
  set -e
  [[ $assertion_status -ne 0 ]]
done
printf '%s\n' "${baseline_codes[@]}" \
  | tee "$EVIDENCE_DIR/baseline-http-codes.txt"
compose logs --no-color envoy \
  | tee "$EVIDENCE_DIR/baseline-envoy.log" >/dev/null
compose logs --no-color mock-gemini \
  | tee "$EVIDENCE_DIR/baseline-mock.log" >/dev/null
baseline_panic_count=$(grep -cF \
  'recovered from panic runtime error: invalid memory address or nil pointer dereference' \
  "$EVIDENCE_DIR/baseline-envoy.log" || true)
baseline_response_log_count=$(grep -cF 'chat completion response body:' \
  "$EVIDENCE_DIR/baseline-envoy.log" || true)
baseline_mock_count=$(grep -cF \
  '"POST /v1beta/models/gemini-pro:generateContent HTTP/1.1" 200' \
  "$EVIDENCE_DIR/baseline-mock.log" || true)
printf 'panic_count=%s\nresponse_log_count=%s\nmock_200_count=%s\n' \
  "$baseline_panic_count" "$baseline_response_log_count" "$baseline_mock_count" \
  | tee "$EVIDENCE_DIR/baseline-counts.txt"
[[ $baseline_panic_count -eq 3 ]]
[[ $baseline_response_log_count -eq 3 ]]
[[ $baseline_mock_count -eq 3 ]]
sha256sum baseline-body-1.bin baseline-body-2.bin baseline-body-3.bin \
  | tee "$EVIDENCE_DIR/baseline-body-sha256.txt"
compose down --volumes --remove-orphans

export WASM_PATH="$EVIDENCE_DIR/ai-proxy-fixed.wasm"
compose config | tee "$EVIDENCE_DIR/compose-resolved-fixed.yaml"
compose up -d
curl --retry 30 --retry-delay 1 --retry-connrefused --retry-all-errors --fail \
  http://127.0.0.1:19988/ready \
  | tee "$EVIDENCE_DIR/fixed-ready.txt"

fixed_codes=()
for i in 1 2 3; do
  code=$(curl --silent --show-error \
    --header 'Content-Type: application/json' \
    --header "X-Request-ID: pr4288-r2-fixed-$i" \
    --header "X-Verification-Iteration: $i" \
    --data-binary @request.json \
    --dump-header "fixed-headers-$i.txt" \
    --output "fixed-body-$i.json" \
    --write-out '%{http_code}' \
    http://127.0.0.1:11088/v1/chat/completions)
  fixed_codes+=("$code")
  [[ $code == 200 ]]
  python3 assert_fixed_response.py "fixed-body-$i.json"
done
printf '%s\n' "${fixed_codes[@]}" \
  | tee "$EVIDENCE_DIR/fixed-http-codes.txt"
compose logs --no-color envoy \
  | tee "$EVIDENCE_DIR/fixed-envoy.log" >/dev/null
compose logs --no-color mock-gemini \
  | tee "$EVIDENCE_DIR/fixed-mock.log" >/dev/null
fixed_panic_count=$(grep -cF \
  'recovered from panic runtime error: invalid memory address or nil pointer dereference' \
  "$EVIDENCE_DIR/fixed-envoy.log" || true)
fixed_response_log_count=$(grep -cF 'chat completion response body:' \
  "$EVIDENCE_DIR/fixed-envoy.log" || true)
fixed_mock_count=$(grep -cF \
  '"POST /v1beta/models/gemini-pro:generateContent HTTP/1.1" 200' \
  "$EVIDENCE_DIR/fixed-mock.log" || true)
printf 'panic_count=%s\nresponse_log_count=%s\nmock_200_count=%s\n' \
  "$fixed_panic_count" "$fixed_response_log_count" "$fixed_mock_count" \
  | tee "$EVIDENCE_DIR/fixed-counts.txt"
[[ $fixed_panic_count -eq 0 ]]
[[ $fixed_response_log_count -eq 3 ]]
[[ $fixed_mock_count -eq 3 ]]
sha256sum fixed-body-1.json fixed-body-2.json fixed-body-3.json \
  | tee "$EVIDENCE_DIR/fixed-body-sha256.txt"
compose down --volumes --remove-orphans

compose ps --all --format json | tee "$EVIDENCE_DIR/cleanup-compose-ps.json"
docker ps -a --filter "label=com.docker.compose.project=$PROJECT" \
  --format '{{.ID}} {{.Names}} {{.Status}}' \
  | tee "$EVIDENCE_DIR/cleanup-docker-ps.txt"

set +e
curl --silent --show-error --fail --max-time 2 \
  http://127.0.0.1:11088/ >"$EVIDENCE_DIR/cleanup-port-11088.txt" 2>&1
port_11088_status=$?
curl --silent --show-error --fail --max-time 2 \
  http://127.0.0.1:19988/ready >"$EVIDENCE_DIR/cleanup-port-19988.txt" 2>&1
port_19988_status=$?
set -e
printf '11088=%s\n19988=%s\n' "$port_11088_status" "$port_19988_status" \
  | tee "$EVIDENCE_DIR/cleanup-port-status.txt"
[[ $port_11088_status -ne 0 ]]
[[ $port_19988_status -ne 0 ]]

trap - EXIT
