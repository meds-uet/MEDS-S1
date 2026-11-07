# `rtl/generated/` — Generated RTL — DO NOT EDIT

## What lives here
Output of `gen/` from `configs/*.yaml`: the SoC top level, address decode, PMA decode.

## What does *not* live here
Anything hand-written. Every file here carries a DO-NOT-EDIT header.

## How to add something
Edit the YAML or the generator template, then re-run `make gen`. CI regenerates and fails on any difference — that check is what stops the memory map being right in the RTL and wrong in the device tree.

## Catalogue projects that land here
R-04 the SoC generator

---
*Conventions: [`docs/guidelines/CODING_STANDARD.md`](../../docs/guidelines/CODING_STANDARD.md) ·
Definition of done: [`EXECUTION_PLAN.md`](../../EXECUTION_PLAN.md) §8*
