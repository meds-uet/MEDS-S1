# `sw/apps/` — Applications and benchmarks

## What lives here
`hello`, the frozen benchmark suite, and the Edge-AI/healthcare reference workloads.

## What does *not* live here
Library code.

## How to add something
One directory per application with its own Makefile. Every benchmark ships a scalar C reference and expected output, or it cannot be a baseline.

## M-07 automation
The Week 4 parser and CI runner are [`parse_results.py`](parse_results.py) and
[`run_ci.py`](run_ci.py). They write machine-readable JSON and a Markdown
result table for CoreMark and Dhrystone. See the [results and automation guide](results-ci/README.md)
for the workflow and output details.



## M-07 — CoreMark & Dhrystone Benchmark Harness

See [`M07.md`](M07.md) for the complete M-07 implementation, build instructions,
benchmark results, CI integration, regression gate, and platform integration status.


## Catalogue projects that land here
M-08 Embench-IoT
---
*Conventions: [`docs/guidelines/CODING_STANDARD.md`](../../docs/guidelines/CODING_STANDARD.md) ·
Definition of done: [`EXECUTION_PLAN.md`](../../EXECUTION_PLAN.md) §8*
