// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// tb_axil_master : AXI4-Lite master bus-functional model
//
// Shared verification IP, pulled into a unit testbench with
//   `include "verif/common/tb_axil_master.sv"
// (path is relative to the repo root: run_unit_tests.py runs from there and
// compiles only rtl/ plus the testbench file).
//
// Timing discipline: every signal this BFM drives changes at the NEGEDGE of
// clk, and every handshake is decided by sampling at the negedge (+#1). Nothing
// samples DUT outputs right after a posedge, so results do not depend on the
// simulator's scheduling of same-time events.
// =============================================================================
`ifndef TB_AXIL_MASTER_SV
`define TB_AXIL_MASTER_SV

module tb_axil_master #(parameter int AW = 40) (
  input  logic clk,
  output logic [AW-1:0] awaddr, output logic awvalid, input logic awready,
  output logic [31:0] wdata, output logic [3:0] wstrb, output logic wvalid, input logic wready,
  input  logic [1:0] bresp, input logic bvalid, output logic bready,
  output logic [AW-1:0] araddr, output logic arvalid, input logic arready,
  input  logic [31:0] rdata, input logic [1:0] rresp, input logic rvalid, output logic rready
);
  int w_first = 0;   // 0: AW and W together, 1: W two cycles before AW, 2: AW before W
  initial begin awvalid = 0; wvalid = 0; bready = 0; arvalid = 0; rready = 0; awaddr = '0; araddr = '0; end

  task automatic do_aw(input logic [AW-1:0] a);
    @(negedge clk); awaddr = a; awvalid = 1; #1;
    while (!awready) begin @(negedge clk); #1; end
    @(posedge clk); #1 awvalid = 0;
  endtask
  task automatic do_w(input logic [31:0] d, input logic [3:0] s);
    @(negedge clk); wdata = d; wstrb = s; wvalid = 1; #1;
    while (!wready) begin @(negedge clk); #1; end
    @(posedge clk); #1 wvalid = 0;
  endtask
  task automatic write(input logic [AW-1:0] a, input logic [31:0] d, input logic [3:0] s,
                       output logic [1:0] resp);
    case (w_first)
      0: fork do_aw(a); do_w(d, s); join
      1: fork do_w(d, s); begin repeat (2) @(negedge clk); do_aw(a); end join
      default: begin do_aw(a); do_w(d, s); end
    endcase
    @(negedge clk); bready = 1; #1;
    while (!bvalid) begin @(negedge clk); #1; end
    resp = bresp; @(posedge clk); #1 bready = 0;
  endtask
  task automatic read(input logic [AW-1:0] a, output logic [31:0] d, output logic [1:0] resp);
    @(negedge clk); araddr = a; arvalid = 1; #1;
    while (!arready) begin @(negedge clk); #1; end
    @(posedge clk); #1 arvalid = 0;
    @(negedge clk); rready = 1; #1;
    while (!rvalid) begin @(negedge clk); #1; end
    d = rdata; resp = rresp; @(posedge clk); #1 rready = 0;
  endtask
endmodule : tb_axil_master

`endif
