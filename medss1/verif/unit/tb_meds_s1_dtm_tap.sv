// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// tb_meds_s1_dtm_tap : unit testbench for meds_s1_dtm_tap              [WIP -- R-06]
//
// Unit testbench for meds_s1_dtm_tap.
//
// Strategy: an independent reference model of the IEEE 1149.1 state table
// and instruction register is stepped alongside the DUT, compared every
// cycle, over a long random TMS/TDI walk (so all 16 states and all
// transitions are exercised, including IR scans interrupted anywhere),
// plus directed checks that encode the spec directly rather than the model:
//   - the Capture-IR pattern (low two bits must be 01) shifts out first;
//   - all four opcodes decode one-hot, every other opcode falls to BYPASS;
//   - five TMS=1 clocks reach Test-Logic-Reset from ANY state;
//   - entering Test-Logic-Reset returns the IR to IDCODE;
//   - asynchronous trst_n_i mid-scan resets immediately.
//
// Timing convention: inputs change just after a falling edge, are sampled
// by the DUT on the next rising edge, and the DUT's falling-edge IR update
// is observed one time-unit after the falling edge.
//
// Expectations come from s1_pkg (R-V2).
//
// Run:  make test-unit TB=meds_s1_dtm_tap
// =============================================================================

module tb_meds_s1_dtm_tap;
  import meds_s1_dtm_pkg::*;

  localparam int unsigned HALF        = 5;
  localparam int unsigned N_RANDOM    = 6000;
  localparam int unsigned N_IR_RANDOM = 24;
  localparam int unsigned N_TLR_TRIES = 32;
  localparam int unsigned MAX_PRINT   = 20;
  localparam longint unsigned TIMEOUT = 64'd5_000_000;

  // Reference state numbering, straight from the 1149.1 state table.
  localparam int unsigned S_TLR   = 0;
  localparam int unsigned S_RTI   = 1;
  localparam int unsigned S_SELDR = 2;
  localparam int unsigned S_CAPDR = 3;
  localparam int unsigned S_SHDR  = 4;
  localparam int unsigned S_EX1DR = 5;
  localparam int unsigned S_PADR  = 6;
  localparam int unsigned S_EX2DR = 7;
  localparam int unsigned S_UPDR  = 8;
  localparam int unsigned S_SELIR = 9;
  localparam int unsigned S_CAPIR = 10;
  localparam int unsigned S_SHIR  = 11;
  localparam int unsigned S_EX1IR = 12;
  localparam int unsigned S_PAIR  = 13;
  localparam int unsigned S_EX2IR = 14;
  localparam int unsigned S_UPIR  = 15;
  localparam int unsigned N_STATES = 16;

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
      $fatal(1, "tb_meds_s1_dtm_tap checked nothing");
    end else if (errors != 0) begin
      $display("=== FAIL : %0d errors of %0d checks ===", errors, checks);
      $fatal(1, "tb_meds_s1_dtm_tap failed");
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

  // ---------------------------------------------------------------------
  // DUT
  // ---------------------------------------------------------------------
  logic clk;
  logic rst_n;
  logic tms;
  logic tdi;
  logic capture_dr, shift_dr, update_dr;
  logic shift_ir, ir_shift_tdo;
  logic sel_bypass, sel_dtmcs, sel_dmi, sel_idcode;

  meds_s1_dtm_tap dut (
    .clk_i          (clk),
    .rst_ni         (rst_n),
    .tms_i          (tms),
    .tdi_i          (tdi),
    .capture_dr_o   (capture_dr),
    .shift_dr_o     (shift_dr),
    .update_dr_o    (update_dr),
    .shift_ir_o     (shift_ir),
    .ir_shift_tdo_o (ir_shift_tdo),
    .sel_bypass_o   (sel_bypass),
    .sel_dtmcs_o    (sel_dtmcs),
    .sel_dmi_o      (sel_dmi),
    .sel_idcode_o   (sel_idcode)
  );

  initial begin
    clk = 1'b0;
    forever #HALF clk = ~clk;
  end

  // ---------------------------------------------------------------------
  // Reference model
  // ---------------------------------------------------------------------
  int unsigned         m_state;
  logic [DTM_IR_W-1:0] m_ir_shift;
  logic [DTM_IR_W-1:0] m_ir_reg;
  int unsigned         visits [N_STATES];

  function automatic int unsigned next_state(input int unsigned s, input logic t);
    case (s)
      S_TLR:   return t ? S_TLR   : S_RTI;
      S_RTI:   return t ? S_SELDR : S_RTI;
      S_SELDR: return t ? S_SELIR : S_CAPDR;
      S_CAPDR: return t ? S_EX1DR : S_SHDR;
      S_SHDR:  return t ? S_EX1DR : S_SHDR;
      S_EX1DR: return t ? S_UPDR  : S_PADR;
      S_PADR:  return t ? S_EX2DR : S_PADR;
      S_EX2DR: return t ? S_UPDR  : S_SHDR;
      S_UPDR:  return t ? S_SELDR : S_RTI;
      S_SELIR: return t ? S_TLR   : S_CAPIR;
      S_CAPIR: return t ? S_EX1IR : S_SHIR;
      S_SHIR:  return t ? S_EX1IR : S_SHIR;
      S_EX1IR: return t ? S_UPIR  : S_PAIR;
      S_PAIR:  return t ? S_EX2IR : S_PAIR;
      S_EX2IR: return t ? S_UPIR  : S_SHIR;
      S_UPIR:  return t ? S_SELDR : S_RTI;
      default: return S_TLR;
    endcase
  endfunction

  task automatic model_reset();
    m_state    = S_TLR;
    m_ir_shift = DTM_IR_RESET_VAL;
    m_ir_reg   = DTM_IR_RESET_VAL;
  endtask

  task automatic compare_strobes();
    check(capture_dr == (m_state == S_CAPDR), "capture_dr matches TAP state");
    check(shift_dr   == (m_state == S_SHDR),  "shift_dr matches TAP state");
    check(update_dr  == (m_state == S_UPDR),  "update_dr matches TAP state");
    check(shift_ir   == (m_state == S_SHIR),  "shift_ir matches TAP state");
    // The serial-out bit only has meaning while shifting the IR.
    if (m_state == S_SHIR)
      check(ir_shift_tdo == m_ir_shift[0], "ir_shift_tdo is the IR shift LSB");
  endtask

  task automatic compare_decode();
    logic exp_idcode, exp_dtmcs, exp_dmi, exp_bypass;
    exp_idcode = (m_ir_reg == DTM_IR_IDCODE);
    exp_dtmcs  = (m_ir_reg == DTM_IR_DTMCS);
    exp_dmi    = (m_ir_reg == DTM_IR_DMI);
    exp_bypass = !(exp_idcode || exp_dtmcs || exp_dmi);
    // While in Test-Logic-Reset the exact cycle on which the IR clears is
    // an implementation detail; the cycle after it is not.
    if (m_state != S_TLR) begin
      check(sel_idcode == exp_idcode, "sel_idcode matches IR");
      check(sel_dtmcs  == exp_dtmcs,  "sel_dtmcs matches IR");
      check(sel_dmi    == exp_dmi,    "sel_dmi matches IR");
      check(sel_bypass == exp_bypass, "sel_bypass matches IR (unknown opcode -> BYPASS)");
      check($onehot({sel_bypass, sel_dtmcs, sel_dmi, sel_idcode}),
            "exactly one data register is selected");
    end
  endtask

  // One TCK cycle. Entered just after a falling edge; returns just after
  // the next falling edge.
  task automatic tck_cycle(input logic tms_v, input logic tdi_v);
    int unsigned old_state;
    tms = tms_v;
    tdi = tdi_v;
    @(posedge clk); #1;
    old_state = m_state;
    if (old_state == S_CAPIR)
      m_ir_shift = DTM_IR_CAPTURE_VAL;
    else if (old_state == S_SHIR)
      m_ir_shift = {tdi_v, m_ir_shift[DTM_IR_W-1:1]};
    m_state = next_state(old_state, tms_v);
    if (m_state == S_TLR) m_ir_reg = DTM_IR_RESET_VAL;
    visits[m_state]++;
    compare_strobes();
    @(negedge clk); #1;
    if (m_state == S_UPIR) m_ir_reg = m_ir_shift;
    compare_decode();
  endtask

  // Asynchronous TAP reset in the middle of a cycle.
  task automatic apply_trst();
    rst_n = 1'b0;
    model_reset();
    #1;
    compare_strobes();
    compare_decode();
    repeat (2) @(posedge clk);
    @(negedge clk); #1;
    rst_n = 1'b1;
  endtask

  // From Run-Test/Idle: scan the IR, LSB first. out_bits is what came out.
  task automatic scan_ir(input  logic [DTM_IR_W-1:0] val,
                         output logic [DTM_IR_W-1:0] out_bits);
    out_bits = '0;
    tck_cycle(1'b1, 1'b0);   // RTI    -> SelectDR
    tck_cycle(1'b1, 1'b0);   // SelDR  -> SelectIR
    tck_cycle(1'b0, 1'b0);   // SelIR  -> CaptureIR
    tck_cycle(1'b0, 1'b0);   // CapIR  -> ShiftIR
    for (int unsigned i = 0; i < DTM_IR_W; i++) begin
      out_bits[i] = ir_shift_tdo;
      tck_cycle(i == DTM_IR_W - 1, val[i]);
    end
    tck_cycle(1'b1, 1'b0);   // Exit1  -> UpdateIR
    tck_cycle(1'b0, 1'b0);   // UpdIR  -> RTI
  endtask

  // From Run-Test/Idle: a DR scan path of n shift cycles with random TDI.
  task automatic dr_path(input int unsigned n_shift);
    tck_cycle(1'b1, 1'b0);   // RTI    -> SelectDR
    tck_cycle(1'b0, 1'b0);   // SelDR  -> CaptureDR
    tck_cycle(1'b0, 1'b0);   // CapDR  -> ShiftDR
    for (int unsigned i = 0; i < n_shift; i++)
      tck_cycle(i == n_shift - 1, 1'($urandom_range(0, 1)));
    tck_cycle(1'b1, 1'b0);   // Exit1  -> UpdateDR
    tck_cycle(1'b0, 1'b0);   // UpdDR  -> RTI
  endtask

  // ---------------------------------------------------------------------
  // Directed tests
  // ---------------------------------------------------------------------
  task automatic test_reset_state();
    check(sel_idcode && !sel_dtmcs && !sel_dmi && !sel_bypass,
          "IR resets to IDCODE");
    check(!capture_dr && !shift_dr && !update_dr && !shift_ir,
          "no strobes in Test-Logic-Reset");
  endtask

  task automatic test_ir_scans();
    logic [DTM_IR_W-1:0] out_bits, val;
    logic [DTM_IR_W-1:0] opcodes [4];
    opcodes[0] = DTM_IR_IDCODE;
    opcodes[1] = DTM_IR_DTMCS;
    opcodes[2] = DTM_IR_DMI;
    opcodes[3] = DTM_IR_BYPASS;

    for (int unsigned k = 0; k < 4 + N_IR_RANDOM; k++) begin
      val = (k < 4) ? opcodes[k] : DTM_IR_W'($urandom());
      scan_ir(val, out_bits);
      check(out_bits == DTM_IR_CAPTURE_VAL, "Capture-IR pattern shifts out LSB first");
      check(out_bits[1:0] == 2'b01, "Capture-IR pattern ends in 01 (1149.1 requirement)");
      check(sel_idcode == (val == DTM_IR_IDCODE), "directed: sel_idcode after scan");
      check(sel_dtmcs  == (val == DTM_IR_DTMCS),  "directed: sel_dtmcs after scan");
      check(sel_dmi    == (val == DTM_IR_DMI),    "directed: sel_dmi after scan");
      check(sel_bypass == !(val == DTM_IR_IDCODE || val == DTM_IR_DTMCS || val == DTM_IR_DMI),
            "directed: every other opcode selects BYPASS");
      // A DR scan must not disturb the instruction.
      dr_path(1 + $urandom_range(0, 40));
      check(sel_idcode == (val == DTM_IR_IDCODE) && sel_dtmcs == (val == DTM_IR_DTMCS) &&
            sel_dmi == (val == DTM_IR_DMI), "DR scan leaves the IR unchanged");
    end
  endtask

  task automatic test_tlr_from_anywhere();
    for (int unsigned t = 0; t < N_TLR_TRIES; t++) begin
      // Wander to an arbitrary state first.
      repeat ($urandom_range(0, 30)) tck_cycle(1'($urandom_range(0, 1)), 1'($urandom_range(0, 1)));
      repeat (5) tck_cycle(1'b1, 1'b0);
      // Five TMS=1 clocks must have put the TAP in Test-Logic-Reset, so
      // 0,1,0 must walk RTI -> SelectDR -> CaptureDR from there.
      tck_cycle(1'b0, 1'b0);
      tck_cycle(1'b1, 1'b0);
      tck_cycle(1'b0, 1'b0);
      check(capture_dr, "five TMS=1 clocks reach Test-Logic-Reset from any state");
      tck_cycle(1'b0, 1'b0);
      check(shift_dr, "Capture-DR advances to Shift-DR");
      // Return to Run-Test/Idle for the next try.
      tck_cycle(1'b1, 1'b0);
      tck_cycle(1'b1, 1'b0);
      tck_cycle(1'b0, 1'b0);
    end
  endtask

  task automatic test_tlr_resets_ir();
    logic [DTM_IR_W-1:0] scanned;
    scan_ir(DTM_IR_DMI, scanned);
    check(scanned == DTM_IR_CAPTURE_VAL, "Capture-IR pattern seen on the way to DMI");
    check(sel_dmi, "precondition: DMI selected before entering Test-Logic-Reset");
    repeat (5) tck_cycle(1'b1, 1'b0);
    tck_cycle(1'b1, 1'b0);     // dwell one extra cycle in TLR
    tck_cycle(1'b0, 1'b0);     // -> Run-Test/Idle
    check(sel_idcode && !sel_dmi,
          "IR returns to IDCODE when the TAP enters Test-Logic-Reset");
  endtask

  task automatic test_async_trst();
    logic [DTM_IR_W-1:0] scanned;
    scan_ir(DTM_IR_DTMCS, scanned);
    check(scanned == DTM_IR_CAPTURE_VAL, "Capture-IR pattern seen on the way to DTMCS");
    check(sel_dtmcs, "precondition: DTMCS selected");
    // Reset in the middle of an IR shift.
    tck_cycle(1'b1, 1'b0);
    tck_cycle(1'b1, 1'b0);
    tck_cycle(1'b0, 1'b0);
    tck_cycle(1'b0, 1'b0);
    tck_cycle(1'b0, 1'b1);
    apply_trst();
    check(sel_idcode && !sel_dtmcs, "trst_n_i mid-scan restores IDCODE");
    check(!shift_ir && !capture_dr && !shift_dr && !update_dr,
          "trst_n_i mid-scan clears all strobes");
    tck_cycle(1'b0, 1'b0);     // leave Test-Logic-Reset
  endtask

  // ---------------------------------------------------------------------
  // Random walk against the reference model
  // ---------------------------------------------------------------------
  task automatic test_random_walk();
    for (int unsigned i = 0; i < N_RANDOM; i++) begin
      if ($urandom_range(0, 499) == 0)
        apply_trst();
      tck_cycle(1'($urandom_range(0, 1)), 1'($urandom_range(0, 1)));
    end
    for (int unsigned s = 0; s < N_STATES; s++)
      check(visits[s] > 0, "random walk visited every TAP state");
  endtask

  // ---------------------------------------------------------------------
  // Main
  // ---------------------------------------------------------------------
  initial begin
    for (int unsigned s = 0; s < N_STATES; s++) visits[s] = 0;
    rst_n = 1'b0;
    tms   = 1'b1;
    tdi   = 1'b0;
    model_reset();
    @(negedge clk); #1;
    apply_trst();
    test_reset_state();

    tck_cycle(1'b0, 1'b0);      // TLR -> Run-Test/Idle
    test_ir_scans();
    test_tlr_from_anywhere();
    test_tlr_resets_ir();
    test_async_trst();
    test_random_walk();

    finish_tb();
  end

endmodule : tb_meds_s1_dtm_tap
