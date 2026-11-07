// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// meds_s1_dtm_tap : JTAG TAP controller, IR and instruction decoder    [WIP -- R-06]
//
// IEEE 1149.1 TAP Controller + 5-bit Instruction Register + Instruction
// Decoder. One clock/reset (R-N6): clk_i/rst_ni here are tck/trst_n_i.
//
// Timing: FSM state, IR capture and IR shift all update on posedge clk_i.
// The IR "update"/architectural register updates on negedge clk_i so it
// settles cleanly before the next posedge, in line with TDO changing on
// the falling edge per standard 1149.1 practice. It is also restored to
// IDCODE whenever the FSM is in Test-Logic-Reset, not only on trst_n_i.
//
// Contract: IEEE 1149.1 TAP state graph; RISC-V External Debug Support
// Specification for the 5-bit instruction encodings (s1_pkg).
//
// Reference: RISC-V External Debug Support Specification (DTM/DMI);
// contract in docs/modules/meds_s1_dtm_tap.md.
// =============================================================================

module meds_s1_dtm_tap
  import meds_s1_dtm_pkg::*;
(
  input  logic clk_i,
  // async active-low TAP reset
  input  logic rst_ni,
  input  logic tms_i,
  input  logic tdi_i,

  output logic capture_dr_o,
  output logic shift_dr_o,
  output logic update_dr_o,

  output logic shift_ir_o,
  output logic ir_shift_tdo_o,

  output logic sel_bypass_o,
  output logic sel_dtmcs_o,
  output logic sel_dmi_o,
  output logic sel_idcode_o
);

  // -------------------------------------------------------------------
  // 16-state TAP FSM (standard IEEE 1149.1 state graph)
  // -------------------------------------------------------------------
  typedef enum logic [3:0] {
    TEST_LOGIC_RESET,
    RUN_TEST_IDLE,
    SELECT_DR_SCAN,
    CAPTURE_DR,
    SHIFT_DR,
    EXIT1_DR,
    PAUSE_DR,
    EXIT2_DR,
    UPDATE_DR,
    SELECT_IR_SCAN,
    CAPTURE_IR,
    SHIFT_IR_ST,
    EXIT1_IR,
    PAUSE_IR,
    EXIT2_IR,
    UPDATE_IR
  } tap_state_e;

  tap_state_e state_q, state_d;

  always_comb begin
    state_d = TEST_LOGIC_RESET;  // R-C3: safe default before case
    unique case (state_q)
      TEST_LOGIC_RESET: state_d = tms_i ? TEST_LOGIC_RESET : RUN_TEST_IDLE;
      RUN_TEST_IDLE:    state_d = tms_i ? SELECT_DR_SCAN   : RUN_TEST_IDLE;

      SELECT_DR_SCAN:   state_d = tms_i ? SELECT_IR_SCAN   : CAPTURE_DR;
      CAPTURE_DR:       state_d = tms_i ? EXIT1_DR         : SHIFT_DR;
      SHIFT_DR:         state_d = tms_i ? EXIT1_DR         : SHIFT_DR;
      EXIT1_DR:         state_d = tms_i ? UPDATE_DR        : PAUSE_DR;
      PAUSE_DR:         state_d = tms_i ? EXIT2_DR         : PAUSE_DR;
      EXIT2_DR:         state_d = tms_i ? UPDATE_DR        : SHIFT_DR;
      UPDATE_DR:        state_d = tms_i ? SELECT_DR_SCAN   : RUN_TEST_IDLE;

      SELECT_IR_SCAN:   state_d = tms_i ? TEST_LOGIC_RESET : CAPTURE_IR;
      CAPTURE_IR:       state_d = tms_i ? EXIT1_IR         : SHIFT_IR_ST;
      SHIFT_IR_ST:      state_d = tms_i ? EXIT1_IR         : SHIFT_IR_ST;
      EXIT1_IR:         state_d = tms_i ? UPDATE_IR        : PAUSE_IR;
      PAUSE_IR:         state_d = tms_i ? EXIT2_IR         : PAUSE_IR;
      EXIT2_IR:         state_d = tms_i ? UPDATE_IR        : SHIFT_IR_ST;
      UPDATE_IR:        state_d = tms_i ? SELECT_DR_SCAN   : RUN_TEST_IDLE;

      default:          state_d = TEST_LOGIC_RESET;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) state_q <= TEST_LOGIC_RESET;
    else         state_q <= state_d;
  end

  // -------------------------------------------------------------------
  // Moore-output decode of current state -> control strobes
  // -------------------------------------------------------------------
  logic capture_ir, update_ir;

  assign capture_dr_o = (state_q == CAPTURE_DR);
  assign shift_dr_o    = (state_q == SHIFT_DR);
  assign update_dr_o   = (state_q == UPDATE_DR);

  assign capture_ir    = (state_q == CAPTURE_IR);
  assign shift_ir_o     = (state_q == SHIFT_IR_ST);
  assign update_ir      = (state_q == UPDATE_IR);

  // -------------------------------------------------------------------
  // IR shift register (posedge clk_i)
  // -------------------------------------------------------------------
  logic [DTM_IR_W-1:0] ir_shift_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)
      ir_shift_q <= DTM_IR_RESET_VAL;
    else if (capture_ir)
      ir_shift_q <= DTM_IR_CAPTURE_VAL;
    else if (shift_ir_o)
      ir_shift_q <= {tdi_i, ir_shift_q[DTM_IR_W-1:1]};
  end

  assign ir_shift_tdo_o = ir_shift_q[0];

  // -------------------------------------------------------------------
  // IR update ("architectural") register: latched on negedge clk_i
  // -------------------------------------------------------------------
  logic [DTM_IR_W-1:0] ir_reg;

  always_ff @(negedge clk_i or negedge rst_ni) begin
    if (!rst_ni)
      ir_reg <= DTM_IR_RESET_VAL;
    // IEEE 1149.1: entering Test-Logic-Reset must restore the default
    // instruction, so a debugger that resets with five TMS=1 clocks (no
    // TRST pin) always finds IDCODE selected, not a stale instruction.
    else if (state_q == TEST_LOGIC_RESET)
      ir_reg <= DTM_IR_RESET_VAL;
    else if (update_ir)
      ir_reg <= ir_shift_q;
  end

  // -------------------------------------------------------------------
  // Instruction decoder: any unimplemented/reserved opcode falls through
  // to BYPASS.
  // -------------------------------------------------------------------
  assign sel_idcode_o = (ir_reg == DTM_IR_IDCODE);
  assign sel_dtmcs_o  = (ir_reg == DTM_IR_DTMCS);
  assign sel_dmi_o    = (ir_reg == DTM_IR_DMI);
  assign sel_bypass_o = ~(sel_idcode_o | sel_dtmcs_o | sel_dmi_o);

endmodule : meds_s1_dtm_tap
