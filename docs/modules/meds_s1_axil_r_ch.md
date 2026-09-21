# `meds_s1_axil_r_ch`

| | |
|---|---|
| **Status** | COMPLETE |
| **Owner** | @EmanMaqsood5 |
| **Backup** | _(assign)_ |
| **Project** | T-04 (fabric) — shared register shell |
| **Spec** | SPEC §18, §20.2, §24; AXI IHI0022 |
| **Source** | `rtl/common/meds_s1_axil_r_ch.sv` |
| **Testbench** | covered through `verif/unit/tb_meds_s1_axil_reg_protocol.sv` |
## Purpose

Performs the register read for a captured address and answers the R channel. It is one of the five channel modules inside `meds_s1_axil_reg_protocol`; see that page for the full contract
and the diagrams.

## Interface contract

| Signal | Meaning | Contract |
|---|---|---|
| `clk_i`, `rst_ni` | clock, reset | single domain; async assert, sync de-assert |
| `ar_captured_*`, `ar_consume_o` | from/to `meds_s1_axil_ar_ch` |  |
| `rd_addr_o` | register read address |  |
| `rd_data_i`, `rd_addr_valid_i` | read result | combinational from `rd_addr_o` |
| `rdata_o`, `rresp_o`, `rvalid_o`, `rready_i` | AXI4-Lite R channel | OKAY or SLVERR |

**Handshake:** READY never depends on VALID (R-C10).
**Reset state:** idle, nothing captured.

## Parameters

| Parameter | Default | Legal range | Effect |
|---|---|---|---|
| `ADDR_WIDTH` | `AXIL_LOCAL_ADDR_W` (16) | 2..40 | address width |
| `DATA_WIDTH` | `AXIL_DATA_W` (32) | 32 | data width |

## Behaviour

R_IDLE → R_LOOKUP when an address is captured (consumed and registered) → R_RESP after one cycle, registering `rd_data_i` and choosing OKAY/SLVERR from `rd_addr_valid_i` → R_IDLE on RREADY.

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
