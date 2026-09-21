// SPDX-License-Identifier: Apache-2.0
// Copyright (c) Maktab-e-Digital Systems Lahore
//
// meds_s1_axi_fabric -- the complete MEDS-S1 bus fabric (SPEC sec18,
// Figure 10):
//
//   narrow masters (64-bit) --[upsizer]--+
//     n[0] I$, n[1] D$, n[2] Debug DM    |
//   wide masters (256-bit) --------------+--> AXI4 crossbar --+--> mem[0] Boot ROM (AXI4)
//     w[0] MXIF coproc,                                       +--> mem[1] SRAM     (AXI4)
//     w[1] Socket0 DMA, w[2] Socket1 DMA                      +--> mem[2] DRAM/MIG (AXI4)
//                                                             +--> [to_axil] --> sk[0] Socket0 cfg_axil
//                                                             +--> [to_axil] --> sk[1] Socket1 cfg_axil
//                                                             +--> [periph subtree] --> p[0..6]
//
// Memory slaves see AXI_SID_W-wide IDs and must echo them back unchanged.
// The DRAM port always sees the cached address: the uncached alias
// (0x1_0000_0000, SPEC sec18.4) is folded onto DRAM_BASE here, so the DRAM
// controller needs no knowledge of the alias.
// Socket cfg and peripheral ports are 32-bit AXI4-Lite with the full 40-bit
// address.

module meds_s1_axi_fabric
  import meds_s1_axi4_pkg::*;
(
  input  logic clk_i,
  input  logic rst_ni,

  // ---------------- narrow 64-bit masters: 0=I$, 1=D$, 2=Debug DM ----------------
  input  logic [2:0][AXI_ID_W-1:0]      n_awid_i,
  input  logic [2:0][AXI_ADDR_W-1:0]    n_awaddr_i,
  input  logic [2:0][7:0]               n_awlen_i,
  input  logic [2:0][2:0]               n_awsize_i,
  input  logic [2:0][1:0]               n_awburst_i,
  input  logic [2:0]                    n_awvalid_i,
  output logic [2:0]                    n_awready_o,
  input  logic [2:0][NARROW_DATA_W-1:0] n_wdata_i,
  input  logic [2:0][NARROW_STRB_W-1:0] n_wstrb_i,
  input  logic [2:0]                    n_wlast_i,
  input  logic [2:0]                    n_wvalid_i,
  output logic [2:0]                    n_wready_o,
  output logic [2:0][AXI_ID_W-1:0]      n_bid_o,
  output logic [2:0][1:0]               n_bresp_o,
  output logic [2:0]                    n_bvalid_o,
  input  logic [2:0]                    n_bready_i,
  input  logic [2:0][AXI_ID_W-1:0]      n_arid_i,
  input  logic [2:0][AXI_ADDR_W-1:0]    n_araddr_i,
  input  logic [2:0][7:0]               n_arlen_i,
  input  logic [2:0][2:0]               n_arsize_i,
  input  logic [2:0][1:0]               n_arburst_i,
  input  logic [2:0]                    n_arvalid_i,
  output logic [2:0]                    n_arready_o,
  output logic [2:0][AXI_ID_W-1:0]      n_rid_o,
  output logic [2:0][NARROW_DATA_W-1:0] n_rdata_o,
  output logic [2:0][1:0]               n_rresp_o,
  output logic [2:0]                    n_rlast_o,
  output logic [2:0]                    n_rvalid_o,
  input  logic [2:0]                    n_rready_i,

  // ---------------- wide 256-bit masters: 0=MXIF, 1=Socket0 DMA, 2=Socket1 DMA ----------------
  input  logic [2:0][AXI_ID_W-1:0]      w_awid_i,
  input  logic [2:0][AXI_ADDR_W-1:0]    w_awaddr_i,
  input  logic [2:0][7:0]               w_awlen_i,
  input  logic [2:0][2:0]               w_awsize_i,
  input  logic [2:0][1:0]               w_awburst_i,
  input  logic [2:0]                    w_awvalid_i,
  output logic [2:0]                    w_awready_o,
  input  logic [2:0][AXI_DATA_W-1:0]    w_wdata_i,
  input  logic [2:0][AXI_STRB_W-1:0]    w_wstrb_i,
  input  logic [2:0]                    w_wlast_i,
  input  logic [2:0]                    w_wvalid_i,
  output logic [2:0]                    w_wready_o,
  output logic [2:0][AXI_ID_W-1:0]      w_bid_o,
  output logic [2:0][1:0]               w_bresp_o,
  output logic [2:0]                    w_bvalid_o,
  input  logic [2:0]                    w_bready_i,
  input  logic [2:0][AXI_ID_W-1:0]      w_arid_i,
  input  logic [2:0][AXI_ADDR_W-1:0]    w_araddr_i,
  input  logic [2:0][7:0]               w_arlen_i,
  input  logic [2:0][2:0]               w_arsize_i,
  input  logic [2:0][1:0]               w_arburst_i,
  input  logic [2:0]                    w_arvalid_i,
  output logic [2:0]                    w_arready_o,
  output logic [2:0][AXI_ID_W-1:0]      w_rid_o,
  output logic [2:0][AXI_DATA_W-1:0]    w_rdata_o,
  output logic [2:0][1:0]               w_rresp_o,
  output logic [2:0]                    w_rlast_o,
  output logic [2:0]                    w_rvalid_o,
  input  logic [2:0]                    w_rready_i,

  // ---------------- AXI4 memory slaves: 0=Boot ROM, 1=SRAM, 2=DRAM ----------------
  output logic [2:0][AXI_SID_W-1:0]     mem_awid_o,
  output logic [2:0][AXI_ADDR_W-1:0]    mem_awaddr_o,
  output logic [2:0][7:0]               mem_awlen_o,
  output logic [2:0][2:0]               mem_awsize_o,
  output logic [2:0][1:0]               mem_awburst_o,
  output logic [2:0]                    mem_awvalid_o,
  input  logic [2:0]                    mem_awready_i,
  output logic [2:0][AXI_DATA_W-1:0]    mem_wdata_o,
  output logic [2:0][AXI_STRB_W-1:0]    mem_wstrb_o,
  output logic [2:0]                    mem_wlast_o,
  output logic [2:0]                    mem_wvalid_o,
  input  logic [2:0]                    mem_wready_i,
  input  logic [2:0][AXI_SID_W-1:0]     mem_bid_i,
  input  logic [2:0][1:0]               mem_bresp_i,
  input  logic [2:0]                    mem_bvalid_i,
  output logic [2:0]                    mem_bready_o,
  output logic [2:0][AXI_SID_W-1:0]     mem_arid_o,
  output logic [2:0][AXI_ADDR_W-1:0]    mem_araddr_o,
  output logic [2:0][7:0]               mem_arlen_o,
  output logic [2:0][2:0]               mem_arsize_o,
  output logic [2:0][1:0]               mem_arburst_o,
  output logic [2:0]                    mem_arvalid_o,
  input  logic [2:0]                    mem_arready_i,
  input  logic [2:0][AXI_SID_W-1:0]     mem_rid_i,
  input  logic [2:0][AXI_DATA_W-1:0]    mem_rdata_i,
  input  logic [2:0][1:0]               mem_rresp_i,
  input  logic [2:0]                    mem_rlast_i,
  input  logic [2:0]                    mem_rvalid_i,
  output logic [2:0]                    mem_rready_o,

  // ---------------- socket cfg_axil ports (SPEC sec20): 0=Socket0, 1=Socket1 ----------------
  output logic [1:0][AXIL_ADDR_W-1:0]   sk_awaddr_o,
  output logic [1:0]                    sk_awvalid_o,
  input  logic [1:0]                    sk_awready_i,
  output logic [1:0][AXIL_DATA_W-1:0]   sk_wdata_o,
  output logic [1:0][AXIL_STRB_W-1:0]   sk_wstrb_o,
  output logic [1:0]                    sk_wvalid_o,
  input  logic [1:0]                    sk_wready_i,
  input  logic [1:0][1:0]               sk_bresp_i,
  input  logic [1:0]                    sk_bvalid_i,
  output logic [1:0]                    sk_bready_o,
  output logic [1:0][AXIL_ADDR_W-1:0]   sk_araddr_o,
  output logic [1:0]                    sk_arvalid_o,
  input  logic [1:0]                    sk_arready_i,
  input  logic [1:0][AXIL_DATA_W-1:0]   sk_rdata_i,
  input  logic [1:0][1:0]               sk_rresp_i,
  input  logic [1:0]                    sk_rvalid_i,
  output logic [1:0]                    sk_rready_o,

  // ---------------- peripheral AXI4-Lite ports (index = PER_*) ----------------
  output logic [NUM_PERIPH-1:0][AXIL_ADDR_W-1:0] p_awaddr_o,
  output logic [NUM_PERIPH-1:0]                  p_awvalid_o,
  input  logic [NUM_PERIPH-1:0]                  p_awready_i,
  output logic [NUM_PERIPH-1:0][AXIL_DATA_W-1:0] p_wdata_o,
  output logic [NUM_PERIPH-1:0][AXIL_STRB_W-1:0] p_wstrb_o,
  output logic [NUM_PERIPH-1:0]                  p_wvalid_o,
  input  logic [NUM_PERIPH-1:0]                  p_wready_i,
  input  logic [NUM_PERIPH-1:0][1:0]             p_bresp_i,
  input  logic [NUM_PERIPH-1:0]                  p_bvalid_i,
  output logic [NUM_PERIPH-1:0]                  p_bready_o,
  output logic [NUM_PERIPH-1:0][AXIL_ADDR_W-1:0] p_araddr_o,
  output logic [NUM_PERIPH-1:0]                  p_arvalid_o,
  input  logic [NUM_PERIPH-1:0]                  p_arready_i,
  input  logic [NUM_PERIPH-1:0][AXIL_DATA_W-1:0] p_rdata_i,
  input  logic [NUM_PERIPH-1:0][1:0]             p_rresp_i,
  input  logic [NUM_PERIPH-1:0]                  p_rvalid_i,
  output logic [NUM_PERIPH-1:0]                  p_rready_o,

  // ---------------- performance events (SPEC sec12) ----------------
  output logic [3:0] evt_axi_read_beats_o,
  output logic [3:0] evt_axi_write_beats_o,
  output logic [5:0] evt_axi_read_outstanding_o,
  output logic [4:0] evt_axi_arb_stall_o
);

  localparam int unsigned NM = NUM_MASTERS;
  localparam int unsigned NS = NUM_SLAVES;

  // ===========================================================================
  // Crossbar master side
  // ===========================================================================
  logic [NM-1:0][AXI_ID_W-1:0]   xm_awid, xm_bid, xm_arid, xm_rid;
  logic [NM-1:0][AXI_ADDR_W-1:0] xm_awaddr, xm_araddr;
  logic [NM-1:0][7:0]            xm_awlen, xm_arlen;
  logic [NM-1:0][2:0]            xm_awsize, xm_arsize;
  logic [NM-1:0][1:0]            xm_awburst, xm_arburst, xm_bresp, xm_rresp;
  logic [NM-1:0]                 xm_awvalid, xm_awready, xm_wlast, xm_wvalid, xm_wready;
  logic [NM-1:0]                 xm_bvalid, xm_bready, xm_arvalid, xm_arready;
  logic [NM-1:0]                 xm_rlast, xm_rvalid, xm_rready;
  logic [NM-1:0][AXI_DATA_W-1:0] xm_wdata, xm_rdata;
  logic [NM-1:0][AXI_STRB_W-1:0] xm_wstrb;

  // Narrow masters through upsizers: n[0]->I$, n[1]->D$, n[2]->Debug DM
  for (genvar n = 0; n < 3; n++) begin : g_narrow
    localparam int unsigned XI = (n == 0) ? MST_ICACHE : (n == 1) ? MST_DCACHE : MST_DEBUG;
    meds_s1_axi4_upsizer u_upsizer (
      .clk_i       (clk_i),
      .rst_ni      (rst_ni),
      .m_awid_i    (n_awid_i[n]),    .m_awaddr_i (n_awaddr_i[n]), .m_awlen_i (n_awlen_i[n]),
      .m_awsize_i  (n_awsize_i[n]),  .m_awburst_i(n_awburst_i[n]),
      .m_awvalid_i (n_awvalid_i[n]), .m_awready_o(n_awready_o[n]),
      .m_wdata_i   (n_wdata_i[n]),   .m_wstrb_i  (n_wstrb_i[n]),  .m_wlast_i (n_wlast_i[n]),
      .m_wvalid_i  (n_wvalid_i[n]),  .m_wready_o (n_wready_o[n]),
      .m_bid_o     (n_bid_o[n]),     .m_bresp_o  (n_bresp_o[n]),
      .m_bvalid_o  (n_bvalid_o[n]),  .m_bready_i (n_bready_i[n]),
      .m_arid_i    (n_arid_i[n]),    .m_araddr_i (n_araddr_i[n]), .m_arlen_i (n_arlen_i[n]),
      .m_arsize_i  (n_arsize_i[n]),  .m_arburst_i(n_arburst_i[n]),
      .m_arvalid_i (n_arvalid_i[n]), .m_arready_o(n_arready_o[n]),
      .m_rid_o     (n_rid_o[n]),     .m_rdata_o  (n_rdata_o[n]),  .m_rresp_o (n_rresp_o[n]),
      .m_rlast_o   (n_rlast_o[n]),   .m_rvalid_o (n_rvalid_o[n]), .m_rready_i(n_rready_i[n]),
      .s_awid_o    (xm_awid[XI]),    .s_awaddr_o (xm_awaddr[XI]), .s_awlen_o (xm_awlen[XI]),
      .s_awsize_o  (xm_awsize[XI]),  .s_awburst_o(xm_awburst[XI]),
      .s_awvalid_o (xm_awvalid[XI]), .s_awready_i(xm_awready[XI]),
      .s_wdata_o   (xm_wdata[XI]),   .s_wstrb_o  (xm_wstrb[XI]),  .s_wlast_o (xm_wlast[XI]),
      .s_wvalid_o  (xm_wvalid[XI]),  .s_wready_i (xm_wready[XI]),
      .s_bid_i     (xm_bid[XI]),     .s_bresp_i  (xm_bresp[XI]),
      .s_bvalid_i  (xm_bvalid[XI]),  .s_bready_o (xm_bready[XI]),
      .s_arid_o    (xm_arid[XI]),    .s_araddr_o (xm_araddr[XI]), .s_arlen_o (xm_arlen[XI]),
      .s_arsize_o  (xm_arsize[XI]),  .s_arburst_o(xm_arburst[XI]),
      .s_arvalid_o (xm_arvalid[XI]), .s_arready_i(xm_arready[XI]),
      .s_rid_i     (xm_rid[XI]),     .s_rdata_i  (xm_rdata[XI]),  .s_rresp_i (xm_rresp[XI]),
      .s_rlast_i   (xm_rlast[XI]),   .s_rvalid_i (xm_rvalid[XI]), .s_rready_o(xm_rready[XI])
    );
  end

  // Wide masters straight in: w[0]->MXIF, w[1]->Socket0 DMA, w[2]->Socket1 DMA
  for (genvar w = 0; w < 3; w++) begin : g_wide
    localparam int unsigned XI = MST_MXIF + w;
    assign xm_awid[XI]    = w_awid_i[w];
    assign xm_awaddr[XI]  = w_awaddr_i[w];
    assign xm_awlen[XI]   = w_awlen_i[w];
    assign xm_awsize[XI]  = w_awsize_i[w];
    assign xm_awburst[XI] = w_awburst_i[w];
    assign xm_awvalid[XI] = w_awvalid_i[w];
    assign w_awready_o[w] = xm_awready[XI];
    assign xm_wdata[XI]   = w_wdata_i[w];
    assign xm_wstrb[XI]   = w_wstrb_i[w];
    assign xm_wlast[XI]   = w_wlast_i[w];
    assign xm_wvalid[XI]  = w_wvalid_i[w];
    assign w_wready_o[w]  = xm_wready[XI];
    assign w_bid_o[w]     = xm_bid[XI];
    assign w_bresp_o[w]   = xm_bresp[XI];
    assign w_bvalid_o[w]  = xm_bvalid[XI];
    assign xm_bready[XI]  = w_bready_i[w];
    assign xm_arid[XI]    = w_arid_i[w];
    assign xm_araddr[XI]  = w_araddr_i[w];
    assign xm_arlen[XI]   = w_arlen_i[w];
    assign xm_arsize[XI]  = w_arsize_i[w];
    assign xm_arburst[XI] = w_arburst_i[w];
    assign xm_arvalid[XI] = w_arvalid_i[w];
    assign w_arready_o[w] = xm_arready[XI];
    assign w_rid_o[w]     = xm_rid[XI];
    assign w_rdata_o[w]   = xm_rdata[XI];
    assign w_rresp_o[w]   = xm_rresp[XI];
    assign w_rlast_o[w]   = xm_rlast[XI];
    assign w_rvalid_o[w]  = xm_rvalid[XI];
    assign xm_rready[XI]  = w_rready_i[w];
  end

  // ===========================================================================
  // Crossbar
  // ===========================================================================
  logic [NS-1:0][AXI_SID_W-1:0]  xs_awid, xs_bid, xs_arid, xs_rid;
  logic [NS-1:0][AXI_ADDR_W-1:0] xs_awaddr, xs_araddr;
  logic [NS-1:0][7:0]            xs_awlen, xs_arlen;
  logic [NS-1:0][2:0]            xs_awsize, xs_arsize;
  logic [NS-1:0][1:0]            xs_awburst, xs_arburst, xs_bresp, xs_rresp;
  logic [NS-1:0]                 xs_awvalid, xs_awready, xs_wlast, xs_wvalid, xs_wready;
  logic [NS-1:0]                 xs_bvalid, xs_bready, xs_arvalid, xs_arready;
  logic [NS-1:0]                 xs_rlast, xs_rvalid, xs_rready;
  logic [NS-1:0][AXI_DATA_W-1:0] xs_wdata, xs_rdata;
  logic [NS-1:0][AXI_STRB_W-1:0] xs_wstrb;

  meds_s1_axi4_crossbar u_xbar (
    .clk_i (clk_i), .rst_ni (rst_ni),
    .m_awid_i (xm_awid), .m_awaddr_i (xm_awaddr), .m_awlen_i (xm_awlen), .m_awsize_i (xm_awsize),
    .m_awburst_i (xm_awburst), .m_awvalid_i (xm_awvalid), .m_awready_o (xm_awready),
    .m_wdata_i (xm_wdata), .m_wstrb_i (xm_wstrb), .m_wlast_i (xm_wlast),
    .m_wvalid_i (xm_wvalid), .m_wready_o (xm_wready),
    .m_bid_o (xm_bid), .m_bresp_o (xm_bresp), .m_bvalid_o (xm_bvalid), .m_bready_i (xm_bready),
    .m_arid_i (xm_arid), .m_araddr_i (xm_araddr), .m_arlen_i (xm_arlen), .m_arsize_i (xm_arsize),
    .m_arburst_i (xm_arburst), .m_arvalid_i (xm_arvalid), .m_arready_o (xm_arready),
    .m_rid_o (xm_rid), .m_rdata_o (xm_rdata), .m_rresp_o (xm_rresp), .m_rlast_o (xm_rlast),
    .m_rvalid_o (xm_rvalid), .m_rready_i (xm_rready),
    .s_awid_o (xs_awid), .s_awaddr_o (xs_awaddr), .s_awlen_o (xs_awlen), .s_awsize_o (xs_awsize),
    .s_awburst_o (xs_awburst), .s_awvalid_o (xs_awvalid), .s_awready_i (xs_awready),
    .s_wdata_o (xs_wdata), .s_wstrb_o (xs_wstrb), .s_wlast_o (xs_wlast),
    .s_wvalid_o (xs_wvalid), .s_wready_i (xs_wready),
    .s_bid_i (xs_bid), .s_bresp_i (xs_bresp), .s_bvalid_i (xs_bvalid), .s_bready_o (xs_bready),
    .s_arid_o (xs_arid), .s_araddr_o (xs_araddr), .s_arlen_o (xs_arlen), .s_arsize_o (xs_arsize),
    .s_arburst_o (xs_arburst), .s_arvalid_o (xs_arvalid), .s_arready_i (xs_arready),
    .s_rid_i (xs_rid), .s_rdata_i (xs_rdata), .s_rresp_i (xs_rresp), .s_rlast_i (xs_rlast),
    .s_rvalid_i (xs_rvalid), .s_rready_o (xs_rready),
    .evt_axi_read_beats_o       (evt_axi_read_beats_o),
    .evt_axi_write_beats_o      (evt_axi_write_beats_o),
    .evt_axi_read_outstanding_o (evt_axi_read_outstanding_o),
    .evt_axi_arb_stall_o        (evt_axi_arb_stall_o)
  );

  // ===========================================================================
  // Memory slaves 0..2 (Boot ROM, SRAM, DRAM) are plain AXI4 pass-through
  // ===========================================================================
  function automatic logic [AXI_ADDR_W-1:0] fold_dram(input logic [AXI_ADDR_W-1:0] a);
    return DRAM_BASE | (a & (DRAM_SIZE - 1));   // uncached alias -> cached address
  endfunction

  for (genvar s = 0; s < 3; s++) begin : g_mem
    assign mem_awid_o[s]    = xs_awid[s];
    assign mem_awaddr_o[s]  = (s == SLV_DRAM) ? fold_dram(xs_awaddr[s]) : xs_awaddr[s];
    assign mem_awlen_o[s]   = xs_awlen[s];
    assign mem_awsize_o[s]  = xs_awsize[s];
    assign mem_awburst_o[s] = xs_awburst[s];
    assign mem_awvalid_o[s] = xs_awvalid[s];
    assign xs_awready[s]    = mem_awready_i[s];
    assign mem_wdata_o[s]   = xs_wdata[s];
    assign mem_wstrb_o[s]   = xs_wstrb[s];
    assign mem_wlast_o[s]   = xs_wlast[s];
    assign mem_wvalid_o[s]  = xs_wvalid[s];
    assign xs_wready[s]     = mem_wready_i[s];
    assign xs_bid[s]        = mem_bid_i[s];
    assign xs_bresp[s]      = mem_bresp_i[s];
    assign xs_bvalid[s]     = mem_bvalid_i[s];
    assign mem_bready_o[s]  = xs_bready[s];
    assign mem_arid_o[s]    = xs_arid[s];
    assign mem_araddr_o[s]  = (s == SLV_DRAM) ? fold_dram(xs_araddr[s]) : xs_araddr[s];
    assign mem_arlen_o[s]   = xs_arlen[s];
    assign mem_arsize_o[s]  = xs_arsize[s];
    assign mem_arburst_o[s] = xs_arburst[s];
    assign mem_arvalid_o[s] = xs_arvalid[s];
    assign xs_arready[s]    = mem_arready_i[s];
    assign xs_rid[s]        = mem_rid_i[s];
    assign xs_rdata[s]      = mem_rdata_i[s];
    assign xs_rresp[s]      = mem_rresp_i[s];
    assign xs_rlast[s]      = mem_rlast_i[s];
    assign xs_rvalid[s]     = mem_rvalid_i[s];
    assign mem_rready_o[s]  = xs_rready[s];
  end

  // ===========================================================================
  // Socket cfg windows (slaves 3, 4): AXI4 -> 32-bit AXI4-Lite cfg_axil
  // ===========================================================================
  for (genvar k = 0; k < 2; k++) begin : g_sock
    localparam int unsigned S = SLV_SOCKET0 + k;
    meds_s1_axi4_to_axil #(.ID_W(AXI_SID_W)) u_cfg (
      .clk_i (clk_i), .rst_ni (rst_ni),
      .awid_i (xs_awid[S]), .awaddr_i (xs_awaddr[S]), .awlen_i (xs_awlen[S]), .awsize_i (xs_awsize[S]),
      .awburst_i (xs_awburst[S]), .awvalid_i (xs_awvalid[S]), .awready_o (xs_awready[S]),
      .wdata_i (xs_wdata[S]), .wstrb_i (xs_wstrb[S]), .wlast_i (xs_wlast[S]),
      .wvalid_i (xs_wvalid[S]), .wready_o (xs_wready[S]),
      .bid_o (xs_bid[S]), .bresp_o (xs_bresp[S]), .bvalid_o (xs_bvalid[S]), .bready_i (xs_bready[S]),
      .arid_i (xs_arid[S]), .araddr_i (xs_araddr[S]), .arlen_i (xs_arlen[S]), .arsize_i (xs_arsize[S]),
      .arburst_i (xs_arburst[S]), .arvalid_i (xs_arvalid[S]), .arready_o (xs_arready[S]),
      .rid_o (xs_rid[S]), .rdata_o (xs_rdata[S]), .rresp_o (xs_rresp[S]), .rlast_o (xs_rlast[S]),
      .rvalid_o (xs_rvalid[S]), .rready_i (xs_rready[S]),
      .l_awaddr_o (sk_awaddr_o[k]), .l_awvalid_o (sk_awvalid_o[k]), .l_awready_i (sk_awready_i[k]),
      .l_wdata_o (sk_wdata_o[k]), .l_wstrb_o (sk_wstrb_o[k]), .l_wvalid_o (sk_wvalid_o[k]),
      .l_wready_i (sk_wready_i[k]),
      .l_bresp_i (sk_bresp_i[k]), .l_bvalid_i (sk_bvalid_i[k]), .l_bready_o (sk_bready_o[k]),
      .l_araddr_o (sk_araddr_o[k]), .l_arvalid_o (sk_arvalid_o[k]), .l_arready_i (sk_arready_i[k]),
      .l_rdata_i (sk_rdata_i[k]), .l_rresp_i (sk_rresp_i[k]), .l_rvalid_i (sk_rvalid_i[k]),
      .l_rready_o (sk_rready_o[k])
    );
  end

  // ===========================================================================
  // Peripheral subtree (slave 5)
  // ===========================================================================
  meds_s1_axil_periph_subtree u_periph (
    .clk_i (clk_i), .rst_ni (rst_ni),
    .axi_awid_i (xs_awid[SLV_PERIPH]), .axi_awaddr_i (xs_awaddr[SLV_PERIPH]),
    .axi_awlen_i (xs_awlen[SLV_PERIPH]), .axi_awsize_i (xs_awsize[SLV_PERIPH]),
    .axi_awburst_i (xs_awburst[SLV_PERIPH]), .axi_awvalid_i (xs_awvalid[SLV_PERIPH]),
    .axi_awready_o (xs_awready[SLV_PERIPH]),
    .axi_wdata_i (xs_wdata[SLV_PERIPH]), .axi_wstrb_i (xs_wstrb[SLV_PERIPH]),
    .axi_wlast_i (xs_wlast[SLV_PERIPH]), .axi_wvalid_i (xs_wvalid[SLV_PERIPH]),
    .axi_wready_o (xs_wready[SLV_PERIPH]),
    .axi_bid_o (xs_bid[SLV_PERIPH]), .axi_bresp_o (xs_bresp[SLV_PERIPH]),
    .axi_bvalid_o (xs_bvalid[SLV_PERIPH]), .axi_bready_i (xs_bready[SLV_PERIPH]),
    .axi_arid_i (xs_arid[SLV_PERIPH]), .axi_araddr_i (xs_araddr[SLV_PERIPH]),
    .axi_arlen_i (xs_arlen[SLV_PERIPH]), .axi_arsize_i (xs_arsize[SLV_PERIPH]),
    .axi_arburst_i (xs_arburst[SLV_PERIPH]), .axi_arvalid_i (xs_arvalid[SLV_PERIPH]),
    .axi_arready_o (xs_arready[SLV_PERIPH]),
    .axi_rid_o (xs_rid[SLV_PERIPH]), .axi_rdata_o (xs_rdata[SLV_PERIPH]),
    .axi_rresp_o (xs_rresp[SLV_PERIPH]), .axi_rlast_o (xs_rlast[SLV_PERIPH]),
    .axi_rvalid_o (xs_rvalid[SLV_PERIPH]), .axi_rready_i (xs_rready[SLV_PERIPH]),
    .p_awaddr_o (p_awaddr_o), .p_awvalid_o (p_awvalid_o), .p_awready_i (p_awready_i),
    .p_wdata_o (p_wdata_o), .p_wstrb_o (p_wstrb_o), .p_wvalid_o (p_wvalid_o), .p_wready_i (p_wready_i),
    .p_bresp_i (p_bresp_i), .p_bvalid_i (p_bvalid_i), .p_bready_o (p_bready_o),
    .p_araddr_o (p_araddr_o), .p_arvalid_o (p_arvalid_o), .p_arready_i (p_arready_i),
    .p_rdata_i (p_rdata_i), .p_rresp_i (p_rresp_i), .p_rvalid_i (p_rvalid_i), .p_rready_o (p_rready_o)
  );

endmodule : meds_s1_axi_fabric
