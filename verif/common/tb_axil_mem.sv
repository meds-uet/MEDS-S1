// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// tb_axil_mem : AXI4-Lite memory model: 3 AW/W acceptance orders, SLVERR at one address
//
// Shared verification IP, pulled into a unit testbench with
//   `include "verif/common/tb_axil_mem.sv"
// (path is relative to the repo root: run_unit_tests.py runs from there and
// compiles only rtl/ plus the testbench file).
//
// Timing discipline: every signal this model drives changes at the NEGEDGE of
// clk, and every handshake is decided by sampling at the negedge (+#1).
// =============================================================================
`ifndef TB_AXIL_MEM_SV
`define TB_AXIL_MEM_SV

module tb_axil_mem #(parameter int MODE = 0, parameter logic [11:0] ERR_ADDR = 12'hFFC) (
  input  logic clk, rst_n,
  input  logic [39:0] awaddr, input logic awvalid, output logic awready,
  input  logic [31:0] wdata, input logic [3:0] wstrb, input logic wvalid, output logic wready,
  output logic [1:0] bresp, output logic bvalid, input logic bready,
  input  logic [39:0] araddr, input logic arvalid, output logic arready,
  output logic [31:0] rdata, output logic [1:0] rresp, output logic rvalid, input logic rready
);
  logic [31:0] mem [longint];
  int aw_hs = 0, w_hs = 0, ar_hs = 0;
  logic have_aw = 0, have_w = 0; logic [39:0] a_q; logic [31:0] d_q; logic [3:0] s_q;

  assign awready = rst_n && !have_aw && !bvalid && (MODE != 2 || have_w);
  assign wready  = rst_n && !have_w  && !bvalid && (MODE != 1 || have_aw);
  assign arready = rst_n && !rvalid;

  // Every write here is non-blocking, including the counters and the `mem`
  // array element -- so the whole model stays one deterministic process
  // (Verilator's BLKSEQ rejects blocking writes to state inside always_ff,
  // and splitting into a second process would make same-cycle read/write
  // collisions on `mem` simulator-scheduling-dependent, which the timing
  // discipline note above specifically avoids). `o` is a true local
  // temporary, so its blocking assignment is unaffected.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin have_aw <= 0; have_w <= 0; bvalid <= 0; rvalid <= 0; end
    else begin
      if (awvalid && awready) begin have_aw <= 1; a_q <= awaddr; aw_hs <= aw_hs + 1; end
      if (wvalid && wready)   begin have_w  <= 1; d_q <= wdata; s_q <= wstrb; w_hs <= w_hs + 1; end
      if (have_aw && have_w && !bvalid) begin
        logic [31:0] o;
        o = mem.exists(a_q >> 2) ? mem[a_q >> 2] : 32'h0;
        for (int i = 0; i < 4; i++) if (s_q[i]) o[i*8 +: 8] = d_q[i*8 +: 8];
        if (a_q[11:0] != ERR_ADDR) mem[a_q >> 2] <= o;
        bresp  <= (a_q[11:0] == ERR_ADDR) ? 2'b10 : 2'b00;
        bvalid <= 1; have_aw <= 0; have_w <= 0;
      end
      if (bvalid && bready) bvalid <= 0;
      if (arvalid && arready) begin
        rvalid <= 1; ar_hs <= ar_hs + 1;
        rdata  <= mem.exists(araddr >> 2) ? mem[araddr >> 2] : 32'h0;
        rresp  <= (araddr[11:0] == ERR_ADDR) ? 2'b10 : 2'b00;
      end
      if (rvalid && rready) rvalid <= 0;
    end
  end
endmodule : tb_axil_mem

`endif
