"""Identical barrier-controlled requests against baseline and fixed Wasm."""
import argparse
import collections
import hashlib
import json
import pathlib
import subprocess
import time
import urllib.request

# All requests stay on loopback; inherited proxy settings must not intercept them.
urllib.request.install_opener(urllib.request.build_opener(urllib.request.ProxyHandler({})))

CONTROL = "http://127.0.0.1:19469"
GATEWAY = "http://127.0.0.1:19468"
CACHED = b'{"source":"cache","value":"fixture-only"}'
UPSTREAM = b'{"source":"upstream","value":"fixture-only"}'


def control(path="/", data=None):
    request = urllib.request.Request(CONTROL + path,
                                    data=json.dumps(data).encode() if data is not None else None,
                                    headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=2) as response:
        return json.load(response)


def wait_for(predicate, seconds):
    deadline = time.monotonic() + seconds
    while True:
        state = control()
        if predicate(state):
            return state
        if time.monotonic() >= deadline:
            return None
        time.sleep(0.01)


def perform(out, variant, mode, round_number, index):
    # Same IDs, keys, bytes, commands and timings for both variants.
    rid = f"{mode}-r{round_number}-{index:03}"
    key = "higress-audit:" + rid
    control("/prepare", {"id": rid, "mode": mode})
    prefix = out / rid
    headers_path = prefix.with_suffix(".headers")
    body_path = prefix.with_suffix(".body")
    argv = ["curl", "--noproxy", "*", "--silent", "--show-error", "--max-time", "10",
            "--dump-header", str(headers_path), "--output", str(body_path),
            "--write-out", "%{http_code}", "--header", "x-http-cache-key: " + rid,
            "--header", "x-verification-id: " + rid, "--header", "Accept-Encoding: gzip",
            GATEWAY + "/fixture"]
    process = subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    before = None
    try:
        assert wait_for(lambda s: any(e["event"] == "redis_get_seen" and e["id"] == rid
                                     for e in s["events"]), 3), "GET not observed"
        if mode == "timeout":
            control("/release-upstream", {"id": rid})
        else:
            before = wait_for(lambda s: s["cases"][rid]["upstream"] > 0,
                              1 if mode == "hit" else 0.05) is not None
            if mode != "hit":
                control("/release-upstream", {"id": rid})
            control("/release-redis", {"id": rid})
        status, stderr = process.communicate(timeout=12)
        data = body_path.read_bytes() if body_path.exists() else b""
        headers = headers_path.read_text() if headers_path.exists() else ""
        result = {"id": rid, "variant": variant, "mode": mode, "round": round_number,
                  "key": key, "status": status.decode(), "curl_exit": process.returncode,
                  "stderr": stderr.decode(), "body_sha256": hashlib.sha256(data).hexdigest(),
                  "body": data.decode(), "upstream_before_release": before}
        control("/client-complete", {"id": rid, "result": {
            "status": result["status"], "curl_exit": process.returncode,
            "body_sha256": result["body_sha256"]}})
        control("/release-upstream", {"id": rid})
        if mode == "timeout":
            control("/release-redis", {"id": rid})
        time.sleep(0.1)  # post-completion quiescence, in addition to causal events
        state = control()
        events = [e for e in state["events"] if e["id"] == rid]
        result["upstream_total"] = state["cases"][rid]["upstream"]
        result["events"] = events
        result["request_command"] = [s.replace(str(out), "RESULT_DIR") for s in argv]
        prefix.with_suffix(".json").write_text(json.dumps(result, indent=2) + "\n")
        if mode == "timeout":
            if process.returncode == 0:
                assert result["upstream_total"] == 1 and data == UPSTREAM
                result["timeout_contract"] = "host callback resumed request once"
            else:
                assert process.returncode == 28 and result["upstream_total"] == 0
                result["timeout_contract"] = "no host callback before client deadline"
        else:
            assert process.returncode == 0 and status == b"200", result
            if mode == "hit":
                assert before == (variant == "baseline"), result
                assert result["upstream_total"] == (1 if variant == "baseline" else 0), result
                assert data == CACHED and "x-cache-status: hit" in headers.lower(), result
                event_names = [e["event"] for e in events]
                if variant == "baseline":
                    assert event_names.index("upstream_seen") < event_names.index("redis_reply_released")
            else:
                assert not before and result["upstream_total"] == 1 and data == UPSTREAM, result
        assert not any(e["event"] in ("fixture_deadline", "unexpected_key", "unexpected_command")
                       for e in events), events
        result["passed"] = True
        prefix.with_suffix(".json").write_text(json.dumps(result, indent=2) + "\n")
        return result
    finally:
        if process.poll() is None:
            process.kill()
            process.communicate()
        control("/release-redis", {"id": rid})
        control("/release-upstream", {"id": rid})


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--variant", choices=["baseline", "fixed"], required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    parser.add_argument("--timeout-only", action="store_true")
    parser.add_argument("--smoke", action="store_true")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    subprocess.run(["curl", "--noproxy", "*", "--fail", "--silent", "--max-time", "10", "--header",
                    "x-higress-skip-response-cache: on", GATEWAY + "/warmup"], check=True,
                   stdout=subprocess.DEVNULL)
    modes = ["timeout"] if args.timeout_only else (["hit"] if args.variant == "baseline"
                                                  else ["hit", "miss", "error", "empty"])
    results = []
    for mode in modes:
        rounds = 1 if args.smoke or args.timeout_only else 3
        count = 1 if args.smoke or args.timeout_only else (50 if mode in ("hit", "miss") else 10)
        for round_number in range(1, rounds + 1):
            control("/reset", {})
            current = [perform(args.output, args.variant, mode, round_number, i) for i in range(count)]
            summary = {"mode": mode, "round": round_number, "requests": count,
                       "upstream_calls": sum(r["upstream_total"] for r in current),
                       "all_passed": all(r["passed"] for r in current)}
            summary["redis_commands"] = dict(collections.Counter(
                e["command"] for e in control()["events"] if e["event"] == "redis_command"))
            results.extend(current)
            (args.output / f"{mode}-round-{round_number}.json").write_text(
                json.dumps({"summary": summary, "fixture": control()}, indent=2) + "\n")
            print(json.dumps(summary), flush=True)
    (args.output / "summary.json").write_text(json.dumps({"variant": args.variant,
        "requests": len(results), "all_passed": all(r["passed"] for r in results),
        "upstream_calls": sum(r["upstream_total"] for r in results),
        "cases": [{k: v for k, v in r.items() if k not in ("events", "request_command")}
                  for r in results]}, indent=2) + "\n")


if __name__ == "__main__":
    main()
