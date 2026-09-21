// SPDX-License-Identifier: Apache-2.0
// Copyright (c) Maktab-e-Digital Systems Lahore
//
// meds_s1_axil_ar_ch — AXI4-Lite read-address channel.
// Captures araddr_i when arvalid_i fires and holds it until ar_consume_i
// pulses. Mirrors meds_s1_axil_aw_ch.

module meds_s1_axil_ar_ch
  import meds_s1_axi4_pkg::*;
#(
  parameter int unsigned ADDR_WIDTH = AXIL_LOCAL_ADDR_W
) (
  input  logic                  clk_i,
  input  logic                  rst_ni,

  input  logic [ADDR_WIDTH-1:0] araddr_i,
  input  logic                  arvalid_i,
  output logic                  arready_o,

  output logic [ADDR_WIDTH-1:0] ar_captured_addr_o,
  output logic                  ar_captured_o,
  input  logic                  ar_consume_i    // pulse: clear the buffer
);

  typedef enum logic {AR_IDLE_E, AR_CAPTURED_E} ar_state_e;

  ar_state_e             state_q, state_d;
  logic [ADDR_WIDTH-1:0] addr_q, addr_d;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= AR_IDLE_E;
      addr_q  <= '0;
    end else begin
      state_q <= state_d;
      addr_q  <= addr_d;
    end
  end

  always_comb begin
    state_d   = state_q;
    addr_d    = addr_q;
    arready_o = 1'b0;

    unique case (state_q)

      AR_IDLE_E: begin
        arready_o = 1'b1;
        if (arvalid_i) begin
          addr_d  = araddr_i;
          state_d = AR_CAPTURED_E;
        end
      end

      AR_CAPTURED_E: begin
        arready_o = 1'b0;
        if (ar_consume_i) state_d = AR_IDLE_E;
      end

      default: state_d = AR_IDLE_E;
    endcase
  end

  assign ar_captured_addr_o = addr_q;
  assign ar_captured_o      = (state_q == AR_CAPTURED_E);

endmodule : meds_s1_axil_ar_ch
