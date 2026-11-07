# `verif/conformance/` — Interface conformance testbenches

## What lives here
`tb_mxif_conformance` and `tb_socket_conformance` — the reusable assets every future coprocessor and accelerator must pass.

## What does *not* live here
Tests for one specific accelerator.

## How to add something
**These outlive every accelerator.** Changing them changes the contract; treat like a frozen interface.

## Catalogue projects that land here
R-07 socket conformance · R-01 MXIF conformance

---
*Conventions: [`docs/guidelines/CODING_STANDARD.md`](../../docs/guidelines/CODING_STANDARD.md) ·
Definition of done: [`EXECUTION_PLAN.md`](../../EXECUTION_PLAN.md) §8*
