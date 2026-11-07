// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// tb_meds_s1_dmi_tck_if : unit testbench for meds_s1_dmi_tck_if        [WIP -- R-06]
//
// Unit testbench for meds_s1_dmi_tck_if, the TCK-domain initiator of the
// 4-phase DMI handshake. The core domain is played by the testbench
// (resp_valid_async_i is driven directly), so the handshake is checked
// from this side alone.
//
// The properties that matter here are the ones that wedge a debugger
// rather than just return a wrong value (R-V5):
//   - req_valid is asserted by a trigger and HELD until the ack is seen,
//     never dropping early and never rising on its own;
//   - the request snapshot is immune to the live DMI register changing
//     while the transaction is in flight;
//   - req_pending covers the WHOLE round trip: it must stay high while the
//     ack is still unwinding, otherwise a new request could be accepted
//     before the previous handshake has returned to zero;
//   - the ack arrives after exactly ACK_SYNC_STAGES edges;
//   - each hardreset pulse flips the toggle exactly once.
// A random-latency stress then re-checks the invariants every cycle.
//
// Run:  make test-unit TB=meds_s1_dmi_tck_if
// =============================================================================

module tb_meds_s1_dmi_tck_if;
  import meds_s1_dtm_pkg::*;

  localparam int unsigned HALF           = 5;
  localparam int unsigned ACK_SYNC_STAGES = 2;     // two-flop synchronizer
  localparam int unsigned N_TXN          = 120;
  localparam int unsigned N_HR           = 40;
  localparam int unsigned MAX_PRINT      = 20;
  localparam longint unsigned TIMEOUT    = 64'd5_000_000;

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
      $fatal(1, "tb_meds_s1_dmi_tck_if checked nothing");
    end else if (errors != 0) begin
      $display("=== FAIL : %0d errors of %0d checks ===", errors, checks);
      $fatal(1, "tb_meds_s1_dmi_tck_if failed");
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

  logic                 clk;
  logic                 rst_n;
  logic [DMI_REQ_W-1:0] dmi_req;
  logic                 req_trigger;
  logic                 hardreset_pulse;
  logic                 resp_valid_async;
  logic                 req_pending;
  logic                 tck_ack;
  logic [DMI_REQ_W-1:0] req_latch;
  logic                 req_valid;
  logic                 hardreset_toggle;

  meds_s1_dmi_tck_if dut (
    .clk_i              (clk),
    .rst_ni             (rst_n),
    .dmi_req_i          (dmi_req),
    .req_trigger_i      (req_trigger),
    .hardreset_pulse_i  (hardreset_pulse),
    .resp_valid_async_i (resp_valid_async),
    .req_pending_o      (req_pending),
    .tck_ack_o          (tck_ack),
    .req_latch_o        (req_latch),
    .req_valid_o        (req_valid),
    .hardreset_toggle_o (hardreset_toggle)
  );

  initial begin
    clk = 1'b0;
    forever #HALF clk = ~clk;
  end

  // Inputs change just after a rising edge; outputs are sampled just
  // after the next one.
  task automatic tick();
    @(posedge clk); #1;
  endtask

  function automatic logic [DMI_REQ_W-1:0] rand_req();
    return DMI_REQ_W'({$urandom(), $urandom()});
  endfunction

  task automatic do_trigger(input logic [DMI_REQ_W-1:0] r);
    dmi_req     = r;
    req_trigger = 1'b1;
    tick();
    req_trigger = 1'b0;
  endtask

  // ---------------------------------------------------------------------
  // Per-cycle invariant monitor
  // ---------------------------------------------------------------------
  logic                 mon_en;
  logic                 pv, pa;
  logic [DMI_REQ_W-1:0] pl;

  initial begin
    mon_en = 1'b0;
    pv     = 1'b0;
    pa     = 1'b0;
    pl     = '0;
    forever begin
      @(posedge clk); #1;
      if (mon_en) begin
        check(req_pending == (req_valid | tck_ack),
              "invariant: req_pending == req_valid | tck_ack");
        if (pv && !pa)
          check(req_valid, "invariant: req_valid held until the ack is seen");
        if (pv)
          check(req_latch == pl, "invariant: snapshot stable while valid");
      end
      pv = req_valid;
      pa = tck_ack;
      pl = req_latch;
    end
  end

  // ---------------------------------------------------------------------
  // Directed handshake walk-through
  // ---------------------------------------------------------------------
  task automatic test_handshake();
    logic [DMI_REQ_W-1:0] r1, r2, garbage;
    r1      = rand_req();
    garbage = ~r1;

    do_trigger(r1);
    check(req_valid == 1'b1,   "trigger raises req_valid");
    check(req_latch == r1,     "snapshot captures the request at the trigger");
    check(req_pending == 1'b1, "req_pending rises with the request");
    check(tck_ack == 1'b0,     "no ack before the core responds");

    // The live DMI register changes; the snapshot must not.
    dmi_req = garbage;
    repeat (6) begin
      tick();
      check(req_valid == 1'b1, "req_valid holds with no ack (never drops early)");
      check(req_latch == r1,   "snapshot ignores the live request changing");
    end

    // The core responds. The ack takes exactly ACK_SYNC_STAGES edges.
    resp_valid_async = 1'b1;
    for (int unsigned i = 1; i < ACK_SYNC_STAGES; i++) begin
      tick();
      check(tck_ack == 1'b0, "ack not visible before the synchronizer has filled");
    end
    tick();
    check(tck_ack == 1'b1,     "ack visible after exactly ACK_SYNC_STAGES edges");
    check(req_valid == 1'b1,   "req_valid still high on the edge the ack first appears");
    check(req_pending == 1'b1, "req_pending high while the ack is rising");

    // The ack is seen: req_valid clears one edge later.
    tick();
    check(req_valid == 1'b0,   "req_valid clears once the ack is seen");
    check(tck_ack == 1'b1,     "ack still high while the core holds resp_valid");

    // The hazard: req_valid is already low, but the handshake has NOT
    // finished unwinding. req_pending must still say so.
    repeat (4) begin
      tick();
      check(req_valid == 1'b0,   "req_valid stays clear");
      check(req_pending == 1'b1, "req_pending stays high while the ack is still up");
    end

    // The core drops resp_valid; the ack falls after the synchronizer
    // delay, and only then may req_pending fall.
    resp_valid_async = 1'b0;
    for (int unsigned i = 1; i < ACK_SYNC_STAGES; i++) begin
      tick();
      check(tck_ack == 1'b1,     "ack not yet released");
      check(req_pending == 1'b1, "req_pending not released before the ack is");
    end
    tick();
    check(tck_ack == 1'b0,     "ack released after ACK_SYNC_STAGES edges");
    check(req_pending == 1'b0, "req_pending falls with the ack, not before");
    check(req_valid == 1'b0,   "handshake fully back to idle");

    // A second transaction works and replaces the snapshot.
    r2 = rand_req();
    do_trigger(r2);
    check(req_latch == r2 && req_valid, "a second transaction is accepted");
    resp_valid_async = 1'b1;
    repeat (ACK_SYNC_STAGES + 2) tick();
    resp_valid_async = 1'b0;
    repeat (ACK_SYNC_STAGES + 1) tick();
    check(!req_pending, "second transaction completes and unwinds");
  endtask

  // ---------------------------------------------------------------------
  // Random-latency stress (invariants checked every cycle by the monitor)
  // ---------------------------------------------------------------------
  task automatic test_random_transactions();
    logic [DMI_REQ_W-1:0] r;
    int unsigned lat, hold;
    for (int unsigned i = 0; i < N_TXN; i++) begin
      r = rand_req();
      do_trigger(r);
      check(req_valid && req_latch == r, "random: request accepted");
      dmi_req = rand_req();                 // live register wanders off
      lat = $urandom_range(0, 8);
      repeat (lat) tick();
      check(req_valid, "random: still valid before the core responds");
      resp_valid_async = 1'b1;
      // Wait (bounded) for the ack.
      for (int unsigned w = 0; w < 6 && !tck_ack; w++) tick();
      check(tck_ack, "random: ack arrives (no hang)");
      hold = $urandom_range(0, 6);
      repeat (hold) tick();
      resp_valid_async = 1'b0;
      for (int unsigned w = 0; w < 6 && tck_ack; w++) tick();
      check(!tck_ack,     "random: ack releases (no hang)");
      check(!req_pending, "random: handshake returns to idle");
      repeat ($urandom_range(0, 3)) tick();
    end
  endtask

  // ---------------------------------------------------------------------
  // Hardreset toggle: exactly one flip per pulse cycle
  // ---------------------------------------------------------------------
  task automatic test_hardreset_toggle();
    logic exp_t;
    exp_t = hardreset_toggle;
    repeat (3) begin
      tick();
      check(hardreset_toggle == exp_t, "toggle holds with no pulse");
    end
    for (int unsigned i = 0; i < N_HR; i++) begin
      hardreset_pulse = 1'($urandom_range(0, 1));
      tick();
      if (hardreset_pulse) exp_t = ~exp_t;
      check(hardreset_toggle == exp_t, "toggle flips exactly once per pulse cycle");
    end
    hardreset_pulse = 1'b0;
  endtask

  // ---------------------------------------------------------------------
  // Asynchronous reset in the middle of a transaction
  // ---------------------------------------------------------------------
  task automatic test_async_reset();
    mon_en = 1'b0;
    do_trigger(rand_req());
    resp_valid_async = 1'b1;
    repeat (ACK_SYNC_STAGES + 1) tick();
    check(tck_ack, "precondition: ack is up before reset");
    @(negedge clk); #1;
    rst_n = 1'b0;
    #1;
    check(!req_valid && !tck_ack && !req_pending,
          "async reset clears the handshake immediately");
    check(req_latch == '0, "async reset clears the snapshot");
    check(hardreset_toggle == 1'b0, "async reset clears the hardreset toggle");
    resp_valid_async = 1'b0;
    @(negedge clk); #1;
    rst_n = 1'b1;
    tick();
    check(!req_pending, "idle after reset release");
  endtask

  initial begin
    rst_n            = 1'b0;
    dmi_req          = '0;
    req_trigger      = 1'b0;
    hardreset_pulse  = 1'b0;
    resp_valid_async = 1'b0;

    repeat (3) tick();
    check(!req_valid && !tck_ack && !req_pending && hardreset_toggle == 1'b0,
          "all outputs idle in reset");
    @(negedge clk); #1;
    rst_n = 1'b1;
    tick();
    mon_en = 1'b1;

    test_handshake();
    test_random_transactions();
    test_hardreset_toggle();
    test_async_reset();

    finish_tb();
  end

endmodule : tb_meds_s1_dmi_tck_if
