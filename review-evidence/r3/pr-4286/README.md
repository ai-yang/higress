# PR #4286 R3 public evidence

This sanitized bundle records the post-rebase validation for
`fix(mcp-server): select from all registry instances` against current Higress
`main`.

- Baseline: `409b3ed2644a977776391eae78ed6cb11e99d3d3`
- Fixed: `81c547a2c26c370f0f101b8342770d47e97378cb`
- Previous fixed revision: `83c5c03560ac212c8bb2e236db559a29e8bf300d`
- Patch continuity: `git range-diff` reports `83c5c035 = 81c547a2`
- Production-patch SHA-256 before and after rebase:
  `9faf5df150b9ee66f3d6e62fce4da91b83d88b4a2ec2e1122e845a440df6b989`

The upstream interval includes an Envoy Go dependency update, so R3 rebuilds
both native filters with the new dependency and reruns a real
kind/Higress/Envoy/Nacos comparison. Both variants use exactly the same chart,
controller, pilot, gateway base, configuration, two healthy equal-weight
backends, and request sequence. Only the compiled filter overlay changes.

## Result

| Revision | Round 1 | Round 2 | Round 3 | Errors |
|---|---:|---:|---:|---:|
| baseline | `100 / 0` | `100 / 0` | `100 / 0` | 0 |
| fixed | `42 / 58` | `53 / 47` | `49 / 51` | 0 |

Each pair is `backend-0 / backend-1` over 100 requests. The baseline excluded
the final healthy instance in all 300 calls. The fixed revision selected both
instances in every independent round. Both variants report zero MCP
server/session Go-filter panic counters, and both Nacos snapshots contain the
same two `healthy=true`, `enabled=true`, `weight=1.0` instances.

The authoritative aggregate is
[`results/summary.json`](results/summary.json); all six raw 100-response result
sets are retained in [`results/`](results/).

## Validation layers

- Fixed package test passed with Go 1.24.4.
- The targeted regression test passed under `-race -count=20`.
- `go vet -mod=readonly ./mcp-server/registry` passed.
- Both baseline and fixed native filters built as Linux AMD64 C shared objects
  using the same current Envoy Go dependency.
- The real gateway loaded each expected shared-object hash before its request
  rounds.
- Three independent 100-request rounds passed all count, JSON-RPC, backend-set,
  and uniqueness assertions for each variant.
- Cleanup negative checks found no `pr4286-r3` kind cluster, container, volume,
  listener on ports 18080/18848, or temporary baseline worktree.

## Runtime identities

- Go build image:
  `golang@sha256:20a022e5112a144aa7b7aeb3f22ebf2cdaefcc4aac0d64e8deeee8cdc18b9c0f`
- Current Envoy Go module:
  `github.com/higress-group/envoy@v0.0.0-20260811163927-9e54c67a6c89`
- Gateway base:
  `higress-registry.cn-hangzhou.cr.aliyuncs.com/higress/gateway@sha256:6cb8367c98ccce4a5b83b19b37ba1b4156721da31871904cc6632ab129757dde`
- Envoy: `1.36.4`, revision `4735dd6b874700fc2bc9a218ce80ba0be759e53f`
- Controller:
  `higress/higress@sha256:11fb1244d35615210faaa6bda54cd187e6a445e09892da4cc2619896c34b0e11`
- Pilot:
  `higress/pilot@sha256:d27d518cc48d8075808422d19cad6209282a9fd7e517552a3bfc3cbe2dad72e1`
- Nacos:
  `nacos/nacos-server@sha256:cca69ab12348b43d95c9b2c1d8d31d5a8d56e634ed4232a510423a9346090a70`
- Backend:
  `hashicorp/http-echo@sha256:fcb75f691c8b0414d670ae570240cbf95502cc18a9ba57e982ecac589760a186`
- kind node:
  `kindest/node@sha256:cd248d1438192f7814fbca8fede13cfe5b9918746dfa12583976158a834fd5c5`
- Baseline filter SHA-256:
  `c8bc4bfc0fa5ab73e96327c19e6454b57590d6278c08583df8bef7eaac54c823`
- Fixed filter SHA-256:
  `a9dbdd158fdadbc1163ceb8b22326759b4ec136f7de78bdf338f971240cd1c12`
- Baseline/fixed overlay image IDs:
  `sha256:196878fb5f6a5ec90c49afb93c9d317dcfa3956c45f9d13ffaef5a2bdcffe54f`
  and
  `sha256:2ac39ec5b2e531c13fc8187b410a79b3a5541b5f7396b0190d4f08ac1838c946`

The stable R2 control-plane images are deliberately retained to isolate the
new gateway/filter ABI and the one-line production change. Baseline and fixed
share those images, so they cannot explain the observed selection difference.

## Evidence map

- Reproduction inputs and executable scripts: [`harness/`](harness/)
- Revision, DCO, range-diff, diff-check, and production-patch identity:
  [`logs/revision-integrity.typescript`](logs/revision-integrity.typescript)
- Package, race (`-count=20`), and vet transcript:
  [`logs/fixed-package-race20-vet.typescript`](logs/fixed-package-race20-vet.typescript)
- Baseline/fixed request summaries:
  [`logs/baseline-rounds.typescript`](logs/baseline-rounds.typescript) and
  [`logs/fixed-rounds.typescript`](logs/fixed-rounds.typescript)
- Registry snapshots:
  [`logs/baseline-nacos-instances.json`](logs/baseline-nacos-instances.json)
  and [`logs/fixed-nacos-instances.json`](logs/fixed-nacos-instances.json)
- Envoy counters:
  [`logs/baseline-envoy-stats.txt`](logs/baseline-envoy-stats.txt) and
  [`logs/fixed-envoy-stats.txt`](logs/fixed-envoy-stats.txt)
- Build, cluster setup, upgrade, capture, environment, image identity, kind
  export, and cleanup transcripts: [`logs/`](logs/)
- The intervening upstream module change:
  [`logs/upstream-golang-filter-diff.typescript`](logs/upstream-golang-filter-diff.typescript)

Machine-specific checkout paths in published transcripts are replaced by
`<repo>`, `<evidence>`, `<baseline>`, or `<workspace>`. The scripts accept
explicit `REPO`, `EVIDENCE`, and `BASELINE` parameters. For example:

```bash
export EVIDENCE="$PWD"
export REPO=/path/to/fixed-higress-checkout
export BASELINE=/path/to/baseline-higress-checkout
bash harness/verify-revision.sh
bash harness/go-verify.sh
bash harness/build-filters.sh
bash harness/build-gateway-images.sh
```

The remaining scripts create the isolated cluster, seed Nacos, run three
rounds per variant, capture state, upgrade only the gateway overlay, summarize
results, and clean up. They expect the pinned `kind`, `kubectl`, and `helm`
binaries under `/tmp/pr4286-bin` and temporary localhost forwards on ports
18080 and 18848.

## Artifact boundary and checksums

Compiled shared objects, verbose component logs, Pod JSON, and the full kind
export are intentionally omitted from the public tree. Their identities remain
in the 130-entry [`SHA256SUMS.full`](SHA256SUMS.full) captured before curation;
that manifest's SHA-256 is
`ac65b8364d3ca218af9610f3d1c03afdd9c0a9ef42dcee593d3a234ab439e5e4`.

[`SHA256SUMS`](SHA256SUMS) validates every curated, sanitized file published in
this directory. The public tree contains no detected local checkout paths,
credentials, tokens, private keys, or common secret assignments.
