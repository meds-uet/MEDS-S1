// SPDX-License-Identifier: Apache-2.0
// Copyright (c) Maktab-e-Digital Systems Lahore
//
// meds_s1_axil_periph_subtree -- crossbar slave SLV_PERIPH, the "AXI4-Lite
// bridge -> periph" of SPEC Figure 1 / Figure 10. AXI4 256-bit in; one
// 32-bit AXI4-Lite port per peripheral out (SPEC sec24, Appendix B):
//   PER_DEBUG  0x0000_0000  4 KB   Debug Module ROM / scratch (SPEC sec13)
//   PER_CLINT  0x0200_0000  64 KB
//   PER_PLIC   0x0C00_0000  4 MB
//   PER_UART0  0x1000_0000  4 KB
//   PER_SPI0   0x1000_1000  4 KB
//   PER_GPIO0  0x1000_2000  4 KB
//   PER_TIMER0 0x1000_3000  4 KB
// Anything else in the peripheral region gets DECERR.
//
// Structure: meds_s1_axi4_to_axil (width/burst conversion) followed by
// meds_s1_axil_demux (address routing). Lite addresses are the full 40-bit
// address; a peripheral uses the low bits it needs.

module meds_s1_axil_periph_subtree
  import meds_s1_axi4_pkg::*;
(
  input  logic                                   clk_i,
  input  logic                                   rst_ni,

  // ---------------- AXI4 slave side (crossbar slot SLV_PERIPH) ----------------
  input  logic [AXI_SID_W-1:0]                   axi_awid_i,
  input  logic [AXI_ADDR_W-1:0]                  axi_awaddr_i,
  input  logic [7:0]                             axi_awlen_i,
  input  logic [2:0]                             axi_awsize_i,
  input  logic [1:0]                             axi_awburst_i,
  input  logic                                   axi_awvalid_i,
  output logic                                   axi_awready_o,
  input  logic [AXI_DATA_W-1:0]                  axi_wdata_i,
  input  logic [AXI_STRB_W-1:0]                  axi_wstrb_i,
  input  logic                                   axi_wlast_i,
  input  logic                                   axi_wvalid_i,
  output logic                                   axi_wready_o,
  output logic [AXI_SID_W-1:0]                   axi_bid_o,
  output logic [1:0]                             axi_bresp_o,
  output logic                                   axi_bvalid_o,
  input  logic                                   axi_bready_i,
  input  logic [AXI_SID_W-1:0]                   axi_arid_i,
  input  logic [AXI_ADDR_W-1:0]                  axi_araddr_i,
  input  logic [7:0]                             axi_arlen_i,
  input  logic [2:0]                             axi_arsize_i,
  input  logic [1:0]                             axi_arburst_i,
  input  logic                                   axi_arvalid_i,
  output logic                                   axi_arready_o,
  output logic [AXI_SID_W-1:0]                   axi_rid_o,
  output logic [AXI_DATA_W-1:0]                  axi_rdata_o,
  output logic [1:0]                             axi_rresp_o,
  output logic                                   axi_rlast_o,
  output logic                                   axi_rvalid_o,
  input  logic                                   axi_rready_i,

  // ---------------- one AXI4-Lite master port per peripheral ----------------
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
  output logic [NUM_PERIPH-1:0]                  p_rready_o
);

  // Single AXI4-Lite bus between the converter and the demux.
  logic [AXIL_ADDR_W-1:0] l_awaddr, l_araddr;
  logic [AXIL_DATA_W-1:0] l_wdata, l_rdata;
  logic [AXIL_STRB_W-1:0] l_wstrb;
  logic [1:0]             l_bresp, l_rresp;
  logic l_awvalid, l_awready, l_wvalid, l_wready, l_bvalid, l_bready;
  logic l_arvalid, l_arready, l_rvalid, l_rready;

  meds_s1_axi4_to_axil #(.ID_W(AXI_SID_W)) u_to_axil (
    .clk_i       (clk_i),
    .rst_ni      (rst_ni),
    .awid_i      (axi_awid_i),
    .awaddr_i    (axi_awaddr_i),
    .awlen_i     (axi_awlen_i),
    .awsize_i    (axi_awsize_i),
    .awburst_i   (axi_awburst_i),
    .awvalid_i   (axi_awvalid_i),
    .awready_o   (axi_awready_o),
    .wdata_i     (axi_wdata_i),
    .wstrb_i     (axi_wstrb_i),
    .wlast_i     (axi_wlast_i),
    .wvalid_i    (axi_wvalid_i),
    .wready_o    (axi_wready_o),
    .bid_o       (axi_bid_o),
    .bresp_o     (axi_bresp_o),
    .bvalid_o    (axi_bvalid_o),
    .bready_i    (axi_bready_i),
    .arid_i      (axi_arid_i),
    .araddr_i    (axi_araddr_i),
    .arlen_i     (axi_arlen_i),
    .arsize_i    (axi_arsize_i),
    .arburst_i   (axi_arburst_i),
    .arvalid_i   (axi_arvalid_i),
    .arready_o   (axi_arready_o),
    .rid_o       (axi_rid_o),
    .rdata_o     (axi_rdata_o),
    .rresp_o     (axi_rresp_o),
    .rlast_o     (axi_rlast_o),
    .rvalid_o    (axi_rvalid_o),
    .rready_i    (axi_rready_i),
    .l_awaddr_o  (l_awaddr),
    .l_awvalid_o (l_awvalid),
    .l_awready_i (l_awready),
    .l_wdata_o   (l_wdata),
    .l_wstrb_o   (l_wstrb),
    .l_wvalid_o  (l_wvalid),
    .l_wready_i  (l_wready),
    .l_bresp_i   (l_bresp),
    .l_bvalid_i  (l_bvalid),
    .l_bready_o  (l_bready),
    .l_araddr_o  (l_araddr),
    .l_arvalid_o (l_arvalid),
    .l_arready_i (l_arready),
    .l_rdata_i   (l_rdata),
    .l_rresp_i   (l_rresp),
    .l_rvalid_i  (l_rvalid),
    .l_rready_o  (l_rready)
  );

  logic [PIDX_W:0] aw_dec, ar_dec;   // {hit, index}
  assign aw_dec = periph_decode(l_awaddr);
  assign ar_dec = periph_decode(l_araddr);

  meds_s1_axil_demux #(.N(NUM_PERIPH), .SW(PIDX_W)) u_demux (
    .clk_i       (clk_i),
    .rst_ni      (rst_ni),
    .aw_hit_i    (aw_dec[PIDX_W]),
    .aw_sel_i    (aw_dec[PIDX_W-1:0]),
    .ar_hit_i    (ar_dec[PIDX_W]),
    .ar_sel_i    (ar_dec[PIDX_W-1:0]),
    .awaddr_i    (l_awaddr),
    .awvalid_i   (l_awvalid),
    .awready_o   (l_awready),
    .wdata_i     (l_wdata),
    .wstrb_i     (l_wstrb),
    .wvalid_i    (l_wvalid),
    .wready_o    (l_wready),
    .bresp_o     (l_bresp),
    .bvalid_o    (l_bvalid),
    .bready_i    (l_bready),
    .araddr_i    (l_araddr),
    .arvalid_i   (l_arvalid),
    .arready_o   (l_arready),
    .rdata_o     (l_rdata),
    .rresp_o     (l_rresp),
    .rvalid_o    (l_rvalid),
    .rready_i    (l_rready),
    .p_awaddr_o  (p_awaddr_o),
    .p_awvalid_o (p_awvalid_o),
    .p_awready_i (p_awready_i),
    .p_wdata_o   (p_wdata_o),
    .p_wstrb_o   (p_wstrb_o),
    .p_wvalid_o  (p_wvalid_o),
    .p_wready_i  (p_wready_i),
    .p_bresp_i   (p_bresp_i),
    .p_bvalid_i  (p_bvalid_i),
    .p_bready_o  (p_bready_o),
    .p_araddr_o  (p_araddr_o),
    .p_arvalid_o (p_arvalid_o),
    .p_arready_i (p_arready_i),
    .p_rdata_i   (p_rdata_i),
    .p_rresp_i   (p_rresp_i),
    .p_rvalid_i  (p_rvalid_i),
    .p_rready_o  (p_rready_o)
  );

endmodule : meds_s1_axil_periph_subtree
