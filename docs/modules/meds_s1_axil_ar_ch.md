# `meds_s1_axil_ar_ch`

| | |
|---|---|
| **Status** | COMPLETE |
| **Owner** | @EmanMaqsood5 |
| **Backup** | _(assign)_ |
| **Project** | T-04 (fabric) — shared register shell |
| **Spec** | SPEC §18, §20.2, §24; AXI IHI0022 |
| **Source** | `rtl/common/meds_s1_axil_ar_ch.sv` |
| **Testbench** | covered through `verif/unit/tb_meds_s1_axil_reg_protocol.sv` |
## Purpose

Holds one AXI4-Lite read address until `meds_s1_axil_r_ch` uses it. It is one of the five channel modules inside `meds_s1_axil_reg_protocol`; see that page for the full contract
and the diagrams.

## Interface contract

| Signal | Meaning | Contract |
|---|---|---|
| `clk_i`, `rst_ni` | clock, reset | single domain; async assert, sync de-assert |
| `araddr_i`, `arvalid_i`, `arready_o` | AXI4-Lite AR channel | READY high whenever empty |
| `ar_captured_addr_o` | captured address | stable while `ar_captured_o` is high |
| `ar_captured_o` | a request is held |  |
| `ar_consume_i` | release the request | from `meds_s1_axil_r_ch` |

**Handshake:** READY never depends on VALID (R-C10).
**Reset state:** idle, nothing captured.

## Parameters

| Parameter | Default | Legal range | Effect |
|---|---|---|---|
| `ADDR_WIDTH` | `AXIL_LOCAL_ADDR_W` (16) | 2..40 | captured address width |

## Behaviour

AR_IDLE (READY high) → AR_CAPTURED on ARVALID → AR_IDLE on `ar_consume_i`.

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
