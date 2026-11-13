#!/usr/bin/env python3
# Copyright 2026 Maktab-e-Digital Systems Lahore.
# Licensed under the Apache License, Version 2.0, see LICENSE file for details.
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# gen/s1_csr_gen.py : CSR table generator [COMPLETE]
#
# Merges rtl/core/defines/core_csr.yaml and extensions/*/csr.yaml into
# rtl/generated/s1_csr_pkg.sv.
# Enforces SPEC 10.2: generated address-decoded structure, no hand-written cases.
# Every entry is validated before anything is written, so a bad table never
# leaves a half-written package behind.
#
# Usage: python3 gen/s1_csr_gen.py           regenerate the package
#        python3 gen/s1_csr_gen.py --check   fail if the checked-in package differs
# Output is "DO NOT EDIT" and regenerated wholesale (CODING_STANDARD.md R-D2).
# =============================================================================

import argparse
from pathlib import Path
import sys

import yaml


# Resolve every repository path from this script, so invocation works from any
# directory (for example, from gen/ or a build directory).
REPO_ROOT = Path(__file__).resolve().parent.parent
CORE_CSR_PATH = REPO_ROOT / "rtl" / "core" / "defines" / "core_csr.yaml"
EXTENSION_CSR_GLOB = "extensions/*/csr.yaml"
OUTPUT_PATH = REPO_ROOT / "rtl" / "generated" / "s1_csr_pkg.sv"

# Enum literals are emitted in this order.
CLASS_ENUM = {
    "core":     "CSR_CLASS_CORE",
    "counter":  "CSR_CLASS_COUNTER",
    "external": "CSR_CLASS_EXTERNAL",
}

# Decoded presences. The others are validated but not emitted, so an access to
# them misses the decoder and is illegal.
PRESENCE_ENUM = {
    "impl":     "CSR_PRESENT_IMPL",
    "ro_zero":  "CSR_PRESENT_RO_ZERO",
    "alias_of": "CSR_PRESENT_ALIAS",
}
NOT_DECODED = ("absent", "deferred", "external")

# Privilege encoding of addr[9:8]; 2 is the hypervisor range.
PRIV_ENC = {"U": 0, "S": 1, "M": 3}
GATES = ("U", "S", "PMP")

REQUIRED_KEYS = {"name", "addr", "class", "presence", "min_priv",
                 "read_only", "debug_only", "desc"}
VALUE_KEYS = {"reset", "write_mask", "wmask_if_S", "ro_const",
              "ro_const_if_U", "ro_const_if_S", "view_mask"}
BOOL_KEYS = {"read_only", "debug_only", "ro_override", "hw_write", "warl"}
KNOWN_KEYS = REQUIRED_KEYS | VALUE_KEYS | BOOL_KEYS | {"index", "config_gate", "view_of"}
STORAGE_KEYS = VALUE_KEYS | {"view_of", "hw_write", "warl"}
RO_CONST_KEYS = ("ro_const", "ro_const_if_U", "ro_const_if_S")


def is_int(value):
    return isinstance(value, int) and not isinstance(value, bool)


def load_table(path, errors):
    """Return the list of raw entries in one YAML file."""
    rel = path.relative_to(REPO_ROOT)
    try:
        with path.open(encoding="utf-8") as source_file:
            data = yaml.safe_load(source_file)
    except yaml.YAMLError as e:
        errors.append(f"{rel}: YAML does not parse: {e}")
        return []

    if not isinstance(data, dict) or not isinstance(data.get("csrs"), list):
        errors.append(f"{rel}: expected a top-level 'csrs:' list")
        return []
    return [(f"{rel}: entry {i}", c) for i, c in enumerate(data["csrs"])]


def check_fields(where, c, errors):
    """Key names and value types. Returns False if the entry cannot be used."""
    if not isinstance(c, dict):
        errors.append(f"{where}: expected a mapping")
        return False

    unknown = set(c) - KNOWN_KEYS
    if unknown:
        errors.append(f"{where}: unknown key(s): {', '.join(sorted(unknown))}")
    missing = REQUIRED_KEYS - set(c)
    if missing:
        errors.append(f"{where}: missing key(s): {', '.join(sorted(missing))}")
        return False

    ok = True
    if not isinstance(c["name"], str) or not c["name"].isidentifier():
        errors.append(f"{where}: name must be an identifier, got {c['name']!r}")
        ok = False
    if not is_int(c["addr"]) or not 0 <= c["addr"] < 0x1000:
        errors.append(f"{where}: addr must be an integer in 0x000-0xFFF, got {c['addr']!r}")
        ok = False
    for key in sorted(BOOL_KEYS & set(c)):
        if not isinstance(c[key], bool):
            errors.append(f"{where}: {key} must be true or false, got {c[key]!r}")
            ok = False
    for key in sorted(VALUE_KEYS & set(c)):
        if not is_int(c[key]) or not 0 <= c[key] < 2**64:
            errors.append(f"{where}: {key} must be an integer in 0 .. 2**64-1, got {c[key]!r}")
            ok = False
    if c["class"] not in CLASS_ENUM:
        errors.append(f"{where}: class must be one of {', '.join(CLASS_ENUM)}, got {c['class']!r}")
        ok = False
    presences = list(PRESENCE_ENUM) + list(NOT_DECODED)
    if c["presence"] not in presences:
        errors.append(f"{where}: presence must be one of {', '.join(presences)}, "
                      f"got {c['presence']!r}")
        ok = False
    if c["min_priv"] not in PRIV_ENC:
        errors.append(f"{where}: min_priv must be U, S or M, got {c['min_priv']!r}")
        ok = False
    if "config_gate" in c and c["config_gate"] not in GATES:
        errors.append(f"{where}: config_gate must be one of {', '.join(GATES)}, "
                      f"got {c['config_gate']!r}")
        ok = False
    if "index" in c:
        idx = c["index"]
        if (not isinstance(idx, list) or len(idx) != 2 or not all(is_int(n) for n in idx)
                or not 0 <= idx[0] <= idx[1]):
            errors.append(f"{where}: index must be [first, last] with 0 <= first <= last")
            ok = False
    return ok


def expand(c):
    """Turn an entry with index: [first, last] into one entry per number."""
    if "index" not in c:
        return [c]
    first, last = c["index"]
    out = []
    for n in range(first, last + 1):
        e = {k: v for k, v in c.items() if k != "index"}
        e["name"] = f"{c['name']}{n}"
        e["addr"] = c["addr"] + n - first
        out.append(e)
    return out


def check_rules(where, c, errors):
    """Access fields against addr[11:8], and the per-presence rules."""
    addr = c["addr"]
    if addr >= 0x1000:
        errors.append(f"{where}: addr {addr:#x} is beyond 0xFFF")
        return

    priv_bits = (addr >> 8) & 0x3
    if priv_bits == 2:
        errors.append(f"{where}: addr[9:8] = 2 is the hypervisor range, which S1 does not have")
    elif PRIV_ENC[c["min_priv"]] != priv_bits:
        errors.append(f"{where}: min_priv {c['min_priv']} does not match addr[9:8] = {priv_bits}")

    ro_range = (addr >> 10) == 0x3
    if ro_range and not c["read_only"]:
        errors.append(f"{where}: addr[11:10] = 3 is read-only, so read_only must be true")
    if c["read_only"] and not ro_range and not c.get("ro_override", False):
        errors.append(f"{where}: read_only in a read/write range needs ro_override: true")
    if c.get("ro_override", False) and (ro_range or not c["read_only"]):
        errors.append(f"{where}: ro_override only applies to a read_only CSR in a read/write range")

    debug_range = 0x7B0 <= addr <= 0x7BF
    if c["debug_only"] != debug_range:
        errors.append(f"{where}: debug_only must be {str(debug_range).lower()} "
                      f"for addr {addr:#05x} (debug-only range is 0x7B0-0x7BF)")

    if (c["class"] == "external") != (c["presence"] == "external"):
        errors.append(f"{where}: class external and presence external go together")

    presence = c["presence"]
    if presence in NOT_DECODED:
        extra = STORAGE_KEYS & set(c)
        if extra:
            errors.append(f"{where}: a {presence} CSR is not decoded, remove "
                          f"{', '.join(sorted(extra))}")
        return

    if "write_mask" not in c:
        errors.append(f"{where}: write_mask is required (there is no default)")
    if presence == "alias_of":
        for key in ("view_of", "view_mask"):
            if key not in c:
                errors.append(f"{where}: alias_of needs {key}")
        for key in ("reset", "wmask_if_S") + RO_CONST_KEYS:
            if key in c:
                errors.append(f"{where}: {key} belongs on the CSR this one is a view of")
        if c.get("write_mask", 0) & ~c.get("view_mask", 0):
            errors.append(f"{where}: write_mask has bits outside view_mask")
        return

    if "reset" not in c:
        errors.append(f"{where}: reset is required")
    for key in ("view_of", "view_mask"):
        if key in c:
            errors.append(f"{where}: {key} only applies to presence alias_of")
    writable = c.get("write_mask", 0) | c.get("wmask_if_S", 0)
    if presence == "ro_zero":
        nonzero = [k for k in ("reset", "write_mask", "wmask_if_S") + RO_CONST_KEYS if c.get(k, 0)]
        if nonzero:
            errors.append(f"{where}: ro_zero must have {', '.join(nonzero)} = 0")
    if c["read_only"] and writable:
        errors.append(f"{where}: read_only CSR must have write_mask and wmask_if_S = 0")
    for key in RO_CONST_KEYS:
        if c.get(key, 0) & writable:
            errors.append(f"{where}: {key} overlaps writable bits")


def load_all():
    """Load, expand and validate every table. Exits with all errors found."""
    errors = []
    if not CORE_CSR_PATH.is_file():
        sys.exit(f"s1_csr_gen: core table not found: {CORE_CSR_PATH.relative_to(REPO_ROOT)}")

    sources = [CORE_CSR_PATH] + sorted(REPO_ROOT.glob(EXTENSION_CSR_GLOB))
    entries = []
    for path in sources:
        for where, raw in load_table(path, errors):
            if check_fields(where, raw, errors):
                for c in expand(raw):
                    entries.append((f"{where} ({c['name']})", c))

    owner_of_name, owner_of_addr = {}, {}
    for where, c in entries:
        if c["name"] in owner_of_name:
            errors.append(f"{where}: name already used by {owner_of_name[c['name']]}")
        if c["addr"] in owner_of_addr:
            errors.append(f"{where}: address {c['addr']:#05x} already used by "
                          f"{owner_of_addr[c['addr']]}")
        owner_of_name.setdefault(c["name"], where)
        owner_of_addr.setdefault(c["addr"], where)
        check_rules(where, c, errors)

    impl_addr = {c["name"]: c["addr"] for _, c in entries if c["presence"] == "impl"}
    for where, c in entries:
        if c["presence"] == "alias_of" and "view_of" in c and c["view_of"] not in impl_addr:
            errors.append(f"{where}: view_of {c['view_of']!r} is not an impl CSR")

    if not errors and not any(c["presence"] in PRESENCE_ENUM for _, c in entries):
        errors.append("no decoded CSRs: NUM_CSRS would be 0")

    if errors:
        for e in errors:
            print(f"s1_csr_gen: {e}", file=sys.stderr)
        sys.exit(1)

    for _, c in entries:
        if c["presence"] == "alias_of":
            c["view_addr"] = impl_addr[c["view_of"]]
    return [c for _, c in entries]


def bit(value):
    return "1'b1" if value else "1'b0"


def hex64(c, key):
    return f"64'h{c.get(key, 0):016x}"


def render(entries):
    """Return the SystemVerilog package text."""
    decoded = [c for c in entries if c["presence"] in PRESENCE_ENUM]
    width = max(len(c["name"]) for c in entries) + len("CSR_")

    out = [
        "// Copyright 2026 Maktab-e-Digital Systems Lahore.",
        "// Licensed under the Apache License, Version 2.0, see LICENSE file for details.",
        "// SPDX-License-Identifier: Apache-2.0",
        "//",
        "// DO NOT EDIT -- generated from core_csr.yaml by gen/s1_csr_gen.py",
        "",
        "package s1_csr_pkg;",
        "",
        "  typedef enum logic [1:0] {",
        ",\n".join(f"    {v}" for v in CLASS_ENUM.values()),
        "  } csr_class_e;",
        "",
        "  typedef enum logic [1:0] {",
        ",\n".join(f"    {v}" for v in PRESENCE_ENUM.values()),
        "  } csr_presence_e;",
        "",
        "  typedef struct packed {",
        "    logic [11:0]   addr;",
        "    csr_class_e    cls;",
        "    csr_presence_e presence;",
        "    logic [1:0]    min_priv;       // addr[9:8] encoding: 0 U, 1 S, 3 M",
        "    logic          read_only;",
        "    logic          debug_only;",
        "    logic          gate_u;         // exists only on configs with U-mode",
        "    logic          gate_s;         // exists only on configs with S-mode",
        "    logic          gate_pmp;       // exists only on configs with PMP regions",
        "    logic          hw_write;       // written by trap entry, xRET or interrupt lines",
        "    logic          has_warl;       // 1 => route through s1_csr_legalize",
        "    logic [11:0]   view_addr;      // alias: the CSR that holds the state",
        "    logic [63:0]   view_mask;      // alias: bits visible through the view",
        "    logic [63:0]   reset_val;",
        "    logic [63:0]   write_mask;     // WPRI: 0 = reserved, ignore write, read 0",
        "    logic [63:0]   wmask_if_s;     // extra writable bits with S-mode",
        "    logic [63:0]   ro_const;       // read-only bits that read as 1",
        "    logic [63:0]   ro_const_if_u;",
        "    logic [63:0]   ro_const_if_s;",
        "  } csr_desc_t;",
        "",
        "  // Every CSR in the table, decoded or not.",
    ]
    for c in entries:
        name = f"CSR_{c['name'].upper()}"
        out.append(f"  localparam logic [11:0] {name:<{width}} = 12'h{c['addr']:03x};")

    out += [
        "",
        f"  localparam int unsigned NUM_CSRS = {len(decoded)};",
        "",
        "  localparam csr_desc_t CSR_TABLE [NUM_CSRS] = '{",
    ]
    for i, c in enumerate(decoded):
        gate = c.get("config_gate")
        comma = "," if i < len(decoded) - 1 else ""
        out += [
            f"    // {c['name']}",
            f"    '{{addr: 12'h{c['addr']:03x}, cls: {CLASS_ENUM[c['class']]}, "
            f"presence: {PRESENCE_ENUM[c['presence']]},",
            f"      min_priv: 2'd{PRIV_ENC[c['min_priv']]}, read_only: {bit(c['read_only'])}, "
            f"debug_only: {bit(c['debug_only'])},",
            f"      gate_u: {bit(gate == 'U')}, gate_s: {bit(gate == 'S')}, "
            f"gate_pmp: {bit(gate == 'PMP')},",
            f"      hw_write: {bit(c.get('hw_write'))}, has_warl: {bit(c.get('warl'))}, "
            f"view_addr: 12'h{c.get('view_addr', 0):03x},",
            f"      view_mask:     {hex64(c, 'view_mask')},",
            f"      reset_val:     {hex64(c, 'reset')},",
            f"      write_mask:    {hex64(c, 'write_mask')},",
            f"      wmask_if_s:    {hex64(c, 'wmask_if_S')},",
            f"      ro_const:      {hex64(c, 'ro_const')},",
            f"      ro_const_if_u: {hex64(c, 'ro_const_if_U')},",
            f"      ro_const_if_s: {hex64(c, 'ro_const_if_S')}}}{comma}",
        ]
    out += ["  };", "", "endpackage", ""]
    return "\n".join(out)


def main():
    parser = argparse.ArgumentParser(description="Generate rtl/generated/s1_csr_pkg.sv")
    parser.add_argument("--check", action="store_true",
                        help="fail if the checked-in package differs from a fresh run")
    args = parser.parse_args()

    text = render(load_all())
    rel = OUTPUT_PATH.relative_to(REPO_ROOT)
    if args.check:
        current = OUTPUT_PATH.read_text(encoding="utf-8") if OUTPUT_PATH.is_file() else ""
        if current != text:
            sys.exit(f"s1_csr_gen: {rel} is out of date; run 'make csr-gen'")
        print(f"s1_csr_gen: {rel} is up to date")
        return
    OUTPUT_PATH.write_text(text, encoding="utf-8")
    print(f"s1_csr_gen: wrote {rel}")


if __name__ == "__main__":
    main()
