// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// tb_meds_s1_axi4_reg_protocol : unit testbench for meds_s1_axi4_reg_protocol
//
// tb_axi4_shell -- meds_s1_axi4_reg_protocol (ID_W = AXI_SID_W) with a
// 4 KB memory behind it (above 4 KB -> SLVERR). Every burst type, length
// 1..20, sizes 1..32 bytes, unaligned starts, all against a byte-level
// reference model whose address math is written independently of the RTL.
//
// Run:  make test-unit TB=meds_s1_axi4_reg_protocol
// =============================================================================
`include "verif/common/tb_axi4_master.sv"

module tb_meds_s1_axi4_reg_protocol;
  import meds_s1_axi4_pkg::*;
  localparam IDW = AXI_SID_W;
  logic clk = 0, rst_n = 0;
  initial forever #5 clk = ~clk;
  int errors = 0, checks = 0;
  task automatic chk(string n, logic [255:0] g, logic [255:0] e);
    checks++; if (g !== e) begin errors++; if (errors < 20) $display("  [FAIL] %s  got=0x%0h exp=0x%0h", n, g, e); end
  endtask

  logic [IDW-1:0] awid, arid, bid, rid; logic [39:0] awaddr, araddr; logic [7:0] awlen, arlen;
  logic [2:0] awsize, arsize; logic [1:0] awburst, arburst, bresp, rresp;
  logic awvalid, awready, wvalid, wready, wlast, bvalid, bready, arvalid, arready, rvalid, rready, rlast;
  logic [255:0] wdata, rdata; logic [31:0] wstrb;
  logic [39:0] wr_a, rd_a; logic [255:0] wr_d, rd_d; logic [31:0] wr_s; logic wr_en, wr_v, rd_v;

  meds_s1_axi4_reg_protocol #(.ID_W(IDW)) dut (.clk_i(clk), .rst_ni(rst_n),
    .awid_i(awid), .awaddr_i(awaddr), .awlen_i(awlen), .awsize_i(awsize), .awburst_i(awburst),
    .awvalid_i(awvalid), .awready_o(awready),
    .wdata_i(wdata), .wstrb_i(wstrb), .wlast_i(wlast), .wvalid_i(wvalid), .wready_o(wready),
    .bid_o(bid), .bresp_o(bresp), .bvalid_o(bvalid), .bready_i(bready),
    .arid_i(arid), .araddr_i(araddr), .arlen_i(arlen), .arsize_i(arsize), .arburst_i(arburst),
    .arvalid_i(arvalid), .arready_o(arready),
    .rid_o(rid), .rdata_o(rdata), .rresp_o(rresp), .rlast_o(rlast), .rvalid_o(rvalid), .rready_i(rready),
    .wr_addr_o(wr_a), .wr_data_o(wr_d), .wr_strb_o(wr_s), .wr_en_o(wr_en), .wr_addr_valid_i(wr_v),
    .rd_addr_o(rd_a), .rd_data_i(rd_d), .rd_addr_valid_i(rd_v));

  tb_axi4_master #(.DW(256), .IDW(IDW)) m (.clk(clk),
    .awid(awid), .awaddr(awaddr), .awlen(awlen), .awsize(awsize), .awburst(awburst),
    .awvalid(awvalid), .awready(awready), .wdata(wdata), .wstrb(wstrb), .wlast(wlast),
    .wvalid(wvalid), .wready(wready), .bid(bid), .bresp(bresp), .bvalid(bvalid), .bready(bready),
    .arid(arid), .araddr(araddr), .arlen(arlen), .arsize(arsize), .arburst(arburst),
    .arvalid(arvalid), .arready(arready), .rid(rid), .rdata(rdata), .rresp(rresp),
    .rlast(rlast), .rvalid(rvalid), .rready(rready));

  // Storage behind the shell: 4 KB, lines of 32 bytes.
  logic [255:0] store [128];
  assign wr_v = (wr_a < 40'h1000);
  assign rd_v = (rd_a < 40'h1000);
  assign rd_d = rd_v ? store[rd_a[11:5]] : '0;
  always_ff @(posedge clk) if (wr_en && wr_v)
    for (int i = 0; i < 32; i++) if (wr_s[i]) store[wr_a[11:5]][i*8 +: 8] <= wr_d[i*8 +: 8];

  // ---- independent reference address math ----
  function automatic longint beat_addr(longint start, int i, int size, int len, int burst);
    longint step = 1 << size, total = step * (len + 1), base;
    if (burst == 0) return start;                         // FIXED
    if (burst == 2) begin                                 // WRAP (start aligned to size)
      base = (start / total) * total;
      return base + ((start - base + i * step) % total);
    end
    if (i == 0) return start;                             // INCR
    return (start / step) * step + i * step;
  endfunction

  logic [7:0] ref_mem [longint];

  task automatic burst_test(longint start, int len, int size, int burst, string tag);
    logic [255:0] d[$], rd[$]; logic [31:0] s[$]; logic [1:0] r; logic [IDW-1:0] id_back; int le;
    logic [IDW-1:0] id;
    d = {}; rd = {}; s = {}; id = IDW'($urandom);
    // write: random data, strobes = exactly the bytes AXI says this beat moves
    for (int i = 0; i <= len; i++) begin
      longint a = beat_addr(start, i, size, len, burst);
      longint lo = a, hi = (a / (1 << size)) * (1 << size) + (1 << size) - 1;
      logic [255:0] dd; logic [31:0] ss;
      ss = 0;
      for (int k = 0; k < 8; k++) dd[k*32 +: 32] = $urandom;
      for (longint b = lo; b <= hi; b++) begin
        ss[b % 32] = 1'b1; ref_mem[b] = dd[(b % 32) * 8 +: 8];
      end
      d.push_back(dd); s.push_back(ss);
    end
    m.write(40'(start), 8'(len), 3'(size), 2'(burst), id, d, s, r, id_back);
    chk({tag, " BRESP"}, r, RESP_OKAY);
    chk({tag, " BID"}, id_back, id);
    // read back and compare the bytes of each beat
    m.read(40'(start), 8'(len), 3'(size), 2'(burst), id ^ 1, rd, r, id_back, le);
    chk({tag, " RRESP"}, r, RESP_OKAY);
    chk({tag, " RID"}, id_back, id ^ 1);
    chk({tag, " RLAST position"}, le, 0);
    for (int i = 0; i <= len; i++) begin
      longint a = beat_addr(start, i, size, len, burst);
      longint hi = (a / (1 << size)) * (1 << size) + (1 << size) - 1;
      for (longint b = a; b <= hi; b++)
        chk($sformatf("%s beat%0d byte@%0h", tag, i, b), rd[i][(b % 32) * 8 +: 8], ref_mem[b]);
    end
  endtask

  initial begin
    logic [255:0] d[$], rd[$]; logic [31:0] s[$]; logic [1:0] r; logic [IDW-1:0] idb; int le;
    foreach (store[i]) store[i] = '0;
    repeat (3) @(posedge clk); rst_n = 1; repeat (2) @(posedge clk);

    for (int len = 0; len < 20; len++) burst_test(64 * len, len, 5, 1, $sformatf("INCR32 len%0d", len+1));
    burst_test(40'h806, 5, 2, 1, "INCR4 unaligned start");
    burst_test(40'h903, 9, 3, 1, "INCR8 unaligned start");
    burst_test(40'hA10, 3, 3, 2, "WRAP4x8");
    burst_test(40'hB28, 7, 3, 2, "WRAP8x8 (cache refill)");
    burst_test(40'hC0C, 15, 2, 2, "WRAP16x4");
    burst_test(40'hD40, 3, 5, 2, "WRAP4x32");
    burst_test(40'hE04, 3, 2, 0, "FIXED4x4");
    for (int it = 0; it < 60; it++) begin
      int size = $urandom_range(5), len = $urandom_range(15), burst = $urandom_range(1);
      longint start = $urandom_range(40'h800) & ~((1 << size) - 1);
      if ($urandom_range(3) == 0 && burst == 1) start = start + $urandom_range((1 << size) - 1);
      burst_test(start, len, size, burst, $sformatf("rand%0d", it));
    end

    // a burst that runs off the end of the storage -> SLVERR
    d = {}; s = {}; for (int i = 0; i < 4; i++) begin d.push_back('1); s.push_back('1); end
    m.write(40'hFC0, 3, 5, 1, 9'h1A5, d, s, r, idb);
    chk("write past end -> SLVERR", r, RESP_SLVERR);
    chk("ID upper bits echoed", idb, 9'h1A5);
    m.read(40'hFC0, 3, 5, 1, 9'h0F3, rd, r, idb, le);
    chk("read past end -> SLVERR", r, RESP_SLVERR);

    if (errors == 0) begin
      $display("=== PASS : %0d checks ===", checks);
      $finish;
    end else begin
      $display("=== FAIL : %0d errors of %0d checks ===", errors, checks);
      $fatal(1, "tb_meds_s1_axi4_reg_protocol failed");
    end
  end
  initial begin #5ms; $fatal(1, "tb_meds_s1_axi4_reg_protocol: TIMEOUT"); end
endmodule
