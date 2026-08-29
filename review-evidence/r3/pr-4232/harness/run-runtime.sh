#!/usr/bin/env bash

set -euo pipefail

: "${EVIDENCE_ROOT:?set EVIDENCE_ROOT to review-evidence/r3/pr-4232}"
: "${BASELINE_WASM:?set BASELINE_WASM to the baseline artifact}"
: "${FIXED_WASM:?set FIXED_WASM to the fixed artifact}"

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

"${script_dir}/run-variant.sh" baseline 100 "${BASELINE_WASM}"
"${script_dir}/run-variant.sh" fixed 82 "${FIXED_WASM}"
"${script_dir}/verify-evidence.py"
