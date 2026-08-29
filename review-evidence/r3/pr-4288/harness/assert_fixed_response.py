#!/usr/bin/env python3
import json
import pathlib
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: assert_fixed_response.py BODY_FILE")

body_path = pathlib.Path(sys.argv[1])
payload = json.loads(body_path.read_text(encoding="utf-8"))
choices = payload.get("choices")
assert isinstance(choices, list) and len(choices) == 1, choices
choice = choices[0]
message = choice.get("message")
assert isinstance(message, dict), message
assert message.get("content") == "Let me check. One moment.", message
calls = message.get("tool_calls")
assert isinstance(calls, list) and len(calls) == 1, calls
call = calls[0]
assert call.get("type") == "function", call
assert call.get("index") == 0, call
function = call.get("function")
assert isinstance(function, dict), function
assert function.get("name") == "lookup", function
assert json.loads(function.get("arguments", "")) == {"id": 42}, function
assert choice.get("finish_reason") == "tool_calls", choice
assert payload.get("usage") == {
    "prompt_tokens": 10,
    "completion_tokens": 5,
    "total_tokens": 15,
}, payload.get("usage")
print("fixed response assertions: PASS")
