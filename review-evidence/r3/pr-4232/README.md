# PR #4232 R3 review evidence

This directory contains sanitized, public, reproducible evidence for
[higress-group/higress#4232](https://github.com/higress-group/higress/pull/4232),
which addresses [issue #3743](https://github.com/higress-group/higress/issues/3743).

## Result

The same Envoy configuration, pinned gateway and Redis images, request, Redis
key, initial quota, two-part upstream response, and three-round harness were
used for both variants. Only the `ai-quota` Wasm artifact changed.

The mock sends one valid non-streaming JSON response as two HTTP/1.1 chunks of
60 bytes each, separated by 350 ms. The boundary falls immediately after the
opening `usage` object. Each fragment is therefore insufficient for the
baseline callback to extract the complete usage, while the reconstructed
120-byte response contains 11 prompt tokens and 7 completion tokens.

| Assertion | Baseline `409b3ed2` | Fixed `d03df020` |
|---|---|---|
| HTTP responses | 3/3 `200`, exact 120-byte body | 3/3 `200`, exact 120-byte body |
| Upstream chunk sizes | 3 × `60,60` | 3 × `60,60` |
| Envoy completed / 2xx requests | `3 / 3` | `3 / 3` |
| Initial Redis quota per round | `100, 100, 100` | `100, 100, 100` |
| Final Redis quota per round | `100, 100, 100` | `82, 82, 82` |
| Correct 18-token decrement log | 0 | 3 |
| Outcome | Reproduces complete under-deduction | Correct quota accounting |

`harness/verify-evidence.py` checks the response bytes, curl metadata, enforced
350 ms split, upstream logs, Envoy request statistics, quota values, and Wasm
update logs. Its final result is `evidence verification: PASS`.

## Why the bug occurs

The baseline registers only the streaming response-body callback. A normal
`application/json` response may still arrive in multiple proxy body callbacks;
the baseline tries to parse each fragment independently and reaches end of
stream without a complete usage object.

The fixed variant:

- registers response-header, streaming-body, and normal response-body handlers;
- buffers only non-SSE completion responses before parsing usage;
- leaves SSE responses on the streaming path;
- routes both paths through one deduplicated quota-update function; and
- permits retry after a synchronous Redis dispatch failure.

## Environment pins

`environment.json` records the source SHAs, image references and IDs, tool
versions, build flags, artifact sizes and hashes, fixed ports, chunk boundary,
and expected outcomes. Principal pins are:

- Higress gateway v2.2.4 digest
  `sha256:3dbd609df5db3fca61653eafe0e2310705e485190c4f8cd02d9aab8f07dcf329`
- Envoy `1.36.4` from that gateway image
- Redis 7.4 digest
  `sha256:3e0669e42d4fe421c9dea0ba5fbc04d336b80b4f32a6c7d25bee3a1d089288a1`
- Go 1.24.4 image digest
  `sha256:20a022e5112a144aa7b7aeb3f22ebf2cdaefcc4aac0d64e8deeee8cdc18b9c0f`

The 5.8 MB Wasm files are not committed. They are reproducibly built by
`harness/go-verify.sh`; their byte sizes and SHA256 values are recorded in
`logs/wasm-artifacts.sizes` and `logs/wasm-artifacts.sha256`.

## Reproduction

Prepare baseline and fixed Higress checkouts at the SHAs in `environment.json`,
then use disposable cache and artifact directories:

```bash
export EVIDENCE_ROOT="$PWD/review-evidence/r3/pr-4232"
export BASELINE_SOURCE_ROOT=/path/to/higress-baseline
export FIXED_SOURCE_ROOT=/path/to/higress-fixed
export GO_MOD_CACHE=/path/to/disposable/go-mod-cache
export GO_BUILD_CACHE=/path/to/disposable/go-build-cache
export ARTIFACT_DIR=/path/to/disposable/artifacts
export GO_IMAGE='golang@sha256:20a022e5112a144aa7b7aeb3f22ebf2cdaefcc4aac0d64e8deeee8cdc18b9c0f'
export GOPROXY='https://proxy.golang.org,direct'

./review-evidence/r3/pr-4232/harness/go-verify.sh

export BASELINE_WASM="$ARTIFACT_DIR/ai-quota-baseline.wasm"
export FIXED_WASM="$ARTIFACT_DIR/ai-quota-fixed.wasm"
export HIGRESS_GATEWAY_IMAGE='higress-registry.cn-hangzhou.cr.aliyuncs.com/higress/gateway@sha256:3dbd609df5db3fca61653eafe0e2310705e485190c4f8cd02d9aab8f07dcf329'
export REDIS_IMAGE='redis:7.4@sha256:3e0669e42d4fe421c9dea0ba5fbc04d336b80b4f32a6c7d25bee3a1d089288a1'

./review-evidence/r3/pr-4232/harness/run-runtime.sh
```

The recorded run used `https://goproxy.cn,direct` after the default Go proxy
timed out during dependency download. The retained logs are the complete,
successful rerun. Runtime networking is limited to the Compose networks and
the two loopback-only ports in `environment.json`; Redis is not published.

## Evidence map

- `harness/`: pinned Compose fixture, Envoy config, deterministic chunked mock,
  fixed-toolchain verification, three-round runner, and assertions.
- `logs/baseline/` and `logs/fixed/`: Go/race/vet/Wasm-host output, runtime
  container logs, Envoy config/stats, coverage, and lifecycle records.
- `results/`: every response body/header, curl result, Redis before/after value,
  per-response hash, and asserted machine summary.
- `logs/source-diff.patch`, `logs/source-diff.stat`, `logs/range-diff.txt`: exact
  change and pre-/post-rebase equivalence.
- `SHA256SUMS`: integrity manifest for every published file except itself.

See `validation-report.md` for the concise matrix, guard checks, and limitations.
