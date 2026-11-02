#!/usr/bin/env python3
# Copyright 2026 Maktab-e-Digital Systems Lahore.
# SPDX-License-Identifier: Apache-2.0
"""Generate PROJECTS.md from the project catalogue.

The catalogue (scripts/gen_project_catalogue.py) is the single source of truth
for what each project is.  This script turns it into the repository index:
which directories each project touches, so a contributor can answer "where does
my code go?" in five seconds.

The directory mapping lives here rather than in the catalogue because it is a
property of the repository layout, not of the project.

Usage:
    python3 scripts/gen_projects_index.py            # write PROJECTS.md
    python3 scripts/gen_projects_index.py --check    # fail if out of date (CI)
"""
from __future__ import annotations

import argparse
import importlib.util
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "PROJECTS.md"
CATALOGUE = ROOT / "scripts" / "gen_project_catalogue.py"

# Which directories each project writes to.  Keep in sync when the layout moves.
DIRS: dict[str, list[str]] = {
    "M-01": ["rtl/peripherals/", "sw/bsp/", "verif/unit/", "configs/"],
    "M-02": ["rtl/peripherals/", "sw/bsp/", "verif/unit/", "configs/"],
    "M-03": ["rtl/peripherals/", "sw/bsp/", "verif/unit/", "configs/"],
    "M-04": ["sw/bsp/", "sw/apps/", "rtl/peripherals/"],
    "M-05": ["verif/unit/", "docs/modules/"],
    "M-06": ["verif/unit/", "docs/modules/"],
    "M-07": ["sw/apps/", "scripts/"],
    "M-08": ["sw/apps/", "scripts/"],
    "M-09": ["sw/bsp/", "sw/bsp/include/"],
    "M-10": ["scripts/", ".github/workflows/", "docs/guidelines/"],
    "M-11": ["verif/riscof/", ".github/workflows/"],
    "M-12": ["boards/kc705/", "docs/"],
    "M-13": ["docs/modules/", "rtl/"],
    "M-14": ["docs/", "docs/adr/"],
    "M-15": ["docs/", "docs/adr/"],
    "M-16": ["verif/unit/", "verif/common/", "docs/guidelines/"],
    "T-01": ["rtl/core/", "verif/unit/", "docs/modules/"],
    "T-02": ["rtl/core/", "verif/unit/", "docs/modules/"],
    "T-03": ["rtl/core/", "verif/unit/", "docs/modules/"],
    "T-04": ["rtl/fabric/", "verif/unit/", "docs/modules/"],
    "T-05": ["rtl/peripherals/", "verif/unit/", "sw/bsp/"],
    "T-06": ["sw/bsp/", "sw/apps/", "boards/"],
    "T-07": ["verif/riscof/", "verif/cosim/", ".github/workflows/"],
    "T-08": ["boards/kc705/", "rtl/generated/"],
    "R-01": ["rtl/core/", "verif/conformance/", "verif/formal/", "docs/modules/"],
    "R-02": ["rtl/core/", "verif/unit/", "docs/modules/"],
    "R-03": ["rtl/cache/", "rtl/common/", "verif/unit/", "docs/modules/"],
    "R-04": ["gen/", "configs/", "rtl/generated/"],
    "R-05": ["rtl/core/", "verif/cosim/", "docs/modules/"],
    "R-06": ["rtl/", "sw/bsp/", "boards/"],
    "R-07": ["rtl/socket/", "verif/conformance/", "sw/drivers/"],
}

TIER_ORDER = {"Mentee": 0, "Mentor": 1, "Graduate RA": 2}

# The work packages the catalogue's `wp=` fields, the `wp<N>/` branch prefix and
# the project board refer to.  (number, scope, depends on, phase)
WORK_PACKAGES: list[tuple[int, str, str, str]] = [
    (0,  "Specs frozen: `INTERFACES`, `ISA_SPEC`, `SCOPE_CONTRACT`, `CODING_STANDARD`", "—", "0"),
    (1,  "Repo, CI skeleton, lint, runner box, Verilator flow", "—", "0"),
    (2,  "Core frontend: PC, BTFN, `fetch_req`/`fetch_rsp`, C-expansion", "WP0", "1"),
    (3,  "Core backend: decode, regfile, ALU, forwarding, hazards", "WP0", "1"),
    (4,  "CSR file (generated), traps, privilege FSM, perf counters", "WP0", "1"),
    (5,  "Completion buffer, retire, MXIF port", "WP0, WP3", "1"),
    (6,  "LSU, store buffer, PMP + PMA check unit, AMO/LR-SC", "WP0, WP3", "1–2"),
    (7,  "I$ and D$, `Zicbom`, SRAM wrapper", "WP6", "2–3"),
    (8,  "AXI fabric, crossbar config, up/downsizers, address decode", "WP0", "2"),
    (9,  "Peripherals: CLINT, PLIC, UART, SPI, GPIO, timer", "WP8", "2"),
    (10, "SoC generator: `soc.yaml` → RTL, ld, headers, DTS, docs", "WP0, WP8", "2"),
    (11, "RVFI port + Spike co-simulation harness", "WP0", "1"),
    (12, "RISCOF + arch-tests + Sail in CI", "WP1", "1"),
    (13, "Unit TBs, coverage model, random generator", "WP1", "1+"),
    (14, "BSP: crt0, newlib, HAL, `libs1_perf`, `make run`", "WP9", "2–3"),
    (15, "Debug Module + DTM + OpenOCD + semihosting", "WP4, WP5", "3"),
    (16, "KC705 board port, MIG/DDR, bring-up", "WP8, WP10", "2–3"),
    (17, "Accelerator socket + conformance TBs", "WP8", "3–4"),
    (18, "MEDS-V MXIF adapter + book erratum", "WP0, WP5", "4"),
    (19, "Benchmark + workload suite (Tier A and B)", "WP14", "2–4"),
    (20, "MMU, PTW (2 ports), Sv39, TLB", "WP6, WP7", "5"),
    (21, "OpenSBI + Buildroot Linux", "WP20", "5"),
    (22, "Docs, release engineering, evidence bundle", "WP1", "all"),
]


def load_projects() -> list[dict]:
    spec = importlib.util.spec_from_file_location("catalogue", CATALOGUE)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.PROJECTS


def render(projects: list[dict]) -> str:
    L: list[str] = []
    add = L.append

    add("# MEDS-S1 — Project Index\n")
    add("**Where does my code go?**  This table maps every project in the "
        "[Project Catalogue](docs/MEDS-S1-Project-Catalogue.pdf) to the directories it touches.\n")
    add("> Generated by `scripts/gen_projects_index.py` from the catalogue — "
        "**do not edit by hand.**  Run `make projects` after changing the catalogue.\n")
    add("New here? Read [`docs/guidelines/ONBOARDING.md`](docs/guidelines/ONBOARDING.md) first, "
        "then find your project below.\n")
    add("---\n")

    # ---- summary ----------------------------------------------------------
    by_tier: dict[str, int] = {}
    by_track: dict[str, int] = {}
    for p in projects:
        by_tier[p["tier"]] = by_tier.get(p["tier"], 0) + 1
        by_track[p["track"]] = by_track.get(p["track"], 0) + 1

    add(f"**{len(projects)} projects** — "
        + " · ".join(f"{k} {v}" for k, v in sorted(by_tier.items(), key=lambda kv: TIER_ORDER.get(kv[0], 9)))
        + "\n")
    add("| Track | Projects |")
    add("|---|---|")
    for track, n in sorted(by_track.items(), key=lambda kv: -kv[1]):
        ids = " ".join(f"`{p['id']}`" for p in projects if p["track"] == track)
        add(f"| {track} ({n}) | {ids} |")
    add("")

    # ---- per tier ---------------------------------------------------------
    for tier in sorted({p["tier"] for p in projects}, key=lambda t: TIER_ORDER.get(t, 9)):
        add(f"\n## {tier}\n")
        add("| ID | Project | WP | Weeks | Pri | Directories you will touch |")
        add("|---|---|---|---|---|---|")
        for p in sorted((x for x in projects if x["tier"] == tier), key=lambda x: x["id"]):
            dirs = DIRS.get(p["id"], [])
            dtxt = " ".join(f"`{d}`" for d in dirs) or "_(unmapped — raise an issue)_"
            pri = p["priority"].replace(" — critical path", " ⚠")
            add(f"| **{p['id']}** | {p['title']} | {p['wp']} | {p['weeks']} | {pri} | {dtxt} |")
        add("")

    # ---- work packages ----------------------------------------------------
    add("\n---\n")
    add("## Work packages\n")
    add("The **WP** column above, the `wp<N>/` branch prefix and the project board's "
        "*Work package* field all refer to this list. A work package is a slice of the "
        "platform with one owner, a written spec, a testbench and a merge gate; "
        "the projects above are the pieces of it that one team can finish.\n")
    add("| WP | Scope | Depends on | Phase |")
    add("|---|---|---|---|")
    for n, scope, deps, phase in WORK_PACKAGES:
        add(f"| **WP{n}** | {scope} | {deps} | {phase} |")

    # ---- reverse index ----------------------------------------------------
    add("\n---\n")
    add("## Reverse index — who works in this directory?\n")
    add("Useful before you change something: these are the people whose work you may collide with.\n")
    rev: dict[str, list[str]] = {}
    for pid, dirs in DIRS.items():
        for d in dirs:
            rev.setdefault(d, []).append(pid)
    add("| Directory | Projects |")
    add("|---|---|")
    for d in sorted(rev):
        add(f"| `{d}` | " + " ".join(f"`{i}`" for i in sorted(rev[d])) + " |")

    # ---- getting started --------------------------------------------------
    add("""
---

## Starting your project

1. **Read your catalogue page** — objective, deliverables, definition of done, week plan.
2. **Read the README of every directory above.** Each says what belongs there and what does not.
3. **Read the house style**: [`rtl/core/s1_alu.sv`](rtl/core/s1_alu.sv) and
   [`verif/unit/tb_s1_alu.sv`](verif/unit/tb_s1_alu.sv). Your code should look like these.
4. **Open your tracking issue** using the `module` or `task` template, and put it on the board.
5. **Branch** as `<project-id>/<short-description>`, e.g. `m-01/uart-wrapper`.
6. **Before every push**: `make check && make lint && make test-unit`.

## Definition of done — every project

A work package is not done because the RTL exists:

- ☐ Spec or design note reviewed **before** implementation
- ☐ Code merged, lint clean, no unjustified waivers
- ☐ Unit testbench in CI, passing, with a plausible check count
- ☐ `docs/modules/<module>.md` stating the interface contract (NFR-7)
- ☐ Integrated into at least one named config and elaborating in CI
- ☐ Owner **and backup** recorded
- ☐ Demonstrated at a demo day — running, not slides
""")
    return "\n".join(L) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true",
                    help="exit non-zero if PROJECTS.md is out of date")
    args = ap.parse_args()

    projects = load_projects()
    text = render(projects)

    unmapped = [p["id"] for p in projects if p["id"] not in DIRS]
    if unmapped:
        print(f"warning: no directory mapping for {', '.join(unmapped)}")

    if args.check:
        current = OUT.read_text() if OUT.exists() else ""
        if current != text:
            print("PROJECTS.md is out of date -- run `make projects`")
            return 1
        print("PROJECTS.md is up to date")
        return 0

    OUT.write_text(text)
    print(f"wrote {OUT.relative_to(ROOT)} ({len(projects)} projects, "
          f"{len({d for ds in DIRS.values() for d in ds})} directories)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
