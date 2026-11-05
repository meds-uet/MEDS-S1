// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// tb_s1_regfile : unit testbench for s1_regfile                   [COMPLETE]
//
// Every read is checked against a shadow register file, one cycle after its
// address was presented.  Directed tests cover x0, the two write bypasses and
// a held read address; a randomised soak then writes on most cycles while every
// read port reads on every cycle, which is the case two single-port banks per
// read port exist to survive.
//
// Run:  make test-unit                (all testbenches)
//       make test-unit TB=s1_regfile  (just this one)
// =============================================================================

module tb_s1_regfile
  import s1_pkg::*;
;

  localparam int unsigned N_READ = 2;
  localparam int unsigned N_REG  = 2**REG_ADDR_W;
  localparam int unsigned N_SOAK = 5000;

  logic                  clk;
  logic                  rst_n;
  logic [N_READ-1:0][REG_ADDR_W-1:0] raddr;  // packed, to match the DUT ports
  logic [N_READ-1:0][XLEN-1:0]       rdata;
  logic                  we;
  logic [REG_ADDR_W-1:0] waddr;
  logic [XLEN-1:0]       wdata;

  // What the tests ask for next.  The DUT inputs above are registered from
  // these, so the DUT is driven the way the pipeline drives it: from flops.
  logic [REG_ADDR_W-1:0] raddr_n [N_READ];
  logic                  we_n;
  logic [REG_ADDR_W-1:0] waddr_n;
  logic [XLEN-1:0]       wdata_n;
  string                 phase = "reset";
  bit                    live  = 1'b0;      // set once reset is released

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  s1_regfile #(.N_READ(N_READ)) dut (
    .clk_i   (clk),
    .rst_ni  (rst_n),
    .raddr_i (raddr),
    .rdata_o (rdata),
    .we_i    (we),
    .waddr_i (waddr),
    .wdata_i (wdata)
  );

  int unsigned checks = 0;
  int unsigned errors = 0;

  // ---------------------------------------------------------------------------
  // Golden model.  The register file as the ISA describes it: an array, x0 is
  // zero, a write is visible to every later read.  It knows nothing about
  // banks, read latency or bypasses.
  // ---------------------------------------------------------------------------
  logic [XLEN-1:0]       shadow  [N_REG];
  bit                    written [N_REG];     // storage is not reset: unwritten = unknown
  logic [REG_ADDR_W-1:0] raddr_prev [N_READ];
  bit                    prev_valid;

  // Drive the DUT, and keep the model in step with what the DUT sampled.
  always_ff @(posedge clk) begin
    we    <= we_n;
    waddr <= waddr_n;
    wdata <= wdata_n;
    for (int unsigned p = 0; p < N_READ; p++) begin
      raddr[p]      <= raddr_n[p];
      raddr_prev[p] <= raddr[p];
    end
    prev_valid <= live;
    if (live && we && (waddr != '0)) begin
      shadow[waddr]  <= wdata;
      written[waddr] <= 1'b1;
    end
  end

  // Mid-cycle, check the data for LAST cycle's addresses.  A write presented
  // THIS cycle to the same register must already be visible.
  initial forever begin
    logic [REG_ADDR_W-1:0] a;
    logic [XLEN-1:0]       exp;
    @(negedge clk);
    if (prev_valid) begin
      for (int unsigned p = 0; p < N_READ; p++) begin
        a = raddr_prev[p];
        if (a == '0)                  exp = '0;
        else if (we && (waddr == a))  exp = wdata;
        else                          exp = shadow[a];
        if ((a == '0) || (we && (waddr == a)) || written[a]) begin
          checks++;
          if (rdata[p] !== exp) begin
            errors++;
            $display("  FAIL %-22s port %0d x%0d got=0x%h exp=0x%h", phase, p, a, rdata[p], exp);
          end
        end
      end
    end
  end

  // Hand the requested stimulus to the next clock cycle.
  task automatic cycle(input string name);
    phase = name;
    @(negedge clk);
  endtask

  task automatic set_write(input logic [REG_ADDR_W-1:0] a, input logic [XLEN-1:0] d);
    we_n = 1'b1; waddr_n = a; wdata_n = d;
  endtask

  task automatic no_write();
    we_n = 1'b0; waddr_n = '0; wdata_n = '0;
  endtask

  task automatic read_all(input logic [REG_ADDR_W-1:0] a);
    for (int unsigned p = 0; p < N_READ; p++) raddr_n[p] = a;
  endtask

  function automatic logic [XLEN-1:0] rand_data();
    logic [XLEN-1:0] d;
    for (int unsigned i = 0; i < XLEN; i += 32) d = (d << 32) | XLEN'($urandom());
    return d;
  endfunction

  // A value that depends on the register number in every byte.
  function automatic logic [XLEN-1:0] pattern(input int unsigned r, input logic [7:0] salt);
    logic [XLEN-1:0] d;
    for (int unsigned i = 0; i < XLEN/8; i++) d[i*8 +: 8] = 8'(r + i) ^ salt;
    return d;
  endfunction

  initial begin
    logic [REG_ADDR_W-1:0] r_a, r_b;

    rst_n = 1'b0;
    no_write();
    read_all('0);
    repeat (2) @(negedge clk);
    rst_n = 1'b1;
    live  = 1'b1;

    // -- x0 reads zero, before and after a write aimed at it -----------------
    read_all('0);             cycle("x0 after reset");
    set_write('0, '1);        cycle("write to x0");
    no_write();               cycle("x0 after write");
                              cycle("x0 after write");

    // -- plain storage: write every register, then read every one back --------
    for (int unsigned r = 1; r < N_REG; r++) begin
      set_write(REG_ADDR_W'(r), pattern(r, 8'h00));
      read_all(REG_ADDR_W'(r - 1));
      cycle("fill");
    end
    no_write();
    for (int unsigned r = 0; r < N_REG; r++) begin
      for (int unsigned p = 0; p < N_READ; p++) raddr_n[p] = REG_ADDR_W'((r + p) % N_REG);
      cycle("read back");
    end
    cycle("read back");

    r_a = REG_ADDR_W'(N_REG - 1);
    r_b = REG_ADDR_W'(N_REG / 2);

    // -- write in the same cycle as the read address (last-cycle bypass) ------
    read_all(r_a); set_write(r_a, pattern(1, 8'hA5));  cycle("write with address");
    no_write();                                        cycle("write with address");

    // -- write in the cycle the data is consumed (retire bypass) --------------
    read_all(r_b); no_write();                         cycle("write with data");
    set_write(r_b, pattern(2, 8'h5A));                 cycle("write with data");
    no_write();                                        cycle("write with data");

    // -- address held, as in a stalled ID, across back-to-back writes ---------
    read_all(r_a);
    for (int unsigned i = 0; i < 8; i++) begin
      set_write(r_a, pattern(i, 8'hC3));
      cycle("held address");
    end
    no_write();
    repeat (3) cycle("held address");

    // -- a write to one register leaves its neighbours alone ------------------
    set_write(r_b, pattern(3, 8'h3C)); read_all(REG_ADDR_W'(r_b - 1)); cycle("neighbour");
    no_write();                        read_all(REG_ADDR_W'(r_b + 1)); cycle("neighbour");
                                                                       cycle("neighbour");

    // -- soak: reads on every port every cycle, writes on most cycles ---------
    for (int unsigned i = 0; i < N_SOAK; i++) begin
      for (int unsigned p = 0; p < N_READ; p++)
        raddr_n[p] = REG_ADDR_W'($urandom_range(N_REG - 1, 0));
      if ($urandom_range(3, 0) != 0)
        // a narrow address range half the time, to force read/write collisions
        set_write(REG_ADDR_W'($urandom_range((i % 2 == 0) ? 3 : N_REG - 1, 0)), rand_data());
      else
        no_write();
      cycle("soak");
    end
    no_write();
    repeat (3) cycle("soak");

    $display("---------------------------------------------------------------");
    if (errors == 0)
      $display("=== PASS : %0d checks ===", checks);
    else
      $display("=== FAIL : %0d errors of %0d checks ===", errors, checks);
    $display("---------------------------------------------------------------");

    if (errors == 0) $finish;
    else             $fatal(1, "tb_s1_regfile failed");
  end

endmodule
