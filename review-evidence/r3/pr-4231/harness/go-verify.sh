#!/usr/bin/env bash

set -euo pipefail

: "${HIGRESS_SOURCE_ROOT:?set HIGRESS_SOURCE_ROOT to the fixed source checkout}"
: "${GO_MOD_CACHE:?set GO_MOD_CACHE to a writable module cache directory}"
: "${GO_BUILD_CACHE:?set GO_BUILD_CACHE to a writable build cache directory}"

docker_bin="${DOCKER:-docker}"
go_image="${GO_IMAGE:-golang@sha256:dc2521c2a906db43073b8b4d99f491b6341cf15610b6ebbab187c45153f9959e}"
go_proxy="${GOPROXY:-https://proxy.golang.org,direct}"

"${docker_bin}" run --rm \
  --volume "${HIGRESS_SOURCE_ROOT}:/src:ro" \
  --volume "${HIGRESS_SOURCE_ROOT}/envoy/go-control-plane:/src/external/go-control-plane:ro" \
  --volume "${HIGRESS_SOURCE_ROOT}/istio/api:/src/external/api:ro" \
  --volume "${HIGRESS_SOURCE_ROOT}/istio/client-go:/src/external/client-go:ro" \
  --volume "${HIGRESS_SOURCE_ROOT}/istio/istio:/src/external/istio:ro" \
  --volume "${HIGRESS_SOURCE_ROOT}/istio/pkg:/src/external/pkg:ro" \
  --volume "${GO_MOD_CACHE}:/go/pkg/mod" \
  --volume "${GO_BUILD_CACHE}:/root/.cache/go-build" \
  --env "GOPROXY=${go_proxy}" \
  --workdir /src \
  "${go_image}" \
  bash -euo pipefail -c '
    go version
    echo "[go-verify] targeted unit tests"
    go test -mod=readonly ./pkg/ingress/kube/gateway/istio -run "Test(BuildDestinationHigressServiceBackend|ConvertHTTPRouteWithHigressServiceBackend)$" -count=1
    echo "[go-verify] full package tests"
    go test -mod=readonly ./pkg/ingress/kube/gateway/istio -count=1
    echo "[go-verify] targeted race tests, count=20"
    go test -mod=readonly -race ./pkg/ingress/kube/gateway/istio -run "Test(BuildDestinationHigressServiceBackend|ConvertHTTPRouteWithHigressServiceBackend)$" -count=20
    echo "[go-verify] package vet"
    go vet -mod=readonly ./pkg/ingress/kube/gateway/istio
    echo "[go-verify] PASS"
  '
