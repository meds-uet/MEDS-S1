# `s1_irq_prio`

| | |
|---|---|
| **Status** | WIP — complete for the six standard interrupts; not yet wired to `s1_core`'s `irq_*` ports |
| **Owner** | @AbdurRahman020 |
| **Backup** | _(assign at Phase-0 review)_ |
| **Project** | T-03 CSR file, trap unit, privilege |
| **Spec** | SPEC §10.3; RISC-V Privileged Architecture `mip`/`mie`, `mideleg`, `sip`/`sie` |
| **Source** | `rtl/core/csr/s1_irq_prio.sv` |
| **Testbench** | `verif/unit/tb_s1_irq_prio.sv` — 10,485,774 checks |

## Purpose

This module chooses which interrupt, if any, the hart takes this cycle. It is a separate module so that the rule, which is the most error-prone part of interrupt handling, can be checked exhaustively in isolation. Its outputs are the shape of `s1_core`'s `irq_valid_i`/`irq_code_i`: a pending, enabled, already-prioritised interrupt.

## Interface contract

| Signal | Dir | Width | Meaning | Contract |
|---|---|---|---|---|
| `mip_i` | in | `XLEN` | `mip` | only bits 1, 3, 5, 7, 9, 11 are used; the rest are ignored |
| `mie_i` | in | `XLEN` | `mie` | same bits |
| `mideleg_i` | in | `XLEN` | `mideleg` | only bits 1, 5, 9, and only with S-mode |
| `mstatus_mie_i` | in | 1 | `mstatus.MIE` | |
| `mstatus_sie_i` | in | 1 | `mstatus.SIE` | ignored without S-mode |
| `priv_i` | in | `priv_lvl_e` | current privilege | the real mode, not the MPRV-effective one |
| `irq_valid_o` | out | 1 | an interrupt is to be taken | combinational |
| `irq_code_o` | out | 6 | its cause code (`mcause`/`scause` low field) | 0 when `irq_valid_o` is 0 |

**Handshake:** none. **Latency:** combinational. **Backpressure:** none. **Reset state:** stateless; it follows its inputs.

The output does not say *where* the interrupt goes. The trap unit decides that from `mideleg` and the mode, by the same rule as this module (a delegated cause from below M goes to S).

## Parameters

| Parameter | Default | Legal range | Effect |
|---|---|---|---|
| `S_MODE_PRESENT` | 0 | 0, 1 | 0: SEI, SSI and STI are ignored and nothing is delegated. Set it from the config (SPEC §5.3; only S1-Linux has S). |

## Behaviour

The rules and why each holds. Quotations are from the ratified Privileged Architecture v1.12; check the wording against the version the project pins.

1. **When an interrupt goes to M.** §3.1.9: *"An interrupt i will trap to M-mode … if all of the following are true: (a) either the current privilege mode is M and the MIE bit in the mstatus register is set, or the current privilege mode has less privilege than M-mode; (b) bit i is set in both mip and mie; and (c) if register mideleg exists, bit i is not set in mideleg."*
   - Implemented as `m_enabled = (priv != M) || MIE` and `to_m = pending & ~deleg`.
   - `mstatus.MIE` masks M interrupts only in M-mode. Below M they are always enabled, because a lower mode must not be able to block a more privileged interrupt.
2. **When an interrupt goes to S.** §4.1.3: *"An interrupt i will trap to S-mode if both of the following are true: (a) either the current privilege mode is S and the SIE bit in the sstatus register is set, or the current privilege mode has less privilege than S-mode; and (b) bit i is set in both sip and sie."*
   - `sip`/`sie` are the delegated bits of `mip`/`mie`, so this is `to_s = pending & deleg` with `s_enabled = (priv == U) || (priv == S && SIE)`.
   - In M-mode a delegated interrupt is not taken at all. Traps never go to a less privileged mode, so an interrupt delegated to S waits until the hart is below M.
3. **M-level interrupts are never delegated.**
   - This is a T-03 decision, not a spec quotation. `mideleg` has write mask `0x222` in `core_csr.yaml`, so its M bits are read-only zero, and this module masks `mideleg` with the S-level bits again. A stray bit therefore cannot send MEI, MSI or MTI to S.
   - Without S-mode the mask is 0 and nothing is delegated.
4. **Priority.** §3.1.9: *"Multiple simultaneous interrupts destined for M-mode are handled in the following decreasing priority order: MEI, MSI, MTI, SEI, SSI, STI."* §4.1.3: *"Multiple simultaneous interrupts destined for different privilege modes are handled in decreasing order of destined privilege mode."*
   - So every interrupt destined for M beats every interrupt destined for S. Within a destination the order is MEI > MSI > MTI > SEI > SSI > STI.
   - This refines ASSUMPTION-2: a non-delegated SSI (to M) beats a delegated SEI (to S), even though SEI is earlier in the flat list. The testbench's mutation check confirms the difference is observable.

## Exceptions and errors

None. An interrupt is reported, not raised: the trap unit takes it.

## Verification status

| Layer | Status | Where |
|---|---|---|
| Lint | clean (`-Wall`, S absent and present) | `make lint` |
| Unit test | 10,485,774 checks: exhaustive over the six standard bits of `mip`, `mie` and `mideleg` × mode × MIE × SIE, for S absent and present, with random non-standard bits; reference model written independently | `verif/unit/tb_s1_irq_prio.sv` |
| Co-simulation | not applicable yet | |
| Formal | none | |

The testbench was also run against three deliberately broken copies of the RTL: a flat priority list, M bits delegable, and SIE ignored. It failed on each.

## Known limitations

- Only the six standard interrupts are handled. Platform interrupts (16 and up) and LCOFI (13, Sscofpmf) are ignored.
- It is not instantiated yet. Wiring it between `s1_csr_file` and the trap unit, and to `s1_core`'s `irq_*`, is part of the port migration.
- `mip` is not yet driven by the CLINT/PLIC lines (`mip` is `hw_write` in the CSR table).

## Open questions

- ASSUMPTION-2 in `rtl/core/csr/csr_access_matrix.md`: confirm the destination-major reading of §10.3 with the architect.
