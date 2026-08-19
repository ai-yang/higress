# PR #4286 R2 public evidence

This is the sanitized, curated publication of the second post-rebase
validation for `fix(mcp): randomly select from all registry instances`.

- Baseline: `4b23e08a386779c8958673ebb052fc6306fe807c`
- Fixed: `83c5c03560ac212c8bb2e236db559a29e8bf300d`
- Patch continuity: `git range-diff` reports `90902418 = 83c5c035`
- Runtime: real kind/Higress/Envoy data plane with Nacos 2.3.2 and two healthy,
  enabled, equal-weight backends

## Result

| Revision | Round 1 | Round 2 | Round 3 | Errors |
|---|---:|---:|---:|---:|
| baseline | `100 / 0` | `100 / 0` | `100 / 0` | 0 |
| fixed | `41 / 59` | `55 / 45` | `48 / 52` | 0 |

Each pair is `backend-0 / backend-1` over 100 requests. The authoritative
aggregate is [`results/summary.json`](results/summary.json), and all six raw
100-line response sets are in [`results/`](results/). Both variants' Nacos
snapshots contain the two expected healthy instances, and both Envoy stats
snapshots report zero MCP Go-filter panic counters.

## Evidence map

- Reproduction inputs and scripts: [`harness/`](harness/)
- Package, race (`-count=20`), and vet transcript:
  [`logs/fixed-package-race20-vet.typescript`](logs/fixed-package-race20-vet.typescript)
- Baseline/fixed request summaries:
  [`logs/baseline-rounds.typescript`](logs/baseline-rounds.typescript) and
  [`logs/fixed-rounds.typescript`](logs/fixed-rounds.typescript)
- Registry state:
  [`logs/baseline-nacos-instances.json`](logs/baseline-nacos-instances.json) and
  [`logs/fixed-nacos-instances.json`](logs/fixed-nacos-instances.json)
- Envoy counters:
  [`logs/baseline-envoy-stats.txt`](logs/baseline-envoy-stats.txt) and
  [`logs/fixed-envoy-stats.txt`](logs/fixed-envoy-stats.txt)
- Source/patch identity:
  [`logs/range-diff.typescript`](logs/range-diff.typescript),
  [`logs/source-runtime-diff.patch`](logs/source-runtime-diff.patch), and
  [`logs/config-parity.sha256`](logs/config-parity.sha256)
- Build, cluster setup, upgrade, capture, environment, image identity, and
  cleanup transcripts: [`logs/`](logs/)

The public scripts replace machine-specific paths with `EVIDENCE`, `REPO`, and
`BASELINE` parameters. For example, from this directory:

```bash
export EVIDENCE="$PWD"
export REPO=/path/to/fixed-higress-checkout
export BASELINE=/path/to/baseline-higress-checkout
bash harness/go-verify.sh
bash harness/build-filters.sh
bash harness/build-gateway-images.sh
```

The remaining scripts encode cluster creation, Nacos seeding, three request
rounds per variant, capture, upgrade, and cleanup. They expect the pinned
`kind`, `kubectl`, and `helm` binaries under `/tmp/pr4286-bin` and the two
localhost port-forwards used by the recorded run (`18080` for the gateway and
`18848` for Nacos).

## Artifact boundary

The compiled shared objects and full kind export were omitted from this public
tree. The shared-object identities are:

- baseline: `962222bdb25c198072d60e97c9cac01486bfa8453500af4901f4acc2549a8ec1`
- fixed: `cb517a76abec6e918f9a0b8d124da956311c2562718aa31cdd295de38fe1efe0`

[`SHA256SUMS.full`](SHA256SUMS.full) is the original 139-entry full-bundle
manifest; its own SHA-256 is
`0945fb98d8070381325bee6a615ea18492aa31d87ae286e8858f11a38d793160`.
[`SHA256SUMS`](SHA256SUMS) validates only the curated, sanitized files published
in this directory.
