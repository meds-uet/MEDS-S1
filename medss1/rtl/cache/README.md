# `rtl/cache/` — Instruction and data caches

## What lives here
I$, D$, their miss FSMs, the `Zicbom` engine, and the AXI adapters that sit behind them.

## What does *not* live here
The SRAM primitive itself — every array goes through `rtl/common/meds_s1_sram.sv`.

## How to add something
Caches are parameterised: size, ways and line length are parameters, never literals. Read latency is one cycle everywhere.

## Catalogue projects that land here
R-03 caches, Zicbom and the SRAM wrapper

---
*Conventions: [`docs/guidelines/CODING_STANDARD.md`](../../docs/guidelines/CODING_STANDARD.md) ·
Definition of done: [`EXECUTION_PLAN.md`](../../EXECUTION_PLAN.md) §8*
