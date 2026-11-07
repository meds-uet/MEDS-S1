# `meds_s1_dtm_top`

| | |
|---|---|
| **Status** | WIP |
| **Owner** | https://github.com/zakriakhan2 |
| **Backup** | *(assign at Phase-0 review)* |
| **Project** | R-06 (debug module) |
| **Spec** | SPEC §27.1 (debug); RISC-V External Debug Support Specification, DTM/DMI chapter |
| **Source** | `rtl/debug/meds_s1_dtm_top.sv` |
| **Testbench** | `verif/unit/tb_meds_s1_dtm_top.sv` — 24518 checks |

## Purpose

Top level of the JTAG debug transport module. Purely structural: it wires the TAP, data registers and the two halves of the DMI crossing together and exposes the JTAG pins on one side and the Debug Module interface on the other. It is the one place where the TCK and core clock domains meet.

## Interface contract

| Signal | Dir | Width | Meaning | Contract |
|---|---|---|---|---|
| `tck_i` | in | 1 | JTAG clock | TCK domain |
| `trst_n_i` | in | 1 | TAP reset | async active-low |
| `tms_i`, `tdi_i` | in | 1 each | JTAG inputs |  |
| `tdo_o` | out | 1 | JTAG output | changes on the falling edge of `tck_i` |
| `core_clk_i` | in | 1 | core clock | core domain |
| `dmi_rst_n_i` | in | 1 | core-domain reset | async active-low |
| `dm_addr_o`, `dm_wdata_o` | out | `DMI_ABITS`, `DMI_DATA_W` | request to the Debug Module | see `meds_s1_dmi_core_if` |
| `dm_write_o`, `dm_read_o` | out | 1 each | access strobes |  |
| `dm_rdata_i`, `dm_ready_i` | in | `DMI_DATA_W`, 1 | response from the Debug Module |  |

**R-N6 exception:** this is the only module with two clocks and two resets, because it is the boundary between two clock domains; every leaf module inside it has exactly one. The port names `trst_n_i` and `dmi_rst_n_i` follow R-N3/R-N4 (`_n` before the direction suffix).

**Debug Module side:** the Debug Module expects exactly `dm_read_o`, `dm_write_o` and `dm_ready_i` (confirmed by the project owner), so this interface is a strobe and acknowledge rather than AXI-style valid/ready. The strobes never depend combinationally on `dm_ready_i`, which is the property R-C10 protects.

## Parameters

| Parameter | Default | Legal range | Effect |
|---|---|---|---|
| `IDCODE_VALUE` | `DTM_IDCODE_DEFAULT` | bit 0 must be 1 | device identification, forwarded to `meds_s1_dtm_dr_regs` |

## Behaviour

Instantiates `meds_s1_dtm_tap`, `meds_s1_dtm_dr_regs`, `meds_s1_dmi_tck_if` and `meds_s1_dmi_core_if` and connects them by name. It contains no logic of its own. The response bus from the core half to the data registers crosses the boundary as a quasi-static bus, sampled only after the synchronised acknowledge confirms it is stable.

## Exceptions and errors

None at this level.

## Verification status

| Layer | Status | Where |
|---|---|---|
| Lint | clean; shared-package `UNUSEDPARAM` waived centrally | `make lint` |
| Unit test | **24,518 checks** across three TCK:core clock ratios in one run (the default, the core 20x slower than TCK, and the core 8x faster), because the request/acknowledge collision hazard only shows as a lost write when the core is slower than TCK: a JTAG probe on the real pins and a behavioural Debug Module with memory, random latency and a stall control. IDCODE, DTMCS, BYPASS, write/read-back, overrun, sticky errors, `dmireset` versus `dmihardreset` (delivery observed), and a sweep of the second request across every phase of the first. | `verif/unit/tb_meds_s1_dtm_top.sv` |
| Co-simulation | not applicable until the Debug Module and core are attached |  |
| Formal | not yet |  |

## Known limitations

- The Debug Module itself is not part of this block; it is a black box behind the `dm_*` ports.
- Single outstanding request.

## Open questions

None.
