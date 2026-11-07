# `meds_s1_dmi_tck_if`

| | |
|---|---|
| **Status** | WIP |
| **Owner** | https://github.com/zakriakhan2 |
| **Backup** | *(assign at Phase-0 review)* |
| **Project** | R-06 (debug module) |
| **Spec** | SPEC §27.1 (debug); RISC-V External Debug Support Specification, DTM/DMI chapter |
| **Source** | `rtl/debug/meds_s1_dmi_tck_if.sv` |
| **Testbench** | `verif/unit/tb_meds_s1_dmi_tck_if.sv` — 686 checks |

## Purpose

The TCK-domain half of the DMI clock-domain crossing: the initiator of the 4-phase request/acknowledge handshake. It is split from the core-clock half so that each module has exactly one clock and one reset (R-N6), with every crossing made through a named synchroniser from `rtl/common/`.

## Interface contract

| Signal | Dir | Width | Meaning | Contract |
|---|---|---|---|---|
| `clk_i` | in | 1 | clock | `tck` |
| `rst_ni` | in | 1 | reset | `trst_n`; async assert |
| `dmi_req_i` | in | `DMI_REQ_W` | live DMI register contents | sampled into the snapshot only on `req_trigger_i` |
| `req_trigger_i` | in | 1 | accept this request | one cycle; only issued while `req_pending_o` is low |
| `hardreset_pulse_i` | in | 1 | DTMCS `dmihardreset` written | one cycle |
| `resp_valid_async_i` | in | 1 | core-domain response valid | asynchronous; synchronised inside |
| `req_pending_o` | out | 1 | no new request may start | high from the trigger until the whole handshake has returned to zero |
| `tck_ack_o` | out | 1 | synchronised acknowledge | two `clk_i` edges behind `resp_valid_async_i` |
| `req_latch_o` | out | `DMI_REQ_W` | stable request snapshot | unchanged while the request is valid |
| `req_valid_o` | out | 1 | request valid level | held until the acknowledge is seen (R-C10) |
| `hardreset_toggle_o` | out | 1 | hardreset toggle | to `meds_s1_cdc_toggle_dst` in the core half |

**Handshake:** 4-phase. `req_valid_o` rises on a trigger and stays high, with a stable `req_latch_o`, until `tck_ack_o` is seen. **Latency:** acknowledge arrives two edges after the core drops/raises `resp_valid`. **Reset state:** all outputs 0.

## Parameters

None.

## Behaviour

A trigger sets `req_valid_o` and snapshots the request into `req_latch_o`, so the debugger shifting the DMI register again cannot change an in-flight request. When the synchronised acknowledge appears, `req_valid_o` clears. `req_pending_o = req_valid_o | tck_ack_o` covers the **whole** round trip: if it covered only the request half, a new request could start while the acknowledge was still unwinding, and with a core clock slower than TCK that request is silently lost. The hardreset pulse goes through `meds_s1_cdc_toggle_src`, not a level synchroniser, so it is delivered at any clock ratio.

## Exceptions and errors

None raised here; an unacceptable request is rejected upstream in `meds_s1_dtm_dr_regs`.

## Verification status

| Layer | Status | Where |
|---|---|---|
| Lint | clean; shared-package `UNUSEDPARAM` waived centrally | `make lint` |
| Unit test | **686 checks**: the full handshake step by step, snapshot immunity, the window where `req_valid_o` is low but `req_pending_o` must stay high, per-cycle invariants over 120 random-latency transactions, hardreset toggle parity, and mid-transaction reset. | `verif/unit/tb_meds_s1_dmi_tck_if.sv` |
| Co-simulation | not applicable until the Debug Module and core are attached |  |
| Formal | not yet |  |

## Known limitations

- Exactly one request may be outstanding.

## Open questions

- None.
