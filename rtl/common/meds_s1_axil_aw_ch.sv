// SPDX-License-Identifier: Apache-2.0
// Copyright (c) Maktab-e-Digital Systems Lahore
//
// meds_s1_axil_aw_ch — AXI4-Lite write-address channel.
// Captures awaddr_i when awvalid_i fires and holds it until aw_consume_i
// pulses. See docs/modules/meds_s1_axil_reg_protocol.md for the
// per-channel design rationale.

module meds_s1_axil_aw_ch
  import meds_s1_axi4_pkg::*;
#(
  parameter int unsigned ADDR_WIDTH = AXIL_LOCAL_ADDR_W
) (
  input  logic                  clk_i,
  input  logic                  rst_ni,

  input  logic [ADDR_WIDTH-1:0] awaddr_i,
  input  logic                  awvalid_i,
  output logic                  awready_o,

  output logic [ADDR_WIDTH-1:0] aw_captured_addr_o,
  output logic                  aw_captured_o,
  input  logic                  aw_consume_i    // pulse: clear the buffer
);

  typedef enum logic {AW_IDLE_E, AW_CAPTURED_E} aw_state_e;

  aw_state_e             state_q, state_d;
  logic [ADDR_WIDTH-1:0] addr_q, addr_d;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= AW_IDLE_E;
      addr_q  <= '0;
    end else begin
      state_q <= state_d;
      addr_q  <= addr_d;
    end
  end

  always_comb begin
    state_d   = state_q;
    addr_d    = addr_q;
    awready_o = 1'b0;

    unique case (state_q)

      AW_IDLE_E: begin
        awready_o = 1'b1;
        if (awvalid_i) begin
          addr_d  = awaddr_i;
          state_d = AW_CAPTURED_E;
        end
      end

      AW_CAPTURED_E: begin
        awready_o = 1'b0;
        if (aw_consume_i) state_d = AW_IDLE_E;
      end

      default: state_d = AW_IDLE_E;
    endcase
  end

  assign aw_captured_addr_o = addr_q;
  assign aw_captured_o      = (state_q == AW_CAPTURED_E);

endmodule : meds_s1_axil_aw_ch
