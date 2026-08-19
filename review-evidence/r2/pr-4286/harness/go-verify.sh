#!/usr/bin/env bash
set -euo pipefail
set -x

: "${REPO:?set REPO to the fixed Higress checkout}"
IMAGE='golang@sha256:20a022e5112a144aa7b7aeb3f22ebf2cdaefcc4aac0d64e8deeee8cdc18b9c0f'

docker run --rm \
  --volume "${REPO}:/src:ro" \
  --volume pr4286-r2-go-mod-cache:/gomodcache \
  --volume pr4286-r2-go-build-cache:/gocache \
  --workdir /src/plugins/golang-filter \
  --env GOMODCACHE=/gomodcache \
  --env GOCACHE=/gocache \
  --env GOPROXY=https://goproxy.cn,direct \
  "${IMAGE}" bash -euo pipefail -c '
    go version
    go test -mod=readonly ./mcp-server/registry
    go test -mod=readonly -race -count=20 -run "^TestSelectOneInstanceCanSelectEveryBackend$" ./mcp-server/registry
    go vet -mod=readonly ./mcp-server/registry
  '
