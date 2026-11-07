# `rtl/fabric/` — AXI4 fabric

## What lives here
Crossbar configuration, width up/downsizers, the address decoder, and the AXI4-Lite bridge.

## What does *not* live here
Peripheral IP (`rtl/peripherals/`), the accelerator socket (`rtl/socket/`).

## How to add something
The crossbar is generated from `configs/*.yaml`; hand-editing the decode is a bug. Change the YAML.

## Catalogue projects that land here
T-04 crossbar and address decode

---
*Conventions: [`docs/guidelines/CODING_STANDARD.md`](../../docs/guidelines/CODING_STANDARD.md) ·
Definition of done: [`EXECUTION_PLAN.md`](../../EXECUTION_PLAN.md) §8*
