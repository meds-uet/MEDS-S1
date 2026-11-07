# `sw/drivers/` — Accelerator drivers

## What lives here
Drivers for anything attached to a socket, built on `accel_open`/`accel_start`/`accel_wait`.

## What does *not* live here
Peripheral HAL code (`sw/bsp/`).

## How to add something
Copy the template. Cache maintenance around DMA buffers is already written in it — do not remove it.

## Catalogue projects that land here
thesis accelerator projects

---
*Conventions: [`docs/guidelines/CODING_STANDARD.md`](../../docs/guidelines/CODING_STANDARD.md) ·
Definition of done: [`EXECUTION_PLAN.md`](../../EXECUTION_PLAN.md) §8*
