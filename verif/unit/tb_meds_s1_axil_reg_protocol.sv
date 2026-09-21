// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// tb_meds_s1_axil_reg_protocol : unit testbench for meds_s1_axil_reg_protocol
//
// tb_axil_shell -- meds_s1_axil_reg_protocol with a 15-register file behind
// it (0x00..0x38 valid, everything else SLVERR). Checks strobes, error
// responses, AW/W in any order, back-to-back traffic, and a random run
// against a scoreboard.
//
// Run:  make test-unit TB=meds_s1_axil_reg_protocol
// =============================================================================
`include "verif/common/tb_axil_master.sv"

module tb_meds_s1_axil_reg_protocol;
  import meds_s1_axi4_pkg::*;
  logic clk = 0, rst_n = 0;
  initial forever #5 clk = ~clk;
  int errors = 0, checks = 0;
  task automatic chk(string n, logic [63:0] g, logic [63:0] e);
    checks++; if (g !== e) begin errors++; $display("  [FAIL] %s  got=0x%0h exp=0x%0h", n, g, e); end
  endtask

  logic [15:0] awaddr, araddr; logic awvalid, awready, wvalid, wready, bvalid, bready;
  logic arvalid, arready, rvalid, rready; logic [31:0] wdata, rdata; logic [3:0] wstrb;
  logic [1:0] bresp, rresp;
  logic [15:0] wr_a, rd_a; logic [31:0] wr_d, rd_d; logic [3:0] wr_s; logic wr_en, wr_v, rd_v;

  meds_s1_axil_reg_protocol dut (
    .clk_i(clk), .rst_ni(rst_n),
    .awaddr_i(awaddr), .awvalid_i(awvalid), .awready_o(awready),
    .wdata_i(wdata), .wstrb_i(wstrb), .wvalid_i(wvalid), .wready_o(wready),
    .bresp_o(bresp), .bvalid_o(bvalid), .bready_i(bready),
    .araddr_i(araddr), .arvalid_i(arvalid), .arready_o(arready),
    .rdata_o(rdata), .rresp_o(rresp), .rvalid_o(rvalid), .rready_i(rready),
    .wr_addr_o(wr_a), .wr_data_o(wr_d), .wr_strb_o(wr_s), .wr_en_o(wr_en), .wr_addr_valid_i(wr_v),
    .rd_addr_o(rd_a), .rd_data_i(rd_d), .rd_addr_valid_i(rd_v));

  tb_axil_master #(.AW(16)) m (.clk(clk),
    .awaddr(awaddr), .awvalid(awvalid), .awready(awready), .wdata(wdata), .wstrb(wstrb),
    .wvalid(wvalid), .wready(wready), .bresp(bresp), .bvalid(bvalid), .bready(bready),
    .araddr(araddr), .arvalid(arvalid), .arready(arready), .rdata(rdata), .rresp(rresp),
    .rvalid(rvalid), .rready(rready));

  // Register file that honours strobes (the shell's contract).
  logic [31:0] regs [15];
  assign wr_v = (wr_a[15:6] == 0) && (wr_a[5:2] < 15) && (wr_a[1:0] == 0);
  assign rd_v = (rd_a[15:6] == 0) && (rd_a[5:2] < 15) && (rd_a[1:0] == 0);
  assign rd_d = rd_v ? regs[rd_a[5:2]] : 32'h0;
  always_ff @(posedge clk) if (wr_en && wr_v)
    for (int i = 0; i < 4; i++) if (wr_s[i]) regs[wr_a[5:2]][i*8 +: 8] <= wr_d[i*8 +: 8];

  logic [1:0] r; logic [31:0] d; logic [31:0] model [15];
  initial begin
    foreach (regs[i]) begin regs[i] = 0; model[i] = 0; end
    repeat (3) @(posedge clk); rst_n = 1; repeat (2) @(posedge clk);

    m.write(16'h08, 32'h1234_5678, 4'hF, r); chk("write OKAY", r, RESP_OKAY);
    m.read (16'h08, d, r); chk("readback", d, 32'h1234_5678); chk("read OKAY", r, RESP_OKAY);
    m.write(16'h08, 32'hAABB_CCDD, 4'b0010, r); m.read(16'h08, d, r);
    chk("byte strobe", d, 32'h1234_CC78);
    m.write(16'h3C, 32'h1, 4'hF, r); chk("unmapped write SLVERR", r, RESP_SLVERR);
    m.read (16'h100, d, r);          chk("unmapped read SLVERR", r, RESP_SLVERR);
    m.w_first = 1; m.write(16'h10, 32'hCAFE_0001, 4'hF, r); m.read(16'h10, d, r);
    chk("W before AW", d, 32'hCAFE_0001);
    m.w_first = 2; m.write(16'h14, 32'hCAFE_0002, 4'hF, r); m.read(16'h14, d, r);
    chk("AW before W", d, 32'hCAFE_0002);
    model[2] = 32'h1234_CC78; model[4] = 32'hCAFE_0001; model[5] = 32'hCAFE_0002;

    // random run against a scoreboard
    for (int it = 0; it < 400; it++) begin
      int idx = $urandom_range(14); logic [31:0] v = $urandom; logic [3:0] s = 4'($urandom);
      m.w_first = $urandom_range(2);
      if ($urandom_range(1)) begin
        m.write(16'(idx*4), v, s, r); chk("rand write resp", r, RESP_OKAY);
        for (int i = 0; i < 4; i++) if (s[i]) model[idx][i*8 +: 8] = v[i*8 +: 8];
      end else begin
        m.read(16'(idx*4), d, r); chk($sformatf("rand read reg%0d", idx), d, model[idx]);
      end
    end
    if (errors == 0) begin
      $display("=== PASS : %0d checks ===", checks);
      $finish;
    end else begin
      $display("=== FAIL : %0d errors of %0d checks ===", errors, checks);
      $fatal(1, "tb_meds_s1_axil_reg_protocol failed");
    end
  end
  initial begin #2ms; $fatal(1, "tb_meds_s1_axil_reg_protocol: TIMEOUT"); end
endmodule
