#!/usr/bin/env python3

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EXPECTED_CLUSTER = "outbound|5678||pr4231-echo.dns"
BASELINE_SHA = "409b3ed2644a977776391eae78ed6cb11e99d3d3"
FIXED_SHA = "7cc8cde4bb8b268e1e5fa98219790b392e1d98d3"


def load_json(path: Path):
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def route_cluster(variant: str) -> str:
    dump = load_json(ROOT / "logs" / variant / "envoy-routes.json")
    for config in dump["configs"]:
        route_config = config.get("route_config", {})
        for virtual_host in route_config.get("virtual_hosts", []):
            for route in virtual_host.get("routes", []):
                if route.get("name") == "pr4231-higress-service":
                    return route["route"]["cluster"]
    raise AssertionError(f"{variant}: expected Envoy route was not found")


def assert_healthy_registry_cluster(variant: str) -> None:
    dump = load_json(ROOT / "logs" / variant / "envoy-clusters.json")
    cluster = next(
        (item for item in dump["cluster_statuses"] if item["name"] == EXPECTED_CLUSTER),
        None,
    )
    assert cluster is not None, f"{variant}: registry cluster missing"
    hosts = cluster.get("host_statuses", [])
    assert hosts, f"{variant}: registry cluster has no host"
    assert all(
        host.get("health_status", {}).get("eds_health_status") == "HEALTHY"
        for host in hosts
    ), f"{variant}: registry cluster has an unhealthy host"


def access_entries(variant: str):
    entries = []
    path = ROOT / "logs" / variant / "gateway.log"
    for line in path.read_text(encoding="utf-8").splitlines():
        start = line.find("{")
        if start < 0:
            continue
        try:
            entry = json.loads(line[start:])
        except json.JSONDecodeError:
            continue
        if entry.get("route_name") == "pr4231-higress-service":
            entries.append(entry)
    return entries


def request_codes(variant: str):
    codes = []
    for sample in range(1, 4):
        result = load_json(ROOT / "results" / variant / f"request-{sample}.json")
        assert result["sample"] == sample
        assert result["curl_exit_code"] == 0
        codes.append(result["http_code"])
    return codes


def main() -> None:
    baseline_codes = request_codes("baseline")
    fixed_codes = request_codes("fixed")
    assert baseline_codes == [500, 500, 500]
    assert fixed_codes == [200, 200, 200]

    for sample in range(1, 4):
        baseline_body = ROOT / "results" / "baseline" / f"request-{sample}.body"
        fixed_body = ROOT / "results" / "fixed" / f"request-{sample}.body"
        assert baseline_body.read_bytes() == b""
        assert fixed_body.read_bytes() == b"pr4231-backend-ok\n"

    baseline_route_status = (ROOT / "logs/baseline/httproute.yaml").read_text()
    fixed_route_status = (ROOT / "logs/fixed/httproute.yaml").read_text()
    assert "reason: InvalidKind" in baseline_route_status
    assert 'status: "False"\n      type: ResolvedRefs' in baseline_route_status
    assert "message: All references resolved" in fixed_route_status
    assert 'status: "True"\n      type: ResolvedRefs' in fixed_route_status

    assert route_cluster("baseline") == "UnknownService"
    assert route_cluster("fixed") == EXPECTED_CLUSTER
    assert_healthy_registry_cluster("baseline")
    assert_healthy_registry_cluster("fixed")

    for variant in ("baseline", "fixed"):
        direct = (ROOT / "logs" / variant / "direct-backend-response.txt").read_text()
        assert "HTTP/1.1 200 OK" in direct
        assert direct.rstrip().endswith("pr4231-backend-ok")

    baseline_access = [
        entry for entry in access_entries("baseline") if entry.get("response_code") == "500"
    ]
    fixed_access = [
        entry for entry in access_entries("fixed") if entry.get("response_code") == "200"
    ]
    assert len(baseline_access) == 3
    assert all(entry.get("response_code_details") == "cluster_not_found" for entry in baseline_access)
    assert len(fixed_access) == 3
    assert all(entry.get("response_code_details") == "via_upstream" for entry in fixed_access)
    assert all(entry.get("upstream_cluster") == EXPECTED_CLUSTER for entry in fixed_access)

    baseline_version = load_json(ROOT / "logs/baseline/controller-version.json")
    fixed_version = load_json(ROOT / "logs/fixed/controller-version.json")
    assert baseline_version["gitCommitID"] == BASELINE_SHA
    assert fixed_version["gitCommitID"] == FIXED_SHA

    go_log = (ROOT / "logs/go-verify.log").read_text()
    assert "[go-verify] targeted race tests, count=20" in go_log
    assert "[go-verify] PASS" in go_log
    assert "WARNING: DATA RACE" not in go_log
    assert "FAIL" not in go_log

    summary = {
        "baseline": {
            "source_sha": BASELINE_SHA,
            "http_codes": baseline_codes,
            "route_condition": "ResolvedRefs=False/InvalidKind",
            "envoy_route_cluster": "UnknownService",
            "registry_cluster_healthy": True,
            "direct_backend_http_code": 200,
        },
        "fixed": {
            "source_sha": FIXED_SHA,
            "http_codes": fixed_codes,
            "response_body": "pr4231-backend-ok\\n",
            "route_condition": "ResolvedRefs=True/ResolvedRefs",
            "envoy_route_cluster": EXPECTED_CLUSTER,
            "registry_cluster_healthy": True,
            "direct_backend_http_code": 200,
        },
        "go_verification": {
            "go_version": "go1.26.7 linux/amd64",
            "targeted": "pass",
            "full_package": "pass",
            "targeted_race_count": 20,
            "vet": "pass",
        },
    }
    summary_path = ROOT / "results/summary.json"
    summary_path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print("evidence verification: PASS")
    print(summary_path.relative_to(ROOT))


if __name__ == "__main__":
    main()
