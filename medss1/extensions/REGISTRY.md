# Extension Registry

**Single source of truth for every allocation that must not collide.** Adding a row is a PR that
requires an architect's approval (`specs/INTERFACES.md` §10).

---

## 1. Custom instruction opcode space

RISC-V reserves four major opcodes for non-standard use. MEDS-S1 allocates them as follows.

| Major opcode | Encoding | Reserved for | Status |
|---|---|---|---|
| `custom-0` | `0x0B` | tightly-coupled compute over MXIF (activations, quantisation, posit) | free |
| `custom-1` | `0x2B` | domain-specific ISA thesis projects | free |
| `custom-2` | `0x5B` | reserved — do not allocate without an ADR | reserved |
| `custom-3` | `0x7B` | experimental / student sandbox, never in a release | free |

### Allocated instructions

| Name | Opcode | funct3 | funct7 | Owner | Extension dir | Status |
|---|---|---|---|---|---|---|
| _(none yet)_ | | | | | | |

> v1.0 ships the **mechanism**, not instances. Shipping the mechanism with zero instances proves it
> is general; shipping one instance proves nothing (`SCOPE_CONTRACT.md` §3).

---

## 2. CSR allocation

**Prefer standard CSRs over custom ones, always.** MEDS-V's use of the ratified `vtype`/`vl`/`vlenb`
is the model. Custom CSRs use the standard custom ranges.

| Address | Name | Access | Owner | Purpose |
|---|---|---|---|---|
| `0x7C0` | `meds_s1_version` | RO | platform | `{major[15:0], minor[15:0]}` — lets software identify its hardware |
| `0x800`–`0x8FF` | | RW-U | unallocated | user-mode custom |
| `0xBC0`–`0xBFF` | | RW-M | unallocated | machine-mode custom |

Coprocessor-owned CSRs are routed through the external CSR port (SPEC §10.2) and are listed here
even though the core does not implement them:

| Address | Name | Owner |
|---|---|---|
| `0x008` | `vstart` | MEDS-V |
| `0x009` | `vxsat` | MEDS-V |
| `0x00A` | `vxrm` | MEDS-V |
| `0x00F` | `vcsr` | MEDS-V |
| `0xC20` | `vl` | MEDS-V |
| `0xC21` | `vtype` | MEDS-V |
| `0xC22` | `vlenb` | MEDS-V |

---

## 3. Accelerator IDs

Every accelerator exposes its ID at offset `0x00` of its MMIO window (SPEC §20.2), so the BSP can
enumerate the bus without accelerator-specific code.

| ID | Accelerator | Owner | Repo | Status |
|---|---|---|---|---|
| `0x0000` | reserved — "no accelerator" | — | — | reserved |
| `0x0001` | `meds-x-conv` — INT8 convolution engine | _(unassigned)_ | `meds-s1-accelerators` | proposed |
| `0x0002`+ | unallocated | | | |

---

## 4. Interrupt IDs

Allocated in `configs/*.yaml` and generated into the device tree and C headers. **Never
hand-assigned in two places.**

| ID range | Reserved for |
|---|---|
| `0` | no interrupt (PLIC convention) |
| `1`–`15` | platform peripherals |
| `16`–`31` | accelerator sockets |
| `32`+ | expansion |

| ID | Source | Config |
|---|---|---|
| 1 | `uart0` | all |
| 2 | `spi0` | `s1_base`+ |
| 3 | `gpio0` | `s1_base`+ |
| 4 | `timer0` | `s1_base`+ |
| 16 | socket 0 | `s1_base`+ |
| 17 | socket 1 | `s1_ai`+ |

---

## 5. Adding a custom instruction — the seven required artefacts

**Nothing merges without all seven** (SPEC §19.5). This checklist is what makes MXIF an extension
*mechanism* rather than a reserved opcode.

| # | Artefact | Location |
|---|---|---|
| 1 | riscv-opcodes-format encoding | `extensions/<name>/<name>.opcodes` |
| 2 | Allocation row in this file | `extensions/REGISTRY.md` |
| 3 | Golden-reference model (Spike plugin or Sail patch) | `extensions/<name>/model/` |
| 4 | Toolchain path — `.insn` macro + inline-asm header minimum | `extensions/<name>/sw/` |
| 5 | RISCOF-format tests against the model from (3) | `extensions/<name>/tests/` |
| 6 | CSR allocation row, if any | `extensions/REGISTRY.md` §2 |
| 7 | `README.md`: semantics, latency, exceptions, `fence` interaction | `extensions/<name>/` |

Copy `extensions/template/` to start.
