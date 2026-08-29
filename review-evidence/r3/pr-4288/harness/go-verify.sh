#!/usr/bin/env bash

set -euo pipefail

: "${EVIDENCE_ROOT:?set EVIDENCE_ROOT to review-evidence/r3/pr-4288}"
: "${BASELINE_SOURCE_ROOT:?set BASELINE_SOURCE_ROOT to the baseline checkout}"
: "${FIXED_SOURCE_ROOT:?set FIXED_SOURCE_ROOT to the fixed checkout}"
: "${GO_IMAGE:?set GO_IMAGE to the pinned Go image}"
: "${GO_MOD_CACHE:?set GO_MOD_CACHE to a disposable directory}"
: "${GO_BUILD_CACHE:?set GO_BUILD_CACHE to a disposable directory}"
: "${ARTIFACT_DIR:?set ARTIFACT_DIR to a disposable directory}"

go_proxy=${GOPROXY:-https://proxy.golang.org,direct}
mkdir -p "${GO_MOD_CACHE}" "${GO_BUILD_CACHE}" "${ARTIFACT_DIR}"
mkdir -p "${EVIDENCE_ROOT}/logs/baseline" "${EVIDENCE_ROOT}/logs/fixed"

run_go() {
  local source_root=$1
  shift
  docker run --rm \
    --volume "${source_root}:/src:ro" \
    --volume "${GO_MOD_CACHE}:/go/pkg/mod" \
    --volume "${GO_BUILD_CACHE}:/root/.cache/go-build" \
    --volume "${ARTIFACT_DIR}:/out" \
    --volume "${EVIDENCE_ROOT}:/evidence" \
    --workdir /src/plugins/wasm-go/extensions/ai-proxy \
    --env "GOPROXY=${go_proxy}" \
    --env GOFLAGS=-buildvcs=false \
    "${GO_IMAGE}" "$@"
}

run_go "${BASELINE_SOURCE_ROOT}" go test -mod=readonly -count=1 ./provider \
  >"${EVIDENCE_ROOT}/logs/baseline/provider-unit.log" 2>&1
run_go "${FIXED_SOURCE_ROOT}" go test -mod=readonly -count=1 ./provider \
  >"${EVIDENCE_ROOT}/logs/fixed/provider-unit.log" 2>&1
run_go "${FIXED_SOURCE_ROOT}" go test -mod=readonly -race ./provider \
  -run '^TestGemini(BuildChatCompletionResponse|TransformResponseBody)' -count=20 \
  >"${EVIDENCE_ROOT}/logs/fixed/provider-race-x20.log" 2>&1

set +e
run_go "${BASELINE_SOURCE_ROOT}" go vet -mod=readonly ./provider \
  >"${EVIDENCE_ROOT}/logs/baseline/provider-vet.log" 2>&1
baseline_vet_status=$?
run_go "${FIXED_SOURCE_ROOT}" go vet -mod=readonly ./provider \
  >"${EVIDENCE_ROOT}/logs/fixed/provider-vet.log" 2>&1
fixed_vet_status=$?
set -e

printf 'baseline=%s\nfixed=%s\n' "${baseline_vet_status}" "${fixed_vet_status}" \
  >"${EVIDENCE_ROOT}/logs/provider-vet-status.txt"
if [[ "${baseline_vet_status}" -ne "${fixed_vet_status}" ]]; then
  echo "baseline and fixed vet statuses differ" >&2
  exit 1
fi
if ! cmp -s "${EVIDENCE_ROOT}/logs/baseline/provider-vet.log" \
  "${EVIDENCE_ROOT}/logs/fixed/provider-vet.log"; then
  echo "baseline and fixed vet diagnostics differ" >&2
  exit 1
fi
if grep -Eq 'gemini\.go|gemini_test\.go' \
  "${EVIDENCE_ROOT}/logs/baseline/provider-vet.log"; then
  echo "vet emitted a diagnostic for a changed Gemini file" >&2
  exit 1
fi

run_go "${BASELINE_SOURCE_ROOT}" /bin/sh -ec \
  'GOOS=wasip1 GOARCH=wasm CGO_ENABLED=0 go build -mod=readonly -trimpath -buildmode=c-shared -o /out/ai-proxy-baseline.wasm .' \
  >"${EVIDENCE_ROOT}/logs/baseline/wasm-build.log" 2>&1
run_go "${FIXED_SOURCE_ROOT}" /bin/sh -ec \
  'GOOS=wasip1 GOARCH=wasm CGO_ENABLED=0 go build -mod=readonly -trimpath -buildmode=c-shared -o /out/ai-proxy-fixed.wasm .' \
  >"${EVIDENCE_ROOT}/logs/fixed/wasm-build.log" 2>&1

run_go "${FIXED_SOURCE_ROOT}" /bin/sh -ec \
  'WASM_PATH=/out/ai-proxy-fixed.wasm go test -mod=readonly -count=1 ./...' \
  >"${EVIDENCE_ROOT}/logs/fixed/full-module-wasm-host.log" 2>&1

run_go "${FIXED_SOURCE_ROOT}" /bin/sh -ec \
  'go test -mod=readonly -count=1 -coverprofile=/evidence/logs/fixed/provider-coverage.out ./provider && go tool cover -func=/evidence/logs/fixed/provider-coverage.out' \
  >"${EVIDENCE_ROOT}/logs/fixed/provider-coverage.log" 2>&1

(
  cd "${ARTIFACT_DIR}"
  sha256sum ai-proxy-baseline.wasm ai-proxy-fixed.wasm
) >"${EVIDENCE_ROOT}/logs/wasm-artifacts.sha256"
(
  cd "${ARTIFACT_DIR}"
  wc -c ai-proxy-baseline.wasm ai-proxy-fixed.wasm
) >"${EVIDENCE_ROOT}/logs/wasm-artifacts.sizes"
