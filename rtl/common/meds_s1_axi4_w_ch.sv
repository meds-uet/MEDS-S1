// SPDX-License-Identifier: Apache-2.0
// Copyright (c) Maktab-e-Digital Systems Lahore
//
// meds_s1_axi4_w_ch — write data channel capture, one beat at a time.
// A burst has several beats; this buffer is drained and refilled once per
// beat by meds_s1_axi4_b_ch, which is the module that actually tracks how
// many beats of the burst have gone by (SPEC sec18.2).

module meds_s1_axi4_w_ch
  import meds_s1_axi4_pkg::*;
(
  input  logic                  clk_i,
  input  logic                  rst_ni,

  input  logic [AXI_DATA_W-1:0] wdata_i,
  input  logic [AXI_STRB_W-1:0] wstrb_i,
  input  logic                  wlast_i,
  input  logic                  wvalid_i,
  output logic                  wready_o,

  output logic [AXI_DATA_W-1:0] w_captured_data_o,
  output logic [AXI_STRB_W-1:0] w_captured_strb_o,
  output logic                  w_captured_last_o,
  output logic                  w_captured_o,
  input  logic                  w_consume_i // pulse: clear the buffer
);

  localparam logic IDLE = 1'b0, CAPTURED = 1'b1;

  logic state_q, state_d;
  logic [AXI_DATA_W-1:0] data_q, data_d;
  logic [AXI_STRB_W-1:0] strb_q, strb_d;
  logic                  last_q, last_d;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= IDLE;
      data_q  <= '0;
      strb_q  <= '0;
      last_q  <= 1'b0;
    end else begin
      state_q <= state_d;
      data_q  <= data_d;
      strb_q  <= strb_d;
      last_q  <= last_d;
    end
  end

  always_comb begin
    state_d = state_q;
    data_d  = data_q;
    strb_d  = strb_q;
    last_d  = last_q;

    wready_o = 1'b0;

    unique case (state_q)

      IDLE: begin
        wready_o = 1'b1;
        if (wvalid_i) begin
          data_d  = wdata_i;
          strb_d  = wstrb_i;
          last_d  = wlast_i;
          state_d = CAPTURED;
        end
      end

      CAPTURED: begin
        wready_o = 1'b0;
        if (w_consume_i) state_d = IDLE;
      end

      default: state_d = IDLE;
    endcase
  end

  assign w_captured_data_o = data_q;
  assign w_captured_strb_o = strb_q;
  assign w_captured_last_o = last_q;
  assign w_captured_o      = (state_q == CAPTURED);

endmodule : meds_s1_axi4_w_ch
