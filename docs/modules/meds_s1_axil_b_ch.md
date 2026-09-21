# `meds_s1_axil_b_ch`

| | |
|---|---|
| **Status** | COMPLETE |
| **Owner** | @EmanMaqsood5 |
| **Backup** | _(assign)_ |
| **Project** | T-04 (fabric) — shared register shell |
| **Spec** | SPEC §18, §20.2, §24; AXI IHI0022 |
| **Source** | `rtl/common/meds_s1_axil_b_ch.sv` |
| **Testbench** | covered through `verif/unit/tb_meds_s1_axil_reg_protocol.sv` |
## Purpose

Performs the register write once both address and data are captured, then answers the B channel. It is one of the five channel modules inside `meds_s1_axil_reg_protocol`; see that page for the full contract
and the diagrams.

## Interface contract

| Signal | Meaning | Contract |
|---|---|---|
| `clk_i`, `rst_ni` | clock, reset | single domain; async assert, sync de-assert |
| `aw_captured_*`, `aw_consume_o` | from/to `meds_s1_axil_aw_ch` |  |
| `w_captured_*`, `w_consume_o` | from/to `meds_s1_axil_w_ch` |  |
| `wr_addr_o`, `wr_data_o`, `wr_strb_o`, `wr_en_o` | register write port | `wr_en_o` is a single-cycle pulse |
| `wr_addr_valid_i` | offset implemented? | sampled while `wr_en_o` is high |
| `bresp_o`, `bvalid_o`, `bready_i` | AXI4-Lite B channel | OKAY or SLVERR |

**Handshake:** READY never depends on VALID (R-C10).
**Reset state:** idle, nothing captured.

## Parameters

| Parameter | Default | Legal range | Effect |
|---|---|---|---|
| `ADDR_WIDTH` | `AXIL_LOCAL_ADDR_W` (16) | 2..40 | address width |
| `DATA_WIDTH` | `AXIL_DATA_W` (32) | 32 | data width |

## Behaviour

B_IDLE → B_COMMIT when AW and W are both captured (both consumed, address/data/strobes registered) → B_RESP after one cycle with `wr_en_o` high, response chosen from `wr_addr_valid_i` → B_IDLE on BREADY.

## Exceptions and errors

Chooses OKAY or SLVERR from the register block's valid flag.

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
