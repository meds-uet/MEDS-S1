# `meds_s1_axi4_aw_ch`

| | |
|---|---|
| **Status** | COMPLETE |
| **Owner** | @EmanMaqsood5 |
| **Backup** | _(assign)_ |
| **Project** | T-04 (fabric) — shared register shell |
| **Spec** | SPEC §18, §20.2, §24; AXI IHI0022 |
| **Source** | `rtl/common/meds_s1_axi4_aw_ch.sv` |
| **Testbench** | covered through `verif/unit/tb_meds_s1_axi4_reg_protocol.sv` |
## Purpose

Holds one full AXI4 burst descriptor (ID, address, AWLEN, AWSIZE, AWBURST) until the whole write burst has been committed by `meds_s1_axi4_b_ch`. It is one of the five channel modules inside `meds_s1_axi4_reg_protocol`; see that page for the full contract
and the diagrams.

## Interface contract

| Signal | Meaning | Contract |
|---|---|---|
| `clk_i`, `rst_ni` | clock, reset | single domain; async assert, sync de-assert |
| `awid_i` … `awburst_i`, `awvalid_i`, `awready_o` | AXI4 AW channel | READY high whenever empty |
| `aw_captured_id_o`, `_addr_o`, `_len_o`, `_size_o`, `_burst_o` | captured descriptor | stable while `aw_captured_o` is high |
| `aw_captured_o` | a burst is held |  |
| `aw_consume_i` | release the descriptor | pulsed by `meds_s1_axi4_b_ch` on the last beat |

**Handshake:** READY never depends on VALID (R-C10).
**Reset state:** idle, nothing captured.

## Parameters

| Parameter | Default | Legal range | Effect |
|---|---|---|---|
| `ID_W` | `AXI_ID_W` (6) | 1..16 | set to `AXI_SID_W` (9) behind a crossbar slave port |

## Behaviour

AW_IDLE (READY high) → AW_CAPTURED on AWVALID → AW_IDLE on `aw_consume_i`. The descriptor stays held for the entire burst because B_CH needs the length, size and burst type on every beat.

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
