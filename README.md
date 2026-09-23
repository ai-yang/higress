# Response-cache header-key lookup: verification evidence

This bundle was prepared locally for human review under approved Proposal
[#4568](https://github.com/higress-group/higress/issues/4568), Design
[#4569](https://github.com/higress-group/higress/issues/4569), `SPEC-4568001`,
`TASK-4569001`, and `TASK-4569002`. It performs no GitHub mutation.
The explicit pre-implementation authorization is recorded in
[the maintainer decision](https://github.com/higress-group/higress/issues/4569#issuecomment-5789855814)
and the included public governance snapshots.

## Source and change

```text
baseline a42482341eb199b2c1553a560c81137ebad14441
fixed    44b0997f4d154686f35244e51aa5b0aa8f6fcd74
```

The baseline was refreshed from canonical main immediately before implementation
and the defect/duplicate audit was repeated. The fixed source changes only the
header-key action selection after Redis dispatch, the corresponding existing
test expectation, and a new test-only ABI helper. See [change.patch](change.patch).
Configuration, provider, callbacks, body-key behavior, formats, and VERSION are
unchanged. There is no production testing seam or dependency change.

## Results and independent assertions

Only use this document as a completed verification report when
[results/audit.json](results/audit.json) has `scope: full-verification` and
`all_passed: true`. The sealing script refuses to produce a bundle otherwise.

- Full native/compiled-Wasm functional suite: pass, no skips.
- New ABI regression on baseline Wasm: expected failure on action 4 vs 0.
- Full race suite: 20 repetitions of each of the eight top-level tests; no
  reported data race or skips. The package completed in 7607.112 seconds.
  Exact repetition counts are verified by the audit.
- `go vet ./...`, Wasm builds and exact-range `git diff --check`: pass.
- Real pinned Envoy data path: final formal matrix below, 511 requests. A
  complete earlier pass is also retained with identical behavioral outcomes.
- Zero client transport errors or Wasm panics in formal runtime traffic.

| Variant / scenario | Rounds × requests | Upstream arrivals |
| --- | ---: | ---: |
| Baseline hit | 3 × 50 | 50 per round, before Redis release |
| Fixed hit | 3 × 50 | 0 per round, before release and after completion |
| Fixed miss | 3 × 50 | 1 per request |
| Fixed RESP error | 3 × 10 | 1 per request |
| Fixed empty cached value | 3 × 10 | 1 per request |
| Fixed withheld Redis / 100 ms host timeout | 1 × 1 | 1 |

Both hit variants return the exact cached HTTP 200 response and
`x-cache-status: hit`; the baseline has already caused unwanted upstream work.
The upstream hit response is held until client completion, preventing it from
winning the response race. The same driver, normal configuration, CPU quota,
bytes, keys, and barrier timing logic are used for both variants.

Each request has a JSON record, response headers/body, SHA-256, curl exit/status,
synthetic request command, and ordered fixture events. Per-round results include
GET/SET counts. [The audit](harness/audit.py) checks response hashes, every
access-log record, aggregate Envoy upstream/request-completion metrics, and
cleanup. Exact callback counts are measured by the test-only ABI host; upstream
arrivals in real Envoy are corroborating but distinct observables.

The default `go test -race ./... -count=20` first exceeded Go's 10-minute outer
deadline in Wazero compilation. [That log](results/race-default-timeout.log)
is retained, not claimed as a pass. The complete rerun extends the outer budget
to 3 hours, retains all 20 repetitions, and matches `GOMAXPROCS=3` to the builder
CPU quota. Runtime request deadlines remain 10 seconds.

## Exact artifacts

```text
baseline.wasm SHA-256 effe5f6904396aa221a344dbaf82028abb8dcdcd98734a4d12cf6f62ee8d41bf
fixed.wasm SHA-256    6464d796b6cfe61cd476523a2f8b1fe802b47a253aa61c27663606c742c496a8
cached body SHA-256   da87d065c0f96d585f02840dc10c88f7e8edac17ae77dbdae4b9e051a619338f
upstream body SHA-256 405de3e3016afb9b6f10e3c4327b8843f4379292888d2513ac167d9fe7d9a2be
```

Builder: Go 1.24.5 pinned by digest. Gateway: Higress v2.2.4 pinned by digest;
it reports Envoy `4735dd6b874700fc2bc9a218ce80ba0be759e53f/1.36.4/Clean/RELEASE/BoringSSL`.
See [images](results/images.txt), [build identities](results/build.json),
[Docker version](results/docker-version.json), [Compose version](results/compose-version.txt),
[platform](results/platform.txt), [normal config](results/envoy-normal.yaml),
[timeout config](results/envoy-timeout.yaml), and [Compose](harness/compose.yaml).

## Rerun, limitations and cleanup

Follow [RERUN.md](RERUN.md) for deterministic build/test/runtime commands and
scoped cleanup. Runtime fixtures have only synthetic data and use a dedicated
Compose bridge with loopback-only published ports. No Kubernetes cluster is
required for this approved standalone real proxy-Wasm verification.

The pinned host invokes its Redis error callback at the lower timeout and
allows upstream completion. This is not a cross-version timeout guarantee.
There is no independent plugin watchdog; if a host never invokes the callback,
disable header-key caching or roll back the action change. The SDK emulator
cannot inject synchronous dispatch failure or count exact resumes, so the
test-only ABI host supplements it without changing production code or the SDK.

Logs retain expected pre-start Redis initialization retries, deliberate RESP
errors and the timeout. The timeout case contains one SDK `critical` log with
generic connection-error wording: the pinned wrapper (`792cb1547bac`,
`redis_wrapper.go:145-147`) uses that wording for every nonzero callback status.
The fixture had already received GET and withheld its reply; upstream/client
completion precede Redis reply release. This is the deliberate timeout case,
not an unobserved or misconfigured Redis connection. Normal runs contain no
critical logs; all runs contain no fixture traceback or Wasm panic.
The final runtime pass explicitly stops Envoy before
capturing logs to flush all access entries; the earlier complete behavioral
pass is preserved as `results/runtime-first-pass/`. Initial network/loopback
preflight problems were fixed before the formal runs and are not counted as
plugin failures or successful measurements.

[Cleanup proof](results/cleanup.json) confirms no project containers, networks,
volumes or test-port listeners remain. Builder containers run with `--rm`.
Only reviewed harness, outputs and public governance snapshots are packaged;
module/build caches and local PR/TASK drafts are excluded. Validate every
packaged file with:

```bash
sha256sum -c SHA256SUMS
python3 harness/audit.py
```

AI participation was material: the coding agent implemented the bounded patch,
prepared tests/harness, interpreted results, and drafted the review materials.
The human owner controls publication, PR submission, and review. This evidence
does not assert that remote TASKs have already been completed.
