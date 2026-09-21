// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// tb_meds_s1_axi4_upsizer : unit testbench for meds_s1_axi4_upsizer
//
// tb_upsizer -- meds_s1_axi4_upsizer between a 64-bit master BFM and a
// 256-bit memory model. Cache-line WRAP refills (critical word first),
// INCR writes, byte/half/word stores, and a random mix checked against a
// byte-level reference.
//
// Run:  make test-unit TB=meds_s1_axi4_upsizer
// =============================================================================
`include "verif/common/tb_axi4_master.sv"
`include "verif/common/tb_axi4_mem.sv"
`include "verif/common/tb_hs_chk.sv"

module tb_meds_s1_axi4_upsizer;
  import meds_s1_axi4_pkg::*;
  logic clk = 0, rst_n = 0;
  initial forever #5 clk = ~clk;
  int errors = 0, checks = 0;
  task automatic chk(string n, logic [63:0] g, logic [63:0] e);
    checks++; if (g !== e) begin errors++; if (errors < 20) $display("  [FAIL] %s  got=0x%0h exp=0x%0h", n, g, e); end
  endtask

  // narrow side
  logic [5:0] awid, arid, bid, rid; logic [39:0] awaddr, araddr; logic [7:0] awlen, arlen;
  logic [2:0] awsize, arsize; logic [1:0] awburst, arburst, bresp, rresp;
  logic awvalid, awready, wvalid, wready, wlast, bvalid, bready, arvalid, arready, rvalid, rready, rlast;
  logic [63:0] wdata, rdata; logic [7:0] wstrb;
  // wide side
  logic [5:0] s_awid, s_arid, s_bid, s_rid; logic [39:0] s_awaddr, s_araddr; logic [7:0] s_awlen, s_arlen;
  logic [2:0] s_awsize, s_arsize; logic [1:0] s_awburst, s_arburst, s_bresp, s_rresp;
  logic s_awvalid, s_awready, s_wvalid, s_wready, s_wlast, s_bvalid, s_bready;
  logic s_arvalid, s_arready, s_rvalid, s_rready, s_rlast;
  logic [255:0] s_wdata, s_rdata; logic [31:0] s_wstrb;

  tb_axi4_master #(.DW(64), .IDW(6)) m (.clk(clk),
    .awid(awid), .awaddr(awaddr), .awlen(awlen), .awsize(awsize), .awburst(awburst),
    .awvalid(awvalid), .awready(awready), .wdata(wdata), .wstrb(wstrb), .wlast(wlast),
    .wvalid(wvalid), .wready(wready), .bid(bid), .bresp(bresp), .bvalid(bvalid), .bready(bready),
    .arid(arid), .araddr(araddr), .arlen(arlen), .arsize(arsize), .arburst(arburst),
    .arvalid(arvalid), .arready(arready), .rid(rid), .rdata(rdata), .rresp(rresp),
    .rlast(rlast), .rvalid(rvalid), .rready(rready));

  meds_s1_axi4_upsizer dut (.clk_i(clk), .rst_ni(rst_n),
    .m_awid_i(awid), .m_awaddr_i(awaddr), .m_awlen_i(awlen), .m_awsize_i(awsize), .m_awburst_i(awburst),
    .m_awvalid_i(awvalid), .m_awready_o(awready),
    .m_wdata_i(wdata), .m_wstrb_i(wstrb), .m_wlast_i(wlast), .m_wvalid_i(wvalid), .m_wready_o(wready),
    .m_bid_o(bid), .m_bresp_o(bresp), .m_bvalid_o(bvalid), .m_bready_i(bready),
    .m_arid_i(arid), .m_araddr_i(araddr), .m_arlen_i(arlen), .m_arsize_i(arsize), .m_arburst_i(arburst),
    .m_arvalid_i(arvalid), .m_arready_o(arready),
    .m_rid_o(rid), .m_rdata_o(rdata), .m_rresp_o(rresp), .m_rlast_o(rlast), .m_rvalid_o(rvalid), .m_rready_i(rready),
    .s_awid_o(s_awid), .s_awaddr_o(s_awaddr), .s_awlen_o(s_awlen), .s_awsize_o(s_awsize), .s_awburst_o(s_awburst),
    .s_awvalid_o(s_awvalid), .s_awready_i(s_awready),
    .s_wdata_o(s_wdata), .s_wstrb_o(s_wstrb), .s_wlast_o(s_wlast), .s_wvalid_o(s_wvalid), .s_wready_i(s_wready),
    .s_bid_i(s_bid), .s_bresp_i(s_bresp), .s_bvalid_i(s_bvalid), .s_bready_o(s_bready),
    .s_arid_o(s_arid), .s_araddr_o(s_araddr), .s_arlen_o(s_arlen), .s_arsize_o(s_arsize), .s_arburst_o(s_arburst),
    .s_arvalid_o(s_arvalid), .s_arready_i(s_arready),
    .s_rid_i(s_rid), .s_rdata_i(s_rdata), .s_rresp_i(s_rresp), .s_rlast_i(s_rlast), .s_rvalid_i(s_rvalid), .s_rready_o(s_rready));

  tb_axi4_mem #(.IDW(6)) smem (.clk(clk), .rst_n(rst_n),
    .awid(s_awid), .awaddr(s_awaddr), .awlen(s_awlen), .awsize(s_awsize), .awburst(s_awburst),
    .awvalid(s_awvalid), .awready(s_awready), .wdata(s_wdata), .wstrb(s_wstrb), .wlast(s_wlast),
    .wvalid(s_wvalid), .wready(s_wready), .bid(s_bid), .bresp(s_bresp), .bvalid(s_bvalid), .bready(s_bready),
    .arid(s_arid), .araddr(s_araddr), .arlen(s_arlen), .arsize(s_arsize), .arburst(s_arburst),
    .arvalid(s_arvalid), .arready(s_arready), .rid(s_rid), .rdata(s_rdata), .rresp(s_rresp),
    .rlast(s_rlast), .rvalid(s_rvalid), .rready(s_rready));

  tb_hs_chk #(.W(58), .NAME("s_aw")) c_aw (clk, rst_n, s_awvalid, s_awready, {s_awid, s_awaddr, s_awlen, s_awsize, s_awburst});
  tb_hs_chk #(.W(58), .NAME("s_ar")) c_ar (clk, rst_n, s_arvalid, s_arready, {s_arid, s_araddr, s_arlen, s_arsize, s_arburst});

  logic [7:0] ref_mem [longint];
  function automatic longint beat_addr(longint start, int i, int size, int len, int burst);
    longint step = 1 << size, total = step * (len + 1), base;
    if (burst == 0) return start;
    if (burst == 2) begin base = (start / total) * total; return base + ((start - base + i * step) % total); end
    if (i == 0) return start;
    return (start / step) * step + i * step;
  endfunction

  task automatic xfer(longint start, int len, int size, int burst, string tag);
    logic [63:0] d[$], rd[$]; logic [7:0] s[$]; logic [1:0] r; logic [5:0] idb; int le;
    d = {}; rd = {}; s = {};
    for (int i = 0; i <= len; i++) begin
      longint a, hi; logic [63:0] dd; logic [7:0] ss;
      a  = beat_addr(start, i, size, len, burst);
      hi = (a / (1 << size)) * (1 << size) + (1 << size) - 1;
      dd = {$urandom, $urandom}; ss = 0;
      for (longint b = a; b <= hi; b++) begin ss[b % 8] = 1; ref_mem[b] = dd[(b % 8) * 8 +: 8]; end
      d.push_back(dd); s.push_back(ss);
    end
    m.write(40'(start), 8'(len), 3'(size), 2'(burst), 6'h21, d, s, r, idb);
    chk({tag, " BRESP"}, r, 0);
    m.read(40'(start), 8'(len), 3'(size), 2'(burst), 6'h12, rd, r, idb, le);
    chk({tag, " RLAST"}, le, 0);
    for (int i = 0; i <= len; i++) begin
      longint a, hi;
      a  = beat_addr(start, i, size, len, burst);
      hi = (a / (1 << size)) * (1 << size) + (1 << size) - 1;
      for (longint b = a; b <= hi; b++) chk($sformatf("%s beat%0d byte %0h", tag, i, b), rd[i][(b % 8) * 8 +: 8], ref_mem[b]);
    end
  endtask

  initial begin
    repeat (3) @(posedge clk); rst_n = 1; repeat (2) @(posedge clk);
    xfer(40'h8000_0000, 7, 3, 1, "line fill INCR8x8");
    xfer(40'h8000_0068, 7, 3, 2, "refill WRAP8x8 critical-word-first");
    xfer(40'h8000_0101, 0, 0, 1, "sb");
    xfer(40'h8000_0112, 0, 1, 1, "sh");
    xfer(40'h8000_011C, 0, 2, 1, "sw");
    xfer(40'h8000_0138, 0, 3, 1, "sd lane 3");
    m.bp = 30; smem.stall = 30;
    for (int it = 0; it < 150; it++) begin
      int size = $urandom_range(3), burst = $urandom_range(2), len;
      longint start;
      len   = (burst == 2) ? (2 << $urandom_range(2)) - 1 : $urandom_range(9);
      start = 40'h8000_1000 + ($urandom_range(40'h400) & ~((1 << size) - 1));
      xfer(start, len, size, burst, $sformatf("rand%0d", it));
    end
    chk("AW payload stable", c_aw.errors, 0);
    chk("AR payload stable", c_ar.errors, 0);
    if (errors == 0) begin
      $display("=== PASS : %0d checks ===", checks);
      $finish;
    end else begin
      $display("=== FAIL : %0d errors of %0d checks ===", errors, checks);
      $fatal(1, "tb_meds_s1_axi4_upsizer failed");
    end
  end
  initial begin #5ms; $fatal(1, "tb_meds_s1_axi4_upsizer: TIMEOUT"); end
endmodule
