# CSR access-control matrix

| | |
|---|---|
| **Status** | DRAFT — defaults recorded below; open questions go to the architect |
| **Project** | T-03 CSR file, trap unit, privilege |
| **Source of truth** | `rtl/core/defines/core_csr.yaml` (this page explains it) |
| **Generated** | `rtl/generated/s1_csr_pkg.sv` by `gen/s1_csr_gen.py` |
| **Spec** | SPEC §5.3, §10.1–10.3, Appendix C; RISC-V privileged spec §2.1–2.2 |

## Columns

| Column | Meaning | Filled by |
|---|---|---|
| `name`, `addr` | CSR name and 12-bit address | privileged spec; `extensions/REGISTRY.md` §2 for custom CSRs |
| `min_priv` | lowest mode that may access it | `addr[9:8]`: 0 U, 1 S, 3 M (2 is the hypervisor range; rejected) |
| `read_only` | a write is illegal | `addr[11:10] == 3`; an RO CSR in a read/write range needs `ro_override` |
| `debug_only` | only accessible in Debug Mode | `addr` in `0x7B0–0x7BF` |
| `presence` | `impl`, `ro_zero`, `alias_of`, `absent`, `deferred`, `external` | see below |
| `config_gate` | the CSR exists only on configs with this feature: `U`, `S`, `PMP` | SPEC §5.3 |
| `reset` | value after `rst_ni` | privileged spec where fixed; otherwise 0 (ASSUMPTION-12) |
| `wmask` | writable bits on every config | WPRI and read-only-zero bits are 0 |
| `wmask_if_S` | extra writable bits on configs with S-mode | ASSUMPTION-1 |
| `ro_const` | read-only bits that read as 1 (`ro_const_if_U`, `ro_const_if_S` for config-dependent ones) | ASSUMPTION-1, -8 |
| `hw_write` | written by trap entry, xRET or interrupt lines, bypassing `wmask` | trap unit, PLIC/CLINT |

Presence values:

- `impl`: decoded, has storage or a constant value.
- `ro_zero`: decoded and legal, reads 0, ignores writes.
- `alias_of`: decoded and legal. It is a view of another CSR's storage (`view_of`, `view_mask`).
- `absent`: does not exist, so any access is illegal.
- `deferred`: will exist, but its owner has not landed yet. It is not decoded, so any access is illegal for now (ASSUMPTION-5).
- `external`: owned by a coprocessor and reached through the §10.2 external port. It is not in the core table and is illegal until that port exists (ASSUMPTION-6).

Only `impl`, `ro_zero` and `alias_of` are emitted into `CSR_TABLE`. Every other address misses the decoder.

## `csr_illegal_o` rules

`csr_illegal_o` is combinational on the EX query (`csr_addr_i`, `csr_re_i`, `csr_we_i`). Privilege is the current mode `priv_o`, not the MPRV-effective mode.

```
illegal = (csr_re_i || csr_we_i) && (
     !decoded(addr)                                   // absent, deferred, external, unlisted
  || (gate_u   && !U_PRESENT)
  || (gate_s   && !S_PRESENT)
  || (gate_pmp && PMP_REGIONS == 0)
  || (priv < min_priv)
  || (csr_we_i && read_only)
  || (debug_only && !debug_mode)                      // always illegal until debug lands
)
```

- An access to a `ro_zero` CSR, or a write to `misa` (WARL, `wmask` 0), is legal; the write is ignored.
- Read value: `(storage & wmask_eff) | ro_const_eff`, where:
  - `wmask_eff = wmask | (S_PRESENT ? wmask_if_S : 0)`
  - `ro_const_eff = ro_const | (U_PRESENT ? ro_const_if_U : 0) | (S_PRESENT ? ro_const_if_S : 0)`
- An alias reads `view_of & view_mask`, and its write changes only the `wmask` bits of `view_of`.
- Added when the counters land: a U/S read of a counter shadow also needs the matching `mcounteren` / `scounteren` bit.
- Added with S-mode: `satp` from S with `mstatus.TVM = 1` is illegal.
- `mret` with `priv_o != PRIV_M` changes no state. The illegal-instruction trap is a core issue (ASSUMPTION-9).

## Matrix

`–` means not applicable or 0. Ranges collapse rows whose fields are identical.

| name | addr | min_priv | read_only | debug_only | presence | config_gate | reset | wmask | wmask_if_S | ro_const | hw_write |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `mvendorid` | 0xF11 | M | yes | no | ro_zero | – | 0 | 0 | – | – | no |
| `marchid` | 0xF12 | M | yes | no | ro_zero | – | 0 | 0 | – | – | no |
| `mimpid` | 0xF13 | M | yes | no | ro_zero | – | 0 | 0 | – | – | no |
| `mhartid` | 0xF14 | M | yes | no | impl | – | `HART_ID` param | 0 | – | – | no |
| `mstatus` | 0x300 | M | no | no | impl | – | 0 | 0x21888 MPRV MPP MPIE MIE | 0x122 SPP SPIE SIE | UXL=2 if U; SXL=2 if S | yes |
| `misa` | 0x301 | M | no (WARL) | no | impl | – | – | 0 | – | MXL=2, I, M, C; U if U; A per config | no |
| `medeleg` | 0x302 | M | no | no | impl | S | 0 | 0xB3FF | – | – | no |
| `mideleg` | 0x303 | M | no | no | impl | S | 0 | 0x222 | – | – | no |
| `mie` | 0x304 | M | no | no | impl | – | 0 | 0x888 MEIE MTIE MSIE | 0x222 SEIE STIE SSIE | – | no |
| `mtvec` | 0x305 | M | no | no | impl (WARL) | – | 0 | all | – | – | no |
| `mcounteren` | 0x306 | M | no | no | deferred | U | | | | | |
| `menvcfg` | 0x30A | M | no | no | ro_zero | U | 0 | 0 | – | – | no |
| `mcountinhibit` | 0x320 | M | no | no | deferred | – | | | | | |
| `mhpmevent3–15` | 0x323–0x32F | M | no | no | deferred | – | | | | | |
| `mscratch` | 0x340 | M | no | no | impl | – | 0 | all | – | – | no |
| `mepc` | 0x341 | M | no | no | impl | – | 0 | all but bit 0 | – | – | yes |
| `mcause` | 0x342 | M | no | no | impl | – | 0 | all | – | – | yes |
| `mtval` | 0x343 | M | no | no | impl | – | 0 | all | – | – | yes |
| `mip` | 0x344 | M | no | no | impl | – | 0 | 0 | 0x222 SEIP STIP SSIP | – | yes |
| `pmpcfg0`, `pmpcfg2` | 0x3A0, 0x3A2 | M | no | no | deferred | PMP | | | | | |
| `pmpcfg1`, `pmpcfg3` | 0x3A1, 0x3A3 | M | no | no | absent | – | | | | | |
| `pmpaddr0–15` | 0x3B0–0x3BF | M | no | no | deferred | PMP | | | | | |
| `mcycle` | 0xB00 | M | no | no | deferred | – | | | | | |
| `minstret` | 0xB02 | M | no | no | deferred | – | | | | | |
| `mhpmcounter3–15` | 0xB03–0xB0F | M | no | no | deferred | – | | | | | |
| `sstatus` | 0x100 | S | no | no | alias_of `mstatus`, view 0x80000003000DE762 | S | – | 0x122 | – | – | via `mstatus` |
| `sie` | 0x104 | S | no | no | alias_of `mie`, view 0x222 | S | – | 0x222 | – | – | no |
| `stvec` | 0x105 | S | no | no | impl (WARL) | S | 0 | all | – | – | no |
| `scounteren` | 0x106 | S | no | no | deferred | S | | | | | |
| `sscratch` | 0x140 | S | no | no | impl | S | 0 | all | – | – | no |
| `sepc` | 0x141 | S | no | no | impl | S | 0 | all but bit 0 | – | – | yes |
| `scause` | 0x142 | S | no | no | impl | S | 0 | all | – | – | yes |
| `stval` | 0x143 | S | no | no | impl | S | 0 | all | – | – | yes |
| `sip` | 0x144 | S | no | no | alias_of `mip`, view 0x222 | S | – | 0x2 SSIP | – | – | via `mip` |
| `satp` | 0x180 | S | no | no | ro_zero | S | 0 | 0 | – | – | no |
| `cycle` | 0xC00 | U | yes | no | deferred | – | | | | | |
| `time` | 0xC01 | U | yes | no | absent | – | | | | | |
| `instret` | 0xC02 | U | yes | no | deferred | – | | | | | |
| `hpmcounter3–15` | 0xC03–0xC0F | U | yes | no | deferred | – | | | | | |
| `tselect`, `tdata1–3` | 0x7A0–0x7A3 | M | no | no | deferred | – | | | | | |
| `dcsr`, `dpc`, `dscratch0–1` | 0x7B0–0x7B3 | M | no | yes | deferred | – | | | | | |
| `meds_s1_version` | 0x7C0 | M | yes (`ro_override`) | no | impl | – | – | 0 | – | 0x0000_0100 | no |
| MEDS-V `vstart`, `vxsat`, `vxrm`, `vcsr` | 0x008–0x00A, 0x00F | U | no | no | external | – | | | | | |
| MEDS-V `vl`, `vtype`, `vlenb` | 0xC20–0xC22 | U | yes | no | external | – | | | | | |

The MEDS-V rows are listed for completeness only. They belong in `extensions/<name>/csr.yaml`, not the core table.

## Assumptions

Each assumption is the default used now. The question under it is what to ask the architect.

**ASSUMPTION-1 — S-mode and U-mode are config-gated (SPEC §5.3).**
- S1-Nano has M; S1-Base and S1-AI have M+U; S1-Linux has M+S+U.
- The S CSRs, `medeleg` and `mideleg` exist only with S. The S bits of `mstatus`, `mie` and `mip` come from `wmask_if_S`.
- `UXL=2` only with U, and `SXL=2` only with S.
- On S1-Nano, `MPRV` is read-only zero and `MPP` is fixed at M. That is a legaliser rule, not a table column.
- Question: §10.1 says S CSRs are "present, stubbed" in v1.0. Does that mean present on every config, or only on S1-Linux? The privileged spec says S CSRs, `medeleg` and `mideleg` must not exist without S.

**ASSUMPTION-2 — Interrupt priority is MEI > MSI > MTI > SEI > SSI > STI.**
- Following the privileged spec, every interrupt destined for M beats every interrupt destined for S. The list applies within each destination (`s1_irq_prio`).
- Question: §10.3 reads "external > software > timer, M > S". Is privilege the major key, as in the privileged spec?

**ASSUMPTION-3 — `mtvec` / `stvec` support Direct and Vectored.**
- A write with MODE ≥ 2 leaves MODE unchanged and still writes BASE.
- Question: is Vectored required in v1.0? §10 is silent; PR #37 says `trap_vec_i` may depend on the trap request "for vectored interrupts".

**ASSUMPTION-4 — PMP on RV64.**
- `pmpcfg1` and `pmpcfg3` are absent, because odd `pmpcfg` CSRs exist only on RV32.
- The PMP CSRs are gated on `PMP_REGIONS != 0`. Their storage owner is deferred to R-02.
- Question: Appendix C lists `pmpcfg0–3`, but every config is RV64. Can the list be corrected? Who owns PMP storage: the CSR file or the PMP checker?

**ASSUMPTION-5 — Deferred CSRs are illegal for now.**
- Deferred: the counters, `mcounteren`, `scounteren`, `mcountinhibit`, the user shadows, `tselect`/`tdata1–3`, and `dcsr`/`dpc`/`dscratch0–1`.
- Debug-only CSRs are illegal outside Debug Mode, and Debug Mode does not exist yet.
- Question: is a temporary illegal-instruction trap on these acceptable until the counters and debug land?

**ASSUMPTION-6 — `time` is absent, and the MEDS-V CSRs are external.**
- A read of `time` traps, so M-mode can emulate it from the CLINT.
- The MEDS-V CSRs are not in the core table and are illegal until the §10.2 external port exists. PR #37 has no such port.
- Question: should `time` read the CLINT `mtime` directly? Is the external port still mandatory for v1.0 (§10.2)?

**ASSUMPTION-7 — `meds_s1_version` stays at 0x7C0 with an explicit read-only override.**
- Conflict 1: 0x7C0 is in the custom **read/write** M range (`addr[11:10] = 01`). A read-only custom M CSR belongs in 0xFC0–0xFFF.
- Conflict 2: REGISTRY.md gives the format `{major[15:0], minor[15:0]}`, but INTERFACES.md gives the value `32'h0000_0100`, which in that format is 0.256.
- Question: move it to 0xFC0? Which format is meant?

**ASSUMPTION-8 — `misa` and the ID CSRs.**
- `misa` is read-only: MXL=2; I, M, C on every config; U with U-mode. A comes from the config ISA (S1-Nano is RV64IMC).
- `misa.S` is 0 on every config, per §10.1.
- `mvendorid`, `marchid` and `mimpid` read 0. `mhartid` comes from a `HART_ID` parameter.
- Question: `misa.S = 0` on S1-Linux contradicts the privileged spec if S-mode is implemented there. Which wins? Is a `marchid` value allocated?

**ASSUMPTION-9 — There is no illegal-instruction path for xRET.**
- EX queries the CSR file only for Zicsr instructions. WB redirects to `mepc_i` on any xRET, and `mret_o` is MRET | SRET | DRET.
- So a U-mode `mret` cannot become an illegal-instruction trap from the CSR file. The CSR file only refuses the state change.
- Question for the core owner: check privilege for xRET in EX (or WB), and split `mret_o` from `sret`/`dret`.

**ASSUMPTION-10 — `menvcfg` is `ro_zero` on configs with U.**
- Question: which fields are implemented? CBIE, CBCFE and CBZE matter because Zicbom/Zicboz are in the ISA (§5.3, §7.4).

**ASSUMPTION-11 — `satp` is `ro_zero` (Bare only) on S1-Linux until Sv39 lands.**
- A write with any other MODE is ignored, as the privileged spec requires for an unsupported MODE.
- Question: §10.1 says "satp writable but translation bypassed". Writable how, if only Bare is legal?

**ASSUMPTION-12 — Reset values.**
- The privileged spec fixes only priv = M, `mstatus.MIE = 0`, `mstatus.MPRV = 0`, `misa`, and PMP `A`/`L` = 0.
- Every other reset value is 0, including `mtvec` and `mcause`.
- Question: is there a required `mtvec` reset value, for example the boot ROM?

**ASSUMPTION-13 — `mstatus` fields beyond MIE, MPIE, MPP, MPRV and the S trap bits are read-only zero.**
- That covers SUM, MXR, TVM, TSR, TW, FS, VS, XS, SD, SBE, MBE and UBE.
- Question: are TW, TVM, TSR, SUM and MXR required on S1-Base/S1-Linux? Does MEDS-V need `mstatus.VS`?

**ASSUMPTION-14 — `sip` writes only SSIP; M-mode can write SEIP, STIP and SSIP in `mip` with S.**
- Question: none; this follows the privileged spec. Confirm it is wanted.

**ASSUMPTION-15 — Privileged-spec CSRs outside Appendix C are not added and stay illegal.**
- These are `mconfigptr` (0xF15), `pmpaddr16–63`, even `pmpcfg4–14`, and `mhpmcounter`/`mhpmevent`/`hpmcounter16–31`.
- Question: the privileged spec (1.12+) expects these to exist (read-only zero where unimplemented). Can Appendix C be extended?

**ASSUMPTION-16 — Naming of the generator input.**
- The input is `core_csr.yaml`, and the generated header says `DO NOT EDIT -- generated from core_csr.yaml`.
- Question: §10.2 names the input `csr_list.yaml`, and Appendix D's header text says "generated from soc.yaml". Which name is normative?

**ASSUMPTION-17 — S1-Nano has CSRs.**
- Question: §5.3 lists S1-Nano as RV64IMC with no Zicsr, but traps need `mtvec`/`mepc`/`mcause`. Is Zicsr implied?

**ASSUMPTION-18 — The CSR file keeps its state in flops, not `meds_s1_sram`.**
- Trap entry writes several CSRs in one cycle (four `hw_*` slots on one edge), and `s1_core` reads `csr_rdata` combinationally. A `meds_s1_sram` read is registered with one-cycle latency (INTERFACES.md §8), so it cannot serve either.
- `rtl/core/csr/s1_csr_file.sv` is therefore exempt from structure check S7 (R-C5) in `scripts/check_structure.py`.
- Question: is this acceptable under INTERFACES.md §8 / R-C5?
