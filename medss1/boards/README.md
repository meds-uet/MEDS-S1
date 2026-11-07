# `boards/` — Board ports

## What lives here
One directory per board. A port is exactly four files: `board.yaml`, `board.xdc`, `board_top.sv`, `openocd.cfg`.

## What does *not* live here
Any logic. `board_top.sv` instantiates PLLs, MIG and IO — nothing else.

## How to add something
Copy `boards/verilator/`. If your port needs a fifth file, the abstraction is leaking; raise it before working around it.

## Catalogue projects that land here
T-08 KC705 port · M-12 Xilinx IP survey

---
*Conventions: [`docs/guidelines/CODING_STANDARD.md`](../docs/guidelines/CODING_STANDARD.md) ·
Definition of done: [`EXECUTION_PLAN.md`](../EXECUTION_PLAN.md) §8*
