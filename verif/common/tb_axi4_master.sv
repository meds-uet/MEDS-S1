// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// tb_axi4_master : AXI4 master bus-functional model
//
// Shared verification IP, pulled into a unit testbench with
//   `include "verif/common/tb_axi4_master.sv"
// (path is relative to the repo root: run_unit_tests.py runs from there and
// compiles only rtl/ plus the testbench file).
//
// Timing discipline: every signal this BFM drives changes at the NEGEDGE of
// clk, and every handshake is decided by sampling at the negedge (+#1). Nothing
// samples DUT outputs right after a posedge, so results do not depend on the
// simulator's scheduling of same-time events.
// =============================================================================
`ifndef TB_AXI4_MASTER_SV
`define TB_AXI4_MASTER_SV

module tb_axi4_master #(parameter int DW = 256, parameter int IDW = 6) (
  input  logic clk,
  output logic [IDW-1:0] awid,   output logic [39:0] awaddr, output logic [7:0] awlen,
  output logic [2:0]     awsize, output logic [1:0]  awburst, output logic awvalid, input logic awready,
  output logic [DW-1:0]  wdata,  output logic [DW/8-1:0] wstrb, output logic wlast, output logic wvalid,
  input  logic wready,
  input  logic [IDW-1:0] bid,    input logic [1:0] bresp, input logic bvalid, output logic bready,
  output logic [IDW-1:0] arid,   output logic [39:0] araddr, output logic [7:0] arlen,
  output logic [2:0]     arsize, output logic [1:0]  arburst, output logic arvalid, input logic arready,
  input  logic [IDW-1:0] rid,    input logic [DW-1:0] rdata, input logic [1:0] rresp,
  input  logic rlast, input logic rvalid, output logic rready
);
  int  bp = 0;          // % chance per cycle to hold BREADY/RREADY low (backpressure)
  bit  park = 0;        // after an address handshake, drive the address bus to 0
  initial begin
    awvalid = 0; wvalid = 0; bready = 0; arvalid = 0; rready = 0;
    awaddr = '0; araddr = '0; awid = '0; arid = '0; wdata = '0; wstrb = '0; wlast = 0;
    awlen = '0; arlen = '0; awsize = '0; arsize = '0; awburst = '0; arburst = '0;
  end

  task automatic aw(input logic [39:0] a, input logic [7:0] len, input logic [2:0] size,
                    input logic [1:0] burst, input logic [IDW-1:0] id);
    @(negedge clk);
    awaddr = a; awlen = len; awsize = size; awburst = burst; awid = id; awvalid = 1; #1;
    while (!awready) begin @(negedge clk); #1; end
    @(posedge clk); #1 awvalid = 0; if (park) awaddr = '0;
  endtask

  task automatic w_beat(input logic [DW-1:0] d, input logic [DW/8-1:0] s, input bit last);
    @(negedge clk);
    wdata = d; wstrb = s; wlast = last; wvalid = 1; #1;
    while (!wready) begin @(negedge clk); #1; end
    @(posedge clk); #1 wvalid = 0;
  endtask

  task automatic b(output logic [1:0] resp, output logic [IDW-1:0] id);
    forever begin
      @(negedge clk); bready = ($urandom_range(99) >= bp); #1;
      if (bvalid && bready) break;
    end
    resp = bresp; id = bid;
    @(posedge clk); #1 bready = 0;
  endtask

  task automatic ar(input logic [39:0] a, input logic [7:0] len, input logic [2:0] size,
                    input logic [1:0] burst, input logic [IDW-1:0] id);
    @(negedge clk);
    araddr = a; arlen = len; arsize = size; arburst = burst; arid = id; arvalid = 1; #1;
    while (!arready) begin @(negedge clk); #1; end
    @(posedge clk); #1 arvalid = 0; if (park) araddr = '0;
  endtask

  task automatic r_beat(output logic [DW-1:0] d, output logic [1:0] resp,
                        output logic [IDW-1:0] id, output bit last);
    forever begin
      @(negedge clk); rready = ($urandom_range(99) >= bp); #1;
      if (rvalid && rready) break;
    end
    d = rdata; resp = rresp; id = rid; last = rlast;
    @(posedge clk); #1 rready = 0;
  endtask

  // Whole write burst. data/strb hold one entry per beat.
  task automatic write(input logic [39:0] a, input logic [7:0] len, input logic [2:0] size,
                       input logic [1:0] burst, input logic [IDW-1:0] id,
                       input logic [DW-1:0] data[$], input logic [DW/8-1:0] strb[$],
                       output logic [1:0] resp, output logic [IDW-1:0] rid_o);
    aw(a, len, size, burst, id);
    for (int i = 0; i <= len; i++) w_beat(data[i], strb[i], i == len);
    b(resp, rid_o);
  endtask

  // Whole read burst. Returns every beat and the worst response.
  task automatic read(input logic [39:0] a, input logic [7:0] len, input logic [2:0] size,
                      input logic [1:0] burst, input logic [IDW-1:0] id,
                      output logic [DW-1:0] data[$], output logic [1:0] resp,
                      output logic [IDW-1:0] rid_o, output int last_err);
    logic [DW-1:0] d; logic [1:0] rr; bit l;
    data = {}; resp = 0; last_err = 0;
    ar(a, len, size, burst, id);
    for (int i = 0; i <= len; i++) begin
      r_beat(d, rr, rid_o, l);
      data.push_back(d);
      if (rr > resp) resp = rr;
      if (l != (i == len)) last_err++;
    end
  endtask

  // Self-checking random traffic (used by the crossbar/fabric benches).
  // Random INCR bursts of full 256-bit beats into [base + part, +4 KB) of a
  // randomly chosen base; ~10% go to `hole` and must return DECERR.
  // Only for DW = 256. Each BFM instance runs its own copy, so several
  // masters can run concurrently without sharing task-local storage.
  int sc_err = 0, sc_ok = 0;
  task automatic selfcheck(input int iters, input longint b0, b1, b2, b3, b4, b5,
                           input longint part, input longint hole);
    longint bases[6];
    bases[0] = b0; bases[1] = b1; bases[2] = b2; bases[3] = b3; bases[4] = b4; bases[5] = b5;
    for (int it = 0; it < iters; it++) begin
      logic [DW-1:0] d[$], rd[$]; logic [DW/8-1:0] s[$]; logic [1:0] r; logic [IDW-1:0] idb, id;
      int le, len; longint a; bit is_hole;
      d = {}; rd = {}; s = {};
      id      = IDW'($urandom);
      len     = $urandom_range(7);
      is_hole = ($urandom_range(9) == 0);
      if (is_hole) begin
        a = hole + part;
      end else begin
        // Two random draws, each in its own statement: combining them into
        // one expression (as this line used to) triggers a lint tool's
        // SIDEEFFECT check, since expression evaluation order isn't guaranteed.
        int base_idx, off;
        base_idx = $urandom_range(5);
        off      = $urandom_range(15);
        a = bases[base_idx] + part + (off * 32);
      end
      for (int i = 0; i <= len; i++) begin
        logic [DW-1:0] dd;
        for (int k = 0; k < DW / 32; k++) dd[k*32 +: 32] = $urandom;
        d.push_back(dd); s.push_back('1);
      end
      write(40'(a), 8'(len), 3'd5, 2'b01, id, d, s, r, idb);
      if (idb !== id) sc_err++;
      if (is_hole) begin
        if (r !== 2'b11) sc_err++;
        read(40'(a), 8'(len), 3'd5, 2'b01, id, rd, r, idb, le);
        if (r !== 2'b11 || le != 0 || rd.size() != len + 1) sc_err++;
      end else begin
        if (r !== 2'b00) sc_err++;
        read(40'(a), 8'(len), 3'd5, 2'b01, ~id, rd, r, idb, le);
        if (r !== 2'b00 || idb !== ~id || le != 0) sc_err++;
        for (int i = 0; i <= len; i++) if (rd[i] !== d[i]) begin
          sc_err++;
          if (sc_err < 4) $display("  [FAIL] %m data mismatch @%h beat %0d", a, i);
        end
        sc_ok++;
      end
    end
  endtask
endmodule : tb_axi4_master

`endif
