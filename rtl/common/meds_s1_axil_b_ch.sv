// SPDX-License-Identifier: Apache-2.0
// Copyright (c) Maktab-e-Digital Systems Lahore
//
// meds_s1_axil_b_ch — AXI4-Lite write-response channel and write-commit
// logic. Waits until both aw_captured_i and w_captured_i are asserted,
// pulls them together, pulses wr_en_o for one cycle to commit the write to
// whatever register storage sits behind the shell, checks wr_addr_valid_i
// to decide OKAY vs SLVERR, then raises bvalid_o and waits for bready_i.

module meds_s1_axil_b_ch
  import meds_s1_axi4_pkg::*;
#(
  parameter int unsigned ADDR_WIDTH = AXIL_LOCAL_ADDR_W,
  parameter int unsigned DATA_WIDTH = AXIL_DATA_W,
  parameter int unsigned STRB_WIDTH = DATA_WIDTH / 8
) (
  input  logic                  clk_i,
  input  logic                  rst_ni,

  // From meds_s1_axil_aw_ch
  input  logic [ADDR_WIDTH-1:0] aw_captured_addr_i,
  input  logic                  aw_captured_i,
  output logic                  aw_consume_o,

  // From meds_s1_axil_w_ch
  input  logic [DATA_WIDTH-1:0] w_captured_data_i,
  input  logic [STRB_WIDTH-1:0] w_captured_strb_i,
  input  logic                  w_captured_i,
  output logic                  w_consume_o,

  // B channel
  output logic [1:0]            bresp_o,
  output logic                  bvalid_o,
  input  logic                  bready_i,

  // Internal write-commit interface (to register storage)
  output logic [ADDR_WIDTH-1:0] wr_addr_o,
  output logic [DATA_WIDTH-1:0] wr_data_o,
  output logic [STRB_WIDTH-1:0] wr_strb_o,
  output logic                  wr_en_o,         // one-cycle commit pulse
  input  logic                  wr_addr_valid_i  // 1 = in range -> OKAY, else SLVERR
);

  typedef enum logic [1:0] {B_IDLE_E, B_COMMIT_E, B_RESP_E} b_state_e;

  b_state_e              state_q, state_d;
  logic [ADDR_WIDTH-1:0] addr_q, addr_d;
  logic [DATA_WIDTH-1:0] data_q, data_d;
  logic [STRB_WIDTH-1:0] strb_q, strb_d;
  logic [1:0]            bresp_q, bresp_d;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= B_IDLE_E;
      addr_q  <= '0;
      data_q  <= '0;
      strb_q  <= '0;
      bresp_q <= RESP_OKAY;
    end else begin
      state_q <= state_d;
      addr_q  <= addr_d;
      data_q  <= data_d;
      strb_q  <= strb_d;
      bresp_q <= bresp_d;
    end
  end

  always_comb begin
    state_d = state_q;
    addr_d  = addr_q;
    data_d  = data_q;
    strb_d  = strb_q;
    bresp_d = bresp_q;

    aw_consume_o = 1'b0;
    w_consume_o  = 1'b0;
    wr_en_o      = 1'b0;
    bvalid_o     = 1'b0;

    unique case (state_q)

      B_IDLE_E: begin
        if (aw_captured_i && w_captured_i) begin
          addr_d       = aw_captured_addr_i;
          data_d       = w_captured_data_i;
          strb_d       = w_captured_strb_i;
          aw_consume_o = 1'b1;
          w_consume_o  = 1'b1;
          state_d      = B_COMMIT_E;
        end
      end

      B_COMMIT_E: begin
        wr_en_o = 1'b1;
        bresp_d = wr_addr_valid_i ? RESP_OKAY : RESP_SLVERR;
        state_d = B_RESP_E;
      end

      B_RESP_E: begin
        bvalid_o = 1'b1;
        if (bready_i) state_d = B_IDLE_E;
      end

      default: state_d = B_IDLE_E;
    endcase
  end

  assign wr_addr_o = addr_q;
  assign wr_data_o = data_q;
  assign wr_strb_o = strb_q;
  assign bresp_o   = bresp_q;

endmodule : meds_s1_axil_b_ch
