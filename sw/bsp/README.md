# `sw/bsp/` — Board support package

## What lives here
`crt0.S`, linker scripts, newlib syscall stubs, the HAL for every peripheral, and `libs1_perf`.

## What does *not* live here
Application code (`sw/apps/`), accelerator drivers (`sw/drivers/`).

## How to add something
One header and one .c per peripheral, named after it. Every HAL function is documented where it is declared.

## M-07 benchmark runtime
M-07 currently uses `crt0.S` and `syscalls.c` here for its temporary benchmark runtime until the T-06 BSP implementation is available. These files are intended to be replaced or adapted when T-06 is integrated, maintaining one shared BSP implementation rather than separate benchmark-specific startup files.

## Catalogue projects that land here
T-06 BSP · M-09 libs1_perf · M-04 boot ROM

---
*Conventions: [`docs/guidelines/CODING_STANDARD.md`](../../docs/guidelines/CODING_STANDARD.md) ·
Definition of done: [`EXECUTION_PLAN.md`](../../EXECUTION_PLAN.md) §8*
