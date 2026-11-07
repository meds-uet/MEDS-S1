# `sw/apps/` — Applications and benchmarks

## What lives here
`hello`, the frozen benchmark suite, and the Edge-AI/healthcare reference workloads.

## What does *not* live here
Library code.

## How to add something
One directory per application with its own Makefile. Every benchmark ships a scalar C reference and expected output, or it cannot be a baseline.

## Catalogue projects that land here
M-07 CoreMark/Dhrystone · M-08 Embench-IoT

---
*Conventions: [`docs/guidelines/CODING_STANDARD.md`](../../docs/guidelines/CODING_STANDARD.md) ·
Definition of done: [`EXECUTION_PLAN.md`](../../EXECUTION_PLAN.md) §8*
