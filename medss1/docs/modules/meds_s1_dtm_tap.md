# `meds_s1_dtm_tap`

| | |
|---|---|
| **Status** | WIP |
| **Owner** | @your-github-handle |
| **Backup** | *(assign at Phase-0 review)* |
| **Project** | R-06 (debug module) |
| **Spec** | SPEC §27.1 (debug); RISC-V External Debug Support Specification, DTM/DMI chapter |
| **Source** | `rtl/debug/meds_s1_dtm_tap.sv` |
| **Testbench** | `verif/unit/tb_meds_s1_dtm_tap.sv` — 70571 checks |

## Purpose

The IEEE 1149.1 TAP controller, the 5-bit instruction register and the instruction decoder for the JTAG debug transport. It is separate from the data registers because it is the only part that sees TMS; everything downstream is driven by its capture/shift/update strobes and one-hot register selects.

## Interface contract

| Signal | Dir | Width | Meaning | Contract |
|---|---|---|---|---|
| `clk_i` | in | 1 | clock | `tck` |
| `rst_ni` | in | 1 | reset | `trst_n`; async assert |
| `tms_i` | in | 1 | test mode select | sampled on the rising edge of `clk_i` |
| `tdi_i` | in | 1 | test data in | sampled on the rising edge of `clk_i` |
| `capture_dr_o` | out | 1 | TAP is in Capture-DR | Moore decode of the current state |
| `shift_dr_o` | out | 1 | TAP is in Shift-DR | Moore decode |
| `update_dr_o` | out | 1 | TAP is in Update-DR | Moore decode; exactly one cycle |
| `shift_ir_o` | out | 1 | TAP is in Shift-IR | selects the IR bit onto TDO in the data-register block |
| `ir_shift_tdo_o` | out | 1 | serial-out bit of the IR shift register | meaningful only while `shift_ir_o` |
| `sel_bypass_o`, `sel_dtmcs_o`, `sel_dmi_o`, `sel_idcode_o` | out | 1 each | instruction decode | exactly one is high; any unimplemented opcode selects BYPASS |

**Handshake:** none. **Latency:** strobes follow the state register; the decode follows the IR update on the falling edge. **Reset state:** Test-Logic-Reset, IR = IDCODE.

## Parameters

None.

## Behaviour

The 16-state IEEE 1149.1 FSM advances on the rising edge of `clk_i`. Capture-IR loads the fixed pattern `DTM_IR_CAPTURE_VAL` (low bits `01`, as 1149.1 requires) and Shift-IR shifts `tdi_i` in LSB first. The instruction that takes effect, `ir_reg`, is latched on the **falling** edge during Update-IR so it settles before the next rising edge. Entering Test-Logic-Reset restores the IR to IDCODE, so a debugger that resets with five TMS=1 clocks always finds IDCODE selected. Opcodes are `DTM_IR_*` in `meds_s1_dtm_pkg`.

## Exceptions and errors

None. An illegal opcode is not an error: it selects BYPASS, as the standard recommends.

## Verification status

| Layer | Status | Where |
|---|---|---|
| Lint | clean; shared-package `UNUSEDPARAM` waived centrally | `make lint` |
| Unit test | **70,571 checks** against an independent reference model of the 1149.1 state table over a 6000-cycle random walk that visits all 16 states, plus directed checks: Capture-IR pattern, one-hot decode, Test-Logic-Reset reachable from any state in five TMS=1 clocks, TLR resets the IR, asynchronous `trst_n` mid-scan. | `verif/unit/tb_meds_s1_dtm_tap.sv` |
| Co-simulation | not applicable until the Debug Module and core are attached |  |
| Formal | not yet |  |

## Known limitations

- The IR update is on the falling edge of `clk_i`, so `clk_i` must have a usable 50% duty cycle at the clock rates in use.

## Open questions

- None.
