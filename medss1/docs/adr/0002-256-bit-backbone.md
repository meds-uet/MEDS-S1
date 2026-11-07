# ADR-0002 — 256-bit AXI4 memory backbone

## Context

The original design document said "AXI4 backbone" without a width. That single unstated number caps
every ML accelerator the lab will ever attach.

At 100 MHz:

| Consumer | Sustained demand |
|---|---|
| Scalar core, 64 B lines | ~0.3 GB/s |
| MEDS-V, VLEN=128, 1 lane | **1.6 GB/s** |
| MEDS-V, VLEN=512, 4 lanes | **6.4 GB/s** |
| 16×16 INT8 systolic array | ~3.2 GB/s |
| **64-bit AXI4** | **0.8 GB/s** |

A 64-bit backbone starves the lab's own vector unit at its *development* configuration, before any
accelerator exists.

## Decision

- **256-bit AXI4** memory backbone (parameterised; 256 and 64 both validated)
- **64-bit** core cache-refill ports, via up/downsizers
- **32-bit AXI4-Lite** peripheral subtree
- **64 B cache line**, so a refill is two beats
- A **bandwidth budget table** (SPEC §18.3) that every accelerator declares against before it is
  accepted — exceeding it is a design-review item, not a merge

## Revisit when

Synthesis shows the crossbar is the critical path, or a second accelerator's declared demand cannot
be met. 512-bit doubles area for headroom nothing currently needs.
