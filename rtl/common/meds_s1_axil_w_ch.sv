// SPDX-License-Identifier: Apache-2.0
// Copyright (c) Maktab-e-Digital Systems Lahore
//
// meds_s1_axil_w_ch — AXI4-Lite write-data channel.
// Captures wdata_i/wstrb_i when wvalid_i fires and holds them until
// w_consume_i pulses.

module meds_s1_axil_w_ch
  import meds_s1_axi4_pkg::*;
#(
  parameter int unsigned DATA_WIDTH = AXIL_DATA_W,
  parameter int unsigned STRB_WIDTH = DATA_WIDTH / 8
) (
  input  logic                  clk_i,
  input  logic                  rst_ni,

  input  logic [DATA_WIDTH-1:0] wdata_i,
  input  logic [STRB_WIDTH-1:0] wstrb_i,
  input  logic                  wvalid_i,
  output logic                  wready_o,

  output logic [DATA_WIDTH-1:0] w_captured_data_o,
  output logic [STRB_WIDTH-1:0] w_captured_strb_o,
  output logic                  w_captured_o,
  input  logic                  w_consume_i     // pulse: clear the buffer
);

  typedef enum logic {W_IDLE_E, W_CAPTURED_E} w_state_e;

  w_state_e              state_q, state_d;
  logic [DATA_WIDTH-1:0] data_q, data_d;
  logic [STRB_WIDTH-1:0] strb_q, strb_d;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= W_IDLE_E;
      data_q  <= '0;
      strb_q  <= '0;
    end else begin
      state_q <= state_d;
      data_q  <= data_d;
      strb_q  <= strb_d;
    end
  end

  always_comb begin
    state_d  = state_q;
    data_d   = data_q;
    strb_d   = strb_q;
    wready_o = 1'b0;

    unique case (state_q)

      W_IDLE_E: begin
        wready_o = 1'b1;
        if (wvalid_i) begin
          data_d  = wdata_i;
          strb_d  = wstrb_i;
          state_d = W_CAPTURED_E;
        end
      end

      W_CAPTURED_E: begin
        wready_o = 1'b0;
        if (w_consume_i) state_d = W_IDLE_E;
      end

      default: state_d = W_IDLE_E;
    endcase
  end

  assign w_captured_data_o = data_q;
  assign w_captured_strb_o = strb_q;
  assign w_captured_o      = (state_q == W_CAPTURED_E);

endmodule : meds_s1_axil_w_ch
