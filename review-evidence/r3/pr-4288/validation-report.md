# PR #4288 R3 validation report

## Runtime red/green matrix

| Variant | Round | HTTP | Bytes | Provider 200 | Panic | OpenAI assertion |
|---|---:|---:|---:|---:|---:|---|
| Baseline `409b3ed2` | 1 | 200 | 274 | Yes | Yes | Expected failure |
| Baseline `409b3ed2` | 2 | 200 | 274 | Yes | Yes | Expected failure |
| Baseline `409b3ed2` | 3 | 200 | 274 | Yes | Yes | Expected failure |
| Fixed `2869a8e7` | 1 | 200 | 479 | Yes | No | Pass |
| Fixed `2869a8e7` | 2 | 200 | 479 | Yes | No | Pass |
| Fixed `2869a8e7` | 3 | 200 | 479 | Yes | No | Pass |

All three baseline bodies are byte-identical to the original Gemini response at
SHA256 `b041b4eaadaac060cdf578ba79b0b46408b0ae4a7efd2630876e627a7b999abd`.
Fixed response hashes differ because generated call IDs and timestamps are
expected to differ; every fixed body passes the same structural assertions.

## Build and test matrix

| Check | Baseline | Fixed |
|---|---|---|
| Provider suite (`-count=1`) | Pass | Pass |
| Targeted Gemini race tests (`-count=20`) | N/A | Pass |
| Provider vet | Exit 1, documented warnings | Same byte-identical output |
| WASI c-shared build (`-trimpath`) | Pass | Pass |
| Full-module Wasm-host suite (`-count=1`) | N/A | Pass |
| Provider coverage | N/A | Pass; changed response helpers 100% |

## Guard checks

- Fixed parent equals baseline/main SHA
  `409b3ed2644a977776391eae78ed6cb11e99d3d3`.
- The pre-rebase and current production `gemini.go` patch hashes are identical:
  `cc9102b18ad383581789afea8f04b663b58b770599cc56efdfd75e7c31902eff`.
- `range-diff` attributes the only post-rebase delta to 55 additional test lines.
- `git diff --check origin/main...HEAD` passes.
- Baseline and fixed vet logs have identical SHA256
  `46c1d6a65ce14bfd81c48dd0e970df53c6f4f1df5e6ce3bc3c82fb553e8939a6`.
- Runtime verifier observes exactly three provider 200 responses, three Envoy
  completed 2xx requests, and zero active requests per variant.
- Baseline has exactly three recovered nil-pointer panics; fixed has none.
- Both conversion helpers changed by the PR report 100% statement coverage.
- Teardown leaves no project containers; loopback ports 11088 and 19988 refuse
  connections.
- The public tree is scanned for local paths, credentials, tokens, and private
  keys before publication.

## Limitations

- Runtime coverage targets the direct Gemini non-streaming mixed-parts path.
  Streaming and Vertex conversions are intentionally unchanged.
- Generated OpenAI call IDs and response timestamps are nondeterministic;
  validation therefore asserts structure and semantics rather than fixed bytes.
- The provider package contains existing vet warnings for JSON tags on
  unexported fields. Identical baseline/fixed logs demonstrate this PR adds no
  vet diagnostic, but the unrelated warnings remain.
- The synthetic API token is published only as `<redacted-test-token>`.
