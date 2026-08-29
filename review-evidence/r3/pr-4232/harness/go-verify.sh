#!/usr/bin/env bash

set -euo pipefail

: "${EVIDENCE_ROOT:?set EVIDENCE_ROOT to review-evidence/r3/pr-4232}"
: "${BASELINE_SOURCE_ROOT:?set BASELINE_SOURCE_ROOT to the baseline checkout}"
: "${FIXED_SOURCE_ROOT:?set FIXED_SOURCE_ROOT to the fixed checkout}"
: "${GO_IMAGE:?set GO_IMAGE to the pinned Go image}"
: "${GO_MOD_CACHE:?set GO_MOD_CACHE to a disposable directory}"
: "${GO_BUILD_CACHE:?set GO_BUILD_CACHE to a disposable directory}"
: "${ARTIFACT_DIR:?set ARTIFACT_DIR to a disposable directory}"

go_proxy=${GOPROXY:-https://proxy.golang.org,direct}

mkdir -p "${GO_MOD_CACHE}" "${GO_BUILD_CACHE}" "${ARTIFACT_DIR}"
mkdir -p "${EVIDENCE_ROOT}/logs/baseline" "${EVIDENCE_ROOT}/logs/fixed"

run_variant() {
  local variant=$1
  local source_root=$2
  local output_name="ai-quota-${variant}.wasm"
  local log_file="${EVIDENCE_ROOT}/logs/${variant}/go-verify.log"

  docker run --rm \
    --volume "${source_root}:/src:ro" \
    --volume "${GO_MOD_CACHE}:/go/pkg/mod" \
    --volume "${GO_BUILD_CACHE}:/root/.cache/go-build" \
    --volume "${ARTIFACT_DIR}:/out" \
    --workdir /src/plugins/wasm-go/extensions/ai-quota \
    --env CGO_ENABLED=1 \
    --env GOFLAGS=-buildvcs=false \
    --env "GOPROXY=${go_proxy}" \
    --env "OUTPUT_NAME=${output_name}" \
    "${GO_IMAGE}" \
    /bin/sh -ec '
      echo "== go version =="
      go version
      echo "== unit tests =="
      go test -mod=readonly ./...
      echo "== race tests, 20 repetitions =="
      go test -mod=readonly -race ./... -count=20
      echo "== go vet =="
      go vet -mod=readonly ./...
      echo "== Wasm build =="
      GOOS=wasip1 GOARCH=wasm CGO_ENABLED=0 go build -mod=readonly -trimpath -buildmode=c-shared -o "/out/${OUTPUT_NAME}" .
      echo "== Wasm-host tests =="
      WASM_PATH="/out/${OUTPUT_NAME}" go test -mod=readonly -count=1 ./...
      echo "== artifact =="
      wc -c "/out/${OUTPUT_NAME}"
      sha256sum "/out/${OUTPUT_NAME}"
    ' >"${log_file}" 2>&1
}

run_variant baseline "${BASELINE_SOURCE_ROOT}"
run_variant fixed "${FIXED_SOURCE_ROOT}"

(
  cd "${ARTIFACT_DIR}"
  sha256sum ai-quota-baseline.wasm ai-quota-fixed.wasm
) >"${EVIDENCE_ROOT}/logs/wasm-artifacts.sha256"

(
  cd "${ARTIFACT_DIR}"
  wc -c ai-quota-baseline.wasm ai-quota-fixed.wasm
) >"${EVIDENCE_ROOT}/logs/wasm-artifacts.sizes"
