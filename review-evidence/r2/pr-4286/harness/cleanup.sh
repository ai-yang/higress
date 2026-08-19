#!/usr/bin/env bash
set -euo pipefail
set -x

: "${REPO:?set REPO to the fixed Higress checkout}"

/tmp/pr4286-bin/kind get clusters
docker ps -a --filter name=pr4286-r2
docker volume ls --filter name=pr4286-r2
ss -ltnp | grep -E ':(18080|18848)\b' || true

/tmp/pr4286-bin/kind delete cluster --name pr4286-r2
docker volume rm pr4286-r2-go-build-cache pr4286-r2-go-mod-cache
git -C "${REPO}" worktree remove /tmp/higress-pr4286-r2-baseline

/tmp/pr4286-bin/kind get clusters
docker ps -a --filter name=pr4286-r2
docker volume ls --filter name=pr4286-r2
ss -ltnp | grep -E ':(18080|18848)\b' || true
git -C "${REPO}" worktree list
