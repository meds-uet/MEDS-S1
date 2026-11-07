# `gen/` — The SoC generator

## What lives here
Python that turns `configs/*.yaml` into RTL, linker scripts, C headers, a device tree, OpenOCD config and documentation.

## What does *not* live here
Anything hand-maintained that duplicates the YAML.

## How to add something
Add a template under `gen/templates/`, wire it into the emit list, add a golden test. The generator validates before it emits: overlapping regions, IRQ collisions and bandwidth-budget overruns are errors.

## Catalogue projects that land here
R-04 the SoC generator

---
*Conventions: [`docs/guidelines/CODING_STANDARD.md`](../docs/guidelines/CODING_STANDARD.md) ·
Definition of done: [`EXECUTION_PLAN.md`](../EXECUTION_PLAN.md) §8*
