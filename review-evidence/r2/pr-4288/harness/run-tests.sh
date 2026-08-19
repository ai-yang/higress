#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly BASELINE_WORKTREE=${BASELINE_WORKTREE:-/tmp/higress-pr4288-r2-main}
: "${FIXED_WORKTREE:?set FIXED_WORKTREE to the fixed Higress checkout}"
readonly EVIDENCE_DIR=${EVIDENCE_DIR:-${SCRIPT_DIR}}
readonly GOMODCACHE_DIR=/tmp/higress-gomodcache
readonly GOCACHE_DIR=/tmp/higress-gobuildcache
readonly GO_IMAGE='golang:1.24.4@sha256:20a022e5112a144aa7b7aeb3f22ebf2cdaefcc4aac0d64e8deeee8cdc18b9c0f'

mkdir -p "$GOMODCACHE_DIR" "$GOCACHE_DIR"

run_ai_proxy() {
  local worktree=$1
  shift
  docker run --rm \
    -e GOPROXY=https://goproxy.cn,direct \
    -e GOMODCACHE=/gomodcache \
    -e GOCACHE=/gobuildcache \
    -v "$GOMODCACHE_DIR":/gomodcache \
    -v "$GOCACHE_DIR":/gobuildcache \
    -v "$EVIDENCE_DIR":/artifacts \
    -v "$worktree":/src:ro \
    -w /src/plugins/wasm-go/extensions/ai-proxy \
    "$GO_IMAGE" "$@"
}

docker run --rm "$GO_IMAGE" go version 2>&1 | tee "$EVIDENCE_DIR/go-version.txt"

run_ai_proxy "$FIXED_WORKTREE" go test ./provider -count=1 \
  2>&1 | tee "$EVIDENCE_DIR/provider-unit.txt"

run_ai_proxy "$FIXED_WORKTREE" go test -race ./provider \
  -run '^TestGemini(BuildChatCompletionResponse|TransformResponseBody)' -count=20 \
  2>&1 | tee "$EVIDENCE_DIR/provider-race-x20.txt"

set +e
run_ai_proxy "$BASELINE_WORKTREE" go vet ./provider \
  2>&1 | tee "$EVIDENCE_DIR/vet-baseline.txt"
baseline_vet_status=${PIPESTATUS[0]}
run_ai_proxy "$FIXED_WORKTREE" go vet ./provider \
  2>&1 | tee "$EVIDENCE_DIR/vet-fixed.txt"
fixed_vet_status=${PIPESTATUS[0]}
set -e
printf 'baseline=%s\nfixed=%s\n' "$baseline_vet_status" "$fixed_vet_status" \
  | tee "$EVIDENCE_DIR/vet-status.txt"

if [[ $baseline_vet_status -ne 1 || $fixed_vet_status -ne 1 ]]; then
  echo 'unexpected go vet exit status' >&2
  exit 1
fi

run_ai_proxy "$BASELINE_WORKTREE" env GOOS=wasip1 GOARCH=wasm \
  go build -buildmode=c-shared -o /artifacts/ai-proxy-baseline.wasm ./ \
  2>&1 | tee "$EVIDENCE_DIR/wasm-build-baseline.txt"

run_ai_proxy "$FIXED_WORKTREE" env GOOS=wasip1 GOARCH=wasm \
  go build -buildmode=c-shared -o /artifacts/ai-proxy-fixed.wasm ./ \
  2>&1 | tee "$EVIDENCE_DIR/wasm-build-fixed.txt"

run_ai_proxy "$FIXED_WORKTREE" env WASM_PATH=/artifacts/ai-proxy-fixed.wasm \
  go test ./... -count=1 \
  2>&1 | tee "$EVIDENCE_DIR/full-module-tests.txt"

sha256sum "$EVIDENCE_DIR/ai-proxy-baseline.wasm" \
  "$EVIDENCE_DIR/ai-proxy-fixed.wasm" \
  | tee "$EVIDENCE_DIR/wasm-sha256.txt"
