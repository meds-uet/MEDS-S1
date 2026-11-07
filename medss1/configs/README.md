# `configs/` — Build configurations

## What lives here
`s1_nano`, `s1_base`, `s1_ai`, `s1_linux` — the four named configurations of SPEC §5.3.

## What does *not* live here
Board-specific settings (`boards/<board>/board.yaml`).

## How to add something
**A config that is not in CI does not exist.** Adding one means adding it to the elaborate matrix in `.github/workflows/pr.yml`.

## Catalogue projects that land here
R-04

---
*Conventions: [`docs/guidelines/CODING_STANDARD.md`](../docs/guidelines/CODING_STANDARD.md) ·
Definition of done: [`EXECUTION_PLAN.md`](../EXECUTION_PLAN.md) §8*
