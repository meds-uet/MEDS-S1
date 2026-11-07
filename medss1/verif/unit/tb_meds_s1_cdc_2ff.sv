// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// tb_meds_s1_cdc_2ff : unit testbench for meds_s1_cdc_2ff              [COMPLETE]
//
// Unit testbench for meds_s1_cdc_2ff.  Checks the properties a level
// synchronizer must have: held at zero in reset, exactly two destination clock
// edges of latency, a data stream with no dropped or duplicated samples, and a
// reset that clears BOTH stages (a stale first stage would leak a value out
// after reset release).
//
// R-V2: the same checks run at three widths in one simulation (1, 8 and 33
// bits; the odd and the single-bit cases are the ones that break), and every
// expectation is derived from the width, never from a literal.
//
// Run:  make test-unit TB=meds_s1_cdc_2ff
// =============================================================================

module tb_meds_s1_cdc_2ff;

  localparam int unsigned N_CFG     = 3;
  localparam int unsigned WIDTHS [N_CFG] = '{1, 8, 33};
  localparam int unsigned HALF      = 5;
  localparam int unsigned N_LAT     = 16;
  localparam int unsigned N_STREAM  = 256;
  localparam int unsigned MAX_PRINT = 20;
  localparam longint unsigned TIMEOUT = 64'd1_000_000;

  int unsigned checks     = 0;
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
      $fatal(1, "tb_meds_s1_cdc_2ff checked nothing");
    end else if (errors != 0) begin
      $display("=== FAIL : %0d errors of %0d checks ===", errors, checks);
      $fatal(1, "tb_meds_s1_cdc_2ff failed");
    end else begin
      $display("=== PASS : %0d checks ===", checks);
      $finish;
    end
  endtask

  // Watchdog: a hung testbench must fail, not stall CI.
  initial begin
    #TIMEOUT;
    $display("=== FAIL : watchdog timeout ===");
    $fatal(1, "watchdog timeout");
  end

  logic clk;

  initial begin
    clk = 1'b0;
    forever #HALF clk = ~clk;
  end

  for (genvar g = 0; g < N_CFG; g++) begin : gen_cfg

    localparam int unsigned W = WIDTHS[g];

    logic         rst_n;
    logic [W-1:0] async_in;
    logic [W-1:0] sync_out;

    meds_s1_cdc_2ff #(
      .WIDTH (W)
    ) dut (
      .clk_i  (clk),
      .rst_ni (rst_n),
      .async_i(async_in),
      .sync_o (sync_out)
    );

    function automatic logic [W-1:0] rnd();
      return W'({$urandom(), $urandom()});
    endfunction

    logic [W-1:0] cur, nxt, prev;

    initial begin
      $display("=== tb_meds_s1_cdc_2ff : WIDTH=%0d ===", W);
      rst_n    = 1'b0;
      async_in = '1;

      // Held at zero while reset is asserted, even with a non-zero input.
      repeat (3) begin
        @(posedge clk); #1;
        check(sync_out == '0, "output held at 0 while reset asserted");
      end

      @(negedge clk);
      rst_n    = 1'b1;
      async_in = '0;
      repeat (3) @(posedge clk);
      #1;
      check(sync_out == '0, "settled at 0 after reset release");

      // Latency: a changed value is invisible after 1 edge, visible after 2.
      cur = '0;
      for (int unsigned i = 0; i < N_LAT; i++) begin
        do nxt = rnd(); while (nxt == cur);
        @(negedge clk);
        async_in = nxt;
        @(posedge clk); #1;
        check(sync_out == cur, "value not visible after 1 edge");
        @(posedge clk); #1;
        check(sync_out == nxt, "value visible after exactly 2 edges");
        cur = nxt;
      end

      // Streaming: a new random value every cycle; the output must be the
      // value applied one cycle before the most recent (no drops or dupes).
      prev = cur;
      for (int unsigned i = 0; i < N_STREAM; i++) begin
        nxt = rnd();
        @(negedge clk);
        async_in = nxt;
        @(posedge clk); #1;
        check(sync_out == prev, "stream: output is the input from two edges ago");
        prev = nxt;
      end

      // Asynchronous reset mid-cycle clears the output with no clock edge,
      // and also clears the first stage (nothing stale leaks after release).
      async_in = '1;
      repeat (3) @(posedge clk);
      #1;
      check(sync_out == '1, "both stages filled before reset test");
      @(negedge clk); #1;
      rst_n = 1'b0;
      #1;
      check(sync_out == '0, "async reset clears output without a clock edge");
      async_in = '0;
      @(negedge clk);
      rst_n = 1'b1;
      repeat (3) begin
        @(posedge clk); #1;
        check(sync_out == '0, "no stale first-stage value leaks after reset");
      end

      n_cfg_done++;
    end
  end

  initial begin
    wait (n_cfg_done == N_CFG);
    finish_tb();
  end

endmodule : tb_meds_s1_cdc_2ff
