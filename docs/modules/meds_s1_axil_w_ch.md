# `meds_s1_axil_w_ch`

| | |
|---|---|
| **Status** | COMPLETE |
| **Owner** | @EmanMaqsood5 |
| **Backup** | _(assign)_ |
| **Project** | T-04 (fabric) — shared register shell |
| **Spec** | SPEC §18, §20.2, §24; AXI IHI0022 |
| **Source** | `rtl/common/meds_s1_axil_w_ch.sv` |
| **Testbench** | covered through `verif/unit/tb_meds_s1_axil_reg_protocol.sv` |
## Purpose

Holds one AXI4-Lite write data word and its strobes until `meds_s1_axil_b_ch` uses them. It is one of the five channel modules inside `meds_s1_axil_reg_protocol`; see that page for the full contract
and the diagrams.

## Interface contract

| Signal | Meaning | Contract |
|---|---|---|
| `clk_i`, `rst_ni` | clock, reset | single domain; async assert, sync de-assert |
| `wdata_i`, `wstrb_i`, `wvalid_i`, `wready_o` | AXI4-Lite W channel | READY high whenever empty |
| `w_captured_data_o`, `w_captured_strb_o` | captured data and strobes | stable while `w_captured_o` is high |
| `w_captured_o` | a word is held |  |
| `w_consume_i` | release the word | from `meds_s1_axil_b_ch` |

**Handshake:** READY never depends on VALID (R-C10).
**Reset state:** idle, nothing captured.

## Parameters

| Parameter | Default | Legal range | Effect |
|---|---|---|---|
| `DATA_WIDTH` | `AXIL_DATA_W` (32) | 32 | data width |

## Behaviour

W_IDLE (READY high) → W_CAPTURED on WVALID → W_IDLE on `w_consume_i`. Accepting W before AW is allowed.

## Exceptions and errors

None — this module only stores a request.

## Verification status

| Layer | Status | Where |
|---|---|---|
| Lint | clean, all four configs (`make lint`) | |
| Unit test (via top) | 408 checks | `verif/unit/tb_meds_s1_axil_reg_protocol.sv` |
| Co-simulation | not applicable | |
| Formal | not yet | |

## Known limitations

Only reachable through its top level; it is an internal building block of `meds_s1_axil_reg_protocol`, not meant to be instantiated on its own.

## Open questions

None.
