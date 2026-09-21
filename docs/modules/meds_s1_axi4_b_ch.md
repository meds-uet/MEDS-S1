# `meds_s1_axi4_b_ch`

| | |
|---|---|
| **Status** | COMPLETE |
| **Owner** | @EmanMaqsood5 |
| **Backup** | _(assign)_ |
| **Project** | T-04 (fabric) — shared register shell |
| **Spec** | SPEC §18, §20.2, §24; AXI IHI0022 |
| **Source** | `rtl/common/meds_s1_axi4_b_ch.sv` |
| **Testbench** | covered through `verif/unit/tb_meds_s1_axi4_reg_protocol.sv` |
## Purpose

Write-burst sequencer and B channel: writes every beat of a burst to the register port, steps the address, and returns one B for the whole burst. It is one of the five channel modules inside `meds_s1_axi4_reg_protocol`; see that page for the full contract
and the diagrams.

## Interface contract

| Signal | Meaning | Contract |
|---|---|---|
| `clk_i`, `rst_ni` | clock, reset | single domain; async assert, sync de-assert |
| `aw_captured_*`, `aw_consume_o` | from/to `meds_s1_axi4_aw_ch` | `aw_consume_o` pulses on the last beat |
| `w_captured_*`, `w_consume_o` | from/to `meds_s1_axi4_w_ch` | `w_captured_last_i` is unused (see limitations) |
| `wr_addr_o`, `wr_data_o`, `wr_strb_o`, `wr_en_o` | register write port | one `wr_en_o` pulse per beat |
| `wr_addr_valid_i` | address implemented? | sampled with each `wr_en_o` |
| `bid_o`, `bresp_o`, `bvalid_o`, `bready_i` | AXI4 B channel | ID echoed; OKAY or SLVERR |

**Handshake:** READY never depends on VALID (R-C10).
**Reset state:** idle, nothing captured.

## Parameters

| Parameter | Default | Legal range | Effect |
|---|---|---|---|
| `ID_W` | `AXI_ID_W` (6) | 1..16 | set to `AXI_SID_W` (9) behind a crossbar slave port |

## Behaviour

B_IDLE → B_BEAT when AW is captured (address, ID registered; beat count and error flag cleared). In B_BEAT each captured W beat pulses `wr_en_o`, ORs `!wr_addr_valid_i` into the error flag and steps the address with `axi_next_addr()`. After beat `AWLEN` → B_RESP → B_IDLE on BREADY. The beat counter is 8 bits, so every legal length (1..256) works.

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

The last beat is found by counting `AWLEN + 1` beats, which AXI makes authoritative. `w_captured_last_i` is carried for a future protocol checker and waived as unused in `verif/verilator.vlt`; a master that sends a wrong WLAST is not detected.

## Open questions

None.
