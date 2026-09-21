// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// tb_meds_s1_axi4_crossbar : unit testbench for meds_s1_axi4_crossbar
//
// tb_xbar -- meds_s1_axi4_crossbar with 6 master BFMs and 6 memory models.
//   T1 decode of every Appendix-B region, 1 GB DRAM limit, DECERR bursts
//   T2 masters that park their address bus at 0 after the handshake
//   T3 one master, two outstanding writes/reads to DIFFERENT slaves
//   T4 one master, 4 outstanding writes/reads to the SAME slave
//   T5 all 6 masters at once, random bursts, random stalls/backpressure,
//      every read checked against a scoreboard
//   T6 perf events agree with what the slaves saw
// Protocol checkers watch every slave AW/W/AR and every master B/R.
//
// Run:  make test-unit TB=meds_s1_axi4_crossbar
// =============================================================================
`include "verif/common/tb_axi4_master.sv"
`include "verif/common/tb_axi4_mem.sv"
`include "verif/common/tb_hs_chk.sv"

module tb_meds_s1_axi4_crossbar;
  import meds_s1_axi4_pkg::*;
  localparam NM = NUM_MASTERS, NS = NUM_SLAVES, IDW = AXI_ID_W, SIDW = AXI_SID_W;
  logic clk = 0, rst_n = 0;
  initial forever #5 clk = ~clk;
  int errors = 0, checks = 0;
  task automatic chk(string n, logic [255:0] g, logic [255:0] e);
    checks++; if (g !== e) begin errors++; if (errors < 25) $display("  [FAIL] %s  got=0x%0h exp=0x%0h", n, g, e); end
  endtask

  // ---------------- master side ----------------
  logic [NM-1:0][IDW-1:0] m_awid, m_arid, m_bid, m_rid; logic [NM-1:0][39:0] m_awaddr, m_araddr;
  logic [NM-1:0][7:0] m_awlen, m_arlen; logic [NM-1:0][2:0] m_awsize, m_arsize;
  logic [NM-1:0][1:0] m_awburst, m_arburst, m_bresp, m_rresp;
  logic [NM-1:0] m_awvalid, m_awready, m_wvalid, m_wready, m_wlast, m_bvalid, m_bready;
  logic [NM-1:0] m_arvalid, m_arready, m_rvalid, m_rready, m_rlast;
  logic [NM-1:0][255:0] m_wdata, m_rdata; logic [NM-1:0][31:0] m_wstrb;
  // ---------------- slave side ----------------
  logic [NS-1:0][SIDW-1:0] s_awid, s_arid, s_bid, s_rid; logic [NS-1:0][39:0] s_awaddr, s_araddr;
  logic [NS-1:0][7:0] s_awlen, s_arlen; logic [NS-1:0][2:0] s_awsize, s_arsize;
  logic [NS-1:0][1:0] s_awburst, s_arburst, s_bresp, s_rresp;
  logic [NS-1:0] s_awvalid, s_awready, s_wvalid, s_wready, s_wlast, s_bvalid, s_bready;
  logic [NS-1:0] s_arvalid, s_arready, s_rvalid, s_rready, s_rlast;
  logic [NS-1:0][255:0] s_wdata, s_rdata; logic [NS-1:0][31:0] s_wstrb;
  logic [3:0] ev_rb, ev_wb; logic [5:0] ev_ro; logic [4:0] ev_as;

  meds_s1_axi4_crossbar dut (.clk_i(clk), .rst_ni(rst_n),
    .m_awid_i(m_awid), .m_awaddr_i(m_awaddr), .m_awlen_i(m_awlen), .m_awsize_i(m_awsize), .m_awburst_i(m_awburst),
    .m_awvalid_i(m_awvalid), .m_awready_o(m_awready),
    .m_wdata_i(m_wdata), .m_wstrb_i(m_wstrb), .m_wlast_i(m_wlast), .m_wvalid_i(m_wvalid), .m_wready_o(m_wready),
    .m_bid_o(m_bid), .m_bresp_o(m_bresp), .m_bvalid_o(m_bvalid), .m_bready_i(m_bready),
    .m_arid_i(m_arid), .m_araddr_i(m_araddr), .m_arlen_i(m_arlen), .m_arsize_i(m_arsize), .m_arburst_i(m_arburst),
    .m_arvalid_i(m_arvalid), .m_arready_o(m_arready),
    .m_rid_o(m_rid), .m_rdata_o(m_rdata), .m_rresp_o(m_rresp), .m_rlast_o(m_rlast), .m_rvalid_o(m_rvalid), .m_rready_i(m_rready),
    .s_awid_o(s_awid), .s_awaddr_o(s_awaddr), .s_awlen_o(s_awlen), .s_awsize_o(s_awsize), .s_awburst_o(s_awburst),
    .s_awvalid_o(s_awvalid), .s_awready_i(s_awready),
    .s_wdata_o(s_wdata), .s_wstrb_o(s_wstrb), .s_wlast_o(s_wlast), .s_wvalid_o(s_wvalid), .s_wready_i(s_wready),
    .s_bid_i(s_bid), .s_bresp_i(s_bresp), .s_bvalid_i(s_bvalid), .s_bready_o(s_bready),
    .s_arid_o(s_arid), .s_araddr_o(s_araddr), .s_arlen_o(s_arlen), .s_arsize_o(s_arsize), .s_arburst_o(s_arburst),
    .s_arvalid_o(s_arvalid), .s_arready_i(s_arready),
    .s_rid_i(s_rid), .s_rdata_i(s_rdata), .s_rresp_i(s_rresp), .s_rlast_i(s_rlast), .s_rvalid_i(s_rvalid), .s_rready_o(s_rready),
    .evt_axi_read_beats_o(ev_rb), .evt_axi_write_beats_o(ev_wb),
    .evt_axi_read_outstanding_o(ev_ro), .evt_axi_arb_stall_o(ev_as));

  for (genvar s = 0; s < NS; s++) begin : g_s
    tb_axi4_mem #(.IDW(SIDW)) smem (.clk(clk), .rst_n(rst_n),
      .awid(s_awid[s]), .awaddr(s_awaddr[s]), .awlen(s_awlen[s]), .awsize(s_awsize[s]), .awburst(s_awburst[s]),
      .awvalid(s_awvalid[s]), .awready(s_awready[s]), .wdata(s_wdata[s]), .wstrb(s_wstrb[s]), .wlast(s_wlast[s]),
      .wvalid(s_wvalid[s]), .wready(s_wready[s]), .bid(s_bid[s]), .bresp(s_bresp[s]), .bvalid(s_bvalid[s]), .bready(s_bready[s]),
      .arid(s_arid[s]), .araddr(s_araddr[s]), .arlen(s_arlen[s]), .arsize(s_arsize[s]), .arburst(s_arburst[s]),
      .arvalid(s_arvalid[s]), .arready(s_arready[s]), .rid(s_rid[s]), .rdata(s_rdata[s]), .rresp(s_rresp[s]),
      .rlast(s_rlast[s]), .rvalid(s_rvalid[s]), .rready(s_rready[s]));
    tb_hs_chk #(.W(SIDW+53), .NAME("s_aw")) c_aw (clk, rst_n, s_awvalid[s], s_awready[s], {s_awid[s], s_awaddr[s], s_awlen[s], s_awsize[s], s_awburst[s]});
    tb_hs_chk #(.W(289),     .NAME("s_w"))  c_w  (clk, rst_n, s_wvalid[s],  s_wready[s],  {s_wlast[s], s_wstrb[s], s_wdata[s]});
    tb_hs_chk #(.W(SIDW+53), .NAME("s_ar")) c_ar (clk, rst_n, s_arvalid[s], s_arready[s], {s_arid[s], s_araddr[s], s_arlen[s], s_arsize[s], s_arburst[s]});
  end

  for (genvar m = 0; m < NM; m++) begin : g_m
    tb_axi4_master #(.DW(256), .IDW(IDW)) bfm (.clk(clk),
      .awid(m_awid[m]), .awaddr(m_awaddr[m]), .awlen(m_awlen[m]), .awsize(m_awsize[m]), .awburst(m_awburst[m]),
      .awvalid(m_awvalid[m]), .awready(m_awready[m]), .wdata(m_wdata[m]), .wstrb(m_wstrb[m]), .wlast(m_wlast[m]),
      .wvalid(m_wvalid[m]), .wready(m_wready[m]), .bid(m_bid[m]), .bresp(m_bresp[m]), .bvalid(m_bvalid[m]), .bready(m_bready[m]),
      .arid(m_arid[m]), .araddr(m_araddr[m]), .arlen(m_arlen[m]), .arsize(m_arsize[m]), .arburst(m_arburst[m]),
      .arvalid(m_arvalid[m]), .arready(m_arready[m]), .rid(m_rid[m]), .rdata(m_rdata[m]), .rresp(m_rresp[m]),
      .rlast(m_rlast[m]), .rvalid(m_rvalid[m]), .rready(m_rready[m]));
    tb_hs_chk #(.W(IDW+2),   .NAME("m_b")) c_b (clk, rst_n, m_bvalid[m], m_bready[m], {m_bid[m], m_bresp[m]});
    tb_hs_chk #(.W(IDW+259), .NAME("m_r")) c_r (clk, rst_n, m_rvalid[m], m_rready[m], {m_rid[m], m_rresp[m], m_rlast[m], m_rdata[m]});

  end


  // ---------------- helpers ----------------
  function automatic int ar_cnt(int s);
    case (s) 0: return g_s[0].smem.ar_hs; 1: return g_s[1].smem.ar_hs; 2: return g_s[2].smem.ar_hs;
             3: return g_s[3].smem.ar_hs; 4: return g_s[4].smem.ar_hs; 5: return g_s[5].smem.ar_hs; default: return 0; endcase
  endfunction
  function automatic int sum_w_hs(); int t = 0;
    t = g_s[0].smem.w_hs + g_s[1].smem.w_hs + g_s[2].smem.w_hs + g_s[3].smem.w_hs + g_s[4].smem.w_hs + g_s[5].smem.w_hs; return t;
  endfunction
  function automatic int sum_r_hs(); int t = 0;
    t = g_s[0].smem.r_hs + g_s[1].smem.r_hs + g_s[2].smem.r_hs + g_s[3].smem.r_hs + g_s[4].smem.r_hs + g_s[5].smem.r_hs; return t;
  endfunction
  function automatic int chk_errs(); int t = 0;
    t = g_s[0].c_aw.errors + g_s[1].c_aw.errors + g_s[2].c_aw.errors + g_s[3].c_aw.errors + g_s[4].c_aw.errors + g_s[5].c_aw.errors
      + g_s[0].c_w.errors  + g_s[1].c_w.errors  + g_s[2].c_w.errors  + g_s[3].c_w.errors  + g_s[4].c_w.errors  + g_s[5].c_w.errors
      + g_s[0].c_ar.errors + g_s[1].c_ar.errors + g_s[2].c_ar.errors + g_s[3].c_ar.errors + g_s[4].c_ar.errors + g_s[5].c_ar.errors
      + g_m[0].c_b.errors + g_m[1].c_b.errors + g_m[2].c_b.errors + g_m[3].c_b.errors + g_m[4].c_b.errors + g_m[5].c_b.errors
      + g_m[0].c_r.errors + g_m[1].c_r.errors + g_m[2].c_r.errors + g_m[3].c_r.errors + g_m[4].c_r.errors + g_m[5].c_r.errors;
    return t;
  endfunction

  // perf-event accumulators (T6)
  longint acc_wb = 0, acc_rb = 0, acc_ro = 0, acc_as = 0;
  initial forever @(posedge clk) if (rst_n) begin
    acc_wb += ev_wb; acc_rb += ev_rb; acc_ro += ev_ro; acc_as += ev_as;
  end

  // one-beat read by master 0, returns the slave that saw it (or -1) and resp
  task automatic probe(input logic [39:0] a, output int slv, output logic [1:0] resp);
    logic [255:0] rd[$]; logic [IDW-1:0] idb; int le; int cnt0[NS];
    rd = {};
    for (int s = 0; s < NS; s++) cnt0[s] = ar_cnt(s);
    g_m[0].bfm.read(a, 0, 3'd5, BURST_INCR, 6'h3, rd, resp, idb, le);
    slv = -1;
    for (int s = 0; s < NS; s++) if (ar_cnt(s) != cnt0[s]) slv = s;
  endtask

  initial begin
    int slv; logic [1:0] r, r2; logic [255:0] d[$], rd[$]; logic [31:0] s[$]; logic [IDW-1:0] idb; int le;
    repeat (3) @(posedge clk); rst_n = 1; repeat (2) @(posedge clk);

    // ---------------- T1 ----------------
    probe(40'h0000_1000,   slv, r); chk("T1 Boot ROM",           slv, SLV_BOOTROM);
    probe(40'h0000_0000,   slv, r); chk("T1 Debug ROM -> periph", slv, SLV_PERIPH);
    probe(40'h0200_0000,   slv, r); chk("T1 CLINT -> periph",     slv, SLV_PERIPH);
    probe(40'h0C00_0000,   slv, r); chk("T1 PLIC -> periph",      slv, SLV_PERIPH);
    probe(40'h1000_3000,   slv, r); chk("T1 Timer0 -> periph",    slv, SLV_PERIPH);
    probe(40'h2000_0000,   slv, r); chk("T1 Socket0",             slv, SLV_SOCKET0);
    probe(40'h2001_FFE0,   slv, r); chk("T1 Socket1 top",         slv, SLV_SOCKET1);
    probe(40'h4003_FFE0,   slv, r); chk("T1 SRAM top",            slv, SLV_SRAM);
    probe(40'hBFFF_FFE0,   slv, r); chk("T1 DRAM last line",      slv, SLV_DRAM);
    probe(40'h1_0000_0000, slv, r); chk("T1 DRAM uncached alias", slv, SLV_DRAM);
    probe(40'hC000_0000,   slv, r); chk("T1 past 1 GB DRAM: no slave", slv, -1); chk("T1 past 1 GB: DECERR", r, RESP_DECERR);
    probe(40'h1_4000_0000, slv, r); chk("T1 past alias: DECERR",  r, RESP_DECERR);
    probe(40'h3000_0000,   slv, r); chk("T1 hole: DECERR",        r, RESP_DECERR);
    d = {}; s = {}; for (int i = 0; i < 3; i++) begin d.push_back('1); s.push_back('1); end
    g_m[1].bfm.write(40'h3000_0000, 2, 5, BURST_INCR, 6'h2A, d, s, r, idb);
    chk("T1 3-beat write to hole: DECERR", r, RESP_DECERR); chk("T1 DECERR BID", idb, 6'h2A);
    g_m[1].bfm.read(40'h3000_0000, 3, 5, BURST_INCR, 6'h15, rd, r, idb, le);
    chk("T1 4-beat read of hole: 4 beats", rd.size(), 4); chk("T1 RLAST on beat 4", le, 0);
    chk("T1 DECERR RID", idb, 6'h15);

    // ---------------- T2 ----------------
    g_m[2].bfm.park = 1;
    d = {256'h1234}; s = {'1};
    g_m[2].bfm.write(40'h4000_0200, 0, 5, BURST_INCR, 6'h1, d, s, r, idb); chk("T2 parked write OKAY", r, RESP_OKAY);
    g_m[2].bfm.read(40'h4000_0200, 0, 5, BURST_INCR, 6'h1, rd, r, idb, le); chk("T2 parked read data", rd[0], 256'h1234);
    g_m[2].bfm.write(40'h3000_0000, 0, 5, BURST_INCR, 6'h1, d, s, r, idb); chk("T2 parked DECERR write", r, RESP_DECERR);
    g_m[2].bfm.park = 0;

    // ---------------- T3: two slaves, B/R collector runs in parallel ----------------
    fork
      begin
        g_m[0].bfm.aw(40'h4000_0400, 0, 5, BURST_INCR, 6'h11); g_m[0].bfm.w_beat(256'hAAAA, '1, 1);
        g_m[0].bfm.aw(40'h8000_0400, 0, 5, BURST_INCR, 6'h22); g_m[0].bfm.w_beat(256'hBBBB, '1, 1);
      end
      begin repeat (30) @(posedge clk); g_m[0].bfm.b(r, idb); chk("T3 1st B id", idb, 6'h11); g_m[0].bfm.b(r2, idb); chk("T3 2nd B id", idb, 6'h22); end
    join
    fork
      begin g_m[0].bfm.ar(40'h4000_0400, 0, 5, BURST_INCR, 6'h11); g_m[0].bfm.ar(40'h8000_0400, 0, 5, BURST_INCR, 6'h22); end
      begin
        logic [255:0] dd; bit l;
        repeat (30) @(posedge clk);
        g_m[0].bfm.r_beat(dd, r, idb, l); chk("T3 1st R", dd, 256'hAAAA);
        g_m[0].bfm.r_beat(dd, r, idb, l); chk("T3 2nd R", dd, 256'hBBBB);
      end
    join

    // ---------------- T4: 4 outstanding to one slave ----------------
    g_s[SLV_DRAM].smem.stall = 50;
    fork
      begin
        for (int i = 0; i < 4; i++) g_m[3].bfm.aw(40'h8000_1000 + i * 64, 1, 5, BURST_INCR, 6'(i));
      end
      begin
        for (int i = 0; i < 4; i++) begin
          g_m[3].bfm.w_beat(256'(100 + 2 * i), '1, 0); g_m[3].bfm.w_beat(256'(101 + 2 * i), '1, 1);
        end
      end
      begin for (int i = 0; i < 4; i++) begin g_m[3].bfm.b(r, idb); chk($sformatf("T4 B%0d in order", i), idb, i); end end
    join
    fork
      begin for (int i = 0; i < 4; i++) g_m[3].bfm.ar(40'h8000_1000 + i * 64, 1, 5, BURST_INCR, 6'(i)); end
      begin
        logic [255:0] dd; bit l;
        for (int i = 0; i < 8; i++) begin
          g_m[3].bfm.r_beat(dd, r, idb, l);
          chk($sformatf("T4 R beat %0d", i), dd, 256'(100 + i));
          chk($sformatf("T4 R beat %0d last", i), l, i % 2);
        end
      end
    join

    // ---------------- T5: everything at once ----------------
    g_s[0].smem.stall = 30; g_s[1].smem.stall = 30; g_s[2].smem.stall = 40;
    g_s[3].smem.stall = 20; g_s[4].smem.stall = 20; g_s[5].smem.stall = 30;
    g_m[0].bfm.bp = 20; g_m[1].bfm.bp = 20; g_m[2].bfm.bp = 30;
    g_m[3].bfm.bp = 10; g_m[4].bfm.bp = 10; g_m[5].bfm.bp = 40;
    fork
      g_m[0].bfm.selfcheck(80, BOOT_ROM_BASE, SRAM_BASE, DRAM_BASE, SOCKET0_BASE, SOCKET1_BASE, UART0_BASE, 40'h0000, 40'h3000_0000);
      g_m[1].bfm.selfcheck(80, BOOT_ROM_BASE, SRAM_BASE, DRAM_BASE, SOCKET0_BASE, SOCKET1_BASE, UART0_BASE, 40'h1000, 40'h3000_0000);
      g_m[2].bfm.selfcheck(80, BOOT_ROM_BASE, SRAM_BASE, DRAM_BASE, SOCKET0_BASE, SOCKET1_BASE, UART0_BASE, 40'h2000, 40'h3000_0000);
      g_m[3].bfm.selfcheck(80, BOOT_ROM_BASE, SRAM_BASE, DRAM_BASE, SOCKET0_BASE, SOCKET1_BASE, UART0_BASE, 40'h3000, 40'h3000_0000);
      g_m[4].bfm.selfcheck(80, BOOT_ROM_BASE, SRAM_BASE, DRAM_BASE, SOCKET0_BASE, SOCKET1_BASE, UART0_BASE, 40'h4000, 40'h3000_0000);
      g_m[5].bfm.selfcheck(80, BOOT_ROM_BASE, SRAM_BASE, DRAM_BASE, SOCKET0_BASE, SOCKET1_BASE, UART0_BASE, 40'h5000, 40'h3000_0000);
    join
    chk("T5 M0 scoreboard", g_m[0].bfm.sc_err, 0); chk("T5 M1 scoreboard", g_m[1].bfm.sc_err, 0);
    chk("T5 M2 scoreboard", g_m[2].bfm.sc_err, 0); chk("T5 M3 scoreboard", g_m[3].bfm.sc_err, 0);
    chk("T5 M4 scoreboard", g_m[4].bfm.sc_err, 0); chk("T5 M5 scoreboard", g_m[5].bfm.sc_err, 0);
    $display("  T5: %0d checked bursts across 6 concurrent masters",
             g_m[0].bfm.sc_ok + g_m[1].bfm.sc_ok + g_m[2].bfm.sc_ok + g_m[3].bfm.sc_ok + g_m[4].bfm.sc_ok + g_m[5].bfm.sc_ok);

    // ---------------- T6 + protocol ----------------
    repeat (5) @(posedge clk);
    chk("T6 evt write beats == slave W beats", acc_wb, sum_w_hs());
    chk("T6 evt read beats == slave R beats",  acc_rb, sum_r_hs());
    chk("T6 read-outstanding accumulated",     acc_ro > 0, 1);
    chk("T6 arb-stall seen under contention",  acc_as > 0, 1);
    chk("AXI handshake/stability checkers",    chk_errs(), 0);
    $display("  perf: write_beats=%0d read_beats=%0d read_latency_sum=%0d arb_stall=%0d", acc_wb, acc_rb, acc_ro, acc_as);

    if (errors == 0) begin
      $display("=== PASS : %0d checks ===", checks);
      $finish;
    end else begin
      $display("=== FAIL : %0d errors of %0d checks ===", errors, checks);
      $fatal(1, "tb_meds_s1_axi4_crossbar failed");
    end
  end
  initial begin #20ms; $fatal(1, "tb_meds_s1_axi4_crossbar: TIMEOUT"); end
endmodule
