// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// tb_meds_s1_axil_periph_subtree : unit testbench for meds_s1_axil_periph_subtree
//
// tb_periph -- meds_s1_axil_periph_subtree (to_axil + demux). The seven
// Lite peripherals use all three AW/W acceptance orders. Checks decode of
// every Appendix-B window, 64-bit CLINT access, 256-bit bursts, byte
// stores, DECERR for holes, SLVERR propagation, that a read touches only
// the words it asked for, and a random mix against a byte reference.
//
// Run:  make test-unit TB=meds_s1_axil_periph_subtree
// =============================================================================
`include "verif/common/tb_axi4_master.sv"
`include "verif/common/tb_axil_mem.sv"
`include "verif/common/tb_hs_chk.sv"

module tb_meds_s1_axil_periph_subtree;
  import meds_s1_axi4_pkg::*;
  localparam IDW = AXI_SID_W, NP = NUM_PERIPH;
  logic clk = 0, rst_n = 0;
  initial forever #5 clk = ~clk;
  int errors = 0, checks = 0;
  task automatic chk(string n, logic [255:0] g, logic [255:0] e);
    checks++; if (g !== e) begin errors++; if (errors < 25) $display("  [FAIL] %s  got=0x%0h exp=0x%0h", n, g, e); end
  endtask

  logic [IDW-1:0] awid, arid, bid, rid; logic [39:0] awaddr, araddr; logic [7:0] awlen, arlen;
  logic [2:0] awsize, arsize; logic [1:0] awburst, arburst, bresp, rresp;
  logic awvalid, awready, wvalid, wready, wlast, bvalid, bready, arvalid, arready, rvalid, rready, rlast;
  logic [255:0] wdata, rdata; logic [31:0] wstrb;
  logic [NP-1:0][39:0] p_awaddr, p_araddr; logic [NP-1:0][31:0] p_wdata, p_rdata; logic [NP-1:0][3:0] p_wstrb;
  logic [NP-1:0][1:0] p_bresp, p_rresp;
  logic [NP-1:0] p_awvalid, p_awready, p_wvalid, p_wready, p_bvalid, p_bready, p_arvalid, p_arready, p_rvalid, p_rready;

  tb_axi4_master #(.DW(256), .IDW(IDW)) m (.clk(clk),
    .awid(awid), .awaddr(awaddr), .awlen(awlen), .awsize(awsize), .awburst(awburst),
    .awvalid(awvalid), .awready(awready), .wdata(wdata), .wstrb(wstrb), .wlast(wlast),
    .wvalid(wvalid), .wready(wready), .bid(bid), .bresp(bresp), .bvalid(bvalid), .bready(bready),
    .arid(arid), .araddr(araddr), .arlen(arlen), .arsize(arsize), .arburst(arburst),
    .arvalid(arvalid), .arready(arready), .rid(rid), .rdata(rdata), .rresp(rresp),
    .rlast(rlast), .rvalid(rvalid), .rready(rready));

  meds_s1_axil_periph_subtree dut (.clk_i(clk), .rst_ni(rst_n),
    .axi_awid_i(awid), .axi_awaddr_i(awaddr), .axi_awlen_i(awlen), .axi_awsize_i(awsize),
    .axi_awburst_i(awburst), .axi_awvalid_i(awvalid), .axi_awready_o(awready),
    .axi_wdata_i(wdata), .axi_wstrb_i(wstrb), .axi_wlast_i(wlast), .axi_wvalid_i(wvalid), .axi_wready_o(wready),
    .axi_bid_o(bid), .axi_bresp_o(bresp), .axi_bvalid_o(bvalid), .axi_bready_i(bready),
    .axi_arid_i(arid), .axi_araddr_i(araddr), .axi_arlen_i(arlen), .axi_arsize_i(arsize),
    .axi_arburst_i(arburst), .axi_arvalid_i(arvalid), .axi_arready_o(arready),
    .axi_rid_o(rid), .axi_rdata_o(rdata), .axi_rresp_o(rresp), .axi_rlast_o(rlast),
    .axi_rvalid_o(rvalid), .axi_rready_i(rready),
    .p_awaddr_o(p_awaddr), .p_awvalid_o(p_awvalid), .p_awready_i(p_awready),
    .p_wdata_o(p_wdata), .p_wstrb_o(p_wstrb), .p_wvalid_o(p_wvalid), .p_wready_i(p_wready),
    .p_bresp_i(p_bresp), .p_bvalid_i(p_bvalid), .p_bready_o(p_bready),
    .p_araddr_o(p_araddr), .p_arvalid_o(p_arvalid), .p_arready_i(p_arready),
    .p_rdata_i(p_rdata), .p_rresp_i(p_rresp), .p_rvalid_i(p_rvalid), .p_rready_o(p_rready));

  for (genvar i = 0; i < NP; i++) begin : g_p
    tb_axil_mem #(.MODE(i % 3)) pm (.clk(clk), .rst_n(rst_n),
      .awaddr(p_awaddr[i]), .awvalid(p_awvalid[i]), .awready(p_awready[i]),
      .wdata(p_wdata[i]), .wstrb(p_wstrb[i]), .wvalid(p_wvalid[i]), .wready(p_wready[i]),
      .bresp(p_bresp[i]), .bvalid(p_bvalid[i]), .bready(p_bready[i]),
      .araddr(p_araddr[i]), .arvalid(p_arvalid[i]), .arready(p_arready[i]),
      .rdata(p_rdata[i]), .rresp(p_rresp[i]), .rvalid(p_rvalid[i]), .rready(p_rready[i]));
    tb_hs_chk #(.W(40), .NAME("p_aw")) c_aw (clk, rst_n, p_awvalid[i], p_awready[i], p_awaddr[i]);
    tb_hs_chk #(.W(36), .NAME("p_w"))  c_w  (clk, rst_n, p_wvalid[i],  p_wready[i],  {p_wstrb[i], p_wdata[i]});
    tb_hs_chk #(.W(40), .NAME("p_ar")) c_ar (clk, rst_n, p_arvalid[i], p_arready[i], p_araddr[i]);
  end

  // ---- helpers ----
  function automatic int aw_cnt(int p);
    case (p)
      0: return g_p[0].pm.aw_hs;
      1: return g_p[1].pm.aw_hs;
      2: return g_p[2].pm.aw_hs;
      3: return g_p[3].pm.aw_hs;
      4: return g_p[4].pm.aw_hs;
      5: return g_p[5].pm.aw_hs;
      6: return g_p[6].pm.aw_hs;
      default: return 0;
    endcase
  endfunction
  function automatic int ar_cnt(int p);
    case (p)
      0: return g_p[0].pm.ar_hs;
      1: return g_p[1].pm.ar_hs;
      2: return g_p[2].pm.ar_hs;
      3: return g_p[3].pm.ar_hs;
      4: return g_p[4].pm.ar_hs;
      5: return g_p[5].pm.ar_hs;
      6: return g_p[6].pm.ar_hs;
      default: return 0;
    endcase
  endfunction
  function automatic int chk_err(int p);
    case (p)
      0: return g_p[0].c_aw.errors + g_p[0].c_w.errors + g_p[0].c_ar.errors;
      1: return g_p[1].c_aw.errors + g_p[1].c_w.errors + g_p[1].c_ar.errors;
      2: return g_p[2].c_aw.errors + g_p[2].c_w.errors + g_p[2].c_ar.errors;
      3: return g_p[3].c_aw.errors + g_p[3].c_w.errors + g_p[3].c_ar.errors;
      4: return g_p[4].c_aw.errors + g_p[4].c_w.errors + g_p[4].c_ar.errors;
      5: return g_p[5].c_aw.errors + g_p[5].c_w.errors + g_p[5].c_ar.errors;
      6: return g_p[6].c_aw.errors + g_p[6].c_w.errors + g_p[6].c_ar.errors;
      default: return 0;
    endcase
  endfunction
  logic [7:0] ref_mem [longint];
  function automatic longint beat_addr(longint start, int i, int size, int len, int burst);
    longint step = 1 << size, total = step * (len + 1), base;
    if (burst == 0) return start;
    if (burst == 2) begin base = (start / total) * total; return base + ((start - base + i * step) % total); end
    if (i == 0) return start;
    return (start / step) * step + i * step;
  endfunction

  // Write a burst with random data, read it back, compare transferred bytes.
  task automatic xfer(longint start, int len, int size, int burst, string tag);
    logic [255:0] d[$], rd[$]; logic [31:0] s[$]; logic [1:0] r; logic [IDW-1:0] idb; int le;
    d = {}; rd = {}; s = {};
    for (int i = 0; i <= len; i++) begin
      longint a, hi; logic [255:0] dd; logic [31:0] ss;
      a  = beat_addr(start, i, size, len, burst);
      hi = (a / (1 << size)) * (1 << size) + (1 << size) - 1;
      for (int k = 0; k < 8; k++) dd[k*32 +: 32] = $urandom;
      ss = 0;
      for (longint b = a; b <= hi; b++) begin ss[b % 32] = 1; ref_mem[b] = dd[(b % 32) * 8 +: 8]; end
      d.push_back(dd); s.push_back(ss);
    end
    m.write(40'(start), 8'(len), 3'(size), 2'(burst), 9'h1C3, d, s, r, idb);
    chk({tag, " BRESP"}, r, RESP_OKAY);
    chk({tag, " BID"}, idb, 9'h1C3);
    m.read(40'(start), 8'(len), 3'(size), 2'(burst), 9'h0A7, rd, r, idb, le);
    chk({tag, " RRESP"}, r, RESP_OKAY);
    chk({tag, " RID"}, idb, 9'h0A7);
    chk({tag, " RLAST"}, le, 0);
    for (int i = 0; i <= len; i++) begin
      longint a, hi;
      a  = beat_addr(start, i, size, len, burst);
      hi = (a / (1 << size)) * (1 << size) + (1 << size) - 1;
      for (longint b = a; b <= hi; b++)
        chk($sformatf("%s beat%0d byte %0h", tag, i, b), rd[i][(b % 32) * 8 +: 8], ref_mem[b]);
    end
  endtask

  task automatic single(input logic [39:0] a, input logic [2:0] size, output logic [1:0] wr, output logic [1:0] rr);
    logic [255:0] d[$], rd[$]; logic [31:0] s[$]; logic [IDW-1:0] idb; int le;
    d = {'1}; s = {32'hFFFF_FFFF >> (32 - (1 << size)) << a[4:0]};
    m.write(a, 0, size, 1, 0, d, s, wr, idb);
    m.read(a, 0, size, 1, 0, rd, rr, idb, le);
  endtask

  longint base_of [NP];
  initial begin
    logic [1:0] wr, rr; int n0;
    base_of = '{DEBUG_ROM_BASE, CLINT_BASE, PLIC_BASE, UART0_BASE, SPI0_BASE, GPIO0_BASE, TIMER0_BASE};
    repeat (3) @(posedge clk); rst_n = 1; repeat (2) @(posedge clk);

    for (int p = 0; p < NP; p++) begin
      n0 = aw_cnt(p);
      xfer(base_of[p] + 8, 0, 2, 1, $sformatf("periph%0d word", p));
      chk($sformatf("periph%0d reached its own port", p), aw_cnt(p) - n0, 1);
    end
    xfer(40'h0200_4000, 0, 3, 1, "CLINT mtimecmp 64-bit sd/ld");
    chk("64-bit sd split into 2 Lite writes", aw_cnt(PER_CLINT), 3);
    xfer(40'h0C00_0100, 3, 5, 1, "PLIC 4-beat 256-bit INCR burst");
    xfer(40'h1000_0003, 0, 0, 1, "UART byte store @+3");
    xfer(40'h1000_1006, 0, 1, 1, "SPI half store @+6");
    xfer(40'h1000_2040, 3, 2, 2, "GPIO WRAP4x4");

    n0 = ar_cnt(PER_UART0);
    single(40'h1000_0004, 2, wr, rr);
    chk("32-bit read issues exactly one Lite read", ar_cnt(PER_UART0) - n0, 1);

    single(40'h1000_8000, 2, wr, rr);
    chk("hole in periph region: write DECERR", wr, RESP_DECERR);
    chk("hole in periph region: read DECERR",  rr, RESP_DECERR);
    single(40'h1000_0FFC, 2, wr, rr);
    chk("Lite SLVERR propagated on B", wr, RESP_SLVERR);
    chk("Lite SLVERR propagated on R", rr, RESP_SLVERR);

    xfer(40'h1000_3000, 1, 2, 1, "2-beat burst");      // old bridge left a beat behind here
    xfer(40'h1000_2000, 0, 2, 1, "write right after a burst");

    m.bp = 25;
    for (int it = 0; it < 120; it++) begin
      int p = $urandom_range(NP - 1), size = $urandom_range(5), burst = $urandom_range(1), len = $urandom_range(3);
      longint start = base_of[p] + 40'h100 + ($urandom_range(40'h200) & ~((1 << size) - 1));
      xfer(start, len, size, burst, $sformatf("rand%0d", it));
    end

    for (int p = 0; p < NP; p++) chk($sformatf("Lite port %0d handshakes stable", p), chk_err(p), 0);
    if (errors == 0) begin
      $display("=== PASS : %0d checks ===", checks);
      $finish;
    end else begin
      $display("=== FAIL : %0d errors of %0d checks ===", errors, checks);
      $fatal(1, "tb_meds_s1_axil_periph_subtree failed");
    end
  end
  initial begin #10ms; $fatal(1, "tb_meds_s1_axil_periph_subtree: TIMEOUT"); end
endmodule
