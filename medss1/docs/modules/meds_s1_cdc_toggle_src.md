# `meds_s1_cdc_toggle_src`

| | |
|---|---|
| **Status** | COMPLETE |
| **Owner** | https://github.com/zakriakhan2 |
| **Backup** | *(assign at Phase-0 review)* |
| **Project** | R-06 (debug module) |
| **Spec** | SPEC §27.1 (debug); RISC-V External Debug Support Specification, DTM/DMI chapter |
| **Source** | `rtl/common/meds_s1_cdc_toggle_src.sv` |
| **Testbench** | `verif/unit/tb_meds_s1_cdc_toggle_src.sv` — 532 checks |

## Purpose

Source half of a rate-independent pulse synchronizer. It turns each one-cycle pulse into a level *toggle*, which can cross a clock boundary safely however slow the receiving clock is. A plain level synchronizer would miss a pulse narrower than the destination period; a toggle cannot be missed.

## Interface contract

| Signal | Dir | Width | Meaning | Contract |
|---|---|---|---|---|
| `clk_i` | in | 1 | clock | source domain only |
| `rst_ni` | in | 1 | reset | async assert |
| `pulse_i` | in | 1 | event to transmit | one `clk_i` cycle wide; consecutive cycles each count |
| `toggle_o` | out | 1 | toggles once per `pulse_i` cycle | asynchronous to the destination; consume only through `meds_s1_cdc_toggle_dst` |

**Handshake:** none. **Latency:** one `clk_i` edge. **Reset state:** `toggle_o` is 0. **Spacing:** successive pulses must be far enough apart that `toggle_o` is stable for several destination periods, otherwise two toggles can merge (see `meds_s1_cdc_toggle_dst`).

## Parameters

None.

## Behaviour

A single flop that inverts on every cycle `pulse_i` is high and otherwise holds. The parity of the toggle therefore always equals the parity of the number of pulses sent, which is what the destination recovers.

## Exceptions and errors

None.

## Verification status

| Layer | Status | Where |
|---|---|---|
| Lint | clean; shared-package `UNUSEDPARAM` waived centrally | `make lint` |
| Unit test | **532 checks**: reset value, exactly one flip per pulse cycle, a 512-cycle random stream including back-to-back pulses, and asynchronous reset. | `verif/unit/tb_meds_s1_cdc_toggle_src.sv` |
| Co-simulation | not applicable until the Debug Module and core are attached |  |
| Formal | not yet |  |

## Known limitations

- Does not itself prevent two pulses arriving closer together than the destination can resolve; that is a contract on the caller.

## Open questions

None.
