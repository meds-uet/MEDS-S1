// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// tb_meds_s1_dmi_rst_gen : unit testbench for meds_s1_dmi_rst_gen      [COMPLETE]
//
// Unit testbench for meds_s1_dmi_rst_gen. The contract is R-C4's reset
// policy: asynchronous assert, synchronous de-assert. Checked here:
//   - assert is asynchronous (no clock edge needed) for BOTH the external
//     reset and a hardreset pulse, including a pulse narrower than a clock
//     period that never spans an edge;
//   - de-assert is synchronous and takes exactly RELEASE_EDGES edges;
//   - the output only ever changes at a clock edge when releasing;
//   - it cannot wedge: after any random reset/pulse stream, once the
//     inputs go quiet the output always releases (R-V5).
//
// Run:  make test-unit TB=meds_s1_dmi_rst_gen
// =============================================================================

module tb_meds_s1_dmi_rst_gen;

  localparam int unsigned HALF         = 5;
  localparam int unsigned RELEASE_EDGES = 2;   // two-flop release chain
  localparam int unsigned N_RANDOM     = 500;
  localparam int unsigned MAX_PRINT    = 20;
  localparam longint unsigned TIMEOUT  = 64'd1_000_000;

  int unsigned checks = 0;
  int unsigned errors   = 0;

  task automatic check(input bit cond, input string what);
    checks++;
    if (!cond) begin
      errors++;
      if (errors <= MAX_PRINT) $display("FAIL @%0t: %s", $time, what);
    end
  endtask

  task automatic finish_tb();
    if (checks == 0) begin
      $display("=== FAIL : no checks executed ===");
      $fatal(1, "tb_meds_s1_dmi_rst_gen checked nothing");
    end else if (errors != 0) begin
      $display("=== FAIL : %0d errors of %0d checks ===", errors, checks);
      $fatal(1, "tb_meds_s1_dmi_rst_gen failed");
    end else begin
      $display("=== PASS : %0d checks ===", checks);
      $finish;
    end
  endtask

  initial begin
    #TIMEOUT;
    $display("=== FAIL : watchdog timeout ===");
    $fatal(1, "watchdog timeout");
  end

  logic clk;
  logic rst_n;
  logic hr_pulse;
  logic rst_out;

  meds_s1_dmi_rst_gen dut (
    .clk_i            (clk),
    .rst_ni           (rst_n),
    .hardreset_pulse_i(hr_pulse),
    .rst_n_o           (rst_out)
  );

  initial begin
    clk = 1'b0;
    forever #HALF clk = ~clk;
  end

  // Wait for n clock edges, sampling just after each.
  task automatic edges(input int unsigned n);
    repeat (n) begin
      @(posedge clk); #1;
    end
  endtask

  logic m1, m2, asserted;

  initial begin
    rst_n    = 1'b0;
    hr_pulse = 1'b0;

    // External reset asserts with no clock edge needed.
    #1;
    check(rst_out == 1'b0, "external reset asserts asynchronously");
    edges(3);
    check(rst_out == 1'b0, "held while external reset stays asserted");

    // Release: output stays low for RELEASE_EDGES-1 edges, high after
    // exactly RELEASE_EDGES, and only changes at a clock edge.
    @(negedge clk);
    rst_n = 1'b1;
    #1;
    check(rst_out == 1'b0, "release does not take effect between clock edges");
    for (int unsigned i = 1; i < RELEASE_EDGES; i++) begin
      edges(1);
      check(rst_out == 1'b0, "still held before the final release edge");
    end
    edges(1);
    check(rst_out == 1'b1, "released after exactly RELEASE_EDGES edges");
    @(negedge clk); #1;
    check(rst_out == 1'b1, "stays released between edges");

    // A hardreset pulse asserts reset asynchronously, even one so narrow
    // it never spans a clock edge.
    @(negedge clk); #1;
    hr_pulse = 1'b1;
    #1;
    check(rst_out == 1'b0, "hardreset asserts asynchronously");
    hr_pulse = 1'b0;
    #1;
    check(rst_out == 1'b0, "narrow pulse still produces a full reset (no early release)");
    for (int unsigned i = 1; i < RELEASE_EDGES; i++) begin
      edges(1);
      check(rst_out == 1'b0, "held until the release chain completes");
    end
    edges(1);
    check(rst_out == 1'b1, "released after hardreset");

    // A pulse held across several edges keeps reset asserted throughout,
    // then releases RELEASE_EDGES edges after it ends.
    @(negedge clk); #1;
    hr_pulse = 1'b1;
    edges(3);
    check(rst_out == 1'b0, "held while the hardreset pulse spans edges");
    @(negedge clk); #1;
    hr_pulse = 1'b0;
    for (int unsigned i = 1; i < RELEASE_EDGES; i++) begin
      edges(1);
      check(rst_out == 1'b0, "held until the chain completes after a long pulse");
    end
    edges(1);
    check(rst_out == 1'b1, "released after a long hardreset pulse");

    // Random stress against a reference model of the release chain.
    // Start with DUT and model both held in reset; the loop's first
    // action is at the next negedge, so no clock edge separates them.
    rst_n = 1'b0;
    edges(2);
    m1 = 1'b0;
    m2 = 1'b0;
    for (int unsigned i = 0; i < N_RANDOM; i++) begin
      @(negedge clk);
      rst_n    = ($urandom_range(0, 7) != 0);
      hr_pulse = ($urandom_range(0, 5) == 0);
      asserted = !rst_n || hr_pulse;
      if (asserted) begin
        m1 = 1'b0;
        m2 = 1'b0;
      end
      #1;
      check(rst_out == m2, "random: output right after input change");
      @(posedge clk); #1;
      if (!asserted) begin
        m2 = m1;
        m1 = 1'b1;
      end
      check(rst_out == m2, "random: output right after clock edge");
    end

    // No-wedge property: once inputs go quiet it must always release.
    @(negedge clk);
    rst_n    = 1'b1;
    hr_pulse = 1'b0;
    edges(RELEASE_EDGES + 1);
    check(rst_out == 1'b1, "always releases once the inputs are quiet");

    finish_tb();
  end

endmodule : tb_meds_s1_dmi_rst_gen
