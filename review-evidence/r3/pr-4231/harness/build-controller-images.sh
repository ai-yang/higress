#!/usr/bin/env bash

set -euo pipefail

: "${BASELINE_SOURCE_ROOT:?set BASELINE_SOURCE_ROOT to baseline SHA 409b3ed2 checkout}"
: "${FIXED_SOURCE_ROOT:?set FIXED_SOURCE_ROOT to fixed SHA 7cc8cde4 checkout}"
: "${ARTIFACT_DIR:?set ARTIFACT_DIR to a disposable writable directory}"
: "${GO_MOD_CACHE:?set GO_MOD_CACHE to a writable module cache directory}"
: "${GO_BUILD_CACHE:?set GO_BUILD_CACHE to a writable build cache directory}"

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
docker_bin="${DOCKER:-docker}"
go_image="${GO_IMAGE:-golang@sha256:dc2521c2a906db43073b8b4d99f491b6341cf15610b6ebbab187c45153f9959e}"
base_image="${CONTROLLER_BASE_IMAGE:-higress-registry.cn-hangzhou.cr.aliyuncs.com/higress/higress@sha256:11fb1244d35615210faaa6bda54cd187e6a445e09892da4cc2619896c34b0e11}"
go_proxy="${GOPROXY:-https://proxy.golang.org,direct}"

build_one() {
  local variant="$1"
  local source_root="$2"
  local source_sha="$3"
  local expected_binary_sha="$4"
  local image_tag="$5"
  local output_dir="${ARTIFACT_DIR}/${variant}"

  mkdir -p "${output_dir}"
  "${docker_bin}" run --rm \
    --env CGO_ENABLED=0 \
    --env GOOS=linux \
    --env GOARCH=amd64 \
    --env "GOPROXY=${go_proxy}" \
    --env "SOURCE_SHA=${source_sha}" \
    --volume "${source_root}:/src:ro" \
    --volume "${source_root}/envoy/go-control-plane:/src/external/go-control-plane:ro" \
    --volume "${source_root}/istio/api:/src/external/api:ro" \
    --volume "${source_root}/istio/client-go:/src/external/client-go:ro" \
    --volume "${source_root}/istio/istio:/src/external/istio:ro" \
    --volume "${source_root}/istio/pkg:/src/external/pkg:ro" \
    --volume "${GO_MOD_CACHE}:/go/pkg/mod" \
    --volume "${GO_BUILD_CACHE}:/root/.cache/go-build" \
    --volume "${output_dir}:/out" \
    --workdir /src \
    "${go_image}" \
    bash -euo pipefail -c '
      go build -mod=readonly -trimpath -buildvcs=false \
        -ldflags="-s -w -X github.com/alibaba/higress/v2/pkg/cmd/version.higressVersion=v2.2.4 -X github.com/alibaba/higress/v2/pkg/cmd/version.gitCommitID=${SOURCE_SHA}" \
        -o /out/higress ./cmd/higress
    '

  local actual_binary_sha
  actual_binary_sha="$(sha256sum "${output_dir}/higress" | awk '{print $1}')"
  test "${actual_binary_sha}" = "${expected_binary_sha}"

  "${docker_bin}" build \
    --file "${script_dir}/controller-overlay.Dockerfile" \
    --build-arg "BASE_IMAGE=${base_image}" \
    --build-arg "SOURCE_SHA=${source_sha}" \
    --build-arg "BINARY_SHA256=${actual_binary_sha}" \
    --tag "${image_tag}" \
    "${output_dir}"
  "${docker_bin}" image inspect --format '{{.Id}} {{json .Config.Labels}}' "${image_tag}"
}

build_one \
  baseline \
  "${BASELINE_SOURCE_ROOT}" \
  409b3ed2644a977776391eae78ed6cb11e99d3d3 \
  2e19540692a0dc493723ef7b4d8987d2cd472284d30f1571c44518a96f231509 \
  higress-registry.cn-hangzhou.cr.aliyuncs.com/higress/higress:pr4231-r3-baseline-409b3ed2

build_one \
  fixed \
  "${FIXED_SOURCE_ROOT}" \
  7cc8cde4bb8b268e1e5fa98219790b392e1d98d3 \
  fa8042cc22e66506da15d408ea2c971c8d9021a5deff497a6e6168f33fa903f8 \
  higress-registry.cn-hangzhou.cr.aliyuncs.com/higress/higress:pr4231-r3-fixed-7cc8cde4
