// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// meds_s1_abs_ctrl : Abstract Command Controller                     [COMPLETE]
//
// FSM to manage RISC-V Debug Module abstract command execution and error
// reporting (cmderr encodings 1, 2, and 4) for register accesses.
//
// Reference: SPEC section 13, INTERFACES.md section 7.
// Testbench: verif/unit/tb_meds_s1_abs_ctrl.sv.
// =============================================================================

module meds_s1_abs_ctrl (
  input  logic       clk_i,
  input  logic       rst_ni,

  // Command interface
  input  logic       cmd_en_i,
  input  logic [7:0] cmdtype_i,
  input  logic       postexec_i,
  input  logic       cmderr_status_i,

  // Status from core
  input  logic       debug_halted_i,
  input  logic       debug_reg_ready_i,
  input  logic       aarpostincrement_i,

  // Control outputs
  output logic       abs_en_o,
  output logic       debug_reg_en_o,
  output logic       busy_o,
  output logic       set_cmderr_o,
  output logic [2:0] cmderr_o,
  output logic       inc_regno_o
);

  // RISC-V Debug Specification v1.0 (abstractcs.cmderr)
  localparam logic [7:0] CMD_ACCESS_REG      = 8'h00;
  localparam logic [2:0] CMDERR_NONE         = 3'd0;
  localparam logic [2:0] CMDERR_BUSY         = 3'd1;
  localparam logic [2:0] CMDERR_NOT_SUPP     = 3'd2;
  localparam logic [2:0] CMDERR_HALT_RESUME  = 3'd4;

  typedef enum logic [1:0] {
    IDLE_E,
    EXEC_REG_E,
    ERROR_BUSY_E,
    ERROR_WAIT_E
  } abs_state_e;

  abs_state_e state_q, next_state_d;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= IDLE_E;
    end else begin
      state_q <= next_state_d;
    end
  end

  always_comb begin
    // Default assignments to prevent latches
    next_state_d   = state_q;
    abs_en_o       = 1'b0;
    debug_reg_en_o = 1'b0;
    busy_o         = 1'b0;
    set_cmderr_o   = 1'b0;
    cmderr_o       = CMDERR_NONE;
    inc_regno_o    = 1'b0;

    unique case (state_q)
      IDLE_E: begin
        if (cmd_en_i && !cmderr_status_i) begin
          if ((cmdtype_i != CMD_ACCESS_REG) || postexec_i) begin
            set_cmderr_o = 1'b1;
            cmderr_o     = CMDERR_NOT_SUPP;
            next_state_d = ERROR_WAIT_E;
          end else if (!debug_halted_i) begin
            set_cmderr_o = 1'b1;
            cmderr_o     = CMDERR_HALT_RESUME;
            next_state_d = ERROR_WAIT_E;
          end else begin
            next_state_d = EXEC_REG_E;
          end
        end
      end

      EXEC_REG_E: begin
        abs_en_o       = 1'b1;
        debug_reg_en_o = 1'b1;
        busy_o         = 1'b1;

        if (cmd_en_i) begin
          // (busy), while the in-flight command runs to completion.
          set_cmderr_o = 1'b1;
          cmderr_o     = CMDERR_BUSY;
          if (debug_reg_ready_i) begin
            inc_regno_o  = aarpostincrement_i;
            next_state_d = ERROR_WAIT_E;
          end else begin
            next_state_d = ERROR_BUSY_E;
          end
        end else if (debug_reg_ready_i) begin
          inc_regno_o  = aarpostincrement_i;
          next_state_d = IDLE_E;
        end
      end

      ERROR_BUSY_E: begin
        abs_en_o       = 1'b1;
        debug_reg_en_o = 1'b1;
        busy_o         = 1'b1;

        if (debug_reg_ready_i) begin
          inc_regno_o  = aarpostincrement_i;
          next_state_d = ERROR_WAIT_E;
        end
      end

      ERROR_WAIT_E: begin
        // abs_en_o remains 0 so the core is not falsely signaled on error.
        // Wait for the debugger to clear abstractcs.cmderr.
        if (!cmderr_status_i) begin
          next_state_d = IDLE_E;
        end
      end

      default: begin
        next_state_d = IDLE_E;
      end
    endcase
  end

endmodule
