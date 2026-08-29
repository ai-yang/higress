#!/usr/bin/env bash
set -euo pipefail
set -x

: "${REPO:?set REPO to the fixed Higress checkout}"
OLD_BASE=4b23e08a386779c8958673ebb052fc6306fe807c
OLD_HEAD=83c5c03560ac212c8bb2e236db559a29e8bf300d
NEW_BASE=409b3ed2644a977776391eae78ed6cb11e99d3d3
NEW_HEAD=81c547a2c26c370f0f101b8342770d47e97378cb
SOURCE=plugins/golang-filter/mcp-server/registry/remote.go

git -C "${REPO}" rev-parse HEAD^ HEAD
test "$(git -C "${REPO}" rev-parse HEAD^)" = "${NEW_BASE}"
test "$(git -C "${REPO}" rev-parse HEAD)" = "${NEW_HEAD}"
git -C "${REPO}" diff --check "${NEW_BASE}..${NEW_HEAD}"
git -C "${REPO}" log -1 --format=fuller
git -C "${REPO}" diff --stat "${NEW_BASE}..${NEW_HEAD}"
git -C "${REPO}" range-diff \
  "${OLD_BASE}..${OLD_HEAD}" "${NEW_BASE}..${NEW_HEAD}"
git -C "${REPO}" diff "${OLD_BASE}..${OLD_HEAD}" -- "${SOURCE}" | sha256sum
git -C "${REPO}" diff "${NEW_BASE}..${NEW_HEAD}" -- "${SOURCE}" | sha256sum
