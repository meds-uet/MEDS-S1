// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// Shared parts of the three data-cache load tests: the clock, the cache under
// test, a small memory model and the load helpers.  Each test includes this
// file inside its own module, so every test gets its own fresh cache.

  logic clk, rst_n;
  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  dcache_lsu_req_t lsu_req;
  dcache_lsu_rsp_t lsu_rsp;
  dcache_mem_req_t mem_req;
  dcache_mem_rsp_t mem_rsp;

  s1_dcache_basic dut (
    .clk_i     (clk),
    .rst_ni    (rst_n),
    .lsu_req_i (lsu_req),
    .lsu_rsp_o (lsu_rsp),
    .mem_req_o (mem_req),
    .mem_rsp_i (mem_rsp)
  );

  task automatic check(input string name, input logic [DATA_W-1:0] got,
                       input logic [DATA_W-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("  FAIL %-36s got=0x%0h exp=0x%0h", name, got, exp);
    end
  endtask

  // Memory model: every word in memory holds its own address, so the data a
  // load must return is simply the address it asked for.
  function automatic logic [LINE_W-1:0] line_at(input logic [ADDR_W-1:0] line_addr);
    logic [LINE_W-1:0] l;
    for (int unsigned i = 0; i < WORDS; i++) begin
      l[i*DATA_W +: DATA_W] = DATA_W'(line_addr) + DATA_W'(i * WORD_BYTES);
    end
    return l;
  endfunction

  int unsigned       refills    = 0;     // lines the cache fetched from memory
  int unsigned       writebacks = 0;     // lines the cache wrote to memory
  logic [ADDR_W-1:0] refill_addr;        // address of the last fetch
  logic              pending    = 1'b0;

  initial begin
    mem_rsp       = '0;
    mem_rsp.ready = 1'b1;
    forever begin
      @(negedge clk);
      mem_rsp.valid = 1'b0;
      if (pending) begin
        mem_rsp.valid = 1'b1;
        mem_rsp.rdata = line_at(refill_addr);
        pending       = 1'b0;
      end else if (rst_n && mem_req.valid) begin
        if (mem_req.we) begin
          writebacks++;
        end else begin
          refills++;
          refill_addr = mem_req.addr;
          pending     = 1'b1;
        end
      end
    end
  end

  task automatic reset();
    lsu_req = '0;
    rst_n   = 1'b0;
    repeat (3) @(negedge clk);
    rst_n   = 1'b1;
  endtask

  // Drive on the falling edge and sample on the rising edge, like the DUT's flops do.
  // lat counts the cycles from the edge that takes the request to the edge with the answer.
  // one_cycle tells whether the answer lasted one cycle and the cache was ready again after it.
  task automatic load(input logic [ADDR_W-1:0] a, output logic [DATA_W-1:0] d,
                      output int unsigned lat, output logic one_cycle);
    @(negedge clk);
    lsu_req.valid = 1'b1;
    lsu_req.addr  = a;
    lsu_req.we    = 1'b0;
    do @(posedge clk); while (!lsu_rsp.ready);
    @(negedge clk);
    lsu_req.valid = 1'b0;
    lat = 0;
    do begin
      @(posedge clk);
      lat++;
    end while (!lsu_rsp.valid);
    d = lsu_rsp.rdata;
    @(posedge clk);
    one_cycle = !lsu_rsp.valid && lsu_rsp.ready;
  endtask

  function automatic logic [ADDR_W-1:0] addr_of(input int unsigned tag,
                                                input int unsigned set,
                                                input int unsigned word);
    dcache_addr_t a;
    a.tag      = TAG_W'(tag);
    a.index    = INDEX_W'(set);
    a.word     = WORD_IDX_W'(word);
    a.byte_idx = '0;
    return a;
  endfunction

  localparam int unsigned HIT  = 0;      // a hit fetches no line
  localparam int unsigned MISS = 1;      // a miss fetches exactly one line

  // A hit answers in the cycle right after the cache takes the request.
  localparam int unsigned HIT_LATENCY = 1;

  // One load, checked for its data, how many lines were fetched, and that
  // nothing was written back (a load never makes a line dirty).  A hit is also
  // checked for its speed and for a one-cycle answer.
  task automatic load_check(input string name, input logic [ADDR_W-1:0] a,
                            input int unsigned exp_refills);
    logic [DATA_W-1:0] d;
    int unsigned       r0, w0, lat;
    logic              one_cycle;
    dcache_addr_t      line;
    r0 = refills;
    w0 = writebacks;
    load(a, d, lat, one_cycle);
    check({name, ": data"},        d,                        DATA_W'(a));
    check({name, ": refills"},     DATA_W'(refills - r0),    DATA_W'(exp_refills));
    check({name, ": write-backs"}, DATA_W'(writebacks - w0), '0);
    if (exp_refills == HIT) begin
      check({name, ": latency"},          DATA_W'(lat),       DATA_W'(HIT_LATENCY));
      check({name, ": one-cycle answer"}, DATA_W'(one_cycle), DATA_W'(1));
    end
    if (exp_refills == MISS) begin
      line          = a;
      line.word     = '0;
      line.byte_idx = '0;
      check({name, ": refill address"}, DATA_W'(refill_addr), DATA_W'(line));
    end
  endtask
