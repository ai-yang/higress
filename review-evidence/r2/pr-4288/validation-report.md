# PR #4288 post-rebase R2 validation

Run date: 2026-08-11 (Asia/Shanghai)

## Overall assessment

**Ready to share.** The rebased fix passes provider tests, 20 race-enabled targeted repetitions, Wasm builds, and the full module suite. A real Envoy/Proxy-Wasm red/green comparison reproduced the baseline failure in 3/3 requests and verified the fixed response in 3/3 requests. No product-level blocker or unexplained result remains.

## Revisions and patch continuity

- Baseline: `4b23e08a386779c8958673ebb052fc6306fe807c` (`origin/main` at rebase time)
- Fixed: `4649f92bb8607dd9d02bb560634c201b998aadb6`
- Previous R1 baseline/fixed: `16fe3f59052d1285d7dbf08bb707c35e9c2342d2` / `e6e053e84fc77b4c8f4da624916af9629a8c6424`
- The old and new binary diff for the two Gemini files has the same SHA-256: `4c1743f8c78c2dfc674180eafa1988bb64acd085b37d926a70f832a99c81c422`.
- The ai-proxy module tree at the old and new baselines is identical: Git tree `79082fc0ebbe9a5c75f0436836d722287ff3f6b7`.
- `git diff --check 4b23e08a..4649f92b` passed.

These checks independently confirm that the rebase changed only the base history and did not alter the reviewed fix or this module's baseline source.

## Environment

- Host: Linux `5.15.0-186-generic`, `x86_64`
- Go: `go1.24.4 linux/amd64` from `golang:1.24.4@sha256:20a022e5112a144aa7b7aeb3f22ebf2cdaefcc4aac0d64e8deeee8cdc18b9c0f`
- Docker server: `26.0.0`; Docker Compose: `v2.25.0`
- Gateway: `higress-registry.cn-hangzhou.cr.aliyuncs.com/higress/gateway@sha256:93e4da97560d00871299e67163df4f1801732aeea4934a9cea841f9e7b4a26e8`
- Gateway image ID: `sha256:c4e469c1e892f216a508674902cbb527d39aecf03264008123c5f07c62836f4f`
- Mock: `nginx@sha256:65645c7bb6a0661892a8b03b89d0743208a18dd2f3f17a54ef4b76fb8e2f2a10`
- Mock image ID: `sha256:6769dc3a703c719c1d2756bda113659be28ae16cf0da58dd5fd823d6b9a050ea`

The listener/admin ports were bound only to `127.0.0.1`; the mock provider was reachable only on the internal Compose network.

## Test and build results

| Check | Result | Evidence |
|---|---|---|
| `go test ./provider -count=1` | PASS | `logs/provider-unit.txt` |
| Targeted `go test -race`, matching all three added Gemini tests, `-count=20` | PASS | `logs/provider-race-x20.txt` |
| Baseline `go vet ./provider` | Exit 1, existing warnings only | `logs/vet-baseline.txt`, `logs/vet-status.txt` |
| Fixed `go vet ./provider` | Exit 1, byte-identical to baseline | `logs/vet-fixed.txt`, `logs/vet-status.txt` |
| Baseline Wasm build | PASS | `logs/wasm-build-baseline.txt`, artifact below |
| Fixed Wasm build | PASS | `logs/wasm-build-fixed.txt`, artifact below |
| `WASM_PATH=... go test ./... -count=1` | PASS | `logs/full-module-tests.txt` |

Both vet outputs have 86 lines and are byte-identical. Their diagnostics are the pre-existing unexported-field JSON-tag warnings in `context.go` (3), `failover.go` (8), `provider.go` (69), and `retry.go` (4), plus two package headers. Neither `gemini.go` nor `gemini_test.go` appears in either output.

Wasm SHA-256 values:

- Baseline: `699234632268bc4c5cce2c6c981759097d88c87dc40605a2e001f8bddcae83ab`
- Fixed: `e24b2003ae808a1551acdfad2d2b91418c434fb68862c79d4a83af60e550c0d7`

The hashes match R1 because the ai-proxy module baseline and patch are byte-for-byte unchanged.

## Runtime methodology

The baseline and fixed variants used the same pinned images, Envoy/plugin configuration, request, and deterministic Gemini mock. The mock response contains one candidate with three ordered parts: text, `lookup` function call, then text. Each variant received three sequential requests.

Reproduction commands are preserved in `harness/run-tests.sh` and
`harness/run-runtime.sh`. Harness input hashes are unchanged from R1:

- `compose.yaml`: `acf630d780d90de64a01625b10c47a9d20f9d1ebd84a2b5145640e8b7b1fe06f`
- `envoy.yaml`: `342bd88abc61987cac1603aab7766168f636ddf39533630c377ef22f26e60f04`
- `nginx.conf`: `b7b1cabd29b54455ebb9c585788843511e94aadc9ae2b12166661eb46f51fe95`
- `gemini-response.json`: `cf0bf00d4164cf9455f5313a91d17711120ee62e180e49e6d440adc32f800279`
- `request.json`: `e139b74597249a65c8c1ad41213c1ea39685cf01de385a1297f150ba06019a88`
- `assert_fixed_response.py`: `46f1c27d9f46ee36a19f93834037f37fddd06bb7757657c504b5b5608c3427eb`

## Baseline result (red)

- 3/3 requests returned HTTP 200 and the mock logged 3/3 provider responses.
- Envoy logged three response bodies and three recovered panics: `runtime error: invalid memory address or nil pointer dereference`.
- All three bodies were semantically equal to the original Gemini payload and lacked OpenAI `choices`; each OpenAI structural assertion failed with `AssertionError: None`.
- All three bodies were byte-identical at SHA-256 `b041b4eaadaac060cdf578ba79b0b46408b0ae4a7efd2630876e627a7b999abd`.

The evidence is in `results/baseline-http-codes.txt`,
`results/baseline-counts.txt`, `logs/baseline-envoy.log`,
`logs/baseline-mock.log`, the three body/header pairs under `results/`, and
`results/baseline-openai-assert-*.txt`.

## Fixed result (green)

- 3/3 requests returned HTTP 200 and the mock logged 3/3 provider responses.
- All three independent response bodies passed the structural assertion.
- Every response contained exactly one choice, concatenated content `Let me check. One moment.`, one indexed `lookup` tool call with JSON arguments `{"id":42}`, `finish_reason: "tool_calls"`, and exact token usage `10/5/15`.
- The fixed Envoy log contained zero panic or nil-pointer matches.
- Response SHA-256 values were:
  - `d181e18d5ee28b23a6d050e2be8a79ad428fff085235c7feb0941cf1153eae14`
  - `9c4ad8104c3d4e7da4e5756d40f955340845347b1ff69310163cd7d64948b4b0`
  - `1e626a141cff852a0f63cf409c78977904d6e937e771d2846e8c2d6f84dcb80c`

The byte hashes differ as expected because generated completion/tool-call UUIDs
and timestamps are unique. The evidence is in
`results/fixed-http-codes.txt`, `results/fixed-counts.txt`,
`logs/fixed-envoy.log`, `logs/fixed-mock.log`, and the three body/header pairs
under `results/`.

## Harness hardening attempts

- Attempt 1 reached no test request: Envoy's readiness socket reset once during startup, and the original readiness command did not retry that error class. Cleanup ran successfully. The final command adds `--retry-all-errors`.
- Attempt 2 completed the baseline 3/3 reproduction but the wrapper's extra assertion expected all access-log lines to be synchronously visible. Because access logs from multiple workers were not all flushed in that immediate snapshot, the wrapper stopped before the fixed run and cleaned up. The final run uses stable signals already available per request: client HTTP codes, mock 200 count, response-body log count, and panic count.

These were validation-harness issues, not product failures. Their logs are
retained as `logs/runtime-run-attempt1-failed.txt` and
`logs/runtime-run-attempt2-failed.txt` for auditability.

## Cleanup

- `docker compose ps --all` and the project-labelled `docker ps -a` output are empty.
- A final independent audit found zero project-labelled containers, networks, and volumes.
- Both `127.0.0.1:11088` and `127.0.0.1:19988` returned curl exit 7 (`connection refused`) after teardown.
- The temporary detached baseline worktree was removed after evidence collection.

See `results/cleanup-audit.txt`, `results/cleanup-compose-ps.json`,
`results/cleanup-docker-ps.txt`, `results/cleanup-port-status.txt`, and the two
port error files under `results/`.

## Caveats

- The runtime comparison covers the direct Gemini provider's non-streaming chat-completion response path and the reported mixed text/function-call/text failure.
- Fixed response byte hashes are intentionally nondeterministic due to generated IDs and timestamps; assertions compare the stable response structure and values.
- Vet remains non-zero only because of identical pre-existing warnings; it supplies comparative regression evidence rather than a clean repository-wide gate.
