// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// tb_meds_s1_run_ctrl : unit testbench for meds_s1_run_ctrl          [COMPLETE]
//
// Verifies normal halt/resume handshakes, completion buffer x_idle_i gating
// and timeout recovery, reset-halt handshaking, and unexpected un-halt safety.
//
// Run:  make test-unit                     (all testbenches)
//       make test-unit TB=meds_s1_run_ctrl (just this one)
// =============================================================================

module tb_meds_s1_run_ctrl;

  logic clk_i;
  logic rst_ni;

  logic dmactive_i;
  logic ndmreset_i;
  logic hartreset_i;
  logic haltreq_i;
  logic resumereq_i;
  logic resethaltreq_i;
  logic ebreak_match_i;
  logic trigger_match_i;
  logic step_match_i;
  logic debug_halted_i;
  logic x_idle_i;
  logic debug_running_i;

  logic debug_req_o;
  logic core_halted_o;
  logic core_resumed_o;

  int unsigned checks = 0;
  int unsigned errors = 0;

  meds_s1_run_ctrl dut (
    .clk_i           (clk_i),
    .rst_ni          (rst_ni),
    .dmactive_i      (dmactive_i),
    .ndmreset_i      (ndmreset_i),
    .hartreset_i     (hartreset_i),
    .haltreq_i       (haltreq_i),
    .resumereq_i     (resumereq_i),
    .resethaltreq_i  (resethaltreq_i),
    .ebreak_match_i  (ebreak_match_i),
    .trigger_match_i (trigger_match_i),
    .step_match_i    (step_match_i),
    .debug_halted_i  (debug_halted_i),
    .x_idle_i        (x_idle_i),
    .debug_running_i (debug_running_i),
    .debug_req_o     (debug_req_o),
    .core_halted_o   (core_halted_o),
    .core_resumed_o  (core_resumed_o)
  );

  task automatic check1(input string name, input logic got, input logic exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("  FAIL %-32s got=%0d exp=%0d", name, got, exp);
    end
  endtask

  initial clk_i = 1'b0;
  always #5 clk_i <= ~clk_i;

  task automatic step_clk(input int cycles = 1);
    repeat (cycles) @(posedge clk_i);
    #1;
  endtask

  initial begin
    $display("=== tb_meds_s1_run_ctrl ===");

    rst_ni          = 1'b0;
    dmactive_i      = 1'b0;
    ndmreset_i      = 1'b0;
    hartreset_i     = 1'b0;
    haltreq_i       = 1'b0;
    resumereq_i     = 1'b0;
    resethaltreq_i  = 1'b0;
    ebreak_match_i  = 1'b0;
    trigger_match_i = 1'b0;
    step_match_i    = 1'b0;
    debug_halted_i  = 1'b0;
    x_idle_i        = 1'b1;
    debug_running_i = 1'b1;

    step_clk(2);
    rst_ni = 1'b1;
    step_clk(2);

    // -------------------------------------------------------------------------
    // Test 1: Activate DM
    // -------------------------------------------------------------------------
    dmactive_i = 1'b1;
    step_clk(2);
    check1("T1: NORMAL_E after dmactive", (dut.state_q == dut.NORMAL_E), 1'b1);

    // -------------------------------------------------------------------------
    // Test 2: Halt Request with x_idle_i delay
    // -------------------------------------------------------------------------
    haltreq_i = 1'b1;
    step_clk(1);
    check1("T2: HALTING_E entered", (dut.state_q == dut.HALTING_E), 1'b1);
    check1("T2: debug_req_o asserted", debug_req_o, 1'b1);

    debug_halted_i  = 1'b1;
    debug_running_i = 1'b0;
    x_idle_i        = 1'b0;
    step_clk(2);
    check1("T2: Stay HALTING_E without idle", (dut.state_q == dut.HALTING_E), 1'b1);

    x_idle_i = 1'b1;
    #1;
    check1("T2: core_halted_o Mealy assert", core_halted_o, 1'b1);
    step_clk(1);
    check1("T2: HALTED_E after x_idle", (dut.state_q == dut.HALTED_E), 1'b1);
    check1("T2: debug_req_o stays asserted", debug_req_o, 1'b1);

    // -------------------------------------------------------------------------
    // Test 3: Resume sequence
    // -------------------------------------------------------------------------
    haltreq_i   = 1'b0;
    resumereq_i = 1'b1;
    step_clk(1);
    check1("T3: RESUMING_E entered", (dut.state_q == dut.RESUMING_E), 1'b1);
    check1("T3: debug_req_o deasserted", debug_req_o, 1'b0);

    resumereq_i    = 1'b0;
    debug_halted_i = 1'b0;
    step_clk(2);

    debug_running_i = 1'b1;
    #1;
    check1("T3: core_resumed_o Mealy assert", core_resumed_o, 1'b1);

    step_clk(1);
    check1("T3: NORMAL_E reached", (dut.state_q == dut.NORMAL_E), 1'b1);
    check1("T3: core_resumed_o deasserted", core_resumed_o, 1'b0);

    // -------------------------------------------------------------------------
    // Test 4: Hart Reset with resethaltreq_i = 1 (verifies debug_req_o & pulse)
    // -------------------------------------------------------------------------
    resethaltreq_i = 1'b1;
    hartreset_i    = 1'b1;
    #1;
    check1("T4: debug_req_o high in reset", debug_req_o, 1'b1);
    step_clk(1);
    check1("T4: HART_RESET_E entered", (dut.state_q == dut.HART_RESET_E), 1'b1);

    // Deassert hartreset while core is not yet halted -> must go to HALTING_E
    hartreset_i = 1'b0;
    #1;
    check1("T4: debug_req_o stays high", debug_req_o, 1'b1);
    step_clk(1);
    check1("T4: Wait in HALTING_E for core", (dut.state_q == dut.HALTING_E), 1'b1);

    // Core acknowledges halt out of reset
    debug_running_i = 1'b0;
    debug_halted_i  = 1'b1;
    x_idle_i        = 1'b1;
    #1;
    check1("T4: core_halted_o pulses", core_halted_o, 1'b1);
    step_clk(1);
    check1("T4: HALTED_E after ack", (dut.state_q == dut.HALTED_E), 1'b1);
    resethaltreq_i = 1'b0;

    // -------------------------------------------------------------------------
    // Test 5: Unexpected core un-halt without resumereq_i recovers cleanly
    // -------------------------------------------------------------------------
    debug_halted_i  = 1'b0;
    debug_running_i = 1'b1;
    #1;
    check1("T5: core_resumed_o on un-halt", core_resumed_o, 1'b1);
    step_clk(1);
    check1("T5: Recover to NORMAL_E", (dut.state_q == dut.NORMAL_E), 1'b1);

    // -------------------------------------------------------------------------
    // Test 6: x_idle_i timeout prevents permanent hang in HALTING_E
    // -------------------------------------------------------------------------
    ebreak_match_i  = 1'b1;
    step_clk(1);
    ebreak_match_i  = 1'b0;
    debug_running_i = 1'b0;
    debug_halted_i  = 1'b1;
    x_idle_i        = 1'b0; // Coprocessor hung, x_idle_i never asserts

    step_clk(7);
    check1("T6: Timeout forces core_halted", core_halted_o, 1'b1);
    step_clk(1);
    check1("T6: Entered HALTED_E on timeout", (dut.state_q == dut.HALTED_E), 1'b1);

    // -------------------------------------------------------------------------
    // Test 7: dmactive_i drop forces NORMAL_E
    // -------------------------------------------------------------------------
    dmactive_i = 1'b0;
    step_clk(1);
    check1("T7: NORMAL_E on dmactive=0", (dut.state_q == dut.NORMAL_E), 1'b1);
    check1("T7: debug_req_o is 0", debug_req_o, 1'b0);

    if (errors == 0) begin
      $display("=== PASS : %0d checks ===", checks);
      $finish;
    end else begin
      $display("=== FAIL : %0d errors of %0d checks ===", errors, checks);
      $fatal(1, "tb_meds_s1_run_ctrl failed");
    end
  end

endmodule
