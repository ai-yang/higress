#!/usr/bin/env python3

import json
import os
from pathlib import Path


root = Path(os.environ["EVIDENCE_ROOT"])
mock = json.loads((root / "harness" / "gemini-response.json").read_text())
summary = {"result": "PASS", "variants": {}}


def assert_fixed(payload):
    choices = payload.get("choices")
    assert isinstance(choices, list) and len(choices) == 1
    choice = choices[0]
    message = choice["message"]
    assert message.get("content") == "Let me check. One moment."
    calls = message.get("tool_calls")
    assert isinstance(calls, list) and len(calls) == 1
    call = calls[0]
    assert call.get("type") == "function"
    assert call.get("index") == 0
    assert call["function"].get("name") == "lookup"
    assert json.loads(call["function"]["arguments"]) == {"id": 42}
    assert choice.get("finish_reason") == "tool_calls"
    assert payload.get("usage") == {
        "prompt_tokens": 10,
        "completion_tokens": 5,
        "total_tokens": 15,
    }


for variant in ("baseline", "fixed"):
    result_dir = root / "results" / variant
    log_dir = root / "logs" / variant / "runtime"
    envoy_log = (log_dir / "envoy.log").read_text()
    mock_log = (log_dir / "mock.log").read_text()
    stats_payload = json.loads((log_dir / "envoy-stats.json").read_text())
    stats = {
        item["name"]: item.get("value")
        for item in stats_payload["stats"]
        if "name" in item
    }

    panic_text = "recovered from panic runtime error: invalid memory address or nil pointer dereference"
    panic_count = envoy_log.count(panic_text)
    response_log_count = envoy_log.count("chat completion response body:")
    mock_200_count = mock_log.count(
        '"POST /v1beta/models/gemini-pro:generateContent HTTP/1.1" 200'
    )
    assert panic_count == (3 if variant == "baseline" else 0)
    assert response_log_count == 3
    assert mock_200_count == 3
    assert stats["http.pr4288.downstream_rq_completed"] == 3
    assert stats["http.pr4288.downstream_rq_2xx"] == 3
    assert stats["http.pr4288.downstream_rq_active"] == 0

    rounds = []
    for round_number in range(1, 4):
        prefix = result_dir / f"round-{round_number}"
        curl_result = json.loads(Path(f"{prefix}-curl.json").read_text())
        payload = json.loads(Path(f"{prefix}-response.json").read_text())
        assert curl_result["http_code"] == 200
        if variant == "baseline":
            assert payload == mock
            assert "choices" not in payload
        else:
            assert_fixed(payload)
        rounds.append(
            {
                "round": round_number,
                "http_code": curl_result["http_code"],
                "response_bytes": curl_result["size_download"],
                "time_total_seconds": curl_result["time_total"],
            }
        )

    summary["variants"][variant] = {
        "rounds": rounds,
        "panic_count": panic_count,
        "response_log_count": response_log_count,
        "mock_200_count": mock_200_count,
        "envoy_completed_2xx": 3,
    }

(root / "results" / "summary.json").write_text(
    json.dumps(summary, indent=2, sort_keys=True) + "\n"
)
print("evidence verification: PASS")
