// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// tb_s1_csr_file : unit testbench for s1_csr_file                       [WIP]
//
// Directed checks: reset values, read/write round trips, the medeleg, mideleg
// and mstatus.MPP masks, mtvec/stvec MODE legalisation, back-to-back address
// changes, unmapped addresses, and a four-slot hardware trap write.  The
// expectations follow U_MODE/S_MODE (csr_access_matrix.md); addresses and
// values are still literal constants, not the generated CSR_* names.  Reports
// a check count and exits non-zero on failure.
//
// Run: make test-unit TB=s1_csr_file
// =============================================================================

module tb_s1_csr_file;
  import s1_pkg::*;

  // R-V2: Derive width from parameter so this TB runs unmodified at every XLEN config.
  localparam int unsigned W = s1_pkg::XLEN;

  // Config under test; the expectations below follow it (csr_access_matrix.md).
  localparam bit U_MODE = 1'b1;
  localparam bit S_MODE = 1'b0;

  // mstatus read-only constants: UXL = 2 with U-mode, SXL = 2 with S-mode.
  localparam logic [W-1:0] MSTATUS_RO = (U_MODE ? W'(64'h2_0000_0000) : '0)
                                      | (S_MODE ? W'(64'h8_0000_0000) : '0);

  // R-V2: Construct test vectors dynamically based on W. 
  // MUST be at module level, not inside the initial block.
  localparam logic [W-1:0] TEST_BASE = { {(W-2){1'b1}}, 2'b00 };

  // FIX: Remove inline initialization to prevent PROCASSINIT warning
  logic clk;
  logic rst_n;
  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  logic [11:0]     addr;
  logic [W-1:0]    wdata, rdata;
  logic            we, illegal;
  logic            hw_we [4];
  logic [11:0]     hw_addr [4];
  logic [W-1:0]    hw_wdata [4];
  logic [11:0]     ext_addr;
  logic [W-1:0]    ext_wdata, ext_rdata = '0;
  logic            ext_we;
  logic [W-1:0]    trap_mstatus, trap_medeleg, trap_mideleg, trap_mepc, trap_mtvec;
  logic [W-1:0]    trap_sepc, trap_stvec, trap_dcsr, trap_dpc;

  // R-V2: Explicitly pass parameter to DUT to ensure configuration consistency.
  s1_csr_file #(.U_MODE_PRESENT(U_MODE), .S_MODE_PRESENT(S_MODE)) dut (
    .clk_i           (clk),
    .rst_ni          (rst_n),
    .csr_addr_i      (addr),
    .csr_wdata_i     (wdata),
    .csr_we_i        (we),
    .priv_i          (PRIV_M),
    .hw_we_i         (hw_we),
    .hw_addr_i       (hw_addr),
    .hw_wdata_i      (hw_wdata),
    .csr_rdata_o     (rdata),
    .csr_illegal_o   (illegal),
    .trap_mstatus_o  (trap_mstatus),
    .trap_medeleg_o  (trap_medeleg),
    .trap_mideleg_o  (trap_mideleg),
    .trap_mepc_o     (trap_mepc),
    .trap_mtvec_o    (trap_mtvec),
    .trap_sepc_o     (trap_sepc),
    .trap_stvec_o    (trap_stvec),
    .trap_dcsr_o     (trap_dcsr),
    .trap_dpc_o      (trap_dpc),
    .ext_csr_addr_o  (ext_addr),
    .ext_csr_wdata_o (ext_wdata),
    .ext_csr_we_o    (ext_we),
    .ext_csr_rdata_i (ext_rdata)
  );

  // ---------------------------------------------------------------------------
  // Check helpers (R-V3)
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

  task automatic write_csr(input logic [11:0] a, input logic [W-1:0] d);
    addr = a; wdata = d; we = 1;
    @(posedge clk);
    we = 0;
    @(posedge clk);
  endtask

  // ---------------------------------------------------------------------------
  // Stimulus
  // ---------------------------------------------------------------------------
  initial begin
    // FIX: Initialize variables here instead of at declaration
    rst_n = 0;
    we = 0; addr = '0; wdata = '0;
    for (int unsigned p = 0; p < 4; p++) begin
      hw_we[p] = 0; hw_addr[p] = '0; hw_wdata[p] = '0;
    end
    
    #12 rst_n = 1;
    @(posedge clk);

    // --- Reset values --------------------------------------------------------
    // Every core CSR reads its reset value; mstatus also shows UXL/SXL.
    addr = 12'h300; @(posedge clk); check(rdata == MSTATUS_RO, "mstatus reset reads only UXL/SXL");
    addr = 12'h304; @(posedge clk); check(rdata == '0, "mie reset == 0");
    addr = 12'h305; @(posedge clk); check(rdata == '0, "mtvec reset == 0");
    addr = 12'h341; @(posedge clk); check(rdata == '0, "mepc reset == 0");
    addr = 12'h342; @(posedge clk); check(rdata == '0, "mcause reset == 0");
    addr = 12'h343; @(posedge clk); check(rdata == '0, "mtval reset == 0");
    addr = 12'h344; @(posedge clk); check(rdata == '0, "mip reset == 0");

    // --- Plain RW round-trip -------------------------------------------------
    // Use parameterized casts (W'(...)) so values truncate correctly if W=32.
    write_csr(12'h341, W'(64'hDEAD_BEEF_0000_0004));
    check(rdata == W'(64'hDEAD_BEEF_0000_0004), "mepc stores written value");

    write_csr(12'h342, W'(64'h0000_0000_0000_000B)); // exception code 11
    check(rdata == W'(64'h0000_0000_0000_000B), "mcause stores written value");

    write_csr(12'h343, W'(64'h1234_5678_9ABC_DEF0));
    check(rdata == W'(64'h1234_5678_9ABC_DEF0), "mtval stores written value");

    write_csr(12'h300, W'(64'h0000_0000_0000_1888));
    check(rdata == (W'(64'h0000_0000_0000_1888) | MSTATUS_RO), "mstatus stores written value");

    // --- Delegation and privilege WARL masks --------------------------------
    write_csr(12'h302, '1);
    check(rdata == (S_MODE ? W'(64'h0000_0000_0000_B3FF) : '0), "medeleg: delegable causes with S, absent without");

    write_csr(12'h303, '1);
    check(rdata == (S_MODE ? W'(64'h0000_0000_0000_0222) : '0), "mideleg: S interrupts with S, absent without");

    write_csr(12'h300, W'(64'h0000_0000_0000_0800));
    check(rdata[12:11] == 2'b00, "mstatus reserved MPP encoding legalizes to U");

    // --- mtvec WARL legalization ---------------------------------------------
    // Exercise all four MODE encodings. BASE field must remain untouched.
    write_csr(12'h305, TEST_BASE | 2'b00);
    check(rdata[1:0] == 2'b00, "mtvec MODE=00 (Direct) passes through");

    write_csr(12'h305, TEST_BASE | 2'b01);
    check(rdata[1:0] == 2'b01, "mtvec MODE=01 (Vectored) passes through");

    write_csr(12'h305, TEST_BASE | 2'b10);
    check(rdata[1:0] == 2'b00, "mtvec MODE=10 (illegal) legalizes to Direct");

    write_csr(12'h305, TEST_BASE | 2'b11);
    check(rdata[1:0] == 2'b00, "mtvec MODE=11 (illegal) legalizes to Direct");

    check(rdata[W-1:2] == TEST_BASE[W-1:2], "mtvec BASE field unaffected by MODE legalization");

    write_csr(12'h105, TEST_BASE | 2'b10);
    check(rdata[1:0] == 2'b00, "stvec MODE=10 legalizes to Direct");

    // --- Back-to-back address switching (R-V5) -------------------------------
    // Targets stale-index bugs in the comparator array. A hang or silent 
    // aliasing bug here is far worse than a simple wrong answer.
    write_csr(12'h341, W'(64'hAAAA_AAAA_AAAA_AAAA)); // mepc
    
    addr = 12'h342; @(posedge clk);                  // switch to mcause, no write
    check(rdata == W'(64'h0000_0000_0000_000B), "mcause unaffected by mepc write (index switch correct)");

    addr = 12'h341; @(posedge clk);
    check(rdata == W'(64'hAAAA_AAAA_AAAA_AAAA), "mepc still readable after switching away and back");

    // --- Illegal address detection (R-V5) ------------------------------------
    // Ensures unmapped writes do not corrupt state or hang the FSM.
    addr = 12'hFFF; @(posedge clk);
    check(illegal == 1'b1, "unmapped 0xFFF asserts csr_illegal_o");
    check(rdata == '0,       "unmapped address reads 0, not stale data");

    addr = 12'h001; @(posedge clk);
    check(illegal == 1'b1, "unmapped 0x001 asserts csr_illegal_o");

    // Write to unmapped address, then verify unrelated CSR is untouched.
    addr = 12'hFFF; wdata = '1; we = 1;
    @(posedge clk);
    we = 0;
    @(posedge clk);
    
    addr = 12'h341; @(posedge clk);
    check(rdata == W'(64'hAAAA_AAAA_AAAA_AAAA), "unmapped write must not corrupt unrelated CSR");

    // --- Atomic hardware trap writes -----------------------------------------
    hw_we[0] = 1; hw_addr[0] = 12'h341; hw_wdata[0] = W'(64'h8000_0100);
    hw_we[1] = 1; hw_addr[1] = 12'h342; hw_wdata[1] = W'(64'h8000_0000_0000_0007);
    hw_we[2] = 1; hw_addr[2] = 12'h343; hw_wdata[2] = W'(64'hDEAD_BEEF);
    hw_we[3] = 1; hw_addr[3] = 12'h300; hw_wdata[3] = W'(64'h1880);
    @(posedge clk);
    for (int unsigned p = 0; p < 4; p++) hw_we[p] = 0;
    addr = 12'h341; @(posedge clk); check(rdata == W'(64'h8000_0100), "hardware writes mepc");
    addr = 12'h342; @(posedge clk); check(rdata == W'(64'h8000_0000_0000_0007), "hardware writes mcause");
    addr = 12'h343; @(posedge clk); check(rdata == W'(64'hDEAD_BEEF), "hardware writes mtval");
    addr = 12'h300; @(posedge clk); check(rdata == (W'(64'h1880) | MSTATUS_RO), "hardware writes mstatus");

    // ---------------------------------------------------------------------------
    // Summary (R-V3: CI requires exact format and non-zero exit on failure)
    // ---------------------------------------------------------------------------
    if (errors == 0) begin
      $display("=== PASS : %0d checks ===", checks);
      $finish;
    end else begin
      $display("=== FAIL : %0d errors of %0d checks ===", errors, checks);
      $fatal(1, "tb_s1_csr_file failed");
    end
  end

endmodule : tb_s1_csr_file
