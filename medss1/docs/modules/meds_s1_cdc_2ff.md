# `meds_s1_cdc_2ff`

| | |
|---|---|
| **Status** | COMPLETE |
| **Owner** | @your-github-handle |
| **Backup** | *(assign at Phase-0 review)* |
| **Project** | R-06 (debug module) |
| **Spec** | SPEC §27.1 (debug); RISC-V External Debug Support Specification, DTM/DMI chapter |
| **Source** | `rtl/common/meds_s1_cdc_2ff.sv` |
| **Testbench** | `verif/unit/tb_meds_s1_cdc_2ff.sv` — 891 checks |

## Purpose

Double-flop synchronizer for **level** signals entering the clock domain of `clk_i`. It exists as a shared module because CODING_STANDARD R-C9 forbids hand-written clock-domain crossings: every level crossing in the DTM goes through this one reviewed implementation. It is not suitable for single-cycle pulses; use the `meds_s1_cdc_toggle_src` / `_dst` pair for those.

## Interface contract

| Signal | Dir | Width | Meaning | Contract |
|---|---|---|---|---|
| `clk_i` | in | 1 | clock | destination domain only |
| `rst_ni` | in | 1 | reset | async assert; clears both stages |
| `async_i` | in | `WIDTH` | signal from another clock domain | must be held; a pulse shorter than one `clk_i` period can be missed |
| `sync_o` | out | `WIDTH` | synchronised copy | exactly two `clk_i` edges behind `async_i` |

**Handshake:** none. **Latency:** exactly two `clk_i` edges. **Backpressure:** none. **Reset state:** `sync_o` is 0, and the reset clears *both* stages so no stale value leaks out after release.

## Parameters

| Parameter | Default | Legal range | Effect |
|---|---|---|---|
| `WIDTH` | 1 | 1 and up | number of bits; each bit is synchronised independently |

## Behaviour

Two flops in series, both on `clk_i`. The first may go metastable; the second gives it a full cycle to resolve. Bits are independent, so a multi-bit `async_i` has no coherency guarantee between bits; it is only valid for buses whose bits are individually meaningful or quasi-static.

## Exceptions and errors

None. This module cannot fault.

## Verification status

| Layer | Status | Where |
|---|---|---|
| Lint | clean; shared-package `UNUSEDPARAM` waived centrally | `make lint` |
| Unit test | **891 checks**, run at three widths in one simulation (1, 8 and 33 bits; the single-bit and odd widths are the ones that break): reset, exact two-edge latency, a 256-sample random stream with no drops or duplicates, and an asynchronous reset that must clear both stages. | `verif/unit/tb_meds_s1_cdc_2ff.sv` |
| Co-simulation | not applicable until the Debug Module and core are attached |  |
| Formal | not yet |  |

## Known limitations

- Metastability is not modelled in RTL simulation; the two-flop structure is the mitigation and its MTBF depends on the technology and clock rates.
- No bit-to-bit coherency across a multi-bit `WIDTH`.

## Open questions

None.
