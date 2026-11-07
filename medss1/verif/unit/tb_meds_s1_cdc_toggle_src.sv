// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// tb_meds_s1_cdc_toggle_src : unit testbench for meds_s1_cdc_toggle_src  [COMPLETE]
//
// Unit testbench for meds_s1_cdc_toggle_src. The source half of a pulse
// synchronizer must flip its output exactly once per pulse_i cycle and
// otherwise hold, including on back-to-back pulses. Verified against a
// one-line reference model over a random pulse stream.
//
// Run:  make test-unit TB=meds_s1_cdc_toggle_src
// =============================================================================

module tb_meds_s1_cdc_toggle_src;

  localparam int unsigned HALF      = 5;
  localparam int unsigned N_RANDOM  = 512;
  localparam int unsigned MAX_PRINT = 20;
  localparam longint unsigned TIMEOUT = 64'd1_000_000;

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
      $fatal(1, "tb_meds_s1_cdc_toggle_src checked nothing");
    end else if (errors != 0) begin
      $display("=== FAIL : %0d errors of %0d checks ===", errors, checks);
      $fatal(1, "tb_meds_s1_cdc_toggle_src failed");
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
  logic pulse;
  logic toggle;

  meds_s1_cdc_toggle_src dut (
    .clk_i   (clk),
    .rst_ni  (rst_n),
    .pulse_i (pulse),
    .toggle_o(toggle)
  );

  initial begin
    clk = 1'b0;
    forever #HALF clk = ~clk;
  end

  logic        exp_toggle;
  int unsigned n_flips;

  initial begin
    rst_n = 1'b0;
    pulse = 1'b0;
    repeat (2) @(posedge clk);
    #1;
    check(toggle == 1'b0, "toggle is 0 in reset");

    @(negedge clk);
    rst_n      = 1'b1;
    exp_toggle = 1'b0;

    // No pulse: holds.
    repeat (4) begin
      @(posedge clk); #1;
      check(toggle == exp_toggle, "holds without a pulse");
    end

    // Exactly one flip per single-cycle pulse.
    for (int unsigned i = 0; i < 4; i++) begin
      @(negedge clk);
      pulse = 1'b1;
      @(negedge clk);
      pulse = 1'b0;
      exp_toggle = ~exp_toggle;
      #1;
      check(toggle == exp_toggle, "single pulse flips the toggle exactly once");
      repeat (2) begin
        @(posedge clk); #1;
        check(toggle == exp_toggle, "toggle holds after the pulse");
      end
    end

    // Random pulse stream (includes back-to-back pulses): flips once per
    // pulsed cycle, never otherwise.
    n_flips = 0;
    for (int unsigned i = 0; i < N_RANDOM; i++) begin
      @(negedge clk);
      pulse = 1'($urandom_range(0, 1));
      @(posedge clk); #1;
      if (pulse) begin
        exp_toggle = ~exp_toggle;
        n_flips++;
      end
      check(toggle == exp_toggle, "random stream: toggle follows pulse parity");
    end
    check(n_flips > 0, "random stream actually produced pulses");
    @(negedge clk);
    pulse = 1'b0;

    // Asynchronous reset mid-cycle returns the toggle to 0 with no edge.
    if (!exp_toggle) begin
      @(negedge clk);
      pulse = 1'b1;
      @(negedge clk);
      pulse = 1'b0;
    end
    #1;
    check(toggle == 1'b1, "precondition: toggle is high before reset test");
    rst_n = 1'b0;
    #1;
    check(toggle == 1'b0, "async reset clears the toggle without a clock edge");

    finish_tb();
  end

endmodule : tb_meds_s1_cdc_toggle_src
