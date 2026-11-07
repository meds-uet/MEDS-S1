# `rtl/socket/` — Accelerator socket

## What lives here
`meds_s1_accel_socket` and its CDC bridges — the frozen attachment point for every loosely-coupled accelerator.

## What does *not* live here
Accelerators themselves. Those live in the `meds-s1-accelerators` repo and attach by config.

## How to add something
**This is a frozen interface.** Changes need an `interface-change` issue and an architect's approval (INTERFACES.md §10).

## Catalogue projects that land here
R-07 socket and conformance testbenches

---
*Conventions: [`docs/guidelines/CODING_STANDARD.md`](../../docs/guidelines/CODING_STANDARD.md) ·
Definition of done: [`EXECUTION_PLAN.md`](../../EXECUTION_PLAN.md) §8*
