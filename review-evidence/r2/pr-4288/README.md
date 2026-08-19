# PR #4288 R2 public evidence

This is the sanitized public evidence for the post-rebase Gemini mixed
text/function-call/text response fix.

- Baseline: `4b23e08a386779c8958673ebb052fc6306fe807c`
- Fixed: `4649f92bb8607dd9d02bb560634c201b998aadb6`
- Runtime: pinned Higress gateway running a real Envoy/Proxy-Wasm filter against
  a deterministic internal Gemini mock

## Result

- Baseline: 3/3 HTTP 200 responses, 3/3 recovered nil-pointer panics, and 3/3
  bodies left in the original Gemini shape (red).
- Fixed: 3/3 HTTP 200 responses, 3/3 OpenAI structural assertions passed, and
  zero panic/nil-pointer matches (green).
- Unit, targeted race (`-count=20`), Wasm builds, and the full ai-proxy module
  test passed. Baseline/fixed vet output is byte-identical and contains only the
  documented pre-existing warnings.

The complete method, revisions, environment, result hashes, failed harness
attempt disclosure, and cleanup audit are in
[`validation-report.md`](validation-report.md).

## Evidence map

- Compose/Envoy/mock configuration, request/response fixture, assertion code,
  build/runtime scripts, and offline verifier: [`harness/`](harness/)
- Response bodies, headers, HTTP codes, structural assertion failures, counters,
  and cleanup records: [`results/`](results/)
- Full sanitized baseline/fixed Envoy and mock logs, final runtime transcript,
  two disclosed failed harness attempts, test/build/vet logs, image identities,
  and revisions: [`logs/`](logs/)

The Envoy debug logs echoed the deliberately synthetic fixture token many
times. It is represented as `<redacted-test-token>` in this publication; no
runtime response, count, panic line, or assertion was changed.

Run the offline checks for the curated layout with:

```bash
bash harness/verify-evidence.sh
```

For a new runtime execution, copy `harness/` to a scratch directory, place the
two compiled Wasm files there as `ai-proxy-baseline.wasm` and
`ai-proxy-fixed.wasm`, and run `run-runtime.sh`. `run-tests.sh` accepts
`BASELINE_WORKTREE`, `FIXED_WORKTREE`, and `EVIDENCE_DIR` instead of embedding
the original machine's paths.

## Artifact boundary

The Wasm binaries were omitted; their recorded SHA-256 values are:

- baseline: `699234632268bc4c5cce2c6c981759097d88c87dc40605a2e001f8bddcae83ab`
- fixed: `e24b2003ae808a1551acdfad2d2b91418c434fb68862c79d4a83af60e550c0d7`

[`SHA256SUMS.full`](SHA256SUMS.full) is the original 69-entry full-bundle
manifest; its own SHA-256 is
`1da9ea140a09bb472a8308d496332e01c16e01a35fe2515149a3605fbe6e5ab4`.
[`SHA256SUMS`](SHA256SUMS) validates the curated, sanitized public tree.
