// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// tb_meds_s1_abs_ctrl : unit testbench for meds_s1_abs_ctrl          [COMPLETE]
//
// Verifies abstract command execution, cmderr encodings (1: busy, 2: not
// supported, 4: halt/resume), in-flight command completion under busy error,
// and synchronous ERROR_WAIT_E recovery.
//
// Run:  make test-unit                     (all testbenches)
//       make test-unit TB=meds_s1_abs_ctrl (just this one)
// =============================================================================

module tb_meds_s1_abs_ctrl;

  logic       clk_i;
  logic       rst_ni;
  logic       cmd_en_i;
  logic [7:0] cmdtype_i;
  logic       postexec_i;
  logic       cmderr_status_i;
  logic       debug_halted_i;
  logic       debug_reg_ready_i;
  logic       aarpostincrement_i;

  logic       abs_en_o;
  logic       debug_reg_en_o;
  logic       busy_o;
  logic       set_cmderr_o;
  logic [2:0] cmderr_o;
  logic       inc_regno_o;

  // Simulated abstractcs.cmderr register to test real synchronous timing
  logic [2:0] sim_cmderr_q;
  logic       clr_cmderr;

  int unsigned checks = 0;
  int unsigned errors = 0;

  meds_s1_abs_ctrl dut (
    .clk_i              (clk_i),
    .rst_ni             (rst_ni),
    .cmd_en_i           (cmd_en_i),
    .cmdtype_i          (cmdtype_i),
    .postexec_i         (postexec_i),
    .cmderr_status_i    (cmderr_status_i),
    .debug_halted_i     (debug_halted_i),
    .debug_reg_ready_i  (debug_reg_ready_i),
    .aarpostincrement_i (aarpostincrement_i),
    .abs_en_o           (abs_en_o),
    .debug_reg_en_o     (debug_reg_en_o),
    .busy_o             (busy_o),
    .set_cmderr_o       (set_cmderr_o),
    .cmderr_o           (cmderr_o),
    .inc_regno_o        (inc_regno_o)
  );

  // Model synchronous abstractcs.cmderr register driven by DUT outputs
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      sim_cmderr_q <= 3'd0;
    end else if (clr_cmderr) begin
      sim_cmderr_q <= 3'd0;
    end else if (set_cmderr_o && (sim_cmderr_q == 3'd0)) begin
      sim_cmderr_q <= cmderr_o;
    end
  end

  assign cmderr_status_i = (sim_cmderr_q != 3'd0);

  task automatic check1(input string name, input logic got, input logic exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("  FAIL %-32s got=%0d exp=%0d", name, got, exp);
    end
  endtask

  task automatic check3(input string name, input logic [2:0] got, input logic [2:0] exp);
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
    $display("=== tb_meds_s1_abs_ctrl ===");

    rst_ni             = 1'b0;
    cmd_en_i           = 1'b0;
    cmdtype_i          = 8'h0;
    postexec_i         = 1'b0;
    clr_cmderr         = 1'b0;
    debug_halted_i     = 1'b0;
    debug_reg_ready_i  = 1'b0;
    aarpostincrement_i = 1'b0;

    step_clk(2);
    rst_ni = 1'b1;
    step_clk(2);

    // -------------------------------------------------------------------------
    // Test 1: Valid Register Access
    // -------------------------------------------------------------------------
    debug_halted_i = 1'b1;
    cmdtype_i      = 8'h0;
    cmd_en_i       = 1'b1;
    step_clk(1);
    check1("T1: Enter EXEC_REG_E state", (dut.state_q == dut.EXEC_REG_E), 1'b1);
    check1("T1: busy_o asserted", busy_o, 1'b1);
    check1("T1: abs_en_o asserted", abs_en_o, 1'b1);
    check1("T1: debug_reg_en_o asserted", debug_reg_en_o, 1'b1);

    cmd_en_i           = 1'b0;
    debug_reg_ready_i  = 1'b1;
    aarpostincrement_i = 1'b1;
    #1;
    check1("T1: inc_regno_o asserted", inc_regno_o, 1'b1);

    step_clk(1);
    check1("T1: Return to IDLE_E", (dut.state_q == dut.IDLE_E), 1'b1);
    debug_reg_ready_i  = 1'b0;
    aarpostincrement_i = 1'b0;

    // -------------------------------------------------------------------------
    // Test 2: Unsupported command (postexec_i = 1 -> cmderr = 2)
    // -------------------------------------------------------------------------
    postexec_i = 1'b1;
    cmd_en_i   = 1'b1;
    #1;
    check1("T2: set_cmderr_o asserted", set_cmderr_o, 1'b1);
    check3("T2: cmderr_o is 2 (not supp)", cmderr_o, 3'd2);

    step_clk(1);
    cmd_en_i   = 1'b0;
    postexec_i = 1'b0;
    check1("T2: Enter ERROR_WAIT_E", (dut.state_q == dut.ERROR_WAIT_E), 1'b1);
    check1("T2: abs_en_o is 0 on error", abs_en_o, 1'b0);
    check1("T2: busy_o is 0 on error", busy_o, 1'b0);

    // Verify ERROR_WAIT_E genuinely waits across multiple cycles
    step_clk(3);
    check1("T2: Stay in ERROR_WAIT_E", (dut.state_q == dut.ERROR_WAIT_E), 1'b1);
    check3("T2: Latch holds code 2", sim_cmderr_q, 3'd2);

    // Debugger clears cmderr (W1C)
    clr_cmderr = 1'b1;
    step_clk(1);
    clr_cmderr = 1'b0;
    step_clk(1);
    check1("T2: Recover to IDLE_E", (dut.state_q == dut.IDLE_E), 1'b1);

    // -------------------------------------------------------------------------
    // Test 3: Non-halted hart (debug_halted_i = 0 -> cmderr = 4)
    // -------------------------------------------------------------------------
    debug_halted_i = 1'b0;
    cmd_en_i       = 1'b1;
    #1;
    check1("T3: set_cmderr_o asserted", set_cmderr_o, 1'b1);
    check3("T3: cmderr_o is 4 (halt/res)", cmderr_o, 3'd4);

    step_clk(1);
    cmd_en_i = 1'b0;
    check1("T3: Enter ERROR_WAIT_E", (dut.state_q == dut.ERROR_WAIT_E), 1'b1);
    check1("T3: abs_en_o is 0 on error", abs_en_o, 1'b0);

    clr_cmderr = 1'b1;
    step_clk(1);
    clr_cmderr = 1'b0;
    step_clk(1);
    check1("T3: Recover to IDLE_E", (dut.state_q == dut.IDLE_E), 1'b1);

    // -------------------------------------------------------------------------
    // Test 4: Concurrent cmd_en_i during EXEC_REG_E (cmderr = 1, busy)
    // -------------------------------------------------------------------------
    debug_halted_i = 1'b1;
    cmd_en_i       = 1'b1;
    step_clk(1);
    cmd_en_i       = 1'b0;
    check1("T4: In EXEC_REG_E", (dut.state_q == dut.EXEC_REG_E), 1'b1);

    // Issue a second command while the first is still executing
    cmd_en_i = 1'b1;
    #1;
    check1("T4: Busy set_cmderr_o pulse", set_cmderr_o, 1'b1);
    check3("T4: cmderr_o is 1 (busy)", cmderr_o, 3'd1);

    step_clk(1);
    cmd_en_i = 1'b0;
    check1("T4: Enter ERROR_BUSY_E", (dut.state_q == dut.ERROR_BUSY_E), 1'b1);
    check1("T4: In-flight reg stays en", debug_reg_en_o, 1'b1);
    check1("T4: busy_o stays 1", busy_o, 1'b1);

    // Complete the in-flight register transfer
    debug_reg_ready_i = 1'b1;
    step_clk(1);
    debug_reg_ready_i = 1'b0;
    check1("T4: Move to ERROR_WAIT_E", (dut.state_q == dut.ERROR_WAIT_E), 1'b1);
    check1("T4: busy_o drops to 0", busy_o, 1'b0);
    check1("T4: abs_en_o drops to 0", abs_en_o, 1'b0);

    // Clear error and return to IDLE_E
    clr_cmderr = 1'b1;
    step_clk(1);
    clr_cmderr = 1'b0;
    step_clk(1);
    check1("T4: Recover to IDLE_E", (dut.state_q == dut.IDLE_E), 1'b1);

    if (errors == 0) begin
      $display("=== PASS : %0d checks ===", checks);
      $finish;
    end else begin
      $display("=== FAIL : %0d errors of %0d checks ===", errors, checks);
      $fatal(1, "tb_meds_s1_abs_ctrl failed");
    end
  end

endmodule
