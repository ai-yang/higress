#!/usr/bin/env python3
"""Recompute PR #4287 statistics and compare them with the recorded result."""

from __future__ import annotations

import json
import math
import subprocess
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent.parent
ANALYZER = Path(__file__).with_name("analyze_bench.py")
EXPECTED = ROOT / "results" / "accepted" / "stats.json"


def compare(actual: Any, expected: Any, path: str = "$") -> None:
    if isinstance(expected, bool) or expected is None or isinstance(expected, str):
        if actual != expected:
            raise AssertionError(f"{path}: {actual!r} != {expected!r}")
        return
    if isinstance(expected, (int, float)):
        if not isinstance(actual, (int, float)) or not math.isclose(
            float(actual), float(expected), rel_tol=1e-12, abs_tol=1e-9
        ):
            raise AssertionError(f"{path}: {actual!r} != {expected!r}")
        return
    if isinstance(expected, list):
        if not isinstance(actual, list) or len(actual) != len(expected):
            raise AssertionError(f"{path}: list shape differs")
        for index, (actual_item, expected_item) in enumerate(zip(actual, expected)):
            compare(actual_item, expected_item, f"{path}[{index}]")
        return
    if isinstance(expected, dict):
        if not isinstance(actual, dict) or actual.keys() != expected.keys():
            raise AssertionError(f"{path}: object keys differ")
        for key in expected:
            compare(actual[key], expected[key], f"{path}.{key}")
        return
    raise TypeError(f"{path}: unsupported value {expected!r}")


def main() -> None:
    actual = json.loads(subprocess.check_output([sys.executable, str(ANALYZER)]))
    expected = json.loads(EXPECTED.read_text(encoding="utf-8"))
    compare(actual, expected)
    print("recomputed benchmark statistics: PASS")


if __name__ == "__main__":
    main()
