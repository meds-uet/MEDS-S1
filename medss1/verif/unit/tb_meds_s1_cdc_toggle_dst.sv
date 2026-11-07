// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// tb_meds_s1_cdc_toggle_dst : unit testbench for meds_s1_cdc_toggle_dst  [COMPLETE]
//
// Unit testbench for meds_s1_cdc_toggle_dst, exercised end to end with
// meds_s1_cdc_toggle_src across independent clocks. The property that
// justifies this pair over a plain level synchronizer is rate
// independence: every source pulse must come out as exactly one
// destination-clock-wide pulse whatever the clock ratio. So the same
// stimulus runs against several ratios (destination faster, slower,
// equal, and a non-integer ratio), and the minimum pulse spacing is
// derived from each ratio rather than hard-coded (R-V2).
//
// Checks per ratio: no pulse after reset, every pulse delivered
// (sent == seen), no pulse wider than one destination cycle, and nothing
// left asserted after the stream drains.
//
// Run:  make test-unit TB=meds_s1_cdc_toggle_dst
// =============================================================================

module tb_meds_s1_cdc_toggle_dst;

  localparam int unsigned N_CFG     = 4;
  localparam int unsigned N_PULSES  = 60;
  localparam int unsigned MAX_PRINT = 20;
  localparam longint unsigned TIMEOUT = 64'd5_000_000;

  // Half-periods per configuration.
  localparam int unsigned SRC_HALF [N_CFG] = '{5, 5, 40, 7};
  localparam int unsigned DST_HALF [N_CFG] = '{5, 40, 5, 11};

  int unsigned checks   = 0;
  int unsigned errors     = 0;
  int unsigned n_cfg_done = 0;

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
      $fatal(1, "tb_meds_s1_cdc_toggle_dst checked nothing");
    end else if (errors != 0) begin
      $display("=== FAIL : %0d errors of %0d checks ===", errors, checks);
      $fatal(1, "tb_meds_s1_cdc_toggle_dst failed");
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

  for (genvar g = 0; g < N_CFG; g++) begin : gen_cfg

    localparam int unsigned SH = SRC_HALF[g];
    localparam int unsigned DH = DST_HALF[g];

    // The toggle must be stable for at least 4 destination periods to be
    // guaranteed visible; convert that to a source-cycle gap.
    localparam int unsigned MIN_GAP = (4 * 2 * DH + 2 * SH - 1) / (2 * SH);

    logic src_clk;
    logic dst_clk;
    logic rst_n;
    logic pulse;
    logic toggle;
    logic pulse_out;

    meds_s1_cdc_toggle_src u_src (
      .clk_i   (src_clk),
      .rst_ni  (rst_n),
      .pulse_i (pulse),
      .toggle_o(toggle)
    );

    meds_s1_cdc_toggle_dst u_dst (
      .clk_i   (dst_clk),
      .rst_ni  (rst_n),
      .toggle_i(toggle),
      .pulse_o (pulse_out)
    );

    initial begin
      src_clk = 1'b0;
      forever #SH src_clk = ~src_clk;
    end

    // Offset the destination clock so phase alignment is arbitrary.
    initial begin
      dst_clk = 1'b0;
      #3;
      forever #DH dst_clk = ~dst_clk;
    end

    int unsigned sent;
    int unsigned seen;
    int unsigned too_wide;
    logic        prev_pulse;

    // Destination-domain monitor: one sample per destination cycle.
    initial begin
      seen       = 0;
      too_wide   = 0;
      prev_pulse = 1'b0;
      forever begin
        @(posedge dst_clk);
        if (pulse_out) begin
          seen++;
          if (prev_pulse) too_wide++;
        end
        prev_pulse = pulse_out;
      end
    end

    int unsigned gap;

    initial begin
      sent  = 0;
      pulse = 1'b0;
      rst_n = 1'b0;
      repeat (4) @(posedge src_clk);
      @(negedge src_clk);
      rst_n = 1'b1;

      // Nothing may come out of reset.
      repeat (8) @(posedge dst_clk);
      check(seen == 0, "no spurious pulse after reset");

      for (int unsigned i = 0; i < N_PULSES; i++) begin
        gap = MIN_GAP + $urandom_range(0, 3);
        repeat (gap) @(posedge src_clk);
        @(negedge src_clk);
        pulse = 1'b1;
        @(negedge src_clk);
        pulse = 1'b0;
        sent++;
      end

      // Drain: let the last toggle cross, then confirm nothing is stuck.
      repeat (10) @(posedge dst_clk);
      check(sent == N_PULSES, "driver sent the configured number of pulses");
      check(seen == sent, "every source pulse produced exactly one output pulse");
      check(too_wide == 0, "no output pulse wider than one destination cycle");
      check(pulse_out == 1'b0, "output idle after the stream drains");

      n_cfg_done++;
    end
  end

  initial begin
    wait (n_cfg_done == N_CFG);
    finish_tb();
  end

endmodule : tb_meds_s1_cdc_toggle_dst
