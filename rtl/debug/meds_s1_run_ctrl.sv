// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// meds_s1_run_ctrl : Core Run/Halt Controller                        [COMPLETE]
//
// FSM to manage the execution state of the hart (running, halting, halted,
// resuming, reset) and coordinate halt entry with the completion buffer.
//
// Reference: SPEC section 13, INTERFACES.md section 7.
// Testbench: verif/unit/tb_meds_s1_run_ctrl.sv.
// =============================================================================

module meds_s1_run_ctrl (
  input  logic clk_i,
  input  logic rst_ni,

  // Global Overrides
  input  logic dmactive_i,
  input  logic ndmreset_i,
  input  logic hartreset_i,

  // Debug requests and triggers
  input  logic haltreq_i,
  input  logic resumereq_i,
  input  logic resethaltreq_i,
  input  logic ebreak_match_i,
  input  logic trigger_match_i,
  input  logic step_match_i,

  // Status signals from the Core
  input  logic debug_halted_i,
  input  logic x_idle_i,
  input  logic debug_running_i,

  // Control signals to the Core and DM
  output logic debug_req_o,
  output logic core_halted_o,
  output logic core_resumed_o
);

  localparam logic [3:0] IDLE_TIMEOUT_MAX = 4'd7;

  typedef enum logic [2:0] {
    NORMAL_E,
    HALTING_E,
    HALTED_E,
    RESUMING_E,
    HART_RESET_E
  } run_halt_state_e;

  run_halt_state_e state_q, next_state_d;
  logic [3:0]      idle_timer_q, idle_timer_d;
  logic            idle_timeout;

  assign idle_timeout = (idle_timer_q == IDLE_TIMEOUT_MAX);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q      <= NORMAL_E;
      idle_timer_q <= 4'd0;
    end else begin
      state_q      <= next_state_d;
      idle_timer_q <= idle_timer_d;
    end
  end

  always_comb begin
    // Default assignments to prevent latches (CODING_STANDARD.md R-C3)
    next_state_d   = state_q;
    idle_timer_d   = 4'd0;
    debug_req_o    = 1'b0;
    core_halted_o  = 1'b0;
    core_resumed_o = 1'b0;

    if (!dmactive_i) begin
      next_state_d = NORMAL_E;
    end else if (ndmreset_i || hartreset_i) begin
      debug_req_o  = resethaltreq_i || haltreq_i;
      next_state_d = HART_RESET_E;
    end else begin
      unique case (state_q)
        NORMAL_E: begin
          if (haltreq_i || ebreak_match_i || trigger_match_i || step_match_i) begin
            debug_req_o  = 1'b1;
            next_state_d = HALTING_E;
          end
        end

        HALTING_E: begin
          debug_req_o = 1'b1;
          if (debug_halted_i && (x_idle_i || idle_timeout)) begin
            core_halted_o = 1'b1;
            next_state_d  = HALTED_E;
          end else if (debug_halted_i && !x_idle_i) begin
            idle_timer_d = idle_timer_q + 4'd1;
          end
        end

        HALTED_E: begin
          debug_req_o = 1'b1;
          if (resumereq_i && !haltreq_i) begin
            debug_req_o  = 1'b0;
            next_state_d = RESUMING_E;
          end else if (!debug_halted_i && debug_running_i) begin
            // Guard against core leaving halted state without resumereq_i
            if (haltreq_i) begin
              next_state_d = HALTING_E;
            end else begin
              debug_req_o    = 1'b0;
              core_resumed_o = 1'b1;
              next_state_d   = NORMAL_E;
            end
          end
        end

        RESUMING_E: begin
          if (debug_running_i) begin
            core_resumed_o = 1'b1;
            next_state_d   = NORMAL_E;
          end
        end

        HART_RESET_E: begin
          if (resethaltreq_i || haltreq_i) begin
            debug_req_o = 1'b1;
            if (debug_halted_i && x_idle_i) begin
              core_halted_o = 1'b1;
              next_state_d  = HALTED_E;
            end else begin
              next_state_d  = HALTING_E;
            end
          end else begin
            next_state_d = NORMAL_E;
          end
        end

        default: begin
          next_state_d = NORMAL_E;
        end
      endcase
    end
  end

endmodule
