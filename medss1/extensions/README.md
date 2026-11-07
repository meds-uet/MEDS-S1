# `extensions/` — Custom ISA extensions

## What lives here
One directory per extension, each carrying all seven required artefacts, plus `REGISTRY.md` which allocates opcode space, CSRs and accelerator IDs.

## What does *not* live here
Accelerator RTL.

## How to add something
**Nothing merges without all seven items** (SPEC §19.5). Copy `extensions/template/`.

## Catalogue projects that land here
custom-ISA thesis projects

---
*Conventions: [`docs/guidelines/CODING_STANDARD.md`](../docs/guidelines/CODING_STANDARD.md) ·
Definition of done: [`EXECUTION_PLAN.md`](../EXECUTION_PLAN.md) §8*
