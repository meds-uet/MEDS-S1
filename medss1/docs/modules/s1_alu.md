# `s1_alu`

| | |
|---|---|
| **Status** | COMPLETE — REFERENCE (the house-style example to copy) |
| **Owner** | @umershahidengr |
| **Backup** | _(assign at Phase-0 review)_ |
| **Project** | T-02 (core backend), tested by M-06 |
| **Spec** | SPEC §7.3, §8.1 |
| **Source** | `rtl/core/s1_alu.sv` |
| **Testbench** | `verif/unit/tb_s1_alu.sv` — 4206 checks |

## Purpose

The integer ALU and branch comparator for the EX stage. It exists as a separate module because the
branch comparator and the arithmetic result are needed by different consumers in the same cycle
(the branch unit and the completion buffer), and because it is the smallest useful thing a new
contributor can read end to end.

## Interface contract

Purely combinational. No clock, no reset, no state.

| Signal | Dir | Width | Meaning | Contract |
|---|---|---|---|---|
| `op_i` | in | `alu_op_e` | arithmetic operation | must be a legal enum value; out-of-range yields `sum` |
| `cmp_op_i` | in | `cmp_op_e` | branch condition | `CMP_NONE` for non-branches |
| `a_i` | in | `WIDTH` | operand A (rs1) | |
| `b_i` | in | `WIDTH` | operand B (rs2 or immediate) | shift amount is taken from the low bits |
| `result_o` | out | `WIDTH` | arithmetic result | valid in the same cycle |
| `cmp_result_o` | out | 1 | branch taken | **0 when `cmp_op_i == CMP_NONE`** |

**Latency:** zero — combinational.
**Reset state:** none; outputs follow inputs.
**`cmp_result_o` must be 0 for `CMP_NONE`.** If it ever floats, every non-branch instruction becomes
a random branch, which is a hang rather than a wrong answer. `tb_s1_alu` checks this explicitly.

## Parameters

| Parameter | Default | Legal range | Effect |
|---|---|---|---|
| `WIDTH` | `XLEN` (64) | 32, 64 | operand and result width; shift-amount width derives via `$clog2` |

## Behaviour

One shared adder serves ADD, SUB, ADDW, SUBW, SLT and SLTU — subtraction is addition of the two's
complement. Sharing keeps the critical path to a single carry chain rather than two.

The comparator is computed from the operands directly rather than from the adder result, because the
adder is already on the critical path and the comparisons are cheap.

### The RV64 W-forms

`ADDW`, `SUBW`, `SLLW`, `SRLW`, `SRAW` operate on the low 32 bits and **sign-extend the 32-bit
result to 64 bits**, regardless of the operands' upper halves.

`SRLW` shifts in zeros from **bit 31, not bit 63**. This is the single most common RV64 ALU bug — a
64-bit `SRL` on a negative 32-bit value gives a completely different answer — so it has its own named
check rather than hiding inside the sweep.

Shift amounts are **masked, not saturated**: 6 bits for the 64-bit forms, 5 for the W forms. `SLL` by
64 is a no-op, not a zero.

## Exceptions and errors

None. This module cannot fault. Illegal-operation detection belongs to the decoder.

## Verification status

| Layer | Status | Where |
|---|---|---|
| Lint | clean, no waivers | `make lint` |
| Unit test | **4206 checks** — 100 corner pairs × 16 ops, W-form traps, comparator sweep, 2000 random | `verif/unit/tb_s1_alu.sv` |
| Co-simulation | covered indirectly once R-05 lands | |
| Formal | not yet | candidate for T-07 |

## Known limitations

- `WIDTH` other than 64 is untested; the W-form logic assumes a 32-bit sub-word and would need
  revisiting for `WIDTH = 32`.
- No `Zbb` bit-manipulation operations. Out of scope for v1.0.

## Open questions

None. This module is considered done.
