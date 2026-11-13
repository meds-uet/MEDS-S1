# `s1_csr_file`

| | |
|---|---|
| **Status** | WIP — access checks in place; `s1_core` port migration pending |
| **Owner** | @AbdurRahman020 |
| **Backup** | _(assign at Phase-0 review)_ |
| **Project** | T-03 CSR file, trap unit, privilege |
| **Spec** | SPEC §10.1, §10.2, Appendix C |
| **Source** | `rtl/core/csr/s1_csr_file.sv` |
| **Testbench** | `verif/unit/tb_s1_csr_file.sv` |

## Purpose

This module holds the core's CSR state and decides whether each CSR access is legal. Decode, storage, masks and access rules all come from the generated `s1_csr_pkg::CSR_TABLE`, which is built from `rtl/core/defines/core_csr.yaml`. Adding or changing a CSR is a YAML edit and a regeneration, with no change to this RTL. The access rules are designed in `rtl/core/csr/csr_access_matrix.md`.

## Interface contract

| Signal | Dir | Width | Meaning | Contract |
|---|---|---|---|---|
| `clk_i` | in | 1 | clock | single domain |
| `rst_ni` | in | 1 | reset | async assert, sync de-assert; every CSR takes its `reset_val` |
| `csr_addr_i` | in | 12 | CSR address of the access | held for the cycle the read data is wanted |
| `csr_wdata_i` | in | `XLEN` | the final value to write | the caller has already done the CSRRW/RS/RC read-modify-write |
| `csr_we_i` | in | 1 | write intent | must be 0 for CSRRS/CSRRC with rs1 = x0 (or uimm = 0), so that reading a read-only CSR stays legal |
| `priv_i` | in | `priv_lvl_e` | privilege of the accessing instruction | the current mode, not the MPRV-effective mode |
| `hw_we_i[4]`, `hw_addr_i[4]`, `hw_wdata_i[4]` | in | 1, 12, `XLEN` | trap-unit state writes | raw: no mask, no access check; they win over a software write on the same edge |
| `csr_rdata_o` | out | `XLEN` | read data for the address of the **previous** cycle | `(storage \| ro_const) & view_mask`; 0 on a decode miss |
| `csr_illegal_o` | out | 1 | the access is illegal | **combinational** on `csr_addr_i`, `csr_we_i`, `priv_i` |
| `trap_mstatus_o` … `trap_stvec_o` | out | `XLEN` | raw storage taps for the trap unit | no read-only constants applied |
| `trap_dcsr_o`, `trap_dpc_o` | out | `XLEN` | debug taps | `dcsr`/`dpc` are deferred, so these read `storage[0]` (0) |
| `ext_csr_addr_o`, `ext_csr_wdata_o`, `ext_csr_we_o` | out | 12, `XLEN`, 1 | external CSR port (§10.2) | `we` only for a legal write to an external CSR; none are decoded yet |
| `ext_csr_rdata_i` | in | `XLEN` | external read data | returned when the previous cycle's address was external |

**Handshake:** none. An access is a single cycle.
**Latency:** `csr_illegal_o` is combinational. `csr_rdata_o` is registered, one cycle behind `csr_addr_i`.
**Backpressure:** none.
**Reset state:** `csr_rdata_o` = 0 and every CSR holds its table `reset_val`. `csr_illegal_o` follows the current address.

## Parameters

| Parameter | Default | Legal range | Effect |
|---|---|---|---|
| `U_MODE_PRESENT` | 1 | 0, 1 | enables CSRs gated on U (`menvcfg`) and the `ro_const_if_u` bits (`mstatus.UXL`, `misa.U`) |
| `S_MODE_PRESENT` | 0 | 0, 1 | enables CSRs gated on S (S CSRs, `medeleg`, `mideleg`), `wmask_if_s` bits and `ro_const_if_s` bits (`mstatus.SXL`) |
| `PMP_REGIONS` | `s1_pkg::PMP_N` | 0–16 | 0 makes PMP-gated CSRs illegal (all PMP CSRs are deferred today) |

Set them from the config (SPEC §5.3):

| Config | `U_MODE_PRESENT` | `S_MODE_PRESENT` | `PMP_REGIONS` |
|---|---|---|---|
| S1-Nano | 0 | 0 | 0 |
| S1-Base / S1-AI | 1 | 0 | 16 |
| S1-Linux | 1 | 1 | 16 |

## Behaviour

- **Decode.** `csr_addr_i` is matched against `CSR_TABLE`. Only `impl`, `ro_zero` and `alias_of` CSRs are in the table. Absent, deferred and external CSRs miss the decoder, so they are illegal.
- **Access check.** An access is illegal if any of these hold:
  - the address is not decoded;
  - it is config-gated off;
  - `priv_i < min_priv`;
  - it is a write to a `read_only` CSR;
  - the CSR is `debug_only` (always illegal, because Debug Mode is not implemented).
- **Writes.**
  - A legal software write changes only the `write_mask` bits (plus `wmask_if_s` with S); every other bit keeps its value.
  - CSRs with `has_warl` go through `s1_csr_legalize` first.
  - An illegal write has no side effect: no storage change and no external write.
  - `misa` and `ro_zero` CSRs accept writes legally and ignore them.
- **Aliases.** `sstatus`, `sie` and `sip` use the storage of `view_of` (`mstatus`, `mie`, `mip`). They show only `view_mask` and write only their own `write_mask`.
- **Reads.** Storage is ORed with the read-only constants for the config (`mstatus.UXL/SXL`, `misa`, `meds_s1_version`), then masked by `view_mask` for an alias. Storage is never set outside the writable bits, so no write-mask is needed on the read.

## Exceptions and errors

`csr_illegal_o` = 1 means the caller must raise illegal-instruction (cause 2) and must not commit the write. The module drops the write itself as well.

## Verification status

| Layer | Status | Where |
|---|---|---|
| Lint | clean in isolation (`verilator -Wall`) | `make lint` |
| Unit test | 30 checks, 25 pass; the 5 failures are stale expectations (see Known limitations) | `verif/unit/tb_s1_csr_file.sv` |
| Co-simulation | not applicable yet | |
| Formal | none | |

## Known limitations

- **Ports are not the `s1_core` set yet.** The `s1_core` set is `csr_re`, a combinational `csr_rdata`, `csr_commit` (`csr_upd_t`), `trap_req_t`, `mret`, `trap_vec`, `mepc`, `priv_*` and `irq_*`. Migration waits for the owner of `trap_req_t`/`csr_upd_t`; they are defined in open PR #14, not on `main`.
- **There is no `csr_re_i`.** Every addressed cycle counts as an access.
- **xRET.**
  - This module cannot turn an `mret` from below M into an illegal-instruction trap. EX does not query the CSR file for xRET, and `s1_core`'s `mret_o` merges MRET, SRET and DRET.
  - The refusal will be a state-only refusal (no privilege or `mstatus` change).
  - The trap itself needs the core-side fix raised on PR #21. See `csr_access_matrix.md` ASSUMPTION-9.
- **`mhartid` reads 0.** A `HART_ID` parameter is not wired yet.
- **The counter-enable and `satp`/TVM checks** are added when counters and S-mode land.
- **Stale unit-test expectations.** With the defaults, `tb_s1_csr_file` expects:
  - `mstatus` = 0, but `UXL=2` now reads back;
  - writable `medeleg`/`mideleg`, but they are S-gated.
- **The `stvec` MODE check passes vacuously**, because its write is suppressed.

## Open questions

See `rtl/core/csr/csr_access_matrix.md` ASSUMPTION-1 to 18.
