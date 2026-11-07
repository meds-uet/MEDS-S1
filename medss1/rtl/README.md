# `rtl/` — RTL — SystemVerilog sources

## What lives here
All synthesisable hardware, one subdirectory per subsystem.

## What does *not* live here
Testbenches (those live in `verif/`), generated files you hand-edited, board-specific logic (that lives in `boards/<board>/board_top.sv`).

## How to add something
Pick the subdirectory that matches your subsystem, add `<module>.sv`, add `verif/unit/tb_<module>.sv`, and document the interface contract in this directory's README.

## Catalogue projects that land here
all RTL projects

---
*Conventions: [`docs/guidelines/CODING_STANDARD.md`](../docs/guidelines/CODING_STANDARD.md) ·
Definition of done: [`EXECUTION_PLAN.md`](../EXECUTION_PLAN.md) §8*
