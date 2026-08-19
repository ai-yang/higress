#!/usr/bin/env bash
set -euo pipefail
set -x

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
EVIDENCE=${EVIDENCE:-$(cd -- "${SCRIPT_DIR}/.." && pwd)}
BASELINE=${BASELINE:-/tmp/higress-pr4286-r2-baseline}
: "${REPO:?set REPO to the fixed Higress checkout}"
IMAGE='golang@sha256:20a022e5112a144aa7b7aeb3f22ebf2cdaefcc4aac0d64e8deeee8cdc18b9c0f'

mkdir -p "${EVIDENCE}/build/baseline" "${EVIDENCE}/build/fixed"

build_filter() {
  local source_root=$1
  local variant=$2
  docker run --rm \
    --volume "${source_root}:/src:ro" \
    --volume "${EVIDENCE}/build/${variant}:/out" \
    --volume pr4286-r2-go-mod-cache:/gomodcache \
    --volume pr4286-r2-go-build-cache:/gocache \
    --workdir /src/plugins/golang-filter \
    --env GOMODCACHE=/gomodcache \
    --env GOCACHE=/gocache \
    --env GOPROXY=https://goproxy.cn,direct \
    "${IMAGE}" bash -euo pipefail -c '
      go version
      gcc --version | head -n 1
      go env GOOS GOARCH GOVERSION GOPROXY GOMODCACHE GOCACHE
      CGO_ENABLED=1 GOOS=linux GOARCH=amd64 CC=gcc AS=as \
        go build -mod=readonly -buildmode=c-shared -o /out/golang-filter_amd64.so .
    '
}

build_filter "${BASELINE}" baseline
build_filter "${REPO}" fixed
sha256sum "${EVIDENCE}/build/baseline/golang-filter_amd64.so" "${EVIDENCE}/build/fixed/golang-filter_amd64.so"
