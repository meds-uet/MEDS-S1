// =============================================================================
// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// tb_csr_model : minimal CSR stand-in for tb_s1_core            [TESTBENCH ONLY]
// Description  :
// The CSR file is not part of this core -- another project builds it and
// attaches it to s1_core's csr_*/trap ports.  This model is NOT that file.  It
// implements exactly what rv64i_full.s needs so that ECALL, EBREAK and MRET can
// be run and checked against spike:
//
//   mstatus  MIE, MPIE, MPP only        mtvec    direct mode only
//   mepc, mcause, mtval, mscratch       minstret counts instret_i
//   pmpaddr0, pmpcfg0  stored, not used (spike needs them to run U-mode)
//
// Every other address is illegal.  Privilege M and U; no interrupts, no MPRV,
// no vectored mode, no counters other than minstret.
//
// Same contract as the real port: the query is side-effect free and
// combinational, writes come only from csr_commit_i, trap entry beats a write.
// =============================================================================

module tb_csr_model
  import s1_pkg::*;
(
  input  logic            clk_i,
  input  logic            rst_ni,

  input  logic [11:0]     csr_addr_i,
  input  logic            csr_re_i,
  input  logic            csr_we_i,
  output logic [XLEN-1:0] csr_rdata_o,
  output logic            csr_illegal_o,

  input  csr_upd_t        csr_commit_i,
  input  trap_req_t       trap_req_i,
  input  logic            mret_i,
  output logic [XLEN-1:0] trap_vec_o,
  output logic [XLEN-1:0] mepc_o,

  output priv_lvl_e       priv_o,
  output priv_lvl_e       priv_data_o,
  output logic            irq_valid_o,
  output logic [5:0]      irq_code_o,

  input  logic            instret_i
);

  // The architectural addresses this model answers (privileged spec).
  localparam logic [11:0] A_MSTATUS  = 12'h300;
  localparam logic [11:0] A_MTVEC    = 12'h305;
  localparam logic [11:0] A_MSCRATCH = 12'h340;
  localparam logic [11:0] A_MEPC     = 12'h341;
  localparam logic [11:0] A_MCAUSE   = 12'h342;
  localparam logic [11:0] A_MTVAL    = 12'h343;
  localparam logic [11:0] A_PMPCFG0  = 12'h3A0;
  localparam logic [11:0] A_PMPADDR0 = 12'h3B0;
  localparam logic [11:0] A_MINSTRET = 12'hB02;

  priv_lvl_e       priv_q;
  logic            mie_q, mpie_q;
  logic [1:0]      mpp_q;
  logic [XLEN-1:0] mtvec_q, mscratch_q, mepc_q, mcause_q, mtval_q, minstret_q;
  logic [XLEN-1:0] pmpcfg0_q, pmpaddr0_q;

  // ---- query ----------------------------------------------------------------
  logic hit;
  always_comb begin
    hit         = 1'b1;
    csr_rdata_o = '0;
    unique case (csr_addr_i)
      A_MSTATUS:  begin
        csr_rdata_o[3]     = mie_q;
        csr_rdata_o[7]     = mpie_q;
        csr_rdata_o[12:11] = mpp_q;
      end
      A_MTVEC:    csr_rdata_o = mtvec_q;
      A_MSCRATCH: csr_rdata_o = mscratch_q;
      A_MEPC:     csr_rdata_o = mepc_q;
      A_MCAUSE:   csr_rdata_o = mcause_q;
      A_MTVAL:    csr_rdata_o = mtval_q;
      A_PMPCFG0:  csr_rdata_o = pmpcfg0_q;
      A_PMPADDR0: csr_rdata_o = pmpaddr0_q;
      A_MINSTRET: csr_rdata_o = minstret_q;
      default:    hit = 1'b0;
    endcase
    // addr[9:8] is the lowest privilege allowed; addr[11:10] == 11 is read-only.
    csr_illegal_o = (csr_re_i || csr_we_i)
                 && (!hit || (priv_q < priv_lvl_e'(csr_addr_i[9:8]))
                     || (csr_we_i && csr_addr_i[11:10] == 2'b11));
  end

  assign trap_vec_o  = {mtvec_q[XLEN-1:2], 2'b00};
  assign mepc_o      = mepc_q;
  assign priv_o      = priv_q;
  assign priv_data_o = priv_q;
  assign irq_valid_o = 1'b0;
  assign irq_code_o  = '0;

  // ---- state ----------------------------------------------------------------
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      priv_q     <= PRIV_M;
      mie_q      <= 1'b0;
      mpie_q     <= 1'b0;
      mpp_q      <= PRIV_M;
      mtvec_q    <= '0;
      mscratch_q <= '0;
      mepc_q     <= '0;
      mcause_q   <= '0;
      mtval_q    <= '0;
      minstret_q <= '0;
      pmpcfg0_q  <= '0;
      pmpaddr0_q <= '0;
    end else begin
      if (instret_i) minstret_q <= minstret_q + XLEN'(1);

      if (csr_commit_i.we) begin
        unique case (csr_commit_i.addr)
          A_MSTATUS: begin
            mie_q  <= csr_commit_i.wdata[3];
            mpie_q <= csr_commit_i.wdata[7];
            // WARL: only M and U exist here.
            mpp_q  <= (csr_commit_i.wdata[12:11] == PRIV_U) ? PRIV_U : PRIV_M;
          end
          A_MTVEC:    mtvec_q    <= {csr_commit_i.wdata[XLEN-1:2], 2'b00};
          A_MSCRATCH: mscratch_q <= csr_commit_i.wdata;
          A_MEPC:     mepc_q     <= {csr_commit_i.wdata[XLEN-1:1], 1'b0};
          A_MCAUSE:   mcause_q   <= csr_commit_i.wdata;
          A_MTVAL:    mtval_q    <= csr_commit_i.wdata;
          A_PMPCFG0:  pmpcfg0_q  <= csr_commit_i.wdata;
          A_PMPADDR0: pmpaddr0_q <= csr_commit_i.wdata;
          A_MINSTRET: minstret_q <= csr_commit_i.wdata;   // beats the increment
          default: ;
        endcase
      end

      if (trap_req_i.valid) begin
        mepc_q   <= trap_req_i.epc;
        mcause_q <= {trap_req_i.is_irq, {(XLEN-7){1'b0}}, trap_req_i.exccode};
        mtval_q  <= trap_req_i.tval;
        mpie_q   <= mie_q;
        mie_q    <= 1'b0;
        mpp_q    <= priv_q;
        priv_q   <= PRIV_M;
      end else if (mret_i) begin
        mie_q    <= mpie_q;
        mpie_q   <= 1'b1;
        priv_q   <= priv_lvl_e'(mpp_q);
        mpp_q    <= PRIV_U;
      end
    end
  end

endmodule
