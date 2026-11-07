# `verif/cosim/` — Layer 2 — trace co-simulation against Spike

## What lives here
The RVFI trace comparator, the Spike harness, and the diff reporter. This is the verification backbone.

## What does *not* live here
Directed tests.

## How to add something
Build the checker before the thing it checks. This lands in Phase 1, before the datapath exists.

## Catalogue projects that land here
R-05 RVFI trace port and Spike co-simulation

---
*Conventions: [`docs/guidelines/CODING_STANDARD.md`](../../docs/guidelines/CODING_STANDARD.md) ·
Definition of done: [`EXECUTION_PLAN.md`](../../EXECUTION_PLAN.md) §8*
