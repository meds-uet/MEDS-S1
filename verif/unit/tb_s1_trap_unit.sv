// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// tb_s1_trap_unit : unit testbench for s1_trap_unit [COMPLETE]
//
// Directed checks for trap entry/exit FSM and hardware CSR write port.
// Demonstrates mandatory verification habits (VERIFICATION_GUIDE.md section 3):
// 1. Parameterized widths (W) instead of hardcoded constants (R-V2).
// 2. Independent golden model for mstatus using raw bit positions, avoiding
//    circular validation against the DUT's own struct definitions.
// 3. Tests FSM liveness (illegal transitions are strict no-ops) (R-V5).
// 4. Reports check COUNT and exits non-zero on failure for CI (R-V3).
//
// Reference: SPEC section 9.2, 10.1, 10.3. DUT: rtl/core/s1_trap_unit.sv.
// =============================================================================

module tb_s1_trap_unit;
  import s1_pkg::*;

  localparam int unsigned W = s1_pkg::XLEN;
  localparam int unsigned MIE_BIT  = 3;
  localparam int unsigned MPIE_BIT = 7;
  localparam int unsigned MPP_LSB  = 11;

  // Local state parameters. Matches DUT's 1-bit encoding and avoids Verilator 
  // hierarchical enum resolution quirks.
  localparam logic STATE_NORMAL = 1'b0;
  localparam logic STATE_TRAP   = 1'b1;

  logic clk;
  logic rst_n;
  always #5 clk = ~clk;

  logic            trap_valid;
  logic [5:0]      trap_cause;
  logic [W-1:0]    trap_tval;
  logic [W-1:0]    trap_pc;
  logic            mret_valid;
  logic [W-1:0]    mstatus_rdata;
  logic [W-1:0]    mepc_rdata;
  logic [W-1:0]    mtvec_rdata;
  logic            hw_we    [4];
  logic [11:0]     hw_addr  [4];
  logic [W-1:0]    hw_wdata [4];
  logic            redirect_valid;
  logic [W-1:0]    redirect_pc;

  s1_trap_unit #(.WIDTH(W)) dut (
    .clk_i            (clk),
    .rst_ni           (rst_n),
    .trap_valid_i     (trap_valid),
    .trap_cause_i     (trap_cause),
    .trap_tval_i      (trap_tval),
    .trap_pc_i        (trap_pc),
    .mret_valid_i     (mret_valid),
    .mstatus_rdata_i  (mstatus_rdata),
    .mepc_rdata_i     (mepc_rdata),
    .mtvec_rdata_i    (mtvec_rdata),
    .hw_we_o          (hw_we),
    .hw_addr_o        (hw_addr),
    .hw_wdata_o       (hw_wdata),
    .redirect_valid_o (redirect_valid),
    .redirect_pc_o    (redirect_pc)
  );

  // ---------------------------------------------------------------------------
  // Check helper (R-V3)
  // ---------------------------------------------------------------------------
  int unsigned checks = 0;
  int unsigned errors = 0;

  task automatic check(input logic cond, input string msg);
    checks++;
    if (!cond) begin
      errors++;
      $display(" FAIL %-45s", msg);
    end
  endtask

  // ---------------------------------------------------------------------------
  // Golden model for mstatus.
  // Uses raw bit positions to avoid circular validation against the DUT's 
  // struct definitions.
  // ---------------------------------------------------------------------------
  logic [W-1:0] exp_mstatus_trap;
  logic [W-1:0] exp_mstatus_mret;
  logic [W-1:0] exp_mcause;

  // ---------------------------------------------------------------------------
  // Stimulus
  // ---------------------------------------------------------------------------
  initial begin
    clk = 0;
    rst_n = 0;
    checks = 0;
    errors = 0;

    trap_valid = 0; trap_cause = '0; trap_tval = '0; trap_pc = '0;
    mret_valid = 0;
    mstatus_rdata = W'(64'h0000_0000_0000_0088);
    mepc_rdata    = W'(64'h0000_0000_8000_1000);
    mtvec_rdata   = W'(64'h0000_0000_8000_0000);

    #12 rst_n = 1;
    @(negedge clk);
    #1;  // Yield: allow state_q NBA update to resolve

    // --- Reset state ---------------------------------------------------------
    check(dut.state_q == STATE_NORMAL, "reset lands in S_NORMAL");
    check(!(hw_we[0] || hw_we[1] || hw_we[2] || hw_we[3]), "no hw CSR writes asserted out of reset");
    check(redirect_valid == 1'b0, "no redirect asserted out of reset");

    // --- Trap entry ----------------------------------------------------------
    trap_cause   = 6'd11;
    trap_tval    = W'(64'hDEAD_0000_0000_0000);
    trap_pc      = W'(64'h0000_0000_8000_0100);
    trap_valid   = 1;
    #1;  // Yield: allow combinational outputs to settle

    check(hw_we[0] && hw_addr[0] == 12'h341 && hw_wdata[0] == trap_pc, "trap entry: mepc write incorrect");

    exp_mcause = { {(W-6){1'b0}}, trap_cause };
    check(hw_we[1] && hw_addr[1] == 12'h342 && hw_wdata[1] == exp_mcause, "trap entry: mcause write incorrect");

    check(hw_we[2] && hw_addr[2] == 12'h343 && hw_wdata[2] == trap_tval, "trap entry: mtval write incorrect");

    exp_mstatus_trap = mstatus_rdata;
    exp_mstatus_trap[MPIE_BIT] = mstatus_rdata[MIE_BIT];
    exp_mstatus_trap[MIE_BIT] = 1'b0;
    exp_mstatus_trap[MPP_LSB+1:MPP_LSB] = 2'b11;
    check(hw_we[3] && hw_addr[3] == 12'h300 && hw_wdata[3] == exp_mstatus_trap, "trap entry: mstatus write incorrect");

    check(redirect_valid && redirect_pc == mtvec_rdata, "trap entry redirects to mtvec");

    @(negedge clk);
    trap_valid = 0;
    #1;  // Yield: allow combinational deassertion and state_q update

    check(!(hw_we[0] || hw_we[1] || hw_we[2] || hw_we[3]), "hw writes deassert one cycle after trap entry");
    check(redirect_valid == 1'b0, "redirect deasserts one cycle after trap entry");
    check(dut.state_q == STATE_TRAP, "state transitions to S_TRAP");

    // --- FSM Liveness: trap_valid while trapped (R-V5) -----------------------
    // Must be a strict no-op to prevent duplicate CSR writes or hangs.
    trap_valid = 1;
    #1;

    check(!(hw_we[0] || hw_we[1] || hw_we[2] || hw_we[3]), "trap_valid in S_TRAP must not write CSRs");
    check(redirect_valid == 1'b0, "trap_valid in S_TRAP must not redirect");
    check(dut.state_q == STATE_TRAP, "state remains S_TRAP");

    @(negedge clk);
    trap_valid = 0;
    #1;

    // --- mret exit -----------------------------------------------------------
    mstatus_rdata = exp_mstatus_trap;
    mret_valid = 1;
    #1;

    exp_mstatus_mret = mstatus_rdata;
    exp_mstatus_mret[MIE_BIT] = mstatus_rdata[MPIE_BIT];
    exp_mstatus_mret[MPIE_BIT] = 1'b1;
    exp_mstatus_mret[MPP_LSB+1:MPP_LSB] = 2'b11;

    check(hw_we[3] && hw_addr[3] == 12'h300 && hw_wdata[3] == exp_mstatus_mret, "mret: mstatus restore write incorrect");
    check(!hw_we[0] && !hw_we[1] && !hw_we[2], "mret only writes mstatus");
    check(redirect_valid && redirect_pc == mepc_rdata, "mret redirects to mepc");

    @(negedge clk);
    mret_valid = 0;
    #1;

    check(!(hw_we[0] || hw_we[1] || hw_we[2] || hw_we[3]), "hw writes deassert one cycle after mret");
    check(redirect_valid == 1'b0, "redirect deasserts one cycle after mret");
    check(dut.state_q == STATE_NORMAL, "state transitions to S_NORMAL");

    // --- FSM Liveness: mret while in S_NORMAL (R-V5) -------------------------
    // Must be a strict no-op.
    mret_valid = 1;
    #1;

    check(!(hw_we[0] || hw_we[1] || hw_we[2] || hw_we[3]), "mret_valid in S_NORMAL must not write CSRs");
    check(redirect_valid == 1'b0, "mret_valid in S_NORMAL must not redirect");
    check(dut.state_q == STATE_NORMAL, "state remains S_NORMAL");

    @(negedge clk);
    mret_valid = 0;
    #1;

    // --- Second round trip ---------------------------------------------------
    // Verifies save/restore logic isn't hardcoded to the first test's pattern.
    mstatus_rdata = '0;
    trap_cause    = 6'd2;
    trap_tval     = W'(64'h0000_0000_0000_0013);
    trap_pc       = W'(64'h0000_0000_8000_0200);
    trap_valid    = 1;
    #1;

    exp_mstatus_trap = '0;
    exp_mstatus_trap[MPIE_BIT] = 1'b0;
    exp_mstatus_trap[MIE_BIT] = 1'b0;
    exp_mstatus_trap[MPP_LSB+1:MPP_LSB] = 2'b11;

    check(hw_we[3] && hw_addr[3] == 12'h300 && hw_wdata[3] == exp_mstatus_trap, "second trap: mstatus save/clear incorrect");

    @(negedge clk);
    trap_valid = 0;
    mstatus_rdata = exp_mstatus_trap;
    mret_valid = 1;
    #1;

    exp_mstatus_mret = mstatus_rdata;
    exp_mstatus_mret[MIE_BIT] = mstatus_rdata[MPIE_BIT];
    exp_mstatus_mret[MPIE_BIT] = 1'b1;
    exp_mstatus_mret[MPP_LSB+1:MPP_LSB] = 2'b11;

    check(hw_we[3] && hw_addr[3] == 12'h300 && hw_wdata[3] == exp_mstatus_mret, "second mret: mstatus restore incorrect");
    check(redirect_valid && redirect_pc == mepc_rdata, "second mret redirects to mepc");

    @(negedge clk);
    mret_valid = 0;

    // ---------------------------------------------------------------------------
    // Summary (R-V3: CI requires exact format and non-zero exit on failure)
    // ---------------------------------------------------------------------------
    if (errors == 0) begin
      $display("=== PASS : %0d checks ===", checks);
      $finish;
    end else begin
      $display("=== FAIL : %0d errors of %0d checks ===", errors, checks);
      $fatal(1, "tb_s1_trap_unit failed");
    end
  end
  
  initial begin
    $dumpfile("tb_s1_trap_unit.vcd");
    $dumpvars(0, tb_s1_trap_unit);
  end

endmodule : tb_s1_trap_unit
