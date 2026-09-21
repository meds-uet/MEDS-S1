# `meds_s1_axi4_ar_ch`

| | |
|---|---|
| **Status** | COMPLETE |
| **Owner** | @EmanMaqsood5 |
| **Backup** | _(assign)_ |
| **Project** | T-04 (fabric) — shared register shell |
| **Spec** | SPEC §18, §20.2, §24; AXI IHI0022 |
| **Source** | `rtl/common/meds_s1_axi4_ar_ch.sv` |
| **Testbench** | covered through `verif/unit/tb_meds_s1_axi4_reg_protocol.sv` |
## Purpose

Holds one AXI4 read-burst descriptor (ID, address, ARLEN, ARSIZE, ARBURST) until `meds_s1_axi4_r_ch` takes it. It is one of the five channel modules inside `meds_s1_axi4_reg_protocol`; see that page for the full contract
and the diagrams.

## Interface contract

| Signal | Meaning | Contract |
|---|---|---|
| `clk_i`, `rst_ni` | clock, reset | single domain; async assert, sync de-assert |
| `arid_i` … `arburst_i`, `arvalid_i`, `arready_o` | AXI4 AR channel | READY high whenever empty |
| `ar_captured_id_o`, `_addr_o`, `_len_o`, `_size_o`, `_burst_o` | captured descriptor | stable while `ar_captured_o` is high |
| `ar_captured_o` | a burst is held |  |
| `ar_consume_i` | release the descriptor | from `meds_s1_axi4_r_ch` |

**Handshake:** READY never depends on VALID (R-C10).
**Reset state:** idle, nothing captured.

## Parameters

| Parameter | Default | Legal range | Effect |
|---|---|---|---|
| `ID_W` | `AXI_ID_W` (6) | 1..16 | set to `AXI_SID_W` (9) behind a crossbar slave port |

## Behaviour

AR_IDLE (READY high) → AR_CAPTURED on ARVALID → AR_IDLE on `ar_consume_i`. WRAP bursts are captured as-is; the wrapping address arithmetic lives in `meds_s1_axi4_r_ch`.

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
