# Deterministic local rerun

This package does not perform a push, PR creation, or GitHub update. Worktree
paths below are examples; choose unused paths. Keep all evidence paths local
until the human owner approves publication.

## Inputs

- Baseline: `a42482341eb199b2c1553a560c81137ebad14441`
- Fixed: `44b0997f4d154686f35244e51aa5b0aa8f6fcd74`
- Plugin module: `plugins/wasm-go/extensions/response-cache`
- Builder: `golang:1.24.5`, pinned in `harness/verify.py`.
- Gateway: Higress `v2.2.4`, pinned in `harness/compose.yaml`.
- Fixture: Python `3.11-slim-bookworm`, pinned in `harness/compose.yaml`.
- Linux amd64, Docker 26.0.0, Compose v2.25.0; Python 3 and curl on the driver.
- Builder: 3 CPUs/3 GiB with `GOMAXPROCS=3`; Envoy: 1 CPU/512 MiB; fixture: 1 CPU/256 MiB.
- One dedicated Compose bridge network; host control/data/admin ports bind
  only to `127.0.0.1:19469/19468/19470`. The fixture uses synthetic data only.

## Build and checks

Create clean baseline/fixed checkouts from these exact commits. From this
package's directory, set these variables to your chosen absolute paths:

```bash
BASELINE_SOURCE=/path/to/baseline-checkout
FIXED_SOURCE=/path/to/fixed-checkout
EVIDENCE_DIR="$PWD"
CACHE_DIR="$PWD/.cache"
BUILDER=golang@sha256:ef5b4be1f94b36c90385abd9b6b4f201723ae28e71acacb76d00687333c17282
mkdir -p "$CACHE_DIR" results
docker run --rm --user "$(id -u):$(id -g)" \
  -e GOTOOLCHAIN=local -e GOPATH=/cache/gopath \
  -e GOMODCACHE=/cache/mod -e GOCACHE=/cache/build \
  -v "$CACHE_DIR:/cache" \
  -v "$FIXED_SOURCE/plugins/wasm-go/extensions/response-cache:/src:ro" \
  -w /src "$BUILDER" go mod download
python3 harness/verify.py --baseline-source "$BASELINE_SOURCE" \
  --fixed-source "$FIXED_SOURCE" --output results --cache "$CACHE_DIR" --stage build
git -C "$FIXED_SOURCE" diff --check \
  a42482341eb199b2c1553a560c81137ebad14441...44b0997f4d154686f35244e51aa5b0aa8f6fcd74
sha256sum results/baseline.wasm results/fixed.wasm
```

The build stage mounts source read-only, disables container networking after
dependency download, builds both variants with the same toolchain and commands,
then runs from `/src`:

```bash
go version
GOOS=wasip1 GOARCH=wasm go build -buildmode=c-shared -o /evidence/baseline.wasm ./
# Same command from the fixed checkout, with output /evidence/fixed.wasm.
WASM_FILE_PATH=/evidence/baseline.wasm go test -run TestHeaderKeyLookupABI -count=1 -v ./...
# The preceding regression-red command MUST fail on the action mismatch (4 vs 0).
WASM_FILE_PATH=/evidence/fixed.wasm go test ./... -count=1 -v
WASM_FILE_PATH=/evidence/fixed.wasm go test -race ./... -count=20 -timeout=3h -v
go vet ./...
```

`WASM_FILE_PATH` ensures existing SDK tests and the new ABI tests load the exact
hashed binary. The supplemental test-only ABI host observes exact resume/local
response counts and injects synchronous dispatch failure. The SDK emulator at
`8345453fddd0` always accepts Redis dispatch and stores only the final stream
action; no SDK or production seam is changed. The complete existing suite also
covers unchanged body-key behavior. Wazero is already an existing dependency.

The initial race invocation hit Go's default 10-minute test timeout inside
Wazero compilation, not a failing assertion or a reported data race. Its log is
retained as `results/race-default-timeout.log`. The rerun extends only the outer
test-runner time budget, keeps all 20 repetitions, and sets `GOMAXPROCS=3` to
match the Docker CPU quota. The request-level runtime deadlines are unchanged.

## Runtime checks

```bash
python3 harness/verify.py --baseline-source "$BASELINE_SOURCE" \
  --fixed-source "$FIXED_SOURCE" --output results --cache "$CACHE_DIR" --stage runtime
```

Optional preflight: add `--smoke` (these results go to `results/smoke`, not the
formal `results/runtime` directory). The same driver and normal Envoy config are
used for baseline and fixed. Only the Wasm mount changes. Timeout verification
uses the same fixed Wasm and changes only `cache.timeout` from 10000 to 100 ms.

Each request records GET arrival, a one-second upstream-arrival window for hits,
Redis release, HTTP completion, then a 100 ms quiescence interval. Upstream hit
responses remain held until client completion. The event sequence—not a claimed
Redis timing percentile—is the ordering oracle. Each round resets fixture
counters; requests are sequential. Hit and miss rounds each use 50 requests;
RESP-error and empty-value rounds each use 10. A dedicated timeout request
withholds the Redis response until the client completes or reaches 10 seconds.

All request commands and synthetic keys/values are included in the per-request
JSON. Exact callback counts are measured by ABI tests, while real runtime
verification measures the corresponding upstream arrivals. They are different
observables and are not conflated.

## Cleanup

The runtime runner has a `finally` cleanup for only its Compose project, then
asserts no project containers/networks/volumes and no listeners on its three
ports. If the runner is forcibly killed, rerun this scoped cleanup:

```bash
ENVOY_CONFIG="$PWD/results/envoy-normal.yaml" \
WASM_PATH="$PWD/results/fixed.wasm" \
docker compose --project-name response-cache-4569-20260923 \
  --file harness/compose.yaml down --remove-orphans --timeout 5
docker ps -aq --filter label=com.docker.compose.project=response-cache-4569-20260923
docker network ls -q --filter label=com.docker.compose.project=response-cache-4569-20260923
docker volume ls -q --filter label=com.docker.compose.project=response-cache-4569-20260923
```

Do not prune unrelated Docker resources or the author's other worktrees.

To record an additional final resource check after all tests have exited, run
`python3 harness/check_cleanup.py`. Optionally pass `--race-container CONTAINER_ID`
to verify that a known race builder container was removed as well. Then run
`python3 harness/audit.py` for the complete machine audit. Only after both pass,
`python3 harness/seal.py` creates a new local bundle and checksum manifest;
it deliberately refuses to overwrite an existing bundle/archive.
