#!/usr/bin/env python3
import json
import pathlib
import sys

if len(sys.argv) != 3:
    raise SystemExit("usage: assert_baseline_response.py BODY_FILE MOCK_FILE")

body = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
mock = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
assert body == mock, "baseline response differs from the original Gemini payload"
assert "choices" not in body, body.get("choices")
print("baseline unchanged-Gemini assertion: PASS")
