// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// s1_trap_unit : trap entry, xRET and privilege mode                    [WIP]
//
// Every retiring trap writes xepc, xcause, xtval and mstatus, including a trap
// taken inside a handler; there is no in-trap state.  mret is honoured in
// M-mode and sret in S-mode; elsewhere the request changes no state (the
// illegal-instruction trap belongs to the core, see the module doc).
//
// Reference: SPEC section 10.1, 10.3.  Testbench: verif/unit/tb_s1_trap_unit.sv.
// =============================================================================

module s1_trap_unit
  import s1_pkg::*;
  import s1_csr_pkg::*;
#(
  parameter bit U_MODE_PRESENT = 1'b1,
  parameter bit S_MODE_PRESENT = 1'b0
) (
  input  logic            clk_i,
  input  logic            rst_ni,

  // Retiring trap and xRET requests, one cycle each.
  input  logic            trap_valid_i,
  input  logic            trap_is_interrupt_i,
  input  logic [5:0]      trap_cause_i,
  input  logic [XLEN-1:0] trap_tval_i,
  input  logic [XLEN-1:0] trap_pc_i,
  input  logic            mret_valid_i,
  input  logic            sret_valid_i,

  // Current values from s1_csr_file's trap_*_o taps.
  input  logic [XLEN-1:0] mstatus_rdata_i,
  input  logic [XLEN-1:0] medeleg_rdata_i,
  input  logic [XLEN-1:0] mideleg_rdata_i,
  input  logic [XLEN-1:0] mepc_rdata_i,
  input  logic [XLEN-1:0] mtvec_rdata_i,
  input  logic [XLEN-1:0] sepc_rdata_i,
  input  logic [XLEN-1:0] stvec_rdata_i,

  // To s1_csr_file's hw_* port.
  output logic            hw_we_o    [4],
  output logic [11:0]     hw_addr_o  [4],
  output logic [XLEN-1:0] hw_wdata_o [4],

  output logic            redirect_valid_o,
  output logic [XLEN-1:0] redirect_pc_o,
  output priv_lvl_e       priv_mode_o
);

  // mstatus field positions (privileged spec, mstatus layout).
  localparam int unsigned MSTATUS_SIE  = 1;
  localparam int unsigned MSTATUS_MIE  = 3;
  localparam int unsigned MSTATUS_SPIE = 5;
  localparam int unsigned MSTATUS_MPIE = 7;
  localparam int unsigned MSTATUS_SPP  = 8;
  localparam int unsigned MSTATUS_MPP  = 11;   // [12:11]
  localparam int unsigned MSTATUS_MPRV = 17;

  localparam logic [1:0]  TVEC_VECTORED = 2'b01;

  // hw_* slot per CSR.
  localparam int unsigned SLOT_EPC    = 0;
  localparam int unsigned SLOT_CAUSE  = 1;
  localparam int unsigned SLOT_TVAL   = 2;
  localparam int unsigned SLOT_STATUS = 3;

  // ---------------------------------------------------------------------------
  // Trap target.
  // A trap goes to S only from below M and only when its delegation bit is set.
  // Vectored mode offsets interrupts only; mode bits never reach the PC.
  // ---------------------------------------------------------------------------
  priv_lvl_e        priv_q, priv_d;
  priv_lvl_e        mret_priv;
  logic             trap_to_s;
  logic [XLEN-1:0]  cause_val;
  logic [XLEN-1:0]  tvec;
  logic [XLEN-1:0]  vector_offset;
  logic [XLEN-1:0]  trap_target;

  // MPP is legalised when it is written, so it always names a present mode.
  assign mret_priv = priv_lvl_e'(mstatus_rdata_i[MSTATUS_MPP +: 2]);

  assign trap_to_s = S_MODE_PRESENT && (priv_q != PRIV_M)
                  && (trap_is_interrupt_i ? mideleg_rdata_i[trap_cause_i]
                                          : medeleg_rdata_i[trap_cause_i]);

  assign cause_val     = {trap_is_interrupt_i, {(XLEN-7){1'b0}}, trap_cause_i};
  assign tvec          = trap_to_s ? stvec_rdata_i : mtvec_rdata_i;
  assign vector_offset = {{(XLEN-8){1'b0}}, trap_cause_i, 2'b00};
  assign trap_target   = {tvec[XLEN-1:2], 2'b00}
                       + ((trap_is_interrupt_i && tvec[1:0] == TVEC_VECTORED) ? vector_offset
                                                                              : '0);

  // ---------------------------------------------------------------------------
  // Privilege mode.
  // ---------------------------------------------------------------------------
  always_comb begin
    priv_d = priv_q;
    if (trap_valid_i) begin
      priv_d = trap_to_s ? PRIV_S : PRIV_M;
    end else if (mret_valid_i && priv_q == PRIV_M) begin
      priv_d = mret_priv;
    end else if (S_MODE_PRESENT && sret_valid_i && priv_q == PRIV_S) begin
      priv_d = mstatus_rdata_i[MSTATUS_SPP] ? PRIV_S : PRIV_U;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      priv_q <= PRIV_M;
    end else begin
      priv_q <= priv_d;
    end
  end

  assign priv_mode_o = priv_q;

  // ---------------------------------------------------------------------------
  // mstatus after each action.
  // An xRET to a mode below M clears MPRV; after mret, MPP is the lowest
  // present mode.
  // ---------------------------------------------------------------------------
  logic [XLEN-1:0] mstatus_on_mtrap, mstatus_on_strap, mstatus_on_mret, mstatus_on_sret;

  always_comb begin
    mstatus_on_mtrap                   = mstatus_rdata_i;
    mstatus_on_mtrap[MSTATUS_MPP +: 2] = priv_q;
    mstatus_on_mtrap[MSTATUS_MPIE]     = mstatus_rdata_i[MSTATUS_MIE];
    mstatus_on_mtrap[MSTATUS_MIE]      = 1'b0;

    mstatus_on_strap                   = mstatus_rdata_i;
    mstatus_on_strap[MSTATUS_SPP]      = (priv_q == PRIV_S);
    mstatus_on_strap[MSTATUS_SPIE]     = mstatus_rdata_i[MSTATUS_SIE];
    mstatus_on_strap[MSTATUS_SIE]      = 1'b0;

    mstatus_on_mret                    = mstatus_rdata_i;
    mstatus_on_mret[MSTATUS_MIE]       = mstatus_rdata_i[MSTATUS_MPIE];
    mstatus_on_mret[MSTATUS_MPIE]      = 1'b1;
    mstatus_on_mret[MSTATUS_MPP +: 2]  = U_MODE_PRESENT ? PRIV_U : PRIV_M;
    if (mret_priv != PRIV_M) begin
      mstatus_on_mret[MSTATUS_MPRV]    = 1'b0;
    end

    mstatus_on_sret                    = mstatus_rdata_i;
    mstatus_on_sret[MSTATUS_SIE]       = mstatus_rdata_i[MSTATUS_SPIE];
    mstatus_on_sret[MSTATUS_SPIE]      = 1'b1;
    mstatus_on_sret[MSTATUS_SPP]       = 1'b0;
    mstatus_on_sret[MSTATUS_MPRV]      = 1'b0;
  end

  // ---------------------------------------------------------------------------
  // CSR writes and redirect.
  // ---------------------------------------------------------------------------
  always_comb begin
    for (int unsigned p = 0; p < 4; p++) begin
      hw_we_o[p]    = 1'b0;
      hw_addr_o[p]  = '0;
      hw_wdata_o[p] = '0;
    end
    redirect_valid_o = 1'b0;
    redirect_pc_o    = '0;

    if (trap_valid_i) begin
      hw_we_o[SLOT_EPC]       = 1'b1;
      hw_we_o[SLOT_CAUSE]     = 1'b1;
      hw_we_o[SLOT_TVAL]      = 1'b1;
      hw_we_o[SLOT_STATUS]    = 1'b1;
      hw_addr_o[SLOT_EPC]     = trap_to_s ? CSR_SEPC   : CSR_MEPC;
      hw_addr_o[SLOT_CAUSE]   = trap_to_s ? CSR_SCAUSE : CSR_MCAUSE;
      hw_addr_o[SLOT_TVAL]    = trap_to_s ? CSR_STVAL  : CSR_MTVAL;
      hw_addr_o[SLOT_STATUS]  = CSR_MSTATUS;
      hw_wdata_o[SLOT_EPC]    = trap_pc_i;
      hw_wdata_o[SLOT_CAUSE]  = cause_val;
      hw_wdata_o[SLOT_TVAL]   = trap_tval_i;
      hw_wdata_o[SLOT_STATUS] = trap_to_s ? mstatus_on_strap : mstatus_on_mtrap;
      redirect_valid_o        = 1'b1;
      redirect_pc_o           = trap_target;
    end else if (mret_valid_i && priv_q == PRIV_M) begin
      hw_we_o[SLOT_STATUS]    = 1'b1;
      hw_addr_o[SLOT_STATUS]  = CSR_MSTATUS;
      hw_wdata_o[SLOT_STATUS] = mstatus_on_mret;
      redirect_valid_o        = 1'b1;
      redirect_pc_o           = mepc_rdata_i;
    end else if (S_MODE_PRESENT && sret_valid_i && priv_q == PRIV_S) begin
      hw_we_o[SLOT_STATUS]    = 1'b1;
      hw_addr_o[SLOT_STATUS]  = CSR_MSTATUS;
      hw_wdata_o[SLOT_STATUS] = mstatus_on_sret;
      redirect_valid_o        = 1'b1;
      redirect_pc_o           = sepc_rdata_i;
    end
  end

endmodule : s1_trap_unit
