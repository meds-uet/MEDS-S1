// SPDX-License-Identifier: Apache-2.0
// Copyright (c) Maktab-e-Digital Systems Lahore
//
// meds_s1_axi4_crossbar -- the AXI4 backbone crossbar (SPEC sec18, Fig. 10).
// NUM_MASTERS x NUM_SLAVES, 256-bit data, 40-bit address.
//
// How it stays AXI-correct, in four rules:
//  1. Decode happens only while xVALID is high. A miss goes to an internal
//     DECERR sink, which is just one more slave (index SLV_DECERR). Nothing
//     is ever routed from a master's *current* address bus after the
//     handshake -- responses are routed by the ID tag.
//  2. A master may have up to MAX_OUTSTANDING writes (and, separately,
//     reads) in flight, but all to the SAME slave. So at most one slave can
//     ever respond to a given master: no two B (or R) responses can collide,
//     and same-ID ordering is kept by that single slave.
//  3. Each slave keeps a small FIFO of which master owns the next W burst, in
//     AW-acceptance order, so W data always follows AW order.
//  4. The arbiters lock their grant while VALID && !READY, so a slave never
//     sees the AW/AR payload change before the handshake.
//
// IDs: the master index is prepended (AXI_SID_W = AXI_ID_W + MIDX_W) on the
// way to a slave and stripped on the way back.
//
// Performance events (SPEC sec12, "Fabric" group) are per-cycle increments
// for the core's mhpmcounters:
//   evt_axi_read_beats_o       R beats accepted this cycle (real slaves)
//   evt_axi_write_beats_o      W beats accepted this cycle (real slaves)
//   evt_axi_read_outstanding_o reads in flight this cycle; summed over time
//                              this is axi_read_latency_sum (Little's law)
//   evt_axi_arb_stall_o        AW/AR requests waiting because another master
//                              holds the slave (axi_arb_stall_cycles)

module meds_s1_axi4_crossbar
  import meds_s1_axi4_pkg::*;
(
  input  logic clk_i,
  input  logic rst_ni,

  // ---------------- master ports ----------------
  input  logic [NUM_MASTERS-1:0][AXI_ID_W-1:0]   m_awid_i,
  input  logic [NUM_MASTERS-1:0][AXI_ADDR_W-1:0] m_awaddr_i,
  input  logic [NUM_MASTERS-1:0][7:0]            m_awlen_i,
  input  logic [NUM_MASTERS-1:0][2:0]            m_awsize_i,
  input  logic [NUM_MASTERS-1:0][1:0]            m_awburst_i,
  input  logic [NUM_MASTERS-1:0]                 m_awvalid_i,
  output logic [NUM_MASTERS-1:0]                 m_awready_o,

  input  logic [NUM_MASTERS-1:0][AXI_DATA_W-1:0] m_wdata_i,
  input  logic [NUM_MASTERS-1:0][AXI_STRB_W-1:0] m_wstrb_i,
  input  logic [NUM_MASTERS-1:0]                 m_wlast_i,
  input  logic [NUM_MASTERS-1:0]                 m_wvalid_i,
  output logic [NUM_MASTERS-1:0]                 m_wready_o,

  output logic [NUM_MASTERS-1:0][AXI_ID_W-1:0]   m_bid_o,
  output logic [NUM_MASTERS-1:0][1:0]            m_bresp_o,
  output logic [NUM_MASTERS-1:0]                 m_bvalid_o,
  input  logic [NUM_MASTERS-1:0]                 m_bready_i,

  input  logic [NUM_MASTERS-1:0][AXI_ID_W-1:0]   m_arid_i,
  input  logic [NUM_MASTERS-1:0][AXI_ADDR_W-1:0] m_araddr_i,
  input  logic [NUM_MASTERS-1:0][7:0]            m_arlen_i,
  input  logic [NUM_MASTERS-1:0][2:0]            m_arsize_i,
  input  logic [NUM_MASTERS-1:0][1:0]            m_arburst_i,
  input  logic [NUM_MASTERS-1:0]                 m_arvalid_i,
  output logic [NUM_MASTERS-1:0]                 m_arready_o,

  output logic [NUM_MASTERS-1:0][AXI_ID_W-1:0]   m_rid_o,
  output logic [NUM_MASTERS-1:0][AXI_DATA_W-1:0] m_rdata_o,
  output logic [NUM_MASTERS-1:0][1:0]            m_rresp_o,
  output logic [NUM_MASTERS-1:0]                 m_rlast_o,
  output logic [NUM_MASTERS-1:0]                 m_rvalid_o,
  input  logic [NUM_MASTERS-1:0]                 m_rready_i,

  // ---------------- slave ports ----------------
  output logic [NUM_SLAVES-1:0][AXI_SID_W-1:0]   s_awid_o,
  output logic [NUM_SLAVES-1:0][AXI_ADDR_W-1:0]  s_awaddr_o,
  output logic [NUM_SLAVES-1:0][7:0]             s_awlen_o,
  output logic [NUM_SLAVES-1:0][2:0]             s_awsize_o,
  output logic [NUM_SLAVES-1:0][1:0]             s_awburst_o,
  output logic [NUM_SLAVES-1:0]                  s_awvalid_o,
  input  logic [NUM_SLAVES-1:0]                  s_awready_i,

  output logic [NUM_SLAVES-1:0][AXI_DATA_W-1:0]  s_wdata_o,
  output logic [NUM_SLAVES-1:0][AXI_STRB_W-1:0]  s_wstrb_o,
  output logic [NUM_SLAVES-1:0]                  s_wlast_o,
  output logic [NUM_SLAVES-1:0]                  s_wvalid_o,
  input  logic [NUM_SLAVES-1:0]                  s_wready_i,

  input  logic [NUM_SLAVES-1:0][AXI_SID_W-1:0]   s_bid_i,
  input  logic [NUM_SLAVES-1:0][1:0]             s_bresp_i,
  input  logic [NUM_SLAVES-1:0]                  s_bvalid_i,
  output logic [NUM_SLAVES-1:0]                  s_bready_o,

  output logic [NUM_SLAVES-1:0][AXI_SID_W-1:0]   s_arid_o,
  output logic [NUM_SLAVES-1:0][AXI_ADDR_W-1:0]  s_araddr_o,
  output logic [NUM_SLAVES-1:0][7:0]             s_arlen_o,
  output logic [NUM_SLAVES-1:0][2:0]             s_arsize_o,
  output logic [NUM_SLAVES-1:0][1:0]             s_arburst_o,
  output logic [NUM_SLAVES-1:0]                  s_arvalid_o,
  input  logic [NUM_SLAVES-1:0]                  s_arready_i,

  input  logic [NUM_SLAVES-1:0][AXI_SID_W-1:0]   s_rid_i,
  input  logic [NUM_SLAVES-1:0][AXI_DATA_W-1:0]  s_rdata_i,
  input  logic [NUM_SLAVES-1:0][1:0]             s_rresp_i,
  input  logic [NUM_SLAVES-1:0]                  s_rlast_i,
  input  logic [NUM_SLAVES-1:0]                  s_rvalid_i,
  output logic [NUM_SLAVES-1:0]                  s_rready_o,

  // ---------------- performance events (SPEC sec12) ----------------
  output logic [3:0] evt_axi_read_beats_o,
  output logic [3:0] evt_axi_write_beats_o,
  output logic [5:0] evt_axi_read_outstanding_o,
  output logic [4:0] evt_axi_arb_stall_o
);

  localparam int unsigned NM   = NUM_MASTERS;
  localparam int unsigned NS   = NUM_SLAVES;
  localparam int unsigned NSI  = NUM_SLAVES + 1;   // + DECERR sink
  localparam int unsigned WQ_D = 8;                // W-owner FIFO depth per slave

  // ===========================================================================
  // Internal slave-side bus, index 0..NS-1 = real slaves, NS = DECERR sink
  // ===========================================================================
  logic [NSI-1:0][AXI_SID_W-1:0]  x_awid, x_bid, x_arid, x_rid;
  logic [NSI-1:0][AXI_ADDR_W-1:0] x_awaddr, x_araddr;
  logic [NSI-1:0][7:0]            x_awlen, x_arlen;
  logic [NSI-1:0][2:0]            x_awsize, x_arsize;
  logic [NSI-1:0][1:0]            x_awburst, x_arburst, x_bresp, x_rresp;
  logic [NSI-1:0]                 x_awvalid, x_awready, x_wvalid, x_wready, x_wlast;
  logic [NSI-1:0]                 x_bvalid, x_bready, x_arvalid, x_arready;
  logic [NSI-1:0]                 x_rvalid, x_rready, x_rlast;
  logic [NSI-1:0][AXI_DATA_W-1:0] x_wdata, x_rdata;
  logic [NSI-1:0][AXI_STRB_W-1:0] x_wstrb;

  for (genvar s = 0; s < NS; s++) begin : g_ports
    assign s_awid_o[s]    = x_awid[s];
    assign s_awaddr_o[s]  = x_awaddr[s];
    assign s_awlen_o[s]   = x_awlen[s];
    assign s_awsize_o[s]  = x_awsize[s];
    assign s_awburst_o[s] = x_awburst[s];
    assign s_awvalid_o[s] = x_awvalid[s];
    assign x_awready[s]   = s_awready_i[s];
    assign s_wdata_o[s]   = x_wdata[s];
    assign s_wstrb_o[s]   = x_wstrb[s];
    assign s_wlast_o[s]   = x_wlast[s];
    assign s_wvalid_o[s]  = x_wvalid[s];
    assign x_wready[s]    = s_wready_i[s];
    assign x_bid[s]       = s_bid_i[s];
    assign x_bresp[s]     = s_bresp_i[s];
    assign x_bvalid[s]    = s_bvalid_i[s];
    assign s_bready_o[s]  = x_bready[s];
    assign s_arid_o[s]    = x_arid[s];
    assign s_araddr_o[s]  = x_araddr[s];
    assign s_arlen_o[s]   = x_arlen[s];
    assign s_arsize_o[s]  = x_arsize[s];
    assign s_arburst_o[s] = x_arburst[s];
    assign s_arvalid_o[s] = x_arvalid[s];
    assign x_arready[s]   = s_arready_i[s];
    assign x_rid[s]       = s_rid_i[s];
    assign x_rdata[s]     = s_rdata_i[s];
    assign x_rresp[s]     = s_rresp_i[s];
    assign x_rlast[s]     = s_rlast_i[s];
    assign x_rvalid[s]    = s_rvalid_i[s];
    assign s_rready_o[s]  = x_rready[s];
  end

  meds_s1_axi4_decerr_sink u_decerr_sink (
    .clk_i     (clk_i),
    .rst_ni    (rst_ni),
    .awid_i    (x_awid[NS]),
    .awvalid_i (x_awvalid[NS]),
    .awready_o (x_awready[NS]),
    .wlast_i   (x_wlast[NS]),
    .wvalid_i  (x_wvalid[NS]),
    .wready_o  (x_wready[NS]),
    .bid_o     (x_bid[NS]),
    .bresp_o   (x_bresp[NS]),
    .bvalid_o  (x_bvalid[NS]),
    .bready_i  (x_bready[NS]),
    .arid_i    (x_arid[NS]),
    .arlen_i   (x_arlen[NS]),
    .arvalid_i (x_arvalid[NS]),
    .arready_o (x_arready[NS]),
    .rid_o     (x_rid[NS]),
    .rdata_o   (x_rdata[NS]),
    .rresp_o   (x_rresp[NS]),
    .rlast_o   (x_rlast[NS]),
    .rvalid_o  (x_rvalid[NS]),
    .rready_i  (x_rready[NS])
  );

  // ===========================================================================
  // Address decode (only meaningful while the matching VALID is high)
  // ===========================================================================
  logic [NM-1:0][SIDX_W-1:0] aw_dst, ar_dst;
  always_comb begin
    for (int m = 0; m < NM; m++) begin
      aw_dst[m] = xbar_decode(m_awaddr_i[m]);
      ar_dst[m] = xbar_decode(m_araddr_i[m]);
    end
  end

  // ===========================================================================
  // Per-master outstanding tracking (rule 2)
  // ===========================================================================
  logic [NM-1:0][OUT_CNT_W-1:0] wr_cnt_q, rd_cnt_q;
  logic [NM-1:0][SIDX_W-1:0]    wr_dst_q, rd_dst_q;
  logic [NM-1:0]                aw_ok, ar_ok;
  logic [NM-1:0]                m_aw_hs, m_b_hs, m_ar_hs, m_rlast_hs;

  always_comb begin
    for (int m = 0; m < NM; m++) begin
      aw_ok[m] = (wr_cnt_q[m] == '0) ||
                 ((wr_dst_q[m] == aw_dst[m]) && (wr_cnt_q[m] < OUT_CNT_W'(MAX_OUTSTANDING)));
      ar_ok[m] = (rd_cnt_q[m] == '0) ||
                 ((rd_dst_q[m] == ar_dst[m]) && (rd_cnt_q[m] < OUT_CNT_W'(MAX_OUTSTANDING)));
      m_aw_hs[m]    = m_awvalid_i[m] && m_awready_o[m];
      m_b_hs[m]     = m_bvalid_o[m]  && m_bready_i[m];
      m_ar_hs[m]    = m_arvalid_i[m] && m_arready_o[m];
      m_rlast_hs[m] = m_rvalid_o[m]  && m_rready_i[m] && m_rlast_o[m];
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      wr_cnt_q <= '0; rd_cnt_q <= '0; wr_dst_q <= '0; rd_dst_q <= '0;
    end else begin
      for (int m = 0; m < NM; m++) begin
        if (m_aw_hs[m]) wr_dst_q[m] <= aw_dst[m];
        if (m_ar_hs[m]) rd_dst_q[m] <= ar_dst[m];
        if (m_aw_hs[m] && !m_b_hs[m])      wr_cnt_q[m] <= wr_cnt_q[m] + 1'b1;
        else if (!m_aw_hs[m] && m_b_hs[m]) wr_cnt_q[m] <= wr_cnt_q[m] - 1'b1;
        if (m_ar_hs[m] && !m_rlast_hs[m])      rd_cnt_q[m] <= rd_cnt_q[m] + 1'b1;
        else if (!m_ar_hs[m] && m_rlast_hs[m]) rd_cnt_q[m] <= rd_cnt_q[m] - 1'b1;
      end
    end
  end

  // ===========================================================================
  // Write address: per-slave arbitration (rule 4) + W-owner FIFO (rule 3)
  // ===========================================================================
  logic [NSI-1:0][NM-1:0]     aw_req;
  logic [NSI-1:0]             aw_gnt_v;
  logic [NSI-1:0][MIDX_W-1:0] aw_gnt_i;

  logic [NSI-1:0][WQ_D-1:0][MIDX_W-1:0] wq_mem_q;
  logic [NSI-1:0][2:0]                  wq_wr_q, wq_rd_q;
  logic [NSI-1:0][3:0]                  wq_cnt_q;
  logic [NSI-1:0]                       wq_full, wq_empty, wq_push, wq_pop;
  logic [NSI-1:0][MIDX_W-1:0]           wq_head;

  for (genvar s = 0; s < NSI; s++) begin : g_aw
    for (genvar m = 0; m < NM; m++) begin : g_req
      assign aw_req[s][m] = m_awvalid_i[m] && aw_ok[m] &&
                            (aw_dst[m] == SIDX_W'(s)) && !wq_full[s];
    end

    meds_s1_rr_arbiter #(.N(NM), .IW(MIDX_W)) u_aw_arb (
      .clk_i   (clk_i),
      .rst_ni  (rst_ni),
      .req_i   (aw_req[s]),
      .ready_i (x_awready[s]),
      .valid_o (aw_gnt_v[s]),
      .idx_o   (aw_gnt_i[s])
    );

    assign x_awvalid[s] = aw_gnt_v[s];
    assign x_awid[s]    = {aw_gnt_i[s], m_awid_i[aw_gnt_i[s]]};
    assign x_awaddr[s]  = m_awaddr_i[aw_gnt_i[s]];
    assign x_awlen[s]   = m_awlen_i[aw_gnt_i[s]];
    assign x_awsize[s]  = m_awsize_i[aw_gnt_i[s]];
    assign x_awburst[s] = m_awburst_i[aw_gnt_i[s]];

    // W-owner FIFO: push the master on AW handshake, pop on the WLAST beat.
    assign wq_full[s]  = (wq_cnt_q[s] == 4'(WQ_D));
    assign wq_empty[s] = (wq_cnt_q[s] == 4'd0);
    assign wq_head[s]  = wq_mem_q[s][wq_rd_q[s]];
    assign wq_push[s]  = x_awvalid[s] && x_awready[s];
    assign wq_pop[s]   = x_wvalid[s] && x_wready[s] && x_wlast[s];

    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        wq_mem_q[s] <= '0; wq_wr_q[s] <= '0; wq_rd_q[s] <= '0; wq_cnt_q[s] <= '0;
      end else begin
        if (wq_push[s]) begin
          wq_mem_q[s][wq_wr_q[s]] <= aw_gnt_i[s];
          wq_wr_q[s] <= wq_wr_q[s] + 3'd1;
        end
        if (wq_pop[s]) wq_rd_q[s] <= wq_rd_q[s] + 3'd1;
        if (wq_push[s] && !wq_pop[s])      wq_cnt_q[s] <= wq_cnt_q[s] + 4'd1;
        else if (!wq_push[s] && wq_pop[s]) wq_cnt_q[s] <= wq_cnt_q[s] - 4'd1;
      end
    end

    // W data comes from the master at the head of the FIFO.
    assign x_wvalid[s] = !wq_empty[s] && m_wvalid_i[wq_head[s]];
    assign x_wdata[s]  = m_wdata_i[wq_head[s]];
    assign x_wstrb[s]  = m_wstrb_i[wq_head[s]];
    assign x_wlast[s]  = m_wlast_i[wq_head[s]];
  end

  always_comb begin
    for (int m = 0; m < NM; m++) begin
      m_awready_o[m] = 1'b0;
      m_wready_o[m]  = 1'b0;
      for (int s = 0; s < NSI; s++) begin
        if (aw_gnt_v[s] && (aw_gnt_i[s] == MIDX_W'(m)))
          m_awready_o[m] = x_awready[s];
        if (!wq_empty[s] && (wq_head[s] == MIDX_W'(m)))
          m_wready_o[m] = x_wready[s];
      end
    end
  end

  // ===========================================================================
  // Write response: routed by the ID tag (rule 1)
  // ===========================================================================
  always_comb begin
    m_bvalid_o = '0;
    m_bid_o    = '0;
    m_bresp_o  = '0;
    for (int s = 0; s < NSI; s++) begin
      x_bready[s] = m_bready_i[x_bid[s][AXI_SID_W-1 -: MIDX_W]];
      if (x_bvalid[s]) begin
        m_bvalid_o[x_bid[s][AXI_SID_W-1 -: MIDX_W]] = 1'b1;
        m_bid_o   [x_bid[s][AXI_SID_W-1 -: MIDX_W]] = x_bid[s][AXI_ID_W-1:0];
        m_bresp_o [x_bid[s][AXI_SID_W-1 -: MIDX_W]] = x_bresp[s];
      end
    end
  end

  // ===========================================================================
  // Read address: per-slave arbitration (rule 4)
  // ===========================================================================
  logic [NSI-1:0][NM-1:0]     ar_req;
  logic [NSI-1:0]             ar_gnt_v;
  logic [NSI-1:0][MIDX_W-1:0] ar_gnt_i;

  for (genvar s = 0; s < NSI; s++) begin : g_ar
    for (genvar m = 0; m < NM; m++) begin : g_req
      assign ar_req[s][m] = m_arvalid_i[m] && ar_ok[m] && (ar_dst[m] == SIDX_W'(s));
    end

    meds_s1_rr_arbiter #(.N(NM), .IW(MIDX_W)) u_ar_arb (
      .clk_i   (clk_i),
      .rst_ni  (rst_ni),
      .req_i   (ar_req[s]),
      .ready_i (x_arready[s]),
      .valid_o (ar_gnt_v[s]),
      .idx_o   (ar_gnt_i[s])
    );

    assign x_arvalid[s] = ar_gnt_v[s];
    assign x_arid[s]    = {ar_gnt_i[s], m_arid_i[ar_gnt_i[s]]};
    assign x_araddr[s]  = m_araddr_i[ar_gnt_i[s]];
    assign x_arlen[s]   = m_arlen_i[ar_gnt_i[s]];
    assign x_arsize[s]  = m_arsize_i[ar_gnt_i[s]];
    assign x_arburst[s] = m_arburst_i[ar_gnt_i[s]];
  end

  always_comb begin
    for (int m = 0; m < NM; m++) begin
      m_arready_o[m] = 1'b0;
      for (int s = 0; s < NSI; s++)
        if (ar_gnt_v[s] && (ar_gnt_i[s] == MIDX_W'(m))) m_arready_o[m] = x_arready[s];
    end
  end

  // ===========================================================================
  // Read data: routed by the ID tag (rule 1)
  // ===========================================================================
  always_comb begin
    m_rvalid_o = '0;
    m_rid_o    = '0;
    m_rdata_o  = '0;
    m_rresp_o  = '0;
    m_rlast_o  = '0;
    for (int s = 0; s < NSI; s++) begin
      x_rready[s] = m_rready_i[x_rid[s][AXI_SID_W-1 -: MIDX_W]];
      if (x_rvalid[s]) begin
        m_rvalid_o[x_rid[s][AXI_SID_W-1 -: MIDX_W]] = 1'b1;
        m_rid_o   [x_rid[s][AXI_SID_W-1 -: MIDX_W]] = x_rid[s][AXI_ID_W-1:0];
        m_rdata_o [x_rid[s][AXI_SID_W-1 -: MIDX_W]] = x_rdata[s];
        m_rresp_o [x_rid[s][AXI_SID_W-1 -: MIDX_W]] = x_rresp[s];
        m_rlast_o [x_rid[s][AXI_SID_W-1 -: MIDX_W]] = x_rlast[s];
      end
    end
  end

  // ===========================================================================
  // Performance events (SPEC sec12)
  // ===========================================================================
  always_comb begin
    evt_axi_read_beats_o       = '0;
    evt_axi_write_beats_o      = '0;
    evt_axi_read_outstanding_o = '0;
    evt_axi_arb_stall_o        = '0;
    for (int s = 0; s < NS; s++) begin   // real slaves only
      evt_axi_read_beats_o  += 4'(x_rvalid[s] && x_rready[s]);
      evt_axi_write_beats_o += 4'(x_wvalid[s] && x_wready[s]);
    end
    for (int m = 0; m < NM; m++)
      evt_axi_read_outstanding_o += 6'(rd_cnt_q[m]);
    for (int s = 0; s < NSI; s++) begin
      for (int m = 0; m < NM; m++) begin
        evt_axi_arb_stall_o += 5'(aw_req[s][m] && aw_gnt_i[s] != MIDX_W'(m));
        evt_axi_arb_stall_o += 5'(ar_req[s][m] && ar_gnt_i[s] != MIDX_W'(m));
      end
    end
  end

endmodule : meds_s1_axi4_crossbar
