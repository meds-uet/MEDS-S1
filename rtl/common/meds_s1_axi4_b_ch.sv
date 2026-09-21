// SPDX-License-Identifier: Apache-2.0
// Copyright (c) Maktab-e-Digital Systems Lahore
//
// meds_s1_axi4_b_ch -- write burst sequencer + write response channel.
// For each W beat: drive wr_addr_o/wr_data_o/wr_strb_o, pulse wr_en_o once,
// note whether the address was valid, step the address (FIXED/INCR/WRAP via
// axi_next_addr). After AWLEN+1 beats, return ONE B response: OKAY if every
// beat was valid, else SLVERR (AXI4 has one write response per burst).
// The beat counter is 8 bits, so any legal AXI4 length (1..256) works.

module meds_s1_axi4_b_ch
  import meds_s1_axi4_pkg::*;
#(
  parameter int unsigned ID_W = AXI_ID_W
) (
  input  logic                  clk_i,
  input  logic                  rst_ni,

  // From meds_s1_axi4_aw_ch
  input  logic [ID_W-1:0]       aw_captured_id_i,
  input  logic [AXI_ADDR_W-1:0] aw_captured_addr_i,
  input  logic [7:0]            aw_captured_len_i,
  input  logic [2:0]            aw_captured_size_i,
  input  logic [1:0]            aw_captured_burst_i,
  input  logic                  aw_captured_i,
  output logic                  aw_consume_o,

  // From meds_s1_axi4_w_ch
  input  logic [AXI_DATA_W-1:0] w_captured_data_i,
  input  logic [AXI_STRB_W-1:0] w_captured_strb_i,
  input  logic                  w_captured_last_i,
  input  logic                  w_captured_i,
  output logic                  w_consume_o,

  // B channel
  output logic [ID_W-1:0]       bid_o,
  output logic [1:0]            bresp_o,
  output logic                  bvalid_o,
  input  logic                  bready_i,

  // Register boundary
  output logic [AXI_ADDR_W-1:0] wr_addr_o,
  output logic [AXI_DATA_W-1:0] wr_data_o,
  output logic [AXI_STRB_W-1:0] wr_strb_o,
  output logic                  wr_en_o,          // one pulse per beat
  input  logic                  wr_addr_valid_i   // 0 -> SLVERR
);

  typedef enum logic [1:0] {B_IDLE_E, B_BEAT_E, B_RESP_E} b_state_e;

  b_state_e              state_q;
  logic [AXI_ADDR_W-1:0] addr_q;
  logic [7:0]            beat_q;
  logic                  bad_q;
  logic [ID_W-1:0]       id_q;

  logic last_beat;
  assign last_beat = (beat_q == aw_captured_len_i);

  assign wr_addr_o    = addr_q;
  assign wr_data_o    = w_captured_data_i;
  assign wr_strb_o    = w_captured_strb_i;
  assign wr_en_o      = (state_q == B_BEAT_E) && w_captured_i;
  assign w_consume_o  = wr_en_o;
  assign aw_consume_o = wr_en_o && last_beat;
  assign bvalid_o     = (state_q == B_RESP_E);
  assign bid_o        = id_q;
  assign bresp_o      = bad_q ? RESP_SLVERR : RESP_OKAY;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= B_IDLE_E;
      addr_q  <= '0;
      beat_q  <= '0;
      bad_q   <= 1'b0;
      id_q    <= '0;
    end else begin
      unique case (state_q)
        B_IDLE_E: if (aw_captured_i) begin
          addr_q  <= aw_captured_addr_i;
          beat_q  <= '0;
          bad_q   <= 1'b0;
          id_q    <= aw_captured_id_i;
          state_q <= B_BEAT_E;
        end
        B_BEAT_E: if (wr_en_o) begin
          bad_q <= bad_q | !wr_addr_valid_i;
          if (last_beat) state_q <= B_RESP_E;
          else begin
            beat_q <= beat_q + 8'd1;
            addr_q <= axi_next_addr(addr_q, aw_captured_size_i, aw_captured_len_i, aw_captured_burst_i);
          end
        end
        B_RESP_E: if (bready_i) state_q <= B_IDLE_E;
        default:  state_q <= B_IDLE_E;
      endcase
    end
  end

endmodule : meds_s1_axi4_b_ch
