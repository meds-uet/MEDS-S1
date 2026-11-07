# `verif/act4/` — Layer 3 — architectural compliance (ACT)

## What lives here
act4 configuration, the DUT and reference plugins, and the generated compliance reports.

## What does *not* live here
Hand-written ISA tests. Compliance tests come from `riscv-arch-test` upstream.

## How to add something
Sail is the reference. `make act4` runs the suite; the CI job is present and skipped until the plugin lands.

## Catalogue projects that land here
M-11 ACT triage · T-07 act4 and co-simulation in CI

---
*Conventions: [`docs/guidelines/CODING_STANDARD.md`](../../docs/guidelines/CODING_STANDARD.md) ·
Definition of done: [`EXECUTION_PLAN.md`](../../EXECUTION_PLAN.md) §8*
