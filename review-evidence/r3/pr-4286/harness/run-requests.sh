#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "usage: $0 <variant> <round> <iterations> <expected-unique-backends>" >&2
  exit 2
fi

variant=$1
round=$2
iterations=$3
expected_unique=$4
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
evidence_dir=${EVIDENCE:-$(cd -- "${SCRIPT_DIR}/.." && pwd)}
request_file="${SCRIPT_DIR}/cluster/mcp-tool-call.json"
result_file="${evidence_dir}/results/${variant}-round-${round}-responses.jsonl"

mkdir -p "${evidence_dir}/results"
: >"${result_file}"

for ((iteration = 1; iteration <= iterations; iteration++)); do
  response=$(curl -fsS -X POST \
    http://127.0.0.1:18080/pr4286/mcp \
    -H 'Host: pr4286.example.com' \
    -H 'Content-Type: application/json' \
    --data-binary "@${request_file}")
  printf '%s\n' "${response}" >>"${result_file}"
done

PR4286_RESULT_FILE="${result_file}" \
PR4286_EXPECTED_UNIQUE="${expected_unique}" \
PR4286_EXPECTED_ITERATIONS="${iterations}" \
python3 - <<'PY'
import collections
import json
import os
import pathlib

path = pathlib.Path(os.environ["PR4286_RESULT_FILE"])
expected_unique = int(os.environ["PR4286_EXPECTED_UNIQUE"])
expected_iterations = int(os.environ["PR4286_EXPECTED_ITERATIONS"])
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

summary = {
    "responses": len(lines),
    "counts": dict(sorted(counts.items())),
    "unique_backends": len(counts),
    "errors": errors,
    "expected_responses": expected_iterations,
    "expected_unique_backends": expected_unique,
}
summary["assertion_passed"] = (
    len(lines) == expected_iterations
    and not errors
    and set(counts).issubset({"backend-0", "backend-1"})
    and len(counts) == expected_unique
)
print(json.dumps(summary, indent=2, sort_keys=True))
if not summary["assertion_passed"]:
    raise SystemExit(1)
PY
