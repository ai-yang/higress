#!/usr/bin/env python3

import json
import os
from pathlib import Path


root = Path(os.environ["EVIDENCE_ROOT"])
expected_body = (
    b'{"id":"chatcmpl-pr4232","object":"chat.completion","usage":'
    b'{"prompt_tokens":11,"completion_tokens":7,"total_tokens":18}}'
)
expected_after = {"baseline": 100, "fixed": 82}
summary = {"result": "PASS", "variants": {}}

for variant, final_quota in expected_after.items():
    result_dir = root / "results" / variant
    log_dir = root / "logs" / variant / "runtime"
    rounds = []

    mock_log = (log_dir / "chunked-mock.log").read_text()
    envoy_log = (log_dir / "envoy.log").read_text()
    envoy_stats = json.loads((log_dir / "envoy-stats.json").read_text())
    stats = {
        item["name"]: item.get("value")
        for item in envoy_stats["stats"]
        if "name" in item
    }
    assert mock_log.count("served_chunked_json_round=") == 3
    assert mock_log.count("part_sizes=60,60") == 3
    assert stats["http.pr4232.downstream_rq_completed"] == 3
    assert stats["http.pr4232.downstream_rq_2xx"] == 3
    assert stats["http.pr4232.downstream_rq_active"] == 0

    update_count = envoy_log.count("update consumer:consumer1, totalToken:18")
    assert update_count == (0 if variant == "baseline" else 3)

    for round_number in range(1, 4):
        prefix = result_dir / f"round-{round_number}"
        before = int(Path(f"{prefix}-redis-before.txt").read_text().strip())
        after = int(Path(f"{prefix}-redis-after.txt").read_text().strip())
        body = Path(f"{prefix}-response.body").read_bytes()
        curl_result = json.loads(Path(f"{prefix}-curl.json").read_text())

        assert before == 100
        assert after == final_quota
        assert body == expected_body
        assert curl_result["http_code"] == 200
        assert curl_result["size_download"] == len(expected_body)
        assert curl_result["time_total"] >= 0.30

        rounds.append(
            {
                "round": round_number,
                "http_code": curl_result["http_code"],
                "response_bytes": curl_result["size_download"],
                "time_total_seconds": curl_result["time_total"],
                "redis_before": before,
                "redis_after": after,
            }
        )

    summary["variants"][variant] = {
        "expected_final_quota": final_quota,
        "usage_tokens": 18,
        "chunk_sizes": [60, 60],
        "rounds": rounds,
        "quota_update_log_count": update_count,
    }

summary_path = root / "results" / "summary.json"
summary_path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
print("evidence verification: PASS")
