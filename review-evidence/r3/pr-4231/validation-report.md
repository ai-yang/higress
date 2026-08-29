# PR #4231 R3 validation report

## Conclusion

PASS. The fix converts a valid `networking.higress.io/Service` backendRef into
the existing Higress registry cluster. The baseline deterministically routes to
`UnknownService` and returns 500 even though the intended registry cluster and
healthy endpoint are already present. With only the controller image changed,
the route points to that cluster and returns the backend response 3/3 times.

## Source and static verification

| Check | Result |
|---|---|
| Rebased fixed SHA | `7cc8cde4bb8b268e1e5fa98219790b392e1d98d3` |
| Baseline SHA | `409b3ed2644a977776391eae78ed6cb11e99d3d3` |
| Source diff | 2 files, 120 insertions, 16 deletions |
| `git diff --check` | PASS |
| Targeted unit tests | PASS, `0.080s` |
| Full `pkg/ingress/kube/gateway/istio` tests | PASS, `9.948s` |
| Targeted `-race -count=20` | PASS, `1.328s` |
| Package `go vet` | PASS |

The complete successful output is in `logs/go-verify.log`. A first dependency
bootstrap attempt timed out against `proxy.golang.org` before compilation. The
final recorded run reused the populated cache with an approved mirror and
completed every command successfully.

## Runtime controls

| Control | Evidence | Result |
|---|---|---|
| Exact running controller SHA | `logs/*/controller-version.json` | baseline and fixed SHAs match |
| Registry was valid before the red request | baseline Envoy clusters and direct backend response | cluster present, endpoint healthy, direct 200 |
| Same fixture | `manifests/runtime-fixtures.yaml` | unchanged |
| Same data-plane/runtime images | `environment.json`, live workload YAML | unchanged |
| Only Helm-rendered change | `logs/helm-rendered-controller.diff` | controller tag only |
| Baseline route status | `logs/baseline/httproute.yaml` | `ResolvedRefs=False / InvalidKind` |
| Fixed route status | `logs/fixed/httproute.yaml` | `ResolvedRefs=True / ResolvedRefs` |
| Baseline response | `results/baseline/` | 3/3 HTTP 500 |
| Fixed response | `results/fixed/` | 3/3 HTTP 200 and exact body |
| Data-plane explanation | `logs/*/envoy-routes.json`, gateway logs | `UnknownService` → registry cluster |
| Machine assertions | `harness/verify-evidence.py` | PASS |
| Cleanup | `logs/cleanup.log` | no named kind cluster/container; ports closed |

## Limitations

- The runtime test covers the reported DNS-registry service naming path on a
  single-node IPv4 kind cluster. It does not claim coverage for every registry
  implementation, TLS listener, or cross-namespace ReferenceGrant combination.
- The local controller overlays have image IDs rather than registry digests;
  their pinned base digest, source SHA, deterministic binary SHA256, Dockerfile,
  and build harness are all published so reviewers can rebuild and compare.
- The 119 MB binaries and 1.7 GB image-transfer archive are intentionally not
  published. No assertion depends on downloading those transient artifacts.
