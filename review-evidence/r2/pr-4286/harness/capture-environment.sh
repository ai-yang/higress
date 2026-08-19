#!/usr/bin/env bash
set -euo pipefail
set -x

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
EVIDENCE=${EVIDENCE:-$(cd -- "${SCRIPT_DIR}/.." && pwd)}
BASELINE=${BASELINE:-/tmp/higress-pr4286-r2-baseline}
: "${REPO:?set REPO to the fixed Higress checkout}"

mkdir -p "${EVIDENCE}/raw"

date --iso-8601=seconds
uname -a
nproc
free -h
docker version
/tmp/pr4286-bin/kind version
/tmp/pr4286-bin/kubectl version --client --short
/tmp/pr4286-bin/helm version
git -C "${BASELINE}" rev-parse HEAD
git -C "${REPO}" rev-parse HEAD
git -C "${REPO}" status --short --branch
git -C "${REPO}" diff --exit-code -- plugins/golang-filter/mcp-server/registry
sha256sum "${EVIDENCE}/build/baseline/golang-filter_amd64.so" "${EVIDENCE}/build/fixed/golang-filter_amd64.so"
sha256sum /tmp/pr4286-bin/kind /tmp/pr4286-bin/kubectl /tmp/pr4286-bin/helm

docker image inspect 'higress-registry.cn-hangzhou.cr.aliyuncs.com/higress/gateway:481184afc44176eb23d64e0011dc3ea1ae6a410c' > "${EVIDENCE}/raw/image-gateway-base.json"
docker image inspect 'higress-registry.cn-hangzhou.cr.aliyuncs.com/higress/higress:latest' > "${EVIDENCE}/raw/image-controller.json"
docker image inspect 'higress-registry.cn-hangzhou.cr.aliyuncs.com/higress/pilot:de2c9628294f51b13c4a70b3a862b4372890797a' > "${EVIDENCE}/raw/image-pilot.json"
docker image inspect 'docker.m.daocloud.io/nacos/nacos-server:v2.3.2-slim' > "${EVIDENCE}/raw/image-nacos.json"
docker image inspect 'docker.m.daocloud.io/hashicorp/http-echo:1.0.0' > "${EVIDENCE}/raw/image-http-echo.json"
docker image inspect 'golang:1.24.4' > "${EVIDENCE}/raw/image-golang-build.json"
docker image inspect 'docker.m.daocloud.io/kindest/node:v1.25.3' > "${EVIDENCE}/raw/image-kind-node.json"
