# `meds_s1_dmi_core_if`

| | |
|---|---|
| **Status** | WIP |
| **Owner** | @your-github-handle |
| **Backup** | *(assign at Phase-0 review)* |
| **Project** | R-06 (debug module) |
| **Spec** | SPEC §27.1 (debug); RISC-V External Debug Support Specification, DTM/DMI chapter |
| **Source** | `rtl/debug/meds_s1_dmi_core_if.sv` |
| **Testbench** | `verif/unit/tb_meds_s1_dmi_core_if.sv` — 1978 checks |

## Purpose

The core-clock half of the DMI crossing, containing the Bridge FSM that turns a request into `dm_read_o` / `dm_write_o` strobes for the Debug Module and captures its response. It also receives the hardreset and derives a hardreset-aware reset for its own flops.

## Interface contract

| Signal | Dir | Width | Meaning | Contract |
|---|---|---|---|---|
| `clk_i` | in | 1 | clock | `core_clk` |
| `rst_ni` | in | 1 | reset | external active-low reset; async assert |
| `req_latch_i` | in | `DMI_REQ_W` | stable request snapshot | quasi-static while `req_valid_async_i` is high |
| `req_valid_async_i` | in | 1 | request valid level | asynchronous; synchronised inside |
| `hardreset_toggle_i` | in | 1 | hardreset toggle | asynchronous |
| `resp_valid_async_o` | out | 1 | response valid level | high for the whole COMPLETED state |
| `resp_data_o` | out | `DMI_RESP_W` | `{rdata, status}` | captured once; quasi-static while valid |
| `dm_addr_o`, `dm_wdata_o` | out | `DMI_ABITS`, `DMI_DATA_W` | request to the Debug Module | stable for the whole access |
| `dm_write_o`, `dm_read_o` | out | 1 each | access strobes | high during ACCESS only; never both |
| `dm_rdata_i` | in | `DMI_DATA_W` | read data | sampled on the edge `dm_ready_i` is seen |
| `dm_ready_i` | in | 1 | access complete | must be asserted for a read or write; not needed for NOP or a reserved op |

**Handshake:** `resp_valid_async_o` is held until the request's deassert has crossed back. Strobe, address and data do not depend on `dm_ready_i` and stay stable until it arrives (R-C10). **Latency:** request to strobe in three `core_clk` edges. **Reset state:** FSM idle, response 0.

## Parameters

None.

## Behaviour

IDLE → ACCESS when the synchronised request is seen, then COMPLETED when `dm_ready_i` arrives, then IDLE once the request drops. A NOP, or a **reserved opcode**, goes straight from IDLE to COMPLETED without involving the Debug Module: a NOP returns an all-zero success response; a reserved opcode returns status `FAILED`, so the debugger sees the bad request. Without the reserved-op path the FSM would wait forever for a `dm_ready` that no read or write ever requested. The response register captures once on the edge into COMPLETED, so a Debug Module whose data bus changes straight afterwards cannot corrupt it. A hardreset aborts the access, clears the FSM and synchroniser, and, because the request is still asserted, restarts it.

## Exceptions and errors

Status is `SUCCESS` for a completed access or NOP and `FAILED` for a reserved opcode. There is no `dm_error` input, so a Debug Module failure cannot yet be reported.

## Verification status

| Layer | Status | Where |
|---|---|---|
| Lint | clean; shared-package `UNUSEDPARAM` waived centrally | `make lint` |
| Unit test | **1978 checks**: exact crossing latency, strobes matching the op, payload stable until `dm_ready_i`, response captured once and held, NOP completing with no `dm_ready_i`, a hardreset landing in idle, ACCESS and COMPLETED, a reserved opcode terminating, asynchronous reset, and 80 random accesses. | `verif/unit/tb_meds_s1_dmi_core_if.sv` |
| Co-simulation | not applicable until the Debug Module and core are attached |  |
| Formal | not yet |  |

## Known limitations

- No `dm_error` input.
- The response status is only ever `SUCCESS` or `FAILED` from this module; `BUSY` comes from the TCK side.

## Open questions

- Should the Debug Module be able to report an error back, adding a `dm_error_i` port?
- The module derives its own reset through `meds_s1_dmi_rst_gen` (R-C4 reviewers may prefer it one level up).
