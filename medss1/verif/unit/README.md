# `verif/unit/` — Layer 1 — unit testbenches

## What lives here
One self-checking testbench per RTL module, named `tb_<module>.sv`. `tb_s1_alu.sv` is the worked reference — copy its shape.

## What does *not* live here
Anything needing a full SoC. That is layer 2 or 3.

## How to add something
Copy `tb_s1_alu.sv`. Derive expectations from parameters, not constants. Print `=== PASS : <n> checks ===` and exit non-zero on failure — the runner requires both.

## Catalogue projects that land here
M-05 PMA check unit · M-06 ALU and forwarding

---
*Conventions: [`docs/guidelines/CODING_STANDARD.md`](../../docs/guidelines/CODING_STANDARD.md) ·
Definition of done: [`EXECUTION_PLAN.md`](../../EXECUTION_PLAN.md) §8*
