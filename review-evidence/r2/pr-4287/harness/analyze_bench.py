#!/usr/bin/env python3
"""Validate and summarize PR #4287 Go benchmark samples.

The parser intentionally fails closed: every benchmark/variant/series must have
exactly 20 samples, and allocation metrics must be constant within a variant.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import statistics
from pathlib import Path


DEFAULT_INPUT_DIR = Path(__file__).resolve().parent.parent / "results" / "accepted"
BENCHMARKS = ("BenchmarkExecConditionalStr", "BenchmarkParseTmplStr")
VARIANTS = ("baseline", "optimized")
SERIES = (1, 2)
EXPECTED_SAMPLES = 20
LINE_RE = re.compile(
    r"^(Benchmark(?:ExecConditionalStr|ParseTmplStr))(?:-\d+)?\s+"
    r"\d+\s+([0-9.]+) ns/op\s+(\d+) B/op\s+(\d+) allocs/op$"
)


def parse_file(path: Path) -> dict[str, list[dict[str, float | int]]]:
    parsed = {name: [] for name in BENCHMARKS}
    for line in path.read_text(encoding="utf-8").splitlines():
        match = LINE_RE.match(line.strip())
        if not match:
            continue
        name, ns_op, b_op, allocs_op = match.groups()
        parsed[name].append(
            {
                "ns_op": float(ns_op),
                "b_op": int(b_op),
                "allocs_op": int(allocs_op),
            }
        )
    for name, rows in parsed.items():
        if len(rows) != EXPECTED_SAMPLES:
            raise ValueError(
                f"{path.name}: expected {EXPECTED_SAMPLES} {name} samples, "
                f"found {len(rows)}"
            )
    return parsed


def sample_stats(values: list[float]) -> dict[str, float | int | list[float]]:
    n = len(values)
    mean = statistics.mean(values)
    sd = statistics.stdev(values)
    margin = 1.96 * sd / math.sqrt(n)
    return {
        "n": n,
        "median": statistics.median(values),
        "mean": mean,
        "sd": sd,
        "cv_pct": 100.0 * sd / mean,
        "ci95_mean_normal": [mean - margin, mean + margin],
        "min": min(values),
        "max": max(values),
    }


def one_metric(
    baseline_rows: list[dict[str, float | int]],
    optimized_rows: list[dict[str, float | int]],
) -> dict[str, object]:
    baseline_b = {int(row["b_op"]) for row in baseline_rows}
    optimized_b = {int(row["b_op"]) for row in optimized_rows}
    baseline_a = {int(row["allocs_op"]) for row in baseline_rows}
    optimized_a = {int(row["allocs_op"]) for row in optimized_rows}
    if any(len(values) != 1 for values in (baseline_b, optimized_b, baseline_a, optimized_a)):
        raise ValueError("B/op or allocs/op changed within a benchmark variant")

    baseline_stats = sample_stats([float(row["ns_op"]) for row in baseline_rows])
    optimized_stats = sample_stats([float(row["ns_op"]) for row in optimized_rows])
    baseline_median = float(baseline_stats["median"])
    optimized_median = float(optimized_stats["median"])
    baseline_b_value = next(iter(baseline_b))
    optimized_b_value = next(iter(optimized_b))
    baseline_a_value = next(iter(baseline_a))
    optimized_a_value = next(iter(optimized_a))
    baseline_ci = baseline_stats["ci95_mean_normal"]
    optimized_ci = optimized_stats["ci95_mean_normal"]

    return {
        "baseline": baseline_stats,
        "optimized": optimized_stats,
        "median_time_reduction_pct": 100.0 * (1.0 - optimized_median / baseline_median),
        "median_speedup_x": baseline_median / optimized_median,
        "b_per_op": [baseline_b_value, optimized_b_value],
        "b_reduction_pct": 100.0 * (1.0 - optimized_b_value / baseline_b_value),
        "allocs_per_op": [baseline_a_value, optimized_a_value],
        "allocs_reduction_pct": 100.0 * (1.0 - optimized_a_value / baseline_a_value),
        "ci95_nonoverlap": bool(
            float(optimized_ci[1]) < float(baseline_ci[0])
            or float(baseline_ci[1]) < float(optimized_ci[0])
        ),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--input-dir",
        type=Path,
        default=DEFAULT_INPUT_DIR,
        help="directory containing the four accepted benchmark text files",
    )
    args = parser.parse_args()

    raw: dict[int, dict[str, dict[str, list[dict[str, float | int]]]]] = {}
    for series in SERIES:
        raw[series] = {}
        for variant in VARIANTS:
            path = args.input_dir / f"bench-{variant}-series{series}.txt"
            raw[series][variant] = parse_file(path)

    result: dict[str, object] = {
        "method": {
            "samples_per_variant_per_series": EXPECTED_SAMPLES,
            "series": len(SERIES),
            "summary": "median; sample CV; normal-approximation 95% CI for mean",
        },
        "series": {},
        "combined": {},
    }

    for series in SERIES:
        series_result: dict[str, object] = {}
        for name in BENCHMARKS:
            series_result[name] = one_metric(
                raw[series]["baseline"][name], raw[series]["optimized"][name]
            )
        result["series"][str(series)] = series_result

    for name in BENCHMARKS:
        baseline_rows = [
            row
            for series in SERIES
            for row in raw[series]["baseline"][name]
        ]
        optimized_rows = [
            row
            for series in SERIES
            for row in raw[series]["optimized"][name]
        ]
        result["combined"][name] = one_metric(baseline_rows, optimized_rows)

    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
