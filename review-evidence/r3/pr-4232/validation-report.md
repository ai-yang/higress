# PR #4232 validation report

## Runtime red/green matrix

| Variant | Round | HTTP | Bytes | Chunk sizes | Duration (s) | Redis quota | Expected |
|---|---:|---:|---:|---|---:|---|---|
| Baseline `409b3ed2` | 1 | 200 | 120 | 60 + 60 | 0.360 | 100 → 100 | Bug reproduced |
| Baseline `409b3ed2` | 2 | 200 | 120 | 60 + 60 | 0.359 | 100 → 100 | Bug reproduced |
| Baseline `409b3ed2` | 3 | 200 | 120 | 60 + 60 | 0.358 | 100 → 100 | Bug reproduced |
| Fixed `d03df020` | 1 | 200 | 120 | 60 + 60 | 0.361 | 100 → 82 | Pass |
| Fixed `d03df020` | 2 | 200 | 120 | 60 + 60 | 0.358 | 100 → 82 | Pass |
| Fixed `d03df020` | 3 | 200 | 120 | 60 + 60 | 0.358 | 100 → 82 | Pass |

The exact recorded floating-point timings are in `results/summary.json`. The
rounded values above are informational; the verifier asserts each transfer took
at least 0.30 seconds, proving the 350 ms upstream boundary was observed.

## Build and test matrix

| Check | Baseline | Fixed |
|---|---|---|
| Go version | 1.24.4 | 1.24.4 |
| `go test -mod=readonly ./...` | Pass | Pass |
| `go test -mod=readonly -race ./... -count=20` | Pass | Pass |
| `go vet -mod=readonly ./...` | Pass | Pass |
| WASI c-shared build (`-trimpath`) | Pass | Pass |
| Wasm-host test (`-count=1`) | Pass | Pass |
| Fixed package statement coverage | N/A | 68.8% total; response handlers 100%; common usage path 95.2% |

The full package includes unrelated admin operations. Coverage details are in
`logs/fixed/coverage.txt`; the PR-specific non-streaming, SSE, duplicate-callback,
missing-usage/consumer, and Redis dispatch-failure paths have direct tests.

## Guard checks

- Fixed parent is exactly baseline/main SHA
  `409b3ed2644a977776391eae78ed6cb11e99d3d3`.
- `git range-diff` reports the pre-rebase commit `c7f41a0d` and rebased commit
  `d03df020` as equal.
- `git diff --check origin/main...HEAD` passes.
- Both Wasm artifacts use `GOOS=wasip1`, `GOARCH=wasm`, `CGO_ENABLED=0`,
  `-trimpath`, `-buildmode=c-shared`, and disabled VCS path metadata.
- Every response body is byte-identical and has the published SHA256 value.
- Envoy reports three completed 2xx requests and zero active requests per
  variant at capture time.
- Baseline has zero 18-token update log entries; fixed has exactly three.
- The runner removes Compose containers, volumes and networks after each
  variant. Final container enumeration was empty and both loopback ports
  refused connections.
- The public tree was scanned for local workspace paths, credentials, tokens,
  and private keys before publication.

## Limitations

- The fixture exercises a standard non-SSE JSON completion response with an
  explicit HTTP/1.1 chunk boundary. It does not claim coverage of every provider
  response schema.
- Redis asynchronous server-side errors remain governed by the existing Redis
  client callback behavior; this PR specifically prevents duplicate dispatch
  and restores retry on synchronous dispatch failure.
- Startup can briefly reset the loopback readiness connection while Envoy loads
  the Wasm VM. The runner uses bounded `--retry-all-errors`; requests are sent
  only after `/ready` returns `LIVE`.
