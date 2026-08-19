#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
EVIDENCE=${EVIDENCE:-$(cd -- "${SCRIPT_DIR}/.." && pwd)}
PR4286_EVIDENCE="${EVIDENCE}" python3 - <<'PY'
import collections
import json
import os
import pathlib

root = pathlib.Path(os.environ["PR4286_EVIDENCE"])
variants = {"baseline": 1, "fixed": 2}
summary = {
    "baseline_revision": "4b23e08a386779c8958673ebb052fc6306fe807c",
    "fixed_revision": "83c5c03560ac212c8bb2e236db559a29e8bf300d",
    "iterations_per_round": 100,
    "rounds": [],
    "runtime_health": {},
}

for variant, expected_unique in variants.items():
    for round_number in range(1, 4):
        path = root / "results" / f"{variant}-round-{round_number}-responses.jsonl"
        counts = collections.Counter()
        errors = []
        lines = path.read_text(encoding="utf-8").splitlines()
        for index, line in enumerate(lines, start=1):
            try:
                payload = json.loads(line)
                if "error" in payload:
                    errors.append({"line": index, "error": payload["error"]})
                    continue
                counts[payload["result"]["content"][0]["text"].strip()] += 1
            except Exception as exc:
                errors.append({"line": index, "error": repr(exc), "raw": line})
        observed = set(counts)
        passed = (
            len(lines) == 100
            and not errors
            and observed.issubset({"backend-0", "backend-1"})
            and len(observed) == expected_unique
        )
        summary["rounds"].append({
            "variant": variant,
            "round": round_number,
            "responses": len(lines),
            "counts": dict(sorted(counts.items())),
            "unique_backends": len(observed),
            "errors": errors,
            "expected_unique_backends": expected_unique,
            "assertion_passed": passed,
        })

    instances = json.loads((root / "raw" / f"{variant}-nacos-instances.json").read_text())
    hosts = instances.get("hosts", [])
    stats_lines = (root / "raw" / f"{variant}-envoy-stats.txt").read_text().splitlines()
    panic_values = [
        int(line.rsplit(":", 1)[1].strip())
        for line in stats_lines
        if "golang.panic_error:" in line
    ]
    summary["runtime_health"][variant] = {
        "nacos_instances": [
            {
                "ip": item.get("ip"),
                "port": item.get("port"),
                "healthy": item.get("healthy"),
                "enabled": item.get("enabled"),
                "weight": item.get("weight"),
            }
            for item in hosts
        ],
        "two_healthy_equal_weight_instances": (
            len(hosts) == 2
            and all(item.get("healthy") and item.get("enabled") for item in hosts)
            and all(item.get("weight") == 1.0 for item in hosts)
        ),
        "go_filter_panic_counters": panic_values,
        "zero_go_filter_panics": bool(panic_values) and all(value == 0 for value in panic_values),
    }

summary["all_assertions_passed"] = (
    all(item["assertion_passed"] for item in summary["rounds"])
    and all(item["two_healthy_equal_weight_instances"] for item in summary["runtime_health"].values())
    and all(item["zero_go_filter_panics"] for item in summary["runtime_health"].values())
)
output = root / "results" / "summary.json"
output.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(output.read_text(encoding="utf-8"), end="")
if not summary["all_assertions_passed"]:
    raise SystemExit(1)
PY
