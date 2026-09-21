# `meds_s1_axi4_r_ch`

| | |
|---|---|
| **Status** | COMPLETE |
| **Owner** | @EmanMaqsood5 |
| **Backup** | _(assign)_ |
| **Project** | T-04 (fabric) — shared register shell |
| **Spec** | SPEC §18, §20.2, §24; AXI IHI0022 |
| **Source** | `rtl/common/meds_s1_axi4_r_ch.sv` |
| **Testbench** | covered through `verif/unit/tb_meds_s1_axi4_reg_protocol.sv` |
## Purpose

Read-burst sequencer and R channel: looks up every beat of a burst on the register port and returns it with its own response. It is one of the five channel modules inside `meds_s1_axi4_reg_protocol`; see that page for the full contract
and the diagrams.

## Interface contract

| Signal | Meaning | Contract |
|---|---|---|
| `clk_i`, `rst_ni` | clock, reset | single domain; async assert, sync de-assert |
| `ar_captured_*`, `ar_consume_o` | from/to `meds_s1_axi4_ar_ch` |  |
| `rd_addr_o` | address of the current beat |  |
| `rd_data_i`, `rd_addr_valid_i` | read result | combinational from `rd_addr_o` |
| `rid_o`, `rdata_o`, `rresp_o`, `rlast_o`, `rvalid_o`, `rready_i` | AXI4 R channel | RLAST on beat `ARLEN` |

**Handshake:** READY never depends on VALID (R-C10).
**Reset state:** idle, nothing captured.

## Parameters

| Parameter | Default | Legal range | Effect |
|---|---|---|---|
| `ID_W` | `AXI_ID_W` (6) | 1..16 | set to `AXI_SID_W` (9) behind a crossbar slave port |

## Behaviour

R_IDLE → R_LOOKUP when AR is captured → R_RESP after one cycle (data and per-beat OKAY/SLVERR registered) → on RREADY either R_LOOKUP for the next beat, with the address stepped by `axi_next_addr()`, or R_IDLE after the last beat. The beat counter is 8 bits (1..256 beats).

## Exceptions and errors

Chooses OKAY or SLVERR from the register block's valid flag.

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
