// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// s1_trap_unit : trap entry / mret exit, M-mode only (v1.0 scope) [COMPLETE]
//
// Two-state FSM for M-mode trap handling (SPEC §10.1). S/U-mode transitions
// are stubbed and not yet reachable.
//
// On trap entry (SPEC §10.3, retire rule 6):
//   * mepc         <- faulting/next PC
//   * mcause       <- cause code
//   * mtval        <- faulting address or instruction bits
//   * mstatus.MPIE <- mstatus.MIE   (save)
//   * mstatus.MIE  <- 0             (disable traps inside handler)
//   * mstatus.MPP  <- 2'b11 (M)     (only mode that exists)
//   * PC redirect  -> mtvec
//
// On mret:
//   * mstatus.MIE  <- mstatus.MPIE  (restore)
//   * mstatus.MPP  <- 2'b11 (M)     (no lower mode to fall back to yet)
//   * PC redirect  -> mepc
//
// Reference: SPEC §9.2, §10.1, §10.3. Testbench: verif/unit/tb_s1_trap_unit.sv.
// =============================================================================

module s1_trap_unit
  import s1_pkg::*;
#(
  // Use WIDTH to avoid shadowing s1_pkg::XLEN
  parameter int unsigned WIDTH = s1_pkg::XLEN
) (
  input  logic             clk_i,
  input  logic             rst_ni,

  // Trap entry request, asserted for one cycle at retire (SPEC §9.2)
  input  logic             trap_valid_i,
  input  logic [5:0]       trap_cause_i,
  input  logic [WIDTH-1:0] trap_tval_i,
  input  logic [WIDTH-1:0] trap_pc_i,

  // mret request, asserted for one cycle at retire
  input  logic             mret_valid_i,

  // Current mstatus/mepc, read from the CSR file's software port
  input  logic [WIDTH-1:0] mstatus_rdata_i,
  input  logic [WIDTH-1:0] mepc_rdata_i,
  input  logic [WIDTH-1:0] mtvec_rdata_i,

  // Hardware CSR write port (drives s1_csr_file's hw_* port, index 0..3:
  // 0=mepc, 1=mcause, 2=mtval, 3=mstatus)
  output logic             hw_we_o    [4],
  output logic [11:0]      hw_addr_o  [4],
  output logic [WIDTH-1:0] hw_wdata_o [4],

  // PC redirect to fetch
  output logic             redirect_valid_o,
  output logic [WIDTH-1:0] redirect_pc_o
);

  typedef enum logic { S_NORMAL, S_TRAP } state_e;
  state_e state_q, state_d;

  localparam logic [1:0] MPP_M = 2'b11;

  // ---------------------------------------------------------------------------
  // State register.
  // Default assignment prevents inferred latches (CODING_STANDARD.md R-C3).
  // ---------------------------------------------------------------------------
  always_comb begin
    state_d = state_q;
    unique case (state_q)
      S_NORMAL: if (trap_valid_i) state_d = S_TRAP;
      S_TRAP:   if (mret_valid_i) state_d = S_NORMAL;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) state_q <= S_NORMAL;
    else         state_q <= state_d;
  end

  // ---------------------------------------------------------------------------
  // mstatus field access.
  // Uses s1_pkg::mstatus_t packed structs to prevent bit-slice arithmetic 
  // errors and enforce named-field access over magic offsets.
  // ---------------------------------------------------------------------------
  /* verilator lint_off UNUSEDSIGNAL */
  mstatus_t mstatus_cur, mstatus_on_trap, mstatus_on_mret;
  /* verilator lint_on UNUSEDSIGNAL */

  assign mstatus_cur = mstatus_t'(mstatus_rdata_i);

  assign mstatus_on_trap = '{
    reserved_hi:  mstatus_cur.reserved_hi,
    mpp:          MPP_M,
    reserved_mid: mstatus_cur.reserved_mid,
    mpie:         mstatus_cur.mie,   // Save current MIE to MPIE
    reserved_lo:  mstatus_cur.reserved_lo,
    mie:          1'b0,              // Disable further traps in handler
    reserved_bot: mstatus_cur.reserved_bot
  };

  assign mstatus_on_mret = '{
    reserved_hi:  mstatus_cur.reserved_hi,
    mpp:          MPP_M,
    reserved_mid: mstatus_cur.reserved_mid,
    mpie:         1'b1,              // Set MPIE=1 per spec
    reserved_lo:  mstatus_cur.reserved_lo,
    mie:          mstatus_cur.mpie,  // Restore MIE from saved MPIE
    reserved_bot: mstatus_cur.reserved_bot
  };

  // ---------------------------------------------------------------------------
  // Hardware CSR write port.
  // Defaults to zero to prevent inferred latches (CODING_STANDARD.md R-C3).
  // Addresses are ratified RISC-V CSR addresses, not arbitrary magic numbers.
  // ---------------------------------------------------------------------------
  always_comb begin
    for (int unsigned p = 0; p < 4; p++) begin
      hw_we_o[p]    = 1'b0;   // default first: no inferred latch
      hw_addr_o[p]  = 12'h000;
      hw_wdata_o[p] = '0;
    end

    if (trap_valid_i && state_q == S_NORMAL) begin
      hw_we_o[0] = 1'b1; hw_addr_o[0] = 12'h341; hw_wdata_o[0] = trap_pc_i;
      hw_we_o[1] = 1'b1; hw_addr_o[1] = 12'h342; hw_wdata_o[1] = { {WIDTH-6{1'b0}}, trap_cause_i };
      hw_we_o[2] = 1'b1; hw_addr_o[2] = 12'h343; hw_wdata_o[2] = trap_tval_i;
      hw_we_o[3] = 1'b1; hw_addr_o[3] = 12'h300; hw_wdata_o[3] = WIDTH'(mstatus_on_trap);
    end else if (mret_valid_i && state_q == S_TRAP) begin
      hw_we_o[3] = 1'b1; hw_addr_o[3] = 12'h300; hw_wdata_o[3] = WIDTH'(mstatus_on_mret);
    end
  end

  // ---------------------------------------------------------------------------
  // PC redirect.
  // Defaults to zero to prevent inferred latches (CODING_STANDARD.md R-C3).
  // Redirects to mtvec on trap entry, mepc on mret.
  // ---------------------------------------------------------------------------
  always_comb begin
    redirect_valid_o = 1'b0;   // default first: no inferred latch
    redirect_pc_o    = '0;
    
    if (trap_valid_i && state_q == S_NORMAL) begin
      redirect_valid_o = 1'b1;
      redirect_pc_o    = mtvec_rdata_i;
    end else if (mret_valid_i && state_q == S_TRAP) begin
      redirect_valid_o = 1'b1;
      redirect_pc_o    = mepc_rdata_i;
    end
  end

endmodule : s1_trap_unit
