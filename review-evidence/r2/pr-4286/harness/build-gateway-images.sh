#!/usr/bin/env bash
set -euo pipefail
set -x

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
EVIDENCE=${EVIDENCE:-$(cd -- "${SCRIPT_DIR}/.." && pwd)}
BASE_IMAGE='higress-registry.cn-hangzhou.cr.aliyuncs.com/higress/gateway@sha256:b8221ddf705ef44cada9e426ace0a2ead5801a3a143c2b19e0e40811c1da003d'
BASELINE_IMAGE='higress-registry.cn-hangzhou.cr.aliyuncs.com/higress/gateway:pr4286-r2-baseline-4b23e08a'
FIXED_IMAGE='higress-registry.cn-hangzhou.cr.aliyuncs.com/higress/gateway:pr4286-r2-fixed-83c5c035'

mkdir -p "${EVIDENCE}/raw"

docker build --file "${SCRIPT_DIR}/gateway-overlay.Dockerfile" \
  --build-arg "BASE_IMAGE=${BASE_IMAGE}" \
  --build-arg FILTER_PATH=build/baseline/golang-filter_amd64.so \
  --build-arg SOURCE_REVISION=4b23e08a386779c8958673ebb052fc6306fe807c \
  --build-arg VARIANT=baseline \
  --tag "${BASELINE_IMAGE}" "${EVIDENCE}"

docker build --file "${SCRIPT_DIR}/gateway-overlay.Dockerfile" \
  --build-arg "BASE_IMAGE=${BASE_IMAGE}" \
  --build-arg FILTER_PATH=build/fixed/golang-filter_amd64.so \
  --build-arg SOURCE_REVISION=83c5c03560ac212c8bb2e236db559a29e8bf300d \
  --build-arg VARIANT=fixed \
  --tag "${FIXED_IMAGE}" "${EVIDENCE}"

docker image inspect "${BASELINE_IMAGE}" > "${EVIDENCE}/raw/image-baseline-gateway.json"
docker image inspect "${FIXED_IMAGE}" > "${EVIDENCE}/raw/image-fixed-gateway.json"
