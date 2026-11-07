# `meds_s1_sram`

| | |
|---|---|
| **Status** | COMPLETE (behavioural); FPGA and ASIC variants TODO |
| **Owner** | _(assign at Phase-0 review)_ |
| **Backup** | _(assign)_ |
| **Project** | R-03 (caches, Zicbom and the SRAM wrapper) |
| **Spec** | SPEC §17, `specs/INTERFACES.md` §8, ADR-0005 |
| **Source** | `rtl/common/meds_s1_sram.sv` |
| **Testbench** | TODO — R-03 |

## Purpose

The single-port SRAM wrapper. **Every array in MEDS-S1 goes through this module** — register file,
cache tags, cache data, TLB, VRF, any FIFO deeper than 32 entries. No exceptions.

The rule exists so an ASIC port is a matter of writing one `IMPL` variant rather than hunting thirty
inferred arrays with thirty different latency assumptions. It costs nothing today. Enforced by
`scripts/check_structure.py` rule S7.

## Interface contract

| Signal | Dir | Width | Meaning | Contract |
|---|---|---|---|---|
| `clk_i` | in | 1 | clock | single domain |
| `rst_ni` | in | 1 | reset | async assert, sync de-assert; clears `rdata_o` only |
| `req_i` | in | 1 | access request | |
| `we_i` | in | 1 | write enable | qualified by `req_i` |
| `addr_i` | in | `AW` | word address | `AW = $clog2(DEPTH)` |
| `be_i` | in | `DW/8` | byte enables | writes only |
| `wdata_i` | in | `DW` | write data | |
| `rdata_o` | out | `DW` | read data | **valid exactly one cycle after `req_i`** |

**Latency: one cycle, registered output, everywhere. No exceptions.** A mixed-latency memory system
is where timing closure and verification both go to die.

**Read-during-write returns OLD contents.** Stated deliberately rather than left to the technology —
consumers needing write-forwarding must build it themselves.

**Memory contents are not reset.** Only `rdata_o` is. Consumers must not assume zeroed memory at
power-on; a cache must clear its valid bits itself.

## Parameters

| Parameter | Default | Legal range | Effect |
|---|---|---|---|
| `DW` | 64 | multiple of 8 | data width |
| `DEPTH` | 1024 | ≥ 1 | words |
| `IMPL` | 0 | 0, 1, 2 | 0 behavioural, 1 FPGA BRAM, 2 ASIC macro |
| `AW` | derived | — | do not override |

`IMPL` 1 and 2 currently raise an elaboration-time `$error`. A clear failure beats silently
synthesising the behavioural model into a bitstream.

## Verification status

| Layer | Status | Where |
|---|---|---|
| Lint | clean | `make lint` |
| Unit test | **TODO — R-03** | `verif/unit/tb_meds_s1_sram.sv` |
| Formal | not yet | |

## Known limitations

- Single port only. A dual-port variant (`meds_s1_sram_dp`) will be needed for the register file if
  two read ports cannot be met by duplication — an R-03 decision.
- `IMPL = 1` (FPGA BRAM) is required before the KC705 port can meet timing; T-08 depends on it.

## Open questions

- Does the register file duplicate this wrapper for its second read port, or do we add a dual-port
  variant? Duplication costs area, a second variant costs another ASIC port. **R-03 owns this.**
