# `rtl/debug/` — JTAG debug transport module and DMI bridge

## What lives here

The debug transport: the JTAG TAP controller, the DTM data registers, the clock-domain crossing between TCK and the core clock with its Bridge FSM, the reset generator it uses, and `meds_s1_dtm_pkg.sv`, which holds the DTM/DMI constants and encodings.

## What does *not* live here

The Debug Module itself (abstract commands, `dmcontrol`, halt/resume). It sits behind the `dm_*` ports of `meds_s1_dtm_top`. Generic synchronisers live in `rtl/common/`, not here.

## How to add something

Add `<module>.sv`, add `verif/unit/tb_<module>.sv`, add a page under `docs/modules/`, and add a row to the table below. Every clock-domain crossing goes through a synchroniser in `rtl/common/` (R-C9); never hand-write one. A constant or encoding that two modules must agree on goes in `meds_s1_dtm_pkg.sv`.

## Catalogue projects that land here

R-06 debug module (DTM and DMI bridge)

## Module status

Status tags follow CODING_STANDARD.md §5.

| Module | Status | Project | Testbench | Docs |
|---|---|---|---|---|
| `meds_s1_dtm_pkg.sv` | WIP | R-06 | n/a | shared constants |
| `meds_s1_dmi_rst_gen.sv` | COMPLETE | R-06 | `tb_meds_s1_dmi_rst_gen` (1014 checks) | [page](../../docs/modules/meds_s1_dmi_rst_gen.md) |
| `meds_s1_dtm_tap.sv` | WIP | R-06 | `tb_meds_s1_dtm_tap` (70571 checks) | [page](../../docs/modules/meds_s1_dtm_tap.md) |
| `meds_s1_dtm_dr_regs.sv` | WIP | R-06 | `tb_meds_s1_dtm_dr_regs` (466 checks) | [page](../../docs/modules/meds_s1_dtm_dr_regs.md) |
| `meds_s1_dmi_tck_if.sv` | WIP | R-06 | `tb_meds_s1_dmi_tck_if` (686 checks) | [page](../../docs/modules/meds_s1_dmi_tck_if.md) |
| `meds_s1_dmi_core_if.sv` | WIP | R-06 | `tb_meds_s1_dmi_core_if` (1978 checks) | [page](../../docs/modules/meds_s1_dmi_core_if.md) |
| `meds_s1_dtm_top.sv` | WIP | R-06 | `tb_meds_s1_dtm_top` (24518 checks) | [page](../../docs/modules/meds_s1_dtm_top.md) |

## Rules specific to this directory

- Every leaf module has exactly one clock and one reset. Only `meds_s1_dtm_top` has two, because it is the boundary between the two domains.
- A signal crossing between domains is a held level through `meds_s1_cdc_2ff`, a pulse through `meds_s1_cdc_toggle_src` / `_dst`, or a quasi-static bus qualified by a synchronised handshake level.
- Reset logic is generated only in `meds_s1_dmi_rst_gen` (R-C4).

---

*Conventions: [docs/guidelines/CODING_STANDARD.md](../../docs/guidelines/CODING_STANDARD.md) · Definition of done: [EXECUTION_PLAN.md](../../EXECUTION_PLAN.md) §8*
