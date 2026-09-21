// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// tb_axi4_mem : AXI4 memory model: 256-bit, per-byte strobes, optional random stalls
//
// Shared verification IP, pulled into a unit testbench with
//   `include "verif/common/tb_axi4_mem.sv"
// (path is relative to the repo root: run_unit_tests.py runs from there and
// compiles only rtl/ plus the testbench file).
//
// Timing discipline: every signal this model drives changes at the NEGEDGE of
// clk, and every handshake is decided by sampling at the negedge (+#1).
// =============================================================================
`ifndef TB_AXI4_MEM_SV
`define TB_AXI4_MEM_SV

// Every assignment below is blocking (`=`), including the ones driving
// awready/wready/bvalid/etc. This model is not synthesisable register logic;
// each output is settled well before the edge that samples it (SPEC-style
// negedge/posedge separation, per the timing discipline above), so blocking
// vs non-blocking makes no observable difference here -- and Verilator
// rejects `<=` inside `initial forever` (INITIALDLY), which this file uses
// throughout instead of the plain `always` event-control block (banned by CODING_STANDARD.md R-C1).
module tb_axi4_mem #(parameter int IDW = 9) (
  input  logic clk, rst_n,
  input  logic [IDW-1:0] awid, input logic [39:0] awaddr, input logic [7:0] awlen,
  input  logic [2:0] awsize, input logic [1:0] awburst, input logic awvalid, output logic awready,
  input  logic [255:0] wdata, input logic [31:0] wstrb, input logic wlast, input logic wvalid,
  output logic wready,
  output logic [IDW-1:0] bid, output logic [1:0] bresp, output logic bvalid, input logic bready,
  input  logic [IDW-1:0] arid, input logic [39:0] araddr, input logic [7:0] arlen,
  input  logic [2:0] arsize, input logic [1:0] arburst, input logic arvalid, output logic arready,
  output logic [IDW-1:0] rid, output logic [255:0] rdata, output logic [1:0] rresp,
  output logic rlast, output logic rvalid, input logic rready
);
  import meds_s1_axi4_pkg::*;
  typedef struct { logic [IDW-1:0] id; logic [39:0] addr; logic [7:0] len; logic [2:0] size; logic [1:0] burst; } req_t;
  logic [255:0] mem [longint];
  req_t aw_q[$], ar_q[$]; logic [IDW-1:0] b_q[$];
  int   stall = 0;          // % chance per cycle of withholding a READY / VALID
  int   aw_hs = 0, w_hs = 0, b_hs = 0, ar_hs = 0, r_hs = 0, errors = 0;
  logic [7:0]  wbeat = 0, rbeat = 0;
  logic [39:0] waddr, raddr;

  function automatic logic [255:0] rd_line(logic [39:0] a);
    return mem.exists(a >> 5) ? mem[a >> 5] : {8{32'hA5A5_0000 | 32'(a[15:0])}};
  endfunction
  function automatic bit roll(); return $urandom_range(99) >= stall; endfunction

  initial forever @(negedge clk) begin
    if (!rst_n) begin
      awready = 0; wready = 0; bvalid = 0; arready = 0; rvalid = 0;
      aw_q = {}; ar_q = {}; b_q = {}; wbeat = 0; rbeat = 0;
    end else begin
      awready = (aw_q.size() < 4) && roll();
      wready  = (aw_q.size() > 0) && roll();
      if (!bvalid) begin
        if (b_q.size() > 0 && roll()) begin bvalid = 1; bid = b_q[0]; end
      end
      arready = (ar_q.size() < 4) && roll();
      if (!rvalid && ar_q.size() > 0 && roll()) begin
        if (rbeat == 0) raddr = ar_q[0].addr;
        rvalid = 1; rid = ar_q[0].id; rdata = rd_line(raddr); rlast = (rbeat == ar_q[0].len);
      end
    end
  end
  assign bresp = RESP_OKAY;
  assign rresp = RESP_OKAY;

  // Register clears on acceptance: must be non-blocking, because the DUT's
  // own registers and the c_aw/c_ar checkers below sample these same signals
  // at this same posedge, and only a non-blocking write guarantees they see
  // the pre-edge value (read-before-write). The two negedge-driven backpressure
  // assignments above race with nothing at this edge, so blocking there is
  // fine (see the file-level note); these five are the exception.
  always_ff @(posedge clk or negedge rst_n) begin
    if (rst_n) begin
      if (awvalid && awready) awready <= 1'b0;
      if (wvalid  && wready ) wready  <= 1'b0;
      if (bvalid  && bready ) bvalid  <= 1'b0;
      if (arvalid && arready) arready <= 1'b0;
      if (rvalid  && rready ) rvalid  <= 1'b0;
    end
  end

  // Bookkeeping only (queues, byte writes, counters) -- none of this is read
  // by anything outside this model at this same edge, so blocking is safe.
  initial forever @(posedge clk) if (rst_n) begin
    if (awvalid && awready) begin req_t t; t.id = awid; t.addr = awaddr; t.len = awlen; t.size = awsize; t.burst = awburst; aw_q.push_back(t); aw_hs++; end
    if (wvalid && wready) begin
      logic [255:0] o;
      if (wbeat == 0) waddr = aw_q[0].addr;
      o = rd_line(waddr);
      for (int i = 0; i < 32; i++) if (wstrb[i]) o[i*8 +: 8] = wdata[i*8 +: 8];
      mem[waddr >> 5] = o; w_hs++;
      if (wlast != (wbeat == aw_q[0].len)) begin errors++; $display("  [MEM] WLAST mismatch"); end
      if (wbeat == aw_q[0].len) begin b_q.push_back(aw_q[0].id); void'(aw_q.pop_front()); wbeat = 0; end
      else begin waddr = axi_next_addr(waddr, aw_q[0].size, aw_q[0].len, aw_q[0].burst); wbeat++; end
    end
    if (bvalid && bready) begin void'(b_q.pop_front()); b_hs++; end
    if (arvalid && arready) begin req_t t; t.id = arid; t.addr = araddr; t.len = arlen; t.size = arsize; t.burst = arburst; ar_q.push_back(t); ar_hs++; end
    if (rvalid && rready) begin
      r_hs++;
      if (rbeat == ar_q[0].len) begin void'(ar_q.pop_front()); rbeat = 0; end
      else begin raddr = axi_next_addr(raddr, ar_q[0].size, ar_q[0].len, ar_q[0].burst); rbeat++; end
    end
  end
endmodule : tb_axi4_mem

`endif
