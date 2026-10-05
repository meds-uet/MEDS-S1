#!/usr/bin/env python3
# Copyright 2026 Maktab-e-Digital Systems Lahore.
# SPDX-License-Identifier: Apache-2.0
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
    if "Dhrystone Benchmark, Version 2.1" not in text:
        raise ParseError("missing Dhrystone benchmark header")
    if not re.search(r"^Execution ends\s*$", text, re.MULTILINE):
        raise ParseError("Dhrystone execution did not complete")

    runs = _value(r"Execution starts,\s+(\d+)\s+runs", text, "Dhrystone runs", int)
    total_cycles = _value(r"^Total cycles:\s+(\d+)", text, "Dhrystone total cycles", int)
    cycles_per_run = _value(r"^Cycles per run through Dhrystone:\s+(\d+)", text, "Dhrystone cycles per run", int)
    if runs <= 0 or total_cycles <= 0 or cycles_per_run <= 0:
        raise ParseError("Dhrystone timing values must be positive")
    if cycles_per_run != total_cycles // runs:
        raise ParseError("Dhrystone timing values are inconsistent")

    try:
        globals_text, pointer_text = text.split("Ptr_Glob->", 1)
        ptr_glob_text, next_pointer_text = pointer_text.split("Next_Ptr_Glob->", 1)
        next_ptr_text, locals_text = next_pointer_text.split("Int_1_Loc:", 1)
    except ValueError as error:
        raise ParseError("missing Dhrystone final-value output") from error
    locals_text = "Int_1_Loc:" + locals_text

    def expect(section, pattern, name, expected, cast=str):
        actual = _value(pattern, section, name, cast)
        if actual != expected:
            raise ParseError(
                f"Dhrystone correctness validation failed for {name}: "
                f"expected {expected!r}, got {actual!r}"
            )
        return actual

    scalar_checks = (
        (r"^Int_Glob:\s+(-?\d+)", "Int_Glob", 5, int),
        (r"^Bool_Glob:\s+(-?\d+)", "Bool_Glob", 1, int),
        (r"^Ch_1_Glob:\s+(\S)", "Ch_1_Glob", "A", str),
        (r"^Ch_2_Glob:\s+(\S)", "Ch_2_Glob", "B", str),
        (r"^Arr_1_Glob\[8\]:\s+(-?\d+)", "Arr_1_Glob[8]", 7, int),
        (r"^Arr_2_Glob\[8\]\[7\]:\s+(-?\d+)", "Arr_2_Glob[8][7]", runs + 10, int),
    )
    for pattern, name, expected, cast in scalar_checks:
        expect(globals_text, pattern, name, expected, cast)

    ptr_comp = _value(r"^\s*Ptr_Comp:\s+(\d+)", ptr_glob_text, "Ptr_Glob Ptr_Comp", int)
    next_ptr_comp = expect(next_ptr_text, r"^\s*Ptr_Comp:\s+(\d+)", "Next_Ptr_Glob Ptr_Comp", ptr_comp, int)
    pointer_checks = (
        (ptr_glob_text, r"^\s*Discr:\s+(-?\d+)", "Ptr_Glob Discr", 0, int),
        (ptr_glob_text, r"^\s*Enum_Comp:\s+(-?\d+)", "Ptr_Glob Enum_Comp", 2, int),
        (ptr_glob_text, r"^\s*Int_Comp:\s+(-?\d+)", "Ptr_Glob Int_Comp", 17, int),
        (ptr_glob_text, r"^\s*Str_Comp:\s*(.+)$", "Ptr_Glob Str_Comp", "DHRYSTONE PROGRAM, SOME STRING", str),
        (next_ptr_text, r"^\s*Discr:\s+(-?\d+)", "Next_Ptr_Glob Discr", 0, int),
        (next_ptr_text, r"^\s*Enum_Comp:\s+(-?\d+)", "Next_Ptr_Glob Enum_Comp", 1, int),
        (next_ptr_text, r"^\s*Int_Comp:\s+(-?\d+)", "Next_Ptr_Glob Int_Comp", 18, int),
        (next_ptr_text, r"^\s*Str_Comp:\s*(.+)$", "Next_Ptr_Glob Str_Comp", "DHRYSTONE PROGRAM, SOME STRING", str),
    )
    for section, pattern, name, expected, cast in pointer_checks:
        expect(section, pattern, name, expected, cast)

    local_checks = (
        (r"^Int_1_Loc:\s+(-?\d+)", "Int_1_Loc", 5, int),
        (r"^Int_2_Loc:\s+(-?\d+)", "Int_2_Loc", 13, int),
        (r"^Int_3_Loc:\s+(-?\d+)", "Int_3_Loc", 7, int),
        (r"^Enum_Loc:\s+(-?\d+)", "Enum_Loc", 1, int),
        (r"^Str_1_Loc:\s*(.+)$", "Str_1_Loc", "DHRYSTONE PROGRAM, 1'ST STRING", str),
        (r"^Str_2_Loc:\s*(.+)$", "Str_2_Loc", "DHRYSTONE PROGRAM, 2'ND STRING", str),
    )
    for pattern, name, expected, cast in local_checks:
        expect(locals_text, pattern, name, expected, cast)

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