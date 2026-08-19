# PR #4287 R2 public evidence

This is the sanitized public evidence for the second post-rebase validation of
the API Workflow regular-expression reuse optimization.

- Baseline: `4b23e08a386779c8958673ebb052fc6306fe807c`
- Optimized: `d62bdbdf6f2b46ab11f99b447d38ae7e5cfdef0f`
- Accepted sample count: two independent series of 20 samples per variant,
  `n=40` combined
- Execution order: baseline then optimized in series 1; optimized then baseline
  in series 2

## Headline result

| Benchmark | Baseline median | Optimized median | Reduction | Speedup |
|---|---:|---:|---:|---:|
| `ExecConditionalStr` | `25,753 ns/op` | `8,655.5 ns/op` | `66.39%` | `2.975x` |
| `ParseTmplStr` | `13,502.5 ns/op` | `10,469.5 ns/op` | `22.46%` | `1.290x` |

The full method, allocation results, CV values, confidence intervals, caveats,
and correctness/build gates are in
[`validation-report.md`](validation-report.md).

## Evidence map

- Exact accepted benchmark samples and machine summary:
  [`results/accepted/`](results/accepted/)
- Whole rejected attempts, excluded before formal analysis and never trimmed by
  individual observation: [`results/tainted/`](results/tainted/)
- Benchmark source and statistics analyzer: [`harness/`](harness/)
- Unit, targeted race (`-count=20`), vet, Wasm build, full-module, CPU-idle,
  patch, and range-diff records: [`logs/`](logs/)

Recompute the statistics with:

```bash
python3 harness/analyze_bench.py
python3 harness/verify_stats.py
```

`verify_stats.py` compares the recomputed object to the recorded `stats.json`
with a strict key/list comparison and a `1e-9` absolute tolerance for floating
point values. This permits only runtime-level last-bit representation variance;
all integer samples, medians, allocation values, and structure remain exact.

The compiled Wasm was not included. Its recorded SHA-256 is
`6c813c46292ba77f108e54b3fc841f94fa6621e85522d5151122ef28d009fa8a`.
[`SHA256SUMS.full`](SHA256SUMS.full) is the original 30-entry bundle manifest;
its own SHA-256 is
`76f6d342d2cec9564b8d63e11a108f224695ab03002b144d5f5169390add8759`.
[`SHA256SUMS`](SHA256SUMS) validates this published tree.
