# `meds_s1_dtm_dr_regs`

| | |
|---|---|
| **Status** | WIP |
| **Owner** | @your-github-handle |
| **Backup** | *(assign at Phase-0 review)* |
| **Project** | R-06 (debug module) |
| **Spec** | SPEC §27.1 (debug); RISC-V External Debug Support Specification, DTM/DMI chapter |
| **Source** | `rtl/debug/meds_s1_dtm_dr_regs.sv` |
| **Testbench** | `verif/unit/tb_meds_s1_dtm_dr_regs.sv` — 466 checks |

## Purpose

The data registers selected by the TAP: BYPASS, DTMCS, IDCODE and the unified 41-bit DMI register, plus the sticky `dmistat` error tracker, the response hold register and the central TDO multiplexer. DMI request and response share one physical shift register, as 1149.1 requires. It is separate from the TAP because it holds all of the DTM's debugger-visible state.

## Interface contract

| Signal | Dir | Width | Meaning | Contract |
|---|---|---|---|---|
| `clk_i` | in | 1 | clock | `tck` |
| `rst_ni` | in | 1 | reset | `trst_n`; async assert |
| `tdi_i` | in | 1 | test data in |  |
| `capture_dr_i`, `shift_dr_i`, `update_dr_i` | in | 1 each | TAP strobes | from `meds_s1_dtm_tap` |
| `shift_ir_i`, `ir_shift_tdo_i` | in | 1 each | IR shift state and bit | `shift_ir_i` takes priority at TDO |
| `sel_*_i` | in | 1 each | register select | one-hot, from `meds_s1_dtm_tap` |
| `stable_dmi_resp_i` | in | `DMI_RESP_W` | `{rdata, status}` from the core domain | quasi-static: sampled only on the rising edge of `tck_ack_i` |
| `tck_ack_i` | in | 1 | response-valid level | synchronised into `clk_i`; its rising edge latches the response |
| `req_pending_i` | in | 1 | a transaction is in flight | from `meds_s1_dmi_tck_if` |
| `tdo_o` | out | 1 | test data out | changes on the falling edge of `clk_i` |
| `stable_dmi_req_o` | out | `DMI_REQ_W` | live DMI shift register | latched by the bridge only on `dmi_req_trigger_o` |
| `dmi_req_trigger_o` | out | 1 | accept this request | one cycle, aligned with Update-DR |
| `dmihardreset_pulse_o` | out | 1 | DTMCS `dmihardreset` written | one cycle, aligned with Update-DR |

**Handshake:** a request is accepted only when `dmi_req_trigger_o` pulses. **Backpressure:** none; a request that cannot be accepted is dropped and reported through `dmistat`. **Reset state:** all registers 0 except IDCODE.

## Parameters

| Parameter | Default | Legal range | Effect |
|---|---|---|---|
| `IDCODE_VALUE` | `DTM_IDCODE_DEFAULT` | bit 0 must be 1 (1149.1) | 32-bit device identification, read through the IDCODE register |

## Behaviour

All four registers follow one hold rule: they change only on `sel_x && capture_dr_i` (parallel load) or `sel_x && shift_dr_i` (shift LSB first); otherwise they hold. DMI bit layout, LSB first: `[1:0]` op/status, `[33:2]` data, `[40:34]` address. **DTMCS** reads back version, `abits` (= `DMI_ABITS`), idle and `dmistat`; `dmireset` and `dmihardreset` always read 0 and act as write-1 triggers on Update-DR. **`dmistat`** is a sticky, first-error-wins field: `BUSY` when an Update-DR on DMI arrives while `req_pending_i`, `FAILED` on a failed response, cleared only by `dmireset`/`dmihardreset`, and never touched by a success. While it is non-zero, requests are dropped and Capture-DR returns the status with zeroed data. The response is held on the rising edge of `tck_ack_i`, so Capture-DR sees a stable value however much later it happens. Capture leaves the address bits `[40:34]` holding their last shifted value.

## Exceptions and errors

`dmistat` reports `BUSY` (a request arrived while one was pending) or `FAILED` (the core returned a failed status). The debugger must write DTMCS `dmireset` to clear it; until then DMI requests are silently dropped by design.

## Verification status

| Layer | Status | Where |
|---|---|---|
| Lint | clean; shared-package `UNUSEDPARAM` waived centrally | `make lint` |
| Unit test | **466 checks**: IDCODE, BYPASS and DTMCS contents, DMI request path, overrun, sticky and first-error-wins rules, response hold across an arbitrary delay and a changing bus, TDO priority, hold-when-unselected, asynchronous reset, and a 400-step randomised model of `dmistat` and the request gate. | `verif/unit/tb_meds_s1_dtm_dr_regs.sv` |
| Co-simulation | not applicable until the Debug Module and core are attached |  |
| Formal | not yet |  |

## Known limitations

- Idle cycles are reported as 0 (no extra Run-Test/Idle cycles are required).
- Capture-DR holds the address field rather than zeroing it; the debug specification allows either.
- A dropped request leaves no response of its own; the debugger learns of it only by reading `dmistat`.

## Open questions

- Should capture zero the address field instead of holding it?
