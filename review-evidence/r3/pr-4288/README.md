# PR #4288 R3 review evidence

This directory contains sanitized, public, reproducible post-rebase evidence
for [higress-group/higress#4288](https://github.com/higress-group/higress/pull/4288),
which fixes [issue #4284](https://github.com/higress-group/higress/issues/4284).

## Result

The same request, mixed text/function-call/text Gemini response, pinned gateway
and Nginx images, Envoy config, and three-round harness were used for both
variants. Only the `ai-proxy` Wasm artifact changed.

| Assertion | Baseline `409b3ed2` | Fixed `2869a8e7` |
|---|---|---|
| Mock provider responses | 3/3 `200` | 3/3 `200` |
| Client responses | 3/3 `200` | 3/3 `200` |
| Envoy completed / 2xx requests | `3 / 3` | `3 / 3` |
| Recovered nil-pointer panics | 3 | 0 |
| Response shape | Original Gemini body, no `choices` | Valid OpenAI response |
| OpenAI structural assertion | 0/3 | 3/3 |
| Candidate mapping | Conversion aborted | One candidate → one choice |
| Content | Conversion aborted | `Let me check. One moment.` |
| Tool calls | Conversion aborted | One indexed `lookup({"id":42})` call |
| Finish reason | Conversion aborted | `tool_calls` |
| Usage | Conversion aborted | prompt/completion/total `10/5/15` |

`harness/verify-evidence.py` checks the raw responses, structural semantics,
curl metadata, provider and Envoy logs, panic counts, mock counts, and Envoy
request statistics. Its result is `evidence verification: PASS`.

## Rebase and coverage update

The branch was rebased from `main@4b23e08a` to `main@409b3ed2`. The production
`gemini.go` binary diff is byte-identical before and after rebase, with SHA256
`cc9102b18ad383581789afea8f04b663b58b770599cc56efdfd75e7c31902eff`.

The earlier Codecov report identified seven uncovered changed lines. Three
focused tests were added after rebase for the corresponding branches: an empty
candidate, an inline-data part, and unmarshalable function arguments followed
by a valid call. `buildChatCompletionResponse` and `buildToolCalls` now each
report 100% statement coverage. `logs/range-diff.txt` shows that these tests are
the only intentional delta from the previous PR head.

## Fixed-toolchain verification

- Baseline and fixed provider suites pass.
- All targeted Gemini regression tests pass under `-race -count=20`.
- Baseline and fixed `go vet ./provider` produce byte-identical 86-line output
  and the same exit status; all diagnostics are pre-existing unexported-field
  JSON-tag warnings and neither changed Gemini file appears.
- Both WASI c-shared builds pass.
- The fixed Wasm-host full module suite passes, including the upstream provider
  additions made since R2.
- Fixed provider coverage capture passes; the full provider package reports
  32.1%, while the two changed response-conversion functions report 100%.

## Environment pins

`environment.json` records all source SHAs, image references and IDs, tool
versions, build flags, artifact sizes and hashes, ports, and fixture values.
Principal pins are:

- Higress gateway digest
  `sha256:93e4da97560d00871299e67163df4f1801732aeea4934a9cea841f9e7b4a26e8`
  with Envoy 1.27.7
- Nginx 1.27.5 digest
  `sha256:65645c7bb6a0661892a8b03b89d0743208a18dd2f3f17a54ef4b76fb8e2f2a10`
- Go 1.24.4 image digest
  `sha256:20a022e5112a144aa7b7aeb3f22ebf2cdaefcc4aac0d64e8deeee8cdc18b9c0f`

The 9.5 MB Wasm binaries are not committed. Their reproducible sizes and
SHA256 values are in `logs/wasm-artifacts.sizes` and
`logs/wasm-artifacts.sha256`.

## Reproduction

Prepare baseline and fixed Higress checkouts at the SHAs in `environment.json`.
Use disposable cache and artifact directories:

```bash
export EVIDENCE_ROOT="$PWD/review-evidence/r3/pr-4288"
export BASELINE_SOURCE_ROOT=/path/to/higress-baseline
export FIXED_SOURCE_ROOT=/path/to/higress-fixed
export GO_MOD_CACHE=/path/to/disposable/go-mod-cache
export GO_BUILD_CACHE=/path/to/disposable/go-build-cache
export ARTIFACT_DIR=/path/to/disposable/artifacts
export GO_IMAGE='golang:1.24.4@sha256:20a022e5112a144aa7b7aeb3f22ebf2cdaefcc4aac0d64e8deeee8cdc18b9c0f'
export GOPROXY='https://proxy.golang.org,direct'

./review-evidence/r3/pr-4288/harness/go-verify.sh

export BASELINE_WASM="$ARTIFACT_DIR/ai-proxy-baseline.wasm"
export FIXED_WASM="$ARTIFACT_DIR/ai-proxy-fixed.wasm"
export HIGRESS_GATEWAY_IMAGE='higress-registry.cn-hangzhou.cr.aliyuncs.com/higress/gateway@sha256:93e4da97560d00871299e67163df4f1801732aeea4934a9cea841f9e7b4a26e8'
export MOCK_IMAGE='nginx@sha256:65645c7bb6a0661892a8b03b89d0743208a18dd2f3f17a54ef4b76fb8e2f2a10'

./review-evidence/r3/pr-4288/harness/run-runtime.sh
```

The recorded run used `https://goproxy.cn,direct`. The plugin configuration
contains only the literal `<redacted-test-token>` fixture value; no real
credential is required or published. Runtime service traffic stays on the
internal Compose network, and the two host ports bind only to loopback.

## Evidence map

- `harness/`: pinned fixture, assertions, fixed-toolchain checks, 3+3 runtime
  runner, and machine verifier.
- `logs/baseline/` and `logs/fixed/`: unit/race/vet/build/coverage/full-module
  output, complete sanitized runtime logs, Envoy config and statistics.
- `results/`: every response/header, assertion outcome, curl result, per-body
  hash, and the asserted machine summary.
- `logs/source-diff.patch`, `logs/range-diff.txt`, and
  `logs/production-patch-continuity.txt`: exact change and continuity audit.
- `SHA256SUMS`: integrity manifest for every published file except itself.

The earlier R2 bundle remains available at the immutable revision linked from
the PR. See `validation-report.md` for the concise matrix and limitations.
