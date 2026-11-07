# `rtl/common/` — Shared primitives

## What lives here
`meds_s1_sram` (the mandatory SRAM wrapper), synchronisers, FIFOs, arbiters — anything used by two or more subsystems.

## What does *not* live here
Anything used by exactly one subsystem. Keep it next to its user until a second user appears.

## How to add something
A primitive lands here when the second user shows up, not in anticipation of one.

## Catalogue projects that land here
shared

---
*Conventions: [`docs/guidelines/CODING_STANDARD.md`](../../docs/guidelines/CODING_STANDARD.md) ·
Definition of done: [`EXECUTION_PLAN.md`](../../EXECUTION_PLAN.md) §8*
