// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// tb_meds_s1_axi_fabric : unit testbench for meds_s1_axi_fabric
//
// tb_fabric -- the complete meds_s1_axi_fabric, end to end:
//   3 narrow 64-bit masters (I$, D$, Debug DM) through the upsizers,
//   3 wide 256-bit masters (MXIF, Socket0 DMA, Socket1 DMA),
//   3 AXI4 memory models (Boot ROM, SRAM, DRAM), 2 socket cfg_axil models,
//   7 peripheral AXI4-Lite models.
//
// Run:  make test-unit TB=meds_s1_axi_fabric
// =============================================================================
`include "verif/common/tb_axi4_master.sv"
`include "verif/common/tb_axi4_mem.sv"
`include "verif/common/tb_axil_mem.sv"

module tb_meds_s1_axi_fabric;
  import meds_s1_axi4_pkg::*;
  localparam IDW = AXI_ID_W, SIDW = AXI_SID_W, NP = NUM_PERIPH;
  logic clk = 0, rst_n = 0;
  initial forever #5 clk = ~clk;
  int errors = 0, checks = 0;
  task automatic chk(string n, logic [255:0] g, logic [255:0] e);
    checks++; if (g !== e) begin errors++; if (errors < 25) $display("  [FAIL] %s  got=0x%0h exp=0x%0h", n, g, e); end
  endtask

  // narrow masters
  logic [2:0][IDW-1:0] n_awid, n_arid, n_bid, n_rid; logic [2:0][39:0] n_awaddr, n_araddr;
  logic [2:0][7:0] n_awlen, n_arlen; logic [2:0][2:0] n_awsize, n_arsize; logic [2:0][1:0] n_awburst, n_arburst, n_bresp, n_rresp;
  logic [2:0] n_awvalid, n_awready, n_wvalid, n_wready, n_wlast, n_bvalid, n_bready, n_arvalid, n_arready, n_rvalid, n_rready, n_rlast;
  logic [2:0][63:0] n_wdata, n_rdata; logic [2:0][7:0] n_wstrb;
  // wide masters
  logic [2:0][IDW-1:0] w_awid, w_arid, w_bid, w_rid; logic [2:0][39:0] w_awaddr, w_araddr;
  logic [2:0][7:0] w_awlen, w_arlen; logic [2:0][2:0] w_awsize, w_arsize; logic [2:0][1:0] w_awburst, w_arburst, w_bresp, w_rresp;
  logic [2:0] w_awvalid, w_awready, w_wvalid, w_wready, w_wlast, w_bvalid, w_bready, w_arvalid, w_arready, w_rvalid, w_rready, w_rlast;
  logic [2:0][255:0] w_wdata, w_rdata; logic [2:0][31:0] w_wstrb;
  // memories
  logic [2:0][SIDW-1:0] mm_awid, mm_arid, mm_bid, mm_rid; logic [2:0][39:0] mm_awaddr, mm_araddr;
  logic [2:0][7:0] mm_awlen, mm_arlen; logic [2:0][2:0] mm_awsize, mm_arsize; logic [2:0][1:0] mm_awburst, mm_arburst, mm_bresp, mm_rresp;
  logic [2:0] mm_awvalid, mm_awready, mm_wvalid, mm_wready, mm_wlast, mm_bvalid, mm_bready, mm_arvalid, mm_arready, mm_rvalid, mm_rready, mm_rlast;
  logic [2:0][255:0] mm_wdata, mm_rdata; logic [2:0][31:0] mm_wstrb;
  // socket cfg + peripherals (AXI4-Lite), sockets stored at indices NP, NP+1
  logic [NP+1:0][39:0] l_awaddr, l_araddr; logic [NP+1:0][31:0] l_wdata, l_rdata; logic [NP+1:0][3:0] l_wstrb;
  logic [NP+1:0][1:0] l_bresp, l_rresp;
  logic [NP+1:0] l_awvalid, l_awready, l_wvalid, l_wready, l_bvalid, l_bready, l_arvalid, l_arready, l_rvalid, l_rready;
  logic [3:0] ev_rb, ev_wb; logic [5:0] ev_ro; logic [4:0] ev_as;

  meds_s1_axi_fabric dut (.clk_i(clk), .rst_ni(rst_n),
    .n_awid_i(n_awid), .n_awaddr_i(n_awaddr), .n_awlen_i(n_awlen), .n_awsize_i(n_awsize), .n_awburst_i(n_awburst),
    .n_awvalid_i(n_awvalid), .n_awready_o(n_awready), .n_wdata_i(n_wdata), .n_wstrb_i(n_wstrb), .n_wlast_i(n_wlast),
    .n_wvalid_i(n_wvalid), .n_wready_o(n_wready), .n_bid_o(n_bid), .n_bresp_o(n_bresp), .n_bvalid_o(n_bvalid),
    .n_bready_i(n_bready), .n_arid_i(n_arid), .n_araddr_i(n_araddr), .n_arlen_i(n_arlen), .n_arsize_i(n_arsize),
    .n_arburst_i(n_arburst), .n_arvalid_i(n_arvalid), .n_arready_o(n_arready), .n_rid_o(n_rid), .n_rdata_o(n_rdata),
    .n_rresp_o(n_rresp), .n_rlast_o(n_rlast), .n_rvalid_o(n_rvalid), .n_rready_i(n_rready),
    .w_awid_i(w_awid), .w_awaddr_i(w_awaddr), .w_awlen_i(w_awlen), .w_awsize_i(w_awsize), .w_awburst_i(w_awburst),
    .w_awvalid_i(w_awvalid), .w_awready_o(w_awready), .w_wdata_i(w_wdata), .w_wstrb_i(w_wstrb), .w_wlast_i(w_wlast),
    .w_wvalid_i(w_wvalid), .w_wready_o(w_wready), .w_bid_o(w_bid), .w_bresp_o(w_bresp), .w_bvalid_o(w_bvalid),
    .w_bready_i(w_bready), .w_arid_i(w_arid), .w_araddr_i(w_araddr), .w_arlen_i(w_arlen), .w_arsize_i(w_arsize),
    .w_arburst_i(w_arburst), .w_arvalid_i(w_arvalid), .w_arready_o(w_arready), .w_rid_o(w_rid), .w_rdata_o(w_rdata),
    .w_rresp_o(w_rresp), .w_rlast_o(w_rlast), .w_rvalid_o(w_rvalid), .w_rready_i(w_rready),
    .mem_awid_o(mm_awid), .mem_awaddr_o(mm_awaddr), .mem_awlen_o(mm_awlen), .mem_awsize_o(mm_awsize),
    .mem_awburst_o(mm_awburst), .mem_awvalid_o(mm_awvalid), .mem_awready_i(mm_awready), .mem_wdata_o(mm_wdata),
    .mem_wstrb_o(mm_wstrb), .mem_wlast_o(mm_wlast), .mem_wvalid_o(mm_wvalid), .mem_wready_i(mm_wready),
    .mem_bid_i(mm_bid), .mem_bresp_i(mm_bresp), .mem_bvalid_i(mm_bvalid), .mem_bready_o(mm_bready),
    .mem_arid_o(mm_arid), .mem_araddr_o(mm_araddr), .mem_arlen_o(mm_arlen), .mem_arsize_o(mm_arsize),
    .mem_arburst_o(mm_arburst), .mem_arvalid_o(mm_arvalid), .mem_arready_i(mm_arready), .mem_rid_i(mm_rid),
    .mem_rdata_i(mm_rdata), .mem_rresp_i(mm_rresp), .mem_rlast_i(mm_rlast), .mem_rvalid_i(mm_rvalid), .mem_rready_o(mm_rready),
    .sk_awaddr_o(l_awaddr[NP+1:NP]), .sk_awvalid_o(l_awvalid[NP+1:NP]), .sk_awready_i(l_awready[NP+1:NP]),
    .sk_wdata_o(l_wdata[NP+1:NP]), .sk_wstrb_o(l_wstrb[NP+1:NP]), .sk_wvalid_o(l_wvalid[NP+1:NP]), .sk_wready_i(l_wready[NP+1:NP]),
    .sk_bresp_i(l_bresp[NP+1:NP]), .sk_bvalid_i(l_bvalid[NP+1:NP]), .sk_bready_o(l_bready[NP+1:NP]),
    .sk_araddr_o(l_araddr[NP+1:NP]), .sk_arvalid_o(l_arvalid[NP+1:NP]), .sk_arready_i(l_arready[NP+1:NP]),
    .sk_rdata_i(l_rdata[NP+1:NP]), .sk_rresp_i(l_rresp[NP+1:NP]), .sk_rvalid_i(l_rvalid[NP+1:NP]), .sk_rready_o(l_rready[NP+1:NP]),
    .p_awaddr_o(l_awaddr[NP-1:0]), .p_awvalid_o(l_awvalid[NP-1:0]), .p_awready_i(l_awready[NP-1:0]),
    .p_wdata_o(l_wdata[NP-1:0]), .p_wstrb_o(l_wstrb[NP-1:0]), .p_wvalid_o(l_wvalid[NP-1:0]), .p_wready_i(l_wready[NP-1:0]),
    .p_bresp_i(l_bresp[NP-1:0]), .p_bvalid_i(l_bvalid[NP-1:0]), .p_bready_o(l_bready[NP-1:0]),
    .p_araddr_o(l_araddr[NP-1:0]), .p_arvalid_o(l_arvalid[NP-1:0]), .p_arready_i(l_arready[NP-1:0]),
    .p_rdata_i(l_rdata[NP-1:0]), .p_rresp_i(l_rresp[NP-1:0]), .p_rvalid_i(l_rvalid[NP-1:0]), .p_rready_o(l_rready[NP-1:0]),
    .evt_axi_read_beats_o(ev_rb), .evt_axi_write_beats_o(ev_wb),
    .evt_axi_read_outstanding_o(ev_ro), .evt_axi_arb_stall_o(ev_as));

  for (genvar i = 0; i < 3; i++) begin : g_n
    tb_axi4_master #(.DW(64), .IDW(IDW)) bfm (.clk(clk),
      .awid(n_awid[i]), .awaddr(n_awaddr[i]), .awlen(n_awlen[i]), .awsize(n_awsize[i]), .awburst(n_awburst[i]),
      .awvalid(n_awvalid[i]), .awready(n_awready[i]), .wdata(n_wdata[i]), .wstrb(n_wstrb[i]), .wlast(n_wlast[i]),
      .wvalid(n_wvalid[i]), .wready(n_wready[i]), .bid(n_bid[i]), .bresp(n_bresp[i]), .bvalid(n_bvalid[i]), .bready(n_bready[i]),
      .arid(n_arid[i]), .araddr(n_araddr[i]), .arlen(n_arlen[i]), .arsize(n_arsize[i]), .arburst(n_arburst[i]),
      .arvalid(n_arvalid[i]), .arready(n_arready[i]), .rid(n_rid[i]), .rdata(n_rdata[i]), .rresp(n_rresp[i]),
      .rlast(n_rlast[i]), .rvalid(n_rvalid[i]), .rready(n_rready[i]));
  end
  for (genvar i = 0; i < 3; i++) begin : g_w
    tb_axi4_master #(.DW(256), .IDW(IDW)) bfm (.clk(clk),
      .awid(w_awid[i]), .awaddr(w_awaddr[i]), .awlen(w_awlen[i]), .awsize(w_awsize[i]), .awburst(w_awburst[i]),
      .awvalid(w_awvalid[i]), .awready(w_awready[i]), .wdata(w_wdata[i]), .wstrb(w_wstrb[i]), .wlast(w_wlast[i]),
      .wvalid(w_wvalid[i]), .wready(w_wready[i]), .bid(w_bid[i]), .bresp(w_bresp[i]), .bvalid(w_bvalid[i]), .bready(w_bready[i]),
      .arid(w_arid[i]), .araddr(w_araddr[i]), .arlen(w_arlen[i]), .arsize(w_arsize[i]), .arburst(w_arburst[i]),
      .arvalid(w_arvalid[i]), .arready(w_arready[i]), .rid(w_rid[i]), .rdata(w_rdata[i]), .rresp(w_rresp[i]),
      .rlast(w_rlast[i]), .rvalid(w_rvalid[i]), .rready(w_rready[i]));
  end
  for (genvar i = 0; i < 3; i++) begin : g_mem
    tb_axi4_mem #(.IDW(SIDW)) smem (.clk(clk), .rst_n(rst_n),
      .awid(mm_awid[i]), .awaddr(mm_awaddr[i]), .awlen(mm_awlen[i]), .awsize(mm_awsize[i]), .awburst(mm_awburst[i]),
      .awvalid(mm_awvalid[i]), .awready(mm_awready[i]), .wdata(mm_wdata[i]), .wstrb(mm_wstrb[i]), .wlast(mm_wlast[i]),
      .wvalid(mm_wvalid[i]), .wready(mm_wready[i]), .bid(mm_bid[i]), .bresp(mm_bresp[i]), .bvalid(mm_bvalid[i]), .bready(mm_bready[i]),
      .arid(mm_arid[i]), .araddr(mm_araddr[i]), .arlen(mm_arlen[i]), .arsize(mm_arsize[i]), .arburst(mm_arburst[i]),
      .arvalid(mm_arvalid[i]), .arready(mm_arready[i]), .rid(mm_rid[i]), .rdata(mm_rdata[i]), .rresp(mm_rresp[i]),
      .rlast(mm_rlast[i]), .rvalid(mm_rvalid[i]), .rready(mm_rready[i]));
  end
  for (genvar i = 0; i < NP + 2; i++) begin : g_l
    tb_axil_mem #(.MODE(i % 3)) lm (.clk(clk), .rst_n(rst_n),
      .awaddr(l_awaddr[i]), .awvalid(l_awvalid[i]), .awready(l_awready[i]),
      .wdata(l_wdata[i]), .wstrb(l_wstrb[i]), .wvalid(l_wvalid[i]), .wready(l_wready[i]),
      .bresp(l_bresp[i]), .bvalid(l_bvalid[i]), .bready(l_bready[i]),
      .araddr(l_araddr[i]), .arvalid(l_arvalid[i]), .arready(l_arready[i]),
      .rdata(l_rdata[i]), .rresp(l_rresp[i]), .rvalid(l_rvalid[i]), .rready(l_rready[i]));
  end

  // DRAM model must only ever see cached-range addresses (alias folded)
  int dram_bad_addr = 0;
  initial forever @(posedge clk) begin
    if (mm_awvalid[SLV_DRAM] && (mm_awaddr[SLV_DRAM] < DRAM_BASE || mm_awaddr[SLV_DRAM] >= DRAM_BASE + DRAM_SIZE)) dram_bad_addr++;
    if (mm_arvalid[SLV_DRAM] && (mm_araddr[SLV_DRAM] < DRAM_BASE || mm_araddr[SLV_DRAM] >= DRAM_BASE + DRAM_SIZE)) dram_bad_addr++;
  end
  // last Lite address seen per port
  logic [NP+1:0][39:0] l_last_aw, l_last_ar;
  always_ff @(posedge clk) for (int i = 0; i < NP + 2; i++) begin
    if (l_awvalid[i] && l_awready[i]) l_last_aw[i] <= l_awaddr[i];
    if (l_arvalid[i] && l_arready[i]) l_last_ar[i] <= l_araddr[i];
  end

  // D$ (narrow master 1): repeated 64-bit store/load pairs in its SRAM area
  int dc_err = 0;
  task automatic dcache_loop(int iters);
    for (int it = 0; it < iters; it++) begin
      logic [63:0] d[$], rd[$]; logic [7:0] s[$]; logic [1:0] r; logic [IDW-1:0] idb; int le; logic [39:0] a;
      d = {}; rd = {}; s = {};
      a = SRAM_BASE + 40'h8000 + $urandom_range(511) * 8;
      d.push_back({$urandom, $urandom}); s.push_back(8'hFF);
      g_n[1].bfm.write(a, 0, 3, BURST_INCR, 6'h1, d, s, r, idb);
      g_n[1].bfm.read(a, 0, 3, BURST_INCR, 6'h1, rd, r, idb, le);
      if (rd[0] !== d[0] || r !== RESP_OKAY) dc_err++;
    end
  endtask

  initial begin
    logic [63:0] d[$], rd[$]; logic [7:0] s[$]; logic [255:0] D[$], RD[$]; logic [31:0] S[$];
    logic [1:0] r; logic [IDW-1:0] idb; int le;
    repeat (3) @(posedge clk); rst_n = 1; repeat (2) @(posedge clk);

    // F1: D$ writes a 64 B line (INCR8x8); I$ refills it WRAP8x8 from word 5
    d = {}; s = {};
    for (int i = 0; i < 8; i++) begin d.push_back(64'hC0DE_0000_0000_0000 | i); s.push_back(8'hFF); end
    g_n[1].bfm.write(40'h4000_0040, 7, 3, BURST_INCR, 6'h7, d, s, r, idb); chk("F1 D$ line write", r, RESP_OKAY);
    g_n[0].bfm.read (40'h4000_0068, 7, 3, BURST_WRAP, 6'h9, rd, r, idb, le);
    for (int i = 0; i < 8; i++) chk($sformatf("F1 I$ WRAP refill word %0d", i), rd[i], 64'hC0DE_0000_0000_0000 | ((5 + i) % 8));

    // F2: DMA writes through the uncached alias, D$ reads the cached address
    D = {256'hFACE_FEED}; S = {'1};
    g_w[1].bfm.write(40'h1_0000_2000, 0, 5, BURST_INCR, 6'h3, D, S, r, idb); chk("F2 DMA write via alias", r, RESP_OKAY);
    g_n[1].bfm.read(40'h8000_2000, 0, 3, BURST_INCR, 6'h3, rd, r, idb, le);
    chk("F2 cached read sees alias write", rd[0], 64'hFACE_FEED);
    chk("F2 DRAM port only saw folded addresses", dram_bad_addr, 0);

    // F3: D$ 64-bit sd/ld to CLINT mtimecmp; byte store to UART
    d = {64'h0000_0001_2345_6789}; s = {8'hFF};
    g_n[1].bfm.write(40'h0200_4000, 0, 3, BURST_INCR, 6'h4, d, s, r, idb); chk("F3 sd mtimecmp", r, RESP_OKAY);
    g_n[1].bfm.read (40'h0200_4000, 0, 3, BURST_INCR, 6'h4, rd, r, idb, le); chk("F3 ld mtimecmp", rd[0], 64'h0000_0001_2345_6789);
    d = {64'h00AB_0000_0000_0000}; s = {8'h40};
    g_n[1].bfm.write(40'h1000_0006, 0, 0, BURST_INCR, 6'h4, d, s, r, idb); chk("F3 UART sb", r, RESP_OKAY);
    chk("F3 UART Lite address", l_last_aw[PER_UART0], 40'h1000_0004);

    // F4: Debug DM programs accelerator socket cfg registers
    d = {64'h0000_0004_0000_0000}; s = {8'hF0};
    g_n[2].bfm.write(40'h2000_000C, 0, 2, BURST_INCR, 6'h5, d, s, r, idb); chk("F4 DM -> socket0 cfg write", r, RESP_OKAY);
    chk("F4 socket0 cfg_axil address", l_last_aw[NP], SOCKET0_BASE + ACC_REG_STATUS);
    g_n[2].bfm.read(40'h2000_000C, 0, 2, BURST_INCR, 6'h5, rd, r, idb, le); chk("F4 socket0 cfg readback", rd[0][63:32], 32'h4);
    d = {64'h0000_0000_0000_0001}; s = {8'h0F};
    g_n[2].bfm.write(40'h2001_0008, 0, 2, BURST_INCR, 6'h5, d, s, r, idb);
    chk("F4 socket1 CTRL address", l_last_aw[NP+1], SOCKET1_BASE + ACC_REG_CTRL);

    // F5: I$ fetch from the Debug ROM window reaches the Debug-Module port
    g_n[0].bfm.read(40'h0000_0800, 0, 2, BURST_INCR, 6'h6, rd, r, idb, le);
    chk("F5 debug ROM fetch OKAY", r, RESP_OKAY);
    chk("F5 reached PER_DEBUG port", l_last_ar[PER_DEBUG], 40'h0000_0800);

    // F6: unmapped from MXIF
    g_w[0].bfm.read(40'h3000_0000, 1, 5, BURST_INCR, 6'h8, RD, r, idb, le);
    chk("F6 unmapped -> DECERR", r, RESP_DECERR); chk("F6 two beats", RD.size(), 2);

    // F7: everyone at once
    g_mem[0].smem.stall = 20; g_mem[1].smem.stall = 30; g_mem[2].smem.stall = 40;
    g_w[0].bfm.bp = 20; g_w[1].bfm.bp = 20; g_w[2].bfm.bp = 20;
    fork
      g_w[0].bfm.selfcheck(40, BOOT_ROM_BASE, SRAM_BASE, DRAM_BASE, DRAM_UC_BASE, SOCKET0_BASE, SRAM_BASE, 40'h1000, 40'h3000_0000);
      g_w[1].bfm.selfcheck(40, BOOT_ROM_BASE, SRAM_BASE, DRAM_BASE, DRAM_UC_BASE, SOCKET1_BASE, SRAM_BASE, 40'h2000, 40'h3000_0000);
      g_w[2].bfm.selfcheck(40, BOOT_ROM_BASE, SRAM_BASE, DRAM_BASE, DRAM_UC_BASE, UART0_BASE,   SRAM_BASE, 40'h3000, 40'h3000_0000);
      dcache_loop(150);
    join
    chk("F7 MXIF scoreboard", g_w[0].bfm.sc_err, 0);
    chk("F7 Socket0 DMA scoreboard", g_w[1].bfm.sc_err, 0);
    chk("F7 Socket1 DMA scoreboard", g_w[2].bfm.sc_err, 0);
    chk("F7 D$ scoreboard", dc_err, 0);
    chk("F7 DRAM port only saw folded addresses", dram_bad_addr, 0);

    if (errors == 0) begin
      $display("=== PASS : %0d checks ===", checks);
      $finish;
    end else begin
      $display("=== FAIL : %0d errors of %0d checks ===", errors, checks);
      $fatal(1, "tb_meds_s1_axi_fabric failed");
    end
  end
  initial begin #20ms; $fatal(1, "tb_meds_s1_axi_fabric: TIMEOUT"); end
endmodule
