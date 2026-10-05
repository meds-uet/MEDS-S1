#!/usr/bin/env python3
# Copyright 2026 Maktab-e-Digital Systems Lahore.
# SPDX-License-Identifier: Apache-2.0
"""Run the M-07 benchmarks and publish machine-readable CI results."""

import argparse
import json
import subprocess
import sys
from pathlib import Path

from parse_results import markdown, parse_coremark, parse_dhrystone
from regression_gate import evaluate, load_history, markdown as regression_markdown, record, save_history


ROOT = Path(__file__).resolve().parent.parent
COREMARK = ROOT / "sw" / "apps" / "coremark"
DHRYSTONE = ROOT / "sw" / "apps" / "dhrystone"
BUILD_BENCH = ROOT / "build" / "bench"


def run(command, cwd, output):
    with output.open("w", encoding="utf-8") as stream:
        completed = subprocess.run(command, cwd=cwd, stdout=stream, stderr=subprocess.STDOUT, text=True, check=False)
    if completed.returncode:
        raise RuntimeError(f"command failed ({completed.returncode}): {' '.join(command)}")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--configuration", default="temporary-spike")
    parser.add_argument("--iterations", default="40")
    parser.add_argument("--dhrystone-runs", default="10000")
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--history", type=Path)
    parser.add_argument("--regression-threshold", type=float, default=3.0)
    args = parser.parse_args(argv)

    output_dir = args.output_dir or BUILD_BENCH
    output_dir.mkdir(parents=True, exist_ok=True)
    history_path = args.history or BUILD_BENCH / "results-history.json"
    coremark_log = output_dir / "coremark.log"
    dhrystone_log = output_dir / "dhrystone.log"

    try:
        run(["make", "clean", "PORT_DIR=barebones_riscv", "ITERATIONS=" + args.iterations], COREMARK, output_dir / "coremark-build.log")
        run(["make", "PORT_DIR=barebones_riscv", "ITERATIONS=" + args.iterations, "XCFLAGS=-DVALIDATION_RUN=1", "load", "run2.log"], COREMARK, output_dir / "coremark-run.log")
        coremark_log.write_text((COREMARK / "run2.log").read_text())
        run(["make", "clean"], DHRYSTONE, output_dir / "dhrystone-clean.log")
        run(["make", "DHRY_RUNS=" + args.dhrystone_runs, "run"], DHRYSTONE, dhrystone_log)
        results = [parse_coremark(coremark_log.read_text(), args.configuration), parse_dhrystone(dhrystone_log.read_text(), args.configuration)]
    except (OSError, RuntimeError, ValueError) as error:
        print(f"m07-ci: {error}", file=sys.stderr)
        return 1

    (output_dir / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    (output_dir / "results.md").write_text(markdown(results))
    try:
        history = load_history(history_path)
        report = evaluate(results, history, args.regression_threshold)
        record(history, results, report["passed"])
        save_history(history_path, history)
        (output_dir / "regression.md").write_text(regression_markdown(report))
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"m07-ci: {error}", file=sys.stderr)
        return 1
    print(markdown(results), end="")
    print(regression_markdown(report), end="")
    print(f"results written to {output_dir}")
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())