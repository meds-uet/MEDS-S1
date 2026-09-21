# `meds_s1_axi4_w_ch`

| | |
|---|---|
| **Status** | COMPLETE |
| **Owner** | @EmanMaqsood5 |
| **Backup** | _(assign)_ |
| **Project** | T-04 (fabric) — shared register shell |
| **Spec** | SPEC §18, §20.2, §24; AXI IHI0022 |
| **Source** | `rtl/common/meds_s1_axi4_w_ch.sv` |
| **Testbench** | covered through `verif/unit/tb_meds_s1_axi4_reg_protocol.sv` |
## Purpose

Holds one 256-bit AXI4 write beat (data, strobes, WLAST) until `meds_s1_axi4_b_ch` commits it; refilled once per beat. It is one of the five channel modules inside `meds_s1_axi4_reg_protocol`; see that page for the full contract
and the diagrams.

## Interface contract

| Signal | Meaning | Contract |
|---|---|---|
| `clk_i`, `rst_ni` | clock, reset | single domain; async assert, sync de-assert |
| `wdata_i`, `wstrb_i`, `wlast_i`, `wvalid_i`, `wready_o` | AXI4 W channel | READY high whenever empty |
| `w_captured_data_o`, `_strb_o`, `_last_o` | captured beat | stable while `w_captured_o` is high |
| `w_captured_o` | a beat is held |  |
| `w_consume_i` | release the beat | pulsed by `meds_s1_axi4_b_ch` with `wr_en_o` |

**Handshake:** READY never depends on VALID (R-C10).
**Reset state:** idle, nothing captured.

## Parameters

None beyond the widths in `meds_s1_axi4_pkg`.

## Behaviour

W_IDLE (READY high) → W_CAPTURED on WVALID → W_IDLE on `w_consume_i`. Holding only one beat limits write throughput to one beat every two cycles.

## Exceptions and errors

None — this module only stores a request.

## Verification status

| Layer | Status | Where |
|---|---|---|
| Lint | clean, all four configs (`make lint`) | |
| Unit test (via top) | 13457 checks | `verif/unit/tb_meds_s1_axi4_reg_protocol.sv` |
| Co-simulation | not applicable | |
| Formal | not yet | |

## Known limitations

Only reachable through its top level; it is an internal building block of `meds_s1_axi4_reg_protocol`, not meant to be instantiated on its own.

## Open questions

None.
