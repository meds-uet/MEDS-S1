// SPDX-License-Identifier: Apache-2.0
// Copyright (c) Maktab-e-Digital Systems Lahore
//
// meds_s1_axi4_upsizer -- connects a 64-bit AXI4 master (I$, D$, Debug DM)
// to the 256-bit backbone (SPEC sec18.1, "upsizer 64->256").
//
// A 64-bit master only issues transfers of <= 8 bytes, and AXI4 allows such
// "narrow" transfers on a wide bus unchanged. So AW/AR pass straight
// through; only the data lanes need steering, by the beat address:
//   W: the 64-bit word is copied to all four 64-bit lanes, and WSTRB is
//      shifted into the lane selected by addr[4:3].
//   R: the 64-bit lane selected by addr[4:3] is returned.
// The beat address is tracked with axi_next_addr(), so INCR, WRAP (cache
// refill) and FIXED bursts all work. One write burst and one read burst are
// tracked at a time, which matches blocking caches (SPEC sec15).

module meds_s1_axi4_upsizer
  import meds_s1_axi4_pkg::*;
(
  input  logic                     clk_i,
  input  logic                     rst_ni,

  // ---------------- 64-bit slave side (from the narrow master) ----------------
  input  logic [AXI_ID_W-1:0]      m_awid_i,
  input  logic [AXI_ADDR_W-1:0]    m_awaddr_i,
  input  logic [7:0]               m_awlen_i,
  input  logic [2:0]               m_awsize_i,
  input  logic [1:0]               m_awburst_i,
  input  logic                     m_awvalid_i,
  output logic                     m_awready_o,
  input  logic [NARROW_DATA_W-1:0] m_wdata_i,
  input  logic [NARROW_STRB_W-1:0] m_wstrb_i,
  input  logic                     m_wlast_i,
  input  logic                     m_wvalid_i,
  output logic                     m_wready_o,
  output logic [AXI_ID_W-1:0]      m_bid_o,
  output logic [1:0]               m_bresp_o,
  output logic                     m_bvalid_o,
  input  logic                     m_bready_i,
  input  logic [AXI_ID_W-1:0]      m_arid_i,
  input  logic [AXI_ADDR_W-1:0]    m_araddr_i,
  input  logic [7:0]               m_arlen_i,
  input  logic [2:0]               m_arsize_i,
  input  logic [1:0]               m_arburst_i,
  input  logic                     m_arvalid_i,
  output logic                     m_arready_o,
  output logic [AXI_ID_W-1:0]      m_rid_o,
  output logic [NARROW_DATA_W-1:0] m_rdata_o,
  output logic [1:0]               m_rresp_o,
  output logic                     m_rlast_o,
  output logic                     m_rvalid_o,
  input  logic                     m_rready_i,

  // ---------------- 256-bit master side (to the crossbar) ----------------
  output logic [AXI_ID_W-1:0]      s_awid_o,
  output logic [AXI_ADDR_W-1:0]    s_awaddr_o,
  output logic [7:0]               s_awlen_o,
  output logic [2:0]               s_awsize_o,
  output logic [1:0]               s_awburst_o,
  output logic                     s_awvalid_o,
  input  logic                     s_awready_i,
  output logic [AXI_DATA_W-1:0]    s_wdata_o,
  output logic [AXI_STRB_W-1:0]    s_wstrb_o,
  output logic                     s_wlast_o,
  output logic                     s_wvalid_o,
  input  logic                     s_wready_i,
  input  logic [AXI_ID_W-1:0]      s_bid_i,
  input  logic [1:0]               s_bresp_i,
  input  logic                     s_bvalid_i,
  output logic                     s_bready_o,
  output logic [AXI_ID_W-1:0]      s_arid_o,
  output logic [AXI_ADDR_W-1:0]    s_araddr_o,
  output logic [7:0]               s_arlen_o,
  output logic [2:0]               s_arsize_o,
  output logic [1:0]               s_arburst_o,
  output logic                     s_arvalid_o,
  input  logic                     s_arready_i,
  input  logic [AXI_ID_W-1:0]      s_rid_i,
  input  logic [AXI_DATA_W-1:0]    s_rdata_i,
  input  logic [1:0]               s_rresp_i,
  input  logic                     s_rlast_i,
  input  logic                     s_rvalid_i,
  output logic                     s_rready_o
);

  // ---------------- write ----------------
  logic                  w_busy_q;          // AW accepted, W beats still to come
  logic [AXI_ADDR_W-1:0] w_addr_q;
  logic [7:0]            w_len_q;
  logic [2:0]            w_size_q;
  logic [1:0]            w_burst_q;

  assign s_awid_o    = m_awid_i;
  assign s_awaddr_o  = m_awaddr_i;
  assign s_awlen_o   = m_awlen_i;
  assign s_awsize_o  = m_awsize_i;
  assign s_awburst_o = m_awburst_i;
  assign s_awvalid_o = m_awvalid_i && !w_busy_q;
  assign m_awready_o = s_awready_i && !w_busy_q;

  assign s_wdata_o   = {4{m_wdata_i}};
  assign s_wstrb_o   = AXI_STRB_W'(m_wstrb_i) << (w_addr_q[4:3] * NARROW_STRB_W);
  assign s_wlast_o   = m_wlast_i;
  assign s_wvalid_o  = m_wvalid_i && w_busy_q;
  assign m_wready_o  = s_wready_i && w_busy_q;

  assign m_bid_o     = s_bid_i;
  assign m_bresp_o   = s_bresp_i;
  assign m_bvalid_o  = s_bvalid_i;
  assign s_bready_o  = m_bready_i;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      w_busy_q <= 1'b0; w_addr_q <= '0; w_len_q <= '0; w_size_q <= '0; w_burst_q <= '0;
    end else if (m_awvalid_i && m_awready_o) begin
      w_busy_q  <= 1'b1;
      w_addr_q  <= m_awaddr_i;
      w_len_q   <= m_awlen_i;
      w_size_q  <= m_awsize_i;
      w_burst_q <= m_awburst_i;
    end else if (s_wvalid_o && s_wready_i) begin
      w_addr_q <= axi_next_addr(w_addr_q, w_size_q, w_len_q, w_burst_q);
      if (m_wlast_i) w_busy_q <= 1'b0;
    end
  end

  // ---------------- read ----------------
  logic                  r_busy_q;          // AR accepted, R beats still to come
  logic [AXI_ADDR_W-1:0] r_addr_q;
  logic [7:0]            r_len_q;
  logic [2:0]            r_size_q;
  logic [1:0]            r_burst_q;

  assign s_arid_o    = m_arid_i;
  assign s_araddr_o  = m_araddr_i;
  assign s_arlen_o   = m_arlen_i;
  assign s_arsize_o  = m_arsize_i;
  assign s_arburst_o = m_arburst_i;
  assign s_arvalid_o = m_arvalid_i && !r_busy_q;
  assign m_arready_o = s_arready_i && !r_busy_q;

  assign m_rid_o     = s_rid_i;
  assign m_rdata_o   = s_rdata_i[r_addr_q[4:3] * NARROW_DATA_W +: NARROW_DATA_W];
  assign m_rresp_o   = s_rresp_i;
  assign m_rlast_o   = s_rlast_i;
  assign m_rvalid_o  = s_rvalid_i;
  assign s_rready_o  = m_rready_i;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      r_busy_q <= 1'b0; r_addr_q <= '0; r_len_q <= '0; r_size_q <= '0; r_burst_q <= '0;
    end else if (m_arvalid_i && m_arready_o) begin
      r_busy_q  <= 1'b1;
      r_addr_q  <= m_araddr_i;
      r_len_q   <= m_arlen_i;
      r_size_q  <= m_arsize_i;
      r_burst_q <= m_arburst_i;
    end else if (s_rvalid_i && m_rready_i) begin
      r_addr_q <= axi_next_addr(r_addr_q, r_size_q, r_len_q, r_burst_q);
      if (s_rlast_i) r_busy_q <= 1'b0;
    end
  end

endmodule : meds_s1_axi4_upsizer
