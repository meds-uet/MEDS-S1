// SPDX-License-Identifier: Apache-2.0
// Copyright (c) Maktab-e-Digital Systems Lahore
//
// meds_s1_axi4_decerr_sink -- the crossbar's "slave" for unmapped addresses.
// It is a normal AXI4 slave port (one burst at a time per direction), so the
// crossbar routes to it exactly like to any real slave:
//   write: accept AW, drain every W beat up to WLAST, return one DECERR B.
//   read : accept AR, return ARLEN+1 beats of zero data with DECERR, RLAST
//          on the final beat.

module meds_s1_axi4_decerr_sink
  import meds_s1_axi4_pkg::*;
(
  input  logic                  clk_i,
  input  logic                  rst_ni,

  input  logic [AXI_SID_W-1:0]  awid_i,
  input  logic                  awvalid_i,
  output logic                  awready_o,
  input  logic                  wlast_i,
  input  logic                  wvalid_i,
  output logic                  wready_o,
  output logic [AXI_SID_W-1:0]  bid_o,
  output logic [1:0]            bresp_o,
  output logic                  bvalid_o,
  input  logic                  bready_i,

  input  logic [AXI_SID_W-1:0]  arid_i,
  input  logic [7:0]            arlen_i,
  input  logic                  arvalid_i,
  output logic                  arready_o,
  output logic [AXI_SID_W-1:0]  rid_o,
  output logic [AXI_DATA_W-1:0] rdata_o,
  output logic [1:0]            rresp_o,
  output logic                  rlast_o,
  output logic                  rvalid_o,
  input  logic                  rready_i
);

  // ---------------- write ----------------
  typedef enum logic [1:0] {W_IDLE_E, W_DRAIN_E, W_RESP_E} w_state_e;
  w_state_e             w_state_q;
  logic [AXI_SID_W-1:0] bid_q;

  assign awready_o = (w_state_q == W_IDLE_E);
  assign wready_o  = (w_state_q == W_DRAIN_E);
  assign bvalid_o  = (w_state_q == W_RESP_E);
  assign bid_o     = bid_q;
  assign bresp_o   = RESP_DECERR;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      w_state_q <= W_IDLE_E;
      bid_q     <= '0;
    end else begin
      unique case (w_state_q)
        W_IDLE_E:  if (awvalid_i) begin bid_q <= awid_i; w_state_q <= W_DRAIN_E; end
        W_DRAIN_E: if (wvalid_i && wlast_i) w_state_q <= W_RESP_E;
        W_RESP_E:  if (bready_i) w_state_q <= W_IDLE_E;
        default:   w_state_q <= W_IDLE_E;
      endcase
    end
  end

  // ---------------- read ----------------
  logic                 r_busy_q;
  logic [AXI_SID_W-1:0] rid_q;
  logic [7:0]           beats_left_q;

  assign arready_o = !r_busy_q;
  assign rvalid_o  = r_busy_q;
  assign rid_o     = rid_q;
  assign rdata_o   = '0;
  assign rresp_o   = RESP_DECERR;
  assign rlast_o   = (beats_left_q == 8'd0);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      r_busy_q     <= 1'b0;
      rid_q        <= '0;
      beats_left_q <= '0;
    end else if (!r_busy_q) begin
      if (arvalid_i) begin
        r_busy_q     <= 1'b1;
        rid_q        <= arid_i;
        beats_left_q <= arlen_i;
      end
    end else if (rready_i) begin
      if (beats_left_q == 8'd0) r_busy_q <= 1'b0;
      else                      beats_left_q <= beats_left_q - 8'd1;
    end
  end

endmodule : meds_s1_axi4_decerr_sink
