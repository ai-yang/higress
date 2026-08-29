# PR #4231 R3 review evidence

This directory contains the sanitized, public, reproducible evidence for
[higress-group/higress#4231](https://github.com/higress-group/higress/pull/4231),
which fixes [issue #4185](https://github.com/higress-group/higress/issues/4185).

## Result

The same Gateway, HTTPRoute, `default` McpBridge DNS registry, echo backend,
gateway image, pilot image, chart, Kubernetes cluster, and request harness were
used for both variants. The Helm render differs only in the controller image
tag, as recorded in `logs/helm-rendered-controller.diff`.

| Assertion | Baseline `409b3ed2` | Fixed `7cc8cde4` |
|---|---|---|
| Controller-reported Git SHA | `409b3ed2644a977776391eae78ed6cb11e99d3d3` | `7cc8cde4bb8b268e1e5fa98219790b392e1d98d3` |
| HTTPRoute `ResolvedRefs` | `False / InvalidKind` | `True / ResolvedRefs` |
| Envoy route cluster | `UnknownService` | `outbound\|5678\|\|pr4231-echo.dns` |
| Registered target cluster | Present, one healthy host | Present, one healthy host |
| Direct backend request from gateway | `200`, `pr4231-backend-ok` | `200`, `pr4231-backend-ok` |
| Gateway requests | `500, 500, 500` | `200, 200, 200` |
| Access-log result | 3 × `cluster_not_found` | 3 × `via_upstream` |
| Fixed response body | N/A | 3 × `pr4231-backend-ok\n` |

`harness/verify-evidence.py` checks all rows above and writes the machine-readable
`results/summary.json`. Its final result is `evidence verification: PASS`.

## Environment pins

`environment.json` records every source SHA, submodule SHA, binary hash, image
reference/digest or local image ID, tool hash, build flag, chart version, and
cluster port. The main pins are:

- Kubernetes v1.34.0 on
  `kindest/node:v1.34.0@sha256:7416a61b42b1662ca6ca89f02028ac133a309a2a30ba309614e8ec94d976dc5a`
- Gateway API v1.6.0 standard channel
- Higress chart/app v2.2.4
- Go 1.26.7 image
  `golang@sha256:dc2521c2a906db43073b8b4d99f491b6341cf15610b6ebbab187c45153f9959e`
- gateway v2.2.4 digest `sha256:3dbd609df5db3fca61653eafe0e2310705e485190c4f8cd02d9aab8f07dcf329`
- pilot v2.2.4 digest `sha256:f742ed20f938c5c1eaf6f8c36c6481a87052d06e903ab6cb0c079165ac0c8284`

The baseline and fixed controller binaries are not committed because each is
119 MB. Their SHA256 values are recorded in `environment.json`, embedded as
OCI labels in the local overlay images, and verified by the build harness.

## Reproduction

Prepare two Higress checkouts at the baseline and fixed SHAs and initialize the
five submodules listed in `environment.json`. Supply the pinned `kind`,
`kubectl`, and `helm` binaries through environment variables. Use disposable
cache/artifact/runtime directories.

```bash
export EVIDENCE_ROOT="$PWD/review-evidence/r3/pr-4231"
export BASELINE_SOURCE_ROOT=/path/to/higress-baseline
export FIXED_SOURCE_ROOT=/path/to/higress-fixed
export HIGRESS_SOURCE_ROOT="$FIXED_SOURCE_ROOT"
export GO_MOD_CACHE=/path/to/disposable/go-mod-cache
export GO_BUILD_CACHE=/path/to/disposable/go-build-cache
export ARTIFACT_DIR=/path/to/disposable/artifacts
export RUNTIME_DIR=/path/to/disposable/runtime
export KIND=/path/to/kind-v0.17.0
export KUBECTL=/path/to/kubectl-v1.34.0
export HELM=/path/to/helm-v3.14.4
export KUBECONFIG=/path/to/disposable/kubeconfig

./review-evidence/r3/pr-4231/harness/build-controller-images.sh
./review-evidence/r3/pr-4231/harness/go-verify.sh
./review-evidence/r3/pr-4231/harness/cluster-setup.sh
./review-evidence/r3/pr-4231/harness/run-requests.sh baseline
./review-evidence/r3/pr-4231/harness/capture-variant.sh baseline
./review-evidence/r3/pr-4231/harness/upgrade-fixed.sh
./review-evidence/r3/pr-4231/harness/run-requests.sh fixed
./review-evidence/r3/pr-4231/harness/capture-variant.sh fixed
./review-evidence/r3/pr-4231/harness/verify-evidence.py
./review-evidence/r3/pr-4231/harness/cleanup.sh
```

If `proxy.golang.org` is not reachable, set `GOPROXY` to an approved mirror.
The successful recorded run used `https://goproxy.cn,direct` after an initial
dependency-fetch timeout; the final test log is a clean, cached rerun.

Higress only reconciles the registry bridge named `default` in
`higress-system`. The final fixture follows the repository's
`test/e2e/conformance/tests/httproute-dns-registry.yaml` convention. An early
exploratory fixture with another McpBridge name was rejected before evidence
collection and is not part of these results.

## Evidence map

- `manifests/`: exact kind, Helm, Gateway, HTTPRoute, McpBridge, Service, and
  backend manifests.
- `harness/`: image build, Go verification, cluster setup, capture, request,
  upgrade, assertion, and cleanup scripts.
- `logs/baseline/` and `logs/fixed/`: controller/pilot/gateway logs, live
  resource YAML, controller version, Envoy clusters/routes/stats, and direct
  backend response.
- `results/`: raw response headers/bodies, curl JSON metadata, and the asserted
  summary.
- `logs/source-diff.patch`, `logs/range-diff.txt`: exact source change and
  pre-/post-rebase comparison.
- `SHA256SUMS`: integrity manifest for every published evidence file except the
  checksum file itself.

See `validation-report.md` for the concise test matrix, guard checks, and
limitations.
