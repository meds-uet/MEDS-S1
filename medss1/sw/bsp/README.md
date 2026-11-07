# `sw/bsp/` — Board support package

## What lives here
`crt0.S`, linker scripts, newlib syscall stubs, the HAL for every peripheral, and `libs1_perf`.

## What does *not* live here
Application code (`sw/apps/`), accelerator drivers (`sw/drivers/`).

## How to add something
One header and one .c per peripheral, named after it. Every HAL function is documented where it is declared.

## Catalogue projects that land here
T-06 BSP · M-09 libs1_perf · M-04 boot ROM

---
*Conventions: [`docs/guidelines/CODING_STANDARD.md`](../../docs/guidelines/CODING_STANDARD.md) ·
Definition of done: [`EXECUTION_PLAN.md`](../../EXECUTION_PLAN.md) §8*
