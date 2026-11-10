# `s1_csr_legalize`

| | |
|---|---|
| **Status** | WIP — current rules predate ASSUMPTION-1 and -3 |
| **Owner** | @AbdurRahman020 |
| **Backup** | _(assign at Phase-0 review)_ |
| **Project** | T-03 CSR file, trap unit, privilege |
| **Spec** | SPEC §10.2; RISC-V privileged spec WARL fields |
| **Source** | `rtl/core/csr/s1_csr_legalize.sv` |
| **Testbench** | covered through `verif/unit/tb_s1_csr_file.sv` |

## Purpose

This is purely combinational logic that turns a software write into a legal value for CSR fields that a write mask alone cannot handle (WARL). It is the only hand-written per-address logic in the CSR path. `s1_csr_file` routes a write here only when the CSR's `has_warl` bit in `s1_csr_pkg::CSR_TABLE` is set.

## Interface contract

| Signal | Dir | Width | Meaning | Contract |
|---|---|---|---|---|
| `csr_addr_i` | in | 12 | address of the CSR being written | |
| `wdata_i` | in | `XLEN` | write data, already masked by `write_mask` | the caller masks first |
| `legal_wdata_o` | out | `XLEN` | the value to store | equals `wdata_i` for any CSR without a rule |

**Handshake:** none. **Latency:** combinational. **Backpressure:** none. **Reset state:** stateless.

## Parameters

None. The datapath width is `s1_pkg::XLEN`.

## Behaviour

| CSR | Rule today |
|---|---|
| `mtvec` (0x305), `stvec` (0x105) | MODE ≥ 2 becomes Direct (00); BASE is unchanged |
| `mstatus` (0x300) | an MPP that is not U (00) or M (11) becomes U |

## Exceptions and errors

None. A WARL write never traps; it is legalised.

## Verification status

| Layer | Status | Where |
|---|---|---|
| Lint | clean | `make lint` |
| Unit test | the mtvec MODE and MPP checks in the CSR file testbench | `verif/unit/tb_s1_csr_file.sv` |
| Co-simulation | not applicable yet | |
| Formal | none | |

## Known limitations

- **ASSUMPTION-3 is not implemented.** It says a MODE ≥ 2 write keeps the *previous* MODE. This module has no previous-value input, so it forces Direct instead.
- **MPP never accepts S, even with `S_MODE_PRESENT = 1`.** It also accepts U on S1-Nano, which has no U-mode (ASSUMPTION-1).
- **The rules are keyed on hard-coded addresses**, not on generated constants.

## Open questions

- Add a previous-value input (`storage` of the CSR) and config parameters, so the rules can follow ASSUMPTION-1 and -3.
