// SPDX-License-Identifier: Apache-2.0
// Copyright (c) Maktab-e-Digital Systems Lahore
//
// meds_s1_axi4_ar_ch — full-AXI4 read-address channel capture, one
// outstanding AR at a time (matches meds_s1_axi4_crossbar's "one AR/R
// burst in flight per slave" policy). Mirrors meds_s1_axi4_aw_ch: captures
// ID, address, length, size, and burst type when arvalid_i fires, holds
// them until ar_consume_i clears the buffer. WRAP bursts are captured
// verbatim like any other burst; the wrapping address arithmetic lives
// downstream in meds_s1_axi4_r_ch.
//
// ID_W defaults to AXI_ID_W but must be widened to AXI_SID_W when
// instantiated behind the crossbar, so the master tag in the ID is echoed
// back unchanged (same note as meds_s1_axi4_aw_ch on the write side).

module meds_s1_axi4_ar_ch
  import meds_s1_axi4_pkg::*;
#(
  parameter int unsigned ID_W = AXI_ID_W
) (
  input  logic                  clk_i,
  input  logic                  rst_ni,

  input  logic [ID_W-1:0]       arid_i,
  input  logic [AXI_ADDR_W-1:0] araddr_i,
  input  logic [7:0]            arlen_i,
  input  logic [2:0]            arsize_i,
  input  logic [1:0]            arburst_i,
  input  logic                  arvalid_i,
  output logic                  arready_o,

  output logic [ID_W-1:0]       ar_captured_id_o,
  output logic [AXI_ADDR_W-1:0] ar_captured_addr_o,
  output logic [7:0]            ar_captured_len_o,
  output logic [2:0]            ar_captured_size_o,
  output logic [1:0]            ar_captured_burst_o,
  output logic                  ar_captured_o,
  input  logic                  ar_consume_i // pulse: clear the buffer
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

    arready_o = 1'b0;

    unique case (state_q)

      IDLE: begin
        arready_o = 1'b1;
        if (arvalid_i) begin
          id_d    = arid_i;
          addr_d  = araddr_i;
          len_d   = arlen_i;
          size_d  = arsize_i;
          burst_d = arburst_i;
          state_d = CAPTURED;
        end
      end

      CAPTURED: begin
        arready_o = 1'b0;
        if (ar_consume_i) state_d = IDLE;
      end

      default: state_d = IDLE;
    endcase
  end

  assign ar_captured_id_o    = id_q;
  assign ar_captured_addr_o  = addr_q;
  assign ar_captured_len_o   = len_q;
  assign ar_captured_size_o  = size_q;
  assign ar_captured_burst_o = burst_q;
  assign ar_captured_o       = (state_q == CAPTURED);

endmodule : meds_s1_axi4_ar_ch
