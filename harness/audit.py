"""Re-check completed evidence and create a compact machine summary."""
import collections
import argparse
import hashlib
import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
RESULTS = ROOT / "results"
CACHED = b'{"source":"cache","value":"fixture-only"}'
UPSTREAM = b'{"source":"upstream","value":"fixture-only"}'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime-only", action="store_true")
    args = parser.parse_args()
    build, repeated = None, None
    if not args.runtime_only:
        build = json.loads((RESULTS / "build.json").read_text())
        for variant in ("baseline", "fixed"):
            assert hashlib.sha256((RESULTS / f"{variant}.wasm").read_bytes()).hexdigest() == build["sources"][variant + "_wasm_sha256"]
        race = (RESULTS / "race.log").read_text()
        test = (RESULTS / "test.log").read_text()
        for log in (race, test):
            assert "\nPASS\n" in log and "\nFAIL" not in log and "WARNING: DATA RACE" not in log
            assert "--- SKIP:" not in log
        repeated = collections.Counter(re.findall(r"^--- PASS: (Test\w+) ", race, re.M))
        assert len(repeated) == 8 and set(repeated.values()) == {20}, repeated
        red = (RESULTS / "regression-red.log").read_text()
        assert red.count("expected: 0x4") == 6 and red.count("actual  : 0x0") == 6
        assert len(re.findall(r"^    --- FAIL: TestHeaderKeyLookupABI/", red, re.M)) == 6
        assert len(re.findall(r"^    --- PASS: TestHeaderKeyLookupABI/", red, re.M)) == 3
        assert "unexpected hostcall" not in red and "panic:" not in red
    rows = []
    total = 0
    for label, expected, upstream in (("baseline", 150, 150), ("fixed", 360, 210), ("fixed-timeout", 1, 1)):
        directory = RESULTS / "runtime" / label
        summary = json.loads((directory / "requests" / "summary.json").read_text())
        assert summary["all_passed"] and summary["requests"] == expected
        assert summary["upstream_calls"] == upstream
        logs = (directory / "containers.log").read_text()
        assert "panic:" not in logs and "wasm vm failed" not in logs.lower()
        assert "Traceback" not in logs and "Exception occurred" not in logs
        if label == "fixed-timeout":
            assert logs.count("[critical]") == 1 and "Error occurred while calling redis" in logs
        else:
            assert "[critical]" not in logs
        access = re.findall(r"RID=(\S+) CODE=(\d+) DETAIL=(\S+) FLAGS=(\S+) UPSTREAM=(\S+)", logs)
        for result in summary["cases"]:
            rid = result["id"]
            matches = [a for a in access if a[0] == rid]
            assert len(matches) == 1 and matches[0][1] == "200" and matches[0][3] == "-", (label, rid, matches)
            data = (directory / "requests" / (rid + ".body")).read_bytes()
            detail = json.loads((directory / "requests" / (rid + ".json")).read_text())
            names = [event["event"] for event in detail["events"]]
            assert hashlib.sha256(data).hexdigest() == result["body_sha256"]
            assert result["curl_exit"] == 0 and result["stderr"] == ""
            if result["mode"] == "hit":
                assert data == CACHED and matches[0][2] == "via_wasm::response-cache::response-cache.hit"
                assert names.index("redis_reply_released") < names.index("client_complete")
                if label == "baseline":
                    assert names.index("upstream_seen") < names.index("redis_reply_released")
                else:
                    assert "upstream_seen" not in names
            else:
                assert data == UPSTREAM
                assert names.index("upstream_seen") < names.index("client_complete")
                if result["mode"] == "timeout":
                    assert names.index("redis_get_seen") < names.index("upstream_seen")
                    assert names.index("client_complete") < names.index("redis_reply_released")
                else:
                    assert names.index("redis_reply_released") < names.index("upstream_seen")
        stats = dict(line.rsplit(": ", 1) for line in (directory / "stats-after.txt").read_text().splitlines() if ": " in line)
        assert int(stats["cluster.response-cache-upstream.upstream_rq_total"]) == upstream + 1  # warmup
        assert int(stats["http.verify.downstream_rq_completed"]) == expected + 1
        for path in sorted((directory / "requests").glob("*-round-*.json")):
            value = json.loads(path.read_text())["summary"]
            rows.append({"variant": label, **value})
        total += expected
    cleanup = json.loads((RESULTS / "cleanup.json").read_text())
    assert not cleanup["containers_remaining"] and not cleanup["networks_remaining"] and not cleanup["volumes_remaining"]
    assert cleanup["ports_closed"] == [19468, 19469, 19470]
    result = {"all_passed": True, "scope": "runtime-only" if args.runtime_only else "full-verification",
              "formal_runtime_requests": total, "rounds": rows,
              "race_repetitions_by_test": dict(repeated) if repeated else None, "build": build,
              "cached_body_sha256": hashlib.sha256(CACHED).hexdigest(),
              "upstream_body_sha256": hashlib.sha256(UPSTREAM).hexdigest(), "cleanup": cleanup}
    filename = "runtime-audit.json" if args.runtime_only else "audit.json"
    (RESULTS / filename).write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({k: v for k, v in result.items() if k not in ("build", "cleanup")}, indent=2))


if __name__ == "__main__":
    main()
