# PR #4287 round-2 independent validation

## Assessment

**Ready to share.** On 2026-08-11 (Asia/Shanghai), the rebased patch preserved the
previous patch exactly, passed all requested correctness/build gates, and reproduced
large time and allocation reductions in two independent benchmark series.

The question tested was whether reusing the two fixed compiled regular expressions
in API Workflow preserves behavior and reduces work on the affected hot paths.

## Revisions and patch identity

- Baseline/current `main`: `4b23e08a386779c8958673ebb052fc6306fe807c`
- Optimized PR head: `d62bdbdf6f2b46ab11f99b447d38ae7e5cfdef0f`
- Previous comparison: `16fe3f59052d1285d7dbf08bb707c35e9c2342d2..3cf70749cad5e73aaf518008128961e519ce4466`
- `git range-diff` reports `=` for the old and new PR commits. The upstream-only
  movement between bases is limited to `AGENTS.md` and the `istio/istio` submodule.
- Current baseline-to-head patch SHA-256: `016abc642049628050d44b31b0861c7f4147d451412d718b45d8d5e26949b240`
- Exact benchmark harness in both worktrees: Git blob
  `4f7c21dbde861b50693e64ed42de5aae8b275754`, file SHA-256
  `9f8481829d3c1aab026c1648dea4976c9a03e7c12cda7f15c51e6d6f43eb41a3`.
  The harness was copied into the detached baseline worktree without applying the
  production optimization.

## Method

- Host: Linux/amd64, kernel `5.15.0-186-generic`, Intel Xeon Gold 6133 @ 2.50 GHz.
- Docker `26.0.0`; pinned image
  `golang:1.24.4@sha256:20a022e5112a144aa7b7aeb3f22ebf2cdaefcc4aac0d64e8deeee8cdc18b9c0f`.
- Go `1.24.4`, `--cpuset-cpus=0`, `GOMAXPROCS=1`, identical shared module/build
  caches, `-benchtime=300ms`, `-count=20`, and `-benchmem`.
- Two independent pairs, 20 samples per benchmark and variant in each pair
  (`n=40` combined). Order was baseline -> optimized in series 1 and optimized ->
  baseline in series 2 to reduce execution-order bias.
- CV is sample standard deviation divided by the mean. The reported 95% CI is the
  normal approximation for the mean: `mean +/- 1.96 * sample_sd / sqrt(n)`.
- No observations were removed from an accepted series. An initial concurrent-runtime
  attempt was quarantined before formal analysis. A later baseline attempt with 4.44%
  CV, above the prior round's 2.34% maximum, was also retained under `tainted/` and the
  whole attempt was rerun. Published series all stayed at or below 2.85% CV.
- Before the accepted rerun, CPU0 and its SMT sibling CPU40 were approximately
  98.8% and 99.2% idle; the between-series check showed approximately 98.6% and
  98.7% idle. The raw `mpstat` logs are included.

## Combined benchmark result (`n=40` per variant)

| Benchmark | Baseline median | Optimized median | Time reduction / speedup | B/op | allocs/op |
| --- | ---: | ---: | ---: | ---: | ---: |
| `ExecConditionalStr` | `25,753 ns/op` | `8,655.5 ns/op` | `66.39%` / `2.975x` | `12,017 -> 1,296` (`89.22%` less) | `160 -> 28` (`82.50%` less) |
| `ParseTmplStr` | `13,502.5 ns/op` | `10,469.5 ns/op` | `22.46%` / `1.290x` | `3,304 -> 832` (`74.82%` less) | `33 -> 11` (`66.67%` less) |

Combined normal-approximation 95% CIs did not overlap:

- `ExecConditionalStr`: baseline `[25,695.64, 26,068.61]`, optimized
  `[8,637.24, 8,708.01]` ns/op.
- `ParseTmplStr`: baseline `[13,458.50, 13,577.05]`, optimized
  `[10,444.50, 10,524.00]` ns/op.

## Per-series stability

| Benchmark / series | Baseline median | Optimized median | Reduction / speedup | Baseline CV | Optimized CV | 95% CIs overlap? |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| `ExecConditionalStr` S1 | `25,923.5` | `8,667` | `66.57%` / `2.991x` | `2.85%` | `1.29%` | No |
| `ExecConditionalStr` S2 | `25,632.5` | `8,654.5` | `66.24%` / `2.962x` | `1.24%` | `1.38%` | No |
| `ParseTmplStr` S1 | `13,486` | `10,434.5` | `22.63%` / `1.292x` | `1.65%` | `1.24%` | No |
| `ParseTmplStr` S2 | `13,502.5` | `10,480` | `22.38%` / `1.288x` | `1.17%` | `1.21%` | No |

Units for all medians and confidence intervals are ns/op. Exact means, sample
standard deviations, minima, maxima, and confidence bounds are in
`results/accepted/stats.json`.

## Correctness and build gates

All commands ran against optimized revision `d62bdbdf6f2b46ab11f99b447d38ae7e5cfdef0f`
inside the same pinned Go image:

| Check | Result | Evidence |
| --- | --- | --- |
| `go test ./utils -count=1` | Pass | `logs/unit.log` |
| `go test -race ./utils -run '^(TestExecConditionalStr|TestParseTmplStr)$' -count=20` | Pass | `logs/race-targeted-x20.log` |
| `go vet ./utils` | Pass | `logs/vet.log` (empty because vet emitted no diagnostics) |
| `GOOS=wasip1 GOARCH=wasm go build -buildmode=c-shared ...` | Pass | `logs/wasm-build.log` |
| `WASM_PATH=/artifacts/api-workflow-r2.wasm go test ./... -count=1` | Pass | `logs/full-module.log` |

Built Wasm size: `6,153,450` bytes. SHA-256:
`6c813c46292ba77f108e54b3fc841f94fa6621e85522d5151122ef28d009fa8a`.
This matches the previous pre-rebase validation artifact.

## Interpretation and caveats

- Both independent series reproduce essentially the same improvement, and the
  allocation changes are deterministic in every sample. The performance claim is
  therefore supported and is not based on a single favorable run.
- These are focused Go microbenchmarks of the modified hot paths, not an end-to-end
  gateway throughput or latency test. They establish reduced local CPU work and
  allocations, but do not quantify whole-request impact under production traffic.
- The host is shared. Runtime-validation containers were explicitly allowed to finish,
  CPU0/40 idle checks were saved, execution order was reversed in series 2, and noisy
  attempts are disclosed rather than silently discarded.

## Evidence map

- Formal raw data: `results/accepted/bench-baseline-series{1,2}.txt` and
  `results/accepted/bench-optimized-series{1,2}.txt`
- Validating statistics implementation and output: `harness/analyze_bench.py`,
  `results/accepted/stats.json`
- Independent median spot checks: `results/accepted/spot-check-*-middle.txt`
  (the 20th and 21st
  sorted observations whose averages produce each combined median)
- Patch evidence: `logs/range-diff.txt`, `logs/diff-stat.txt`,
  `logs/diff-check.log`, `logs/patch.sha256`
- CPU-idle evidence: `logs/cpu0-idle-before.log`,
  `logs/cpu0-40-after-rejected-s1.log`, `logs/cpu0-40-between-series.log`
- Correctness/build evidence: `logs/unit.log`, `logs/race-targeted-x20.log`,
  `logs/vet.log`, `logs/wasm-build.log`, `logs/full-module.log`,
  `logs/wasm.sha256`
- Rejected diagnostic runs: `results/tainted/` (never included in headline
  calculations)
