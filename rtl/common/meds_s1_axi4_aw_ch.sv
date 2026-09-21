// SPDX-License-Identifier: Apache-2.0
// Copyright (c) Maktab-e-Digital Systems Lahore
//
// meds_s1_axi4_aw_ch — full-AXI4 write-address channel capture, one
// outstanding AW at a time. Same IDLE/CAPTURED shape as
// meds_s1_axil_aw_ch, but a full burst descriptor (ID, AWLEN, AWSIZE,
// AWBURST) is captured alongside the address, since the rest of the burst
// (SPEC sec18.2: INCR <= 16 beats, WRAP for refill) depends on all four.
// Holds the descriptor stable until aw_consume_i fires, which
// meds_s1_axi4_b_ch only pulses once the burst's last beat has committed.
//
// ID_W defaults to AXI_ID_W (this module's own native width) but must be
// overridden to AXI_SID_W when instantiated behind meds_s1_axi4_crossbar,
// which presents a slave port with the master-index tag folded into the
// ID field. See AXI_SID_W in meds_s1_axi4_pkg.

module meds_s1_axi4_aw_ch
  import meds_s1_axi4_pkg::*;
#(
  parameter int unsigned ID_W = AXI_ID_W
) (
  input  logic                  clk_i,
  input  logic                  rst_ni,

  input  logic [ID_W-1:0]       awid_i,
  input  logic [AXI_ADDR_W-1:0] awaddr_i,
  input  logic [7:0]            awlen_i,
  input  logic [2:0]            awsize_i,
  input  logic [1:0]            awburst_i,
  input  logic                  awvalid_i,
  output logic                  awready_o,

  output logic [ID_W-1:0]       aw_captured_id_o,
  output logic [AXI_ADDR_W-1:0] aw_captured_addr_o,
  output logic [7:0]            aw_captured_len_o,
  output logic [2:0]            aw_captured_size_o,
  output logic [1:0]            aw_captured_burst_o,
  output logic                  aw_captured_o,
  input  logic                  aw_consume_i // pulse: clear the buffer
);

  localparam logic IDLE = 1'b0, CAPTURED = 1'b1;

  logic state_q, state_d;
  logic [ID_W-1:0]       id_q, id_d;
  logic [AXI_ADDR_W-1:0] addr_q, addr_d;
  logic [7:0]            len_q, len_d;
  logic [2:0]            size_q, size_d;
  logic [1:0]            burst_q, burst_d;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= IDLE;
      id_q    <= '0;
      addr_q  <= '0;
      len_q   <= '0;
      size_q  <= '0;
      burst_q <= '0;
    end else begin
      state_q <= state_d;
      id_q    <= id_d;
      addr_q  <= addr_d;
      len_q   <= len_d;
      size_q  <= size_d;
      burst_q <= burst_d;
    end
  end

  always_comb begin
    state_d = state_q;
    id_d    = id_q;
    addr_d  = addr_q;
    len_d   = len_q;
    size_d  = size_q;
    burst_d = burst_q;

    awready_o = 1'b0;

    unique case (state_q)

      IDLE: begin
        awready_o = 1'b1;
        if (awvalid_i) begin
          id_d    = awid_i;
          addr_d  = awaddr_i;
          len_d   = awlen_i;
          size_d  = awsize_i;
          burst_d = awburst_i;
          state_d = CAPTURED;
        end
      end

      CAPTURED: begin
        awready_o = 1'b0;
        if (aw_consume_i) state_d = IDLE;
      end

      default: state_d = IDLE;
    endcase
  end

  assign aw_captured_id_o    = id_q;
  assign aw_captured_addr_o  = addr_q;
  assign aw_captured_len_o   = len_q;
  assign aw_captured_size_o  = size_q;
  assign aw_captured_burst_o = burst_q;
  assign aw_captured_o       = (state_q == CAPTURED);

endmodule : meds_s1_axi4_aw_ch
