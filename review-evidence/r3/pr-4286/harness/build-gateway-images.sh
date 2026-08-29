#!/usr/bin/env bash
set -euo pipefail
set -x

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
EVIDENCE=${EVIDENCE:-$(cd -- "${SCRIPT_DIR}/.." && pwd)}
BASE_IMAGE='higress-registry.cn-hangzhou.cr.aliyuncs.com/higress/gateway@sha256:6cb8367c98ccce4a5b83b19b37ba1b4156721da31871904cc6632ab129757dde'
BASELINE_IMAGE='higress-registry.cn-hangzhou.cr.aliyuncs.com/higress/gateway:pr4286-r3-baseline-409b3ed2'
FIXED_IMAGE='higress-registry.cn-hangzhou.cr.aliyuncs.com/higress/gateway:pr4286-r3-fixed-81c547a2'

mkdir -p "${EVIDENCE}/raw"

docker build --file "${SCRIPT_DIR}/gateway-overlay.Dockerfile" \
  --build-arg "BASE_IMAGE=${BASE_IMAGE}" \
  --build-arg FILTER_PATH=build/baseline/golang-filter_amd64.so \
  --build-arg SOURCE_REVISION=409b3ed2644a977776391eae78ed6cb11e99d3d3 \
  --build-arg VARIANT=baseline \
  --tag "${BASELINE_IMAGE}" "${EVIDENCE}"

docker build --file "${SCRIPT_DIR}/gateway-overlay.Dockerfile" \
  --build-arg "BASE_IMAGE=${BASE_IMAGE}" \
  --build-arg FILTER_PATH=build/fixed/golang-filter_amd64.so \
  --build-arg SOURCE_REVISION=81c547a2c26c370f0f101b8342770d47e97378cb \
  --build-arg VARIANT=fixed \
  --tag "${FIXED_IMAGE}" "${EVIDENCE}"

docker image inspect "${BASELINE_IMAGE}" > "${EVIDENCE}/raw/image-baseline-gateway.json"
docker image inspect "${FIXED_IMAGE}" > "${EVIDENCE}/raw/image-fixed-gateway.json"
