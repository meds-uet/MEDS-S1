#!/usr/bin/env python3
"""Parse MEDS-S1 M-07 CoreMark and Dhrystone console output."""

import argparse
import json
import re
import sys
from pathlib import Path


class ParseError(ValueError):
    """Raised when a benchmark log is incomplete or invalid."""


def _value(pattern, text, name, cast=str):
    match = re.search(pattern, text, re.MULTILINE)
    if not match:
        raise ParseError(f"missing {name}")
    try:
        return cast(match.group(1))
    except ValueError as error:
        raise ParseError(f"invalid {name}: {match.group(1)!r}") from error


def parse_coremark(text, configuration="unknown"):
    if "Correct operation validated." not in text:
        raise ParseError("CoreMark correctness validation did not pass")

    return {
        "benchmark": "coremark",
        "configuration": configuration,
        "size": _value(r"^CoreMark Size\s*:\s*(\d+)", text, "CoreMark size", int),
        "total_ticks": _value(r"^Total ticks\s*:\s*(\d+)", text, "CoreMark ticks", int),
        "iterations": _value(r"^Iterations\s*:\s*(\d+)", text, "CoreMark iterations", int),
        "compiler_version": _value(r"^Compiler version\s*:\s*(.+)$", text, "compiler version"),
        "compiler_flags": _value(r"^Compiler flags\s*:\s*(.+)$", text, "compiler flags"),
        "seedcrc": _value(r"^seedcrc\s*:\s*(0x[0-9a-fA-F]+)", text, "seedcrc"),
        "crclist": _value(r"^\[0\]crclist\s*:\s*(0x[0-9a-fA-F]+)", text, "crclist"),
        "crcmatrix": _value(r"^\[0\]crcmatrix\s*:\s*(0x[0-9a-fA-F]+)", text, "crcmatrix"),
        "crcstate": _value(r"^\[0\]crcstate\s*:\s*(0x[0-9a-fA-F]+)", text, "crcstate"),
        "crcfinal": _value(r"^\[0\]crcfinal\s*:\s*(0x[0-9a-fA-F]+)", text, "crcfinal"),
        "valid": True,
    }


def parse_dhrystone(text, configuration="unknown"):
    runs = _value(r"Execution starts,\s+(\d+)\s+runs", text, "Dhrystone runs", int)
    total_cycles = _value(r"^Total cycles:\s+(\d+)", text, "Dhrystone total cycles", int)
    cycles_per_run = _value(r"^Cycles per run through Dhrystone:\s+(\d+)", text, "Dhrystone cycles per run", int)
    if runs <= 0 or total_cycles <= 0 or cycles_per_run <= 0:
        raise ParseError("Dhrystone timing values must be positive")

    return {
        "benchmark": "dhrystone",
        "configuration": configuration,
        "runs": runs,
        "total_cycles": total_cycles,
        "cycles_per_run": cycles_per_run,
        "valid": True,
    }


def markdown(results):
    lines = [
        "| Benchmark | Configuration | Metric | Value | Valid |",
        "| --- | --- | --- | ---: | --- |",
    ]
    for result in results:
        metric = "ticks" if result["benchmark"] == "coremark" else "cycles/run"
        value = result["total_ticks"] if result["benchmark"] == "coremark" else result["cycles_per_run"]
        lines.append(f"| {result['benchmark']} | {result['configuration']} | {metric} | {value} | {'yes' if result['valid'] else 'no'} |")
    return "\n".join(lines) + "\n"


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--coremark", type=Path)
    parser.add_argument("--dhrystone", type=Path)
    parser.add_argument("--configuration", default="temporary-spike")
    parser.add_argument("--format", choices=("json", "markdown"), default="json")
    args = parser.parse_args(argv)
    if not args.coremark and not args.dhrystone:
        parser.error("provide --coremark and/or --dhrystone")

    try:
        results = []
        if args.coremark:
            results.append(parse_coremark(args.coremark.read_text(), args.configuration))
        if args.dhrystone:
            results.append(parse_dhrystone(args.dhrystone.read_text(), args.configuration))
    except (OSError, ParseError) as error:
        print(f"m07-results: {error}", file=sys.stderr)
        return 1

    if args.format == "markdown":
        sys.stdout.write(markdown(results))
    else:
        json.dump(results, sys.stdout, indent=2)
        sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())