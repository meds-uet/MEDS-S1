#!/usr/bin/env python3
# Copyright 2026 Maktab-e-Digital Systems Lahore.
# SPDX-License-Identifier: Apache-2.0
"""Maintain M-07 benchmark history and enforce the regression threshold."""

import argparse
import json
import numbers
import sys
from datetime import datetime, timezone
from pathlib import Path


DEFAULT_THRESHOLD = 3.0
SCHEMA_VERSION = 1


def _positive_number(result, field, context):
    value = result.get(field)
    if isinstance(value, bool) or not isinstance(value, numbers.Real):
        raise ValueError(f"{context}: missing or invalid {field}")
    if value <= 0:
        raise ValueError(f"{context}: {field} must be positive")
    return value


def validate_result(result, context="benchmark result"):
    if not isinstance(result, dict):
        raise ValueError(f"{context} must be an object")
    if result.get("valid") is not True:
        raise ValueError(f"{context}: valid must be true")

    benchmark = result.get("benchmark")
    if benchmark not in ("coremark", "dhrystone"):
        raise ValueError(f"{context}: unsupported benchmark {benchmark!r}")
    if not isinstance(result.get("configuration"), str) or not result["configuration"]:
        raise ValueError(f"{context}: missing configuration")

    if benchmark == "coremark":
        _positive_number(result, "total_ticks", context)
        _positive_number(result, "iterations", context)
    else:
        _positive_number(result, "cycles_per_run", context)
        _positive_number(result, "runs", context)


def validate_results(results, context="benchmark results"):
    if not isinstance(results, list) or not results:
        raise ValueError(f"{context} must be a non-empty list")
    seen = set()
    for index, result in enumerate(results):
        validate_result(result, f"{context}[{index}]")
        key = (result["benchmark"], result["configuration"])
        if key in seen:
            raise ValueError(f"{context}: duplicate benchmark/configuration {key!r}")
        seen.add(key)


def metric(result):
    validate_result(result)
    if result["benchmark"] == "coremark":
        return result["total_ticks"] / result["iterations"]
    if result["benchmark"] == "dhrystone":
        return result["cycles_per_run"]
    raise ValueError(f"unsupported benchmark: {result['benchmark']}")


def latest_accepted(history, benchmark, configuration):
    for entry in reversed(history.get("entries", [])):
        if entry["accepted"] is not True:
            continue
        for result in entry.get("results", []):
            if result.get("benchmark") == benchmark and result.get("configuration") == configuration:
                return result
    return None


def evaluate(results, history, threshold=DEFAULT_THRESHOLD):
    validate_results(results)
    validate_history(history)
    comparisons = []
    passed = True
    for result in results:
        baseline = latest_accepted(history, result["benchmark"], result["configuration"])
        current_metric = metric(result)
        if baseline is None:
            comparisons.append({
                "benchmark": result["benchmark"],
                "configuration": result["configuration"],
                "current": current_metric,
                "baseline": None,
                "regression_percent": None,
                "status": "baseline",
            })
            continue

        baseline_metric = metric(baseline)
        regression_percent = ((current_metric - baseline_metric) / baseline_metric) * 100
        blocked = regression_percent > threshold
        passed = passed and not blocked
        comparisons.append({
            "benchmark": result["benchmark"],
            "configuration": result["configuration"],
            "current": current_metric,
            "baseline": baseline_metric,
            "regression_percent": regression_percent,
            "status": "blocked" if blocked else "pass",
        })
    return {"passed": passed, "threshold_percent": threshold, "comparisons": comparisons}


def load_history(path):
    if not path.exists():
        return {"schema_version": 1, "entries": []}
    history = json.loads(path.read_text(encoding="utf-8"))
    try:
        validate_history(history)
    except ValueError as error:
        raise ValueError(f"invalid history file {path}: {error}") from error
    return history


def validate_history(history):
    if not isinstance(history, dict) or history.get("schema_version") != SCHEMA_VERSION:
        raise ValueError("schema_version must be 1")
    entries = history.get("entries")
    if not isinstance(entries, list):
        raise ValueError("entries must be a list")
    for index, entry in enumerate(entries):
        if not isinstance(entry, dict):
            raise ValueError(f"entries[{index}] must be an object")
        if not isinstance(entry.get("accepted"), bool):
            raise ValueError(f"entries[{index}].accepted must be boolean")
        validate_results(entry.get("results"), f"entries[{index}].results")


def save_history(path, history):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(history, indent=2) + "\n", encoding="utf-8")


def record(history, results, accepted):
    validate_history(history)
    validate_results(results)
    history.setdefault("entries", []).append({
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "accepted": accepted,
        "results": results,
    })


def markdown(report):
    lines = [
        "| Benchmark | Configuration | Baseline | Current | Change | Status |",
        "| --- | --- | ---: | ---: | ---: | --- |",
    ]
    for comparison in report["comparisons"]:
        baseline = "n/a" if comparison["baseline"] is None else f"{comparison['baseline']:.2f}"
        change = "n/a" if comparison["regression_percent"] is None else f"{comparison['regression_percent']:+.2f}%"
        lines.append(
            f"| {comparison['benchmark']} | {comparison['configuration']} | "
            f"{baseline} | {comparison['current']:.2f} | {change} | {comparison['status']} |"
        )
    return "\n".join(lines) + "\n"


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("results", type=Path)
    parser.add_argument("--history", type=Path, required=True)
    parser.add_argument("--threshold", type=float, default=DEFAULT_THRESHOLD)
    parser.add_argument("--record", action="store_true")
    args = parser.parse_args(argv)

    try:
        results = json.loads(args.results.read_text(encoding="utf-8"))
        history = load_history(args.history)
        report = evaluate(results, history, args.threshold)
        if args.record:
            record(history, results, report["passed"])
            save_history(args.history, history)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"m07-regression: {error}", file=sys.stderr)
        return 1

    sys.stdout.write(markdown(report))
    if not report["passed"]:
        print(f"m07-regression: regression exceeds {args.threshold:.2f}%", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())