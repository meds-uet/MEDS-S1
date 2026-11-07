# `meds_s1_cdc_toggle_dst`

| | |
|---|---|
| **Status** | COMPLETE |
| **Owner** | https://github.com/zakriakhan2 |
| **Backup** | *(assign at Phase-0 review)* |
| **Project** | R-06 (debug module) |
| **Spec** | SPEC §27.1 (debug); RISC-V External Debug Support Specification, DTM/DMI chapter |
| **Source** | `rtl/common/meds_s1_cdc_toggle_dst.sv` |
| **Testbench** | `verif/unit/tb_meds_s1_cdc_toggle_dst.sv` — 20 checks |

## Purpose

Destination half of the rate-independent pulse synchronizer. It synchronises the incoming toggle with `meds_s1_cdc_2ff`, then edge-detects it to produce exactly one `clk_i`-wide pulse for each pulse sent by `meds_s1_cdc_toggle_src`, whatever the ratio between the two clocks.

## Interface contract

| Signal | Dir | Width | Meaning | Contract |
|---|---|---|---|---|
| `clk_i` | in | 1 | clock | destination domain only |
| `rst_ni` | in | 1 | reset | async assert |
| `toggle_i` | in | 1 | toggle from `meds_s1_cdc_toggle_src` | asynchronous; must be stable for at least two `clk_i` edges between changes |
| `pulse_o` | out | 1 | one pulse per source pulse | exactly one `clk_i` cycle wide |

**Handshake:** none. **Latency:** `pulse_o` is high for the cycle after the second `clk_i` edge following a toggle change. **Reset state:** `pulse_o` is 0, and nothing is emitted by coming out of reset.

## Parameters

None.

## Behaviour

`toggle_i` goes through `meds_s1_cdc_2ff`; a further flop delays the synchronised value by one cycle; `pulse_o` is the XOR of the two, so it is high for exactly one cycle per toggle edge. Delivery is independent of the clock ratio provided pulses respect the spacing contract.

## Exceptions and errors

None.

## Verification status

| Layer | Status | Where |
|---|---|---|
| Lint | clean; shared-package `UNUSEDPARAM` waived centrally | `make lint` |
| Unit test | **20 checks**, run end to end with the source half at four clock ratios (destination faster, slower, equal and non-integer): no pulse out of reset, every pulse delivered exactly once, none wider than one cycle, nothing left asserted after draining. | `verif/unit/tb_meds_s1_cdc_toggle_dst.sv` |
| Co-simulation | not applicable until the Debug Module and core are attached |  |
| Formal | not yet |  |

## Known limitations

- Pulses closer together than the spacing contract can merge. The testbench keeps them at least four destination periods apart.

## Open questions

None.
