// =============================================================================
// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// Author(s)    : Eman Nasar <fatehulnasareman@gmail.com>, GitHub EmanNasar001 (Oct,2026)
// Modified By  :
//
// s1_wb        : WB stage -- the architectural commit point   [WIP -- T-02]
// Description  :
// Combinational.  The MEM/WB register lives inside s1_mem, so by the time an
// instruction reaches here it is finished; this stage decides what its arrival
// does to architectural state.
//
// Exactly one instruction commits per cycle, in program order, and everything
// that outlives it happens here:
//
//   1. the register file write, unless it trapped or writes x0
//   2. the CSR write EX computed
//   3. the store buffer entry is marked committed, so it may drain to memory
//   4. RVFI
//   5. minstret
//   6. on a trap: none of 1-3, and the pipeline is flushed to the trap vector
//
// Why commit here rather than in MEM.  A store that has passed MEM has already
// been checked against PMA and PMP, but it is still younger than nothing --
// it is the oldest instruction in the machine only once it reaches WB.  Buffer
// the store in MEM, release it here, and a trap taken by *this* instruction
// cannot have already written memory.
//
// Interrupts are taken here too, in place of a commit, so mepc names an
// instruction that has not executed.  xRET legality is checked here as well:
// this is the last point before privilege changes.
//
// Reference: SPEC 7.5, 10.3, 28.2.  Testbench: verif/unit/tb_s1_wb.sv.
// =============================================================================

module s1_wb
  import s1_pkg::*;
(
  // ---- From MEM ------------------------------------------------------------
  input  logic                  wb_valid_i,
  input  mem_wb_t               wb_i,

  // ---- Interrupts, already masked and prioritised by the CSR file ----------
  input  logic                  irq_valid_i,
  input  logic [5:0]            irq_code_i,

  // ---- Architectural state -------------------------------------------------
  output rf_wr_t                rf_wr_o,
  output csr_upd_t              csr_commit_o,
  output logic                  instret_o,      // minstret: retired, not trapped

  output logic                  sb_commit_o,    // commits MEM's oldest uncommitted store

  // ---- Flush and redirect --------------------------------------------------
  output logic                  flush_o,
  output flush_cause_e          flush_cause_o,
  output logic                  redirect_valid_o,
  output logic [XLEN-1:0]       redirect_pc_o,

  // ---- Trap request to the CSR file, and what it answers with -------------
  output trap_req_t             trap_req_o,
  output logic                  mret_o,
  input  logic [XLEN-1:0]       trap_vec_i,
  input  logic [XLEN-1:0]       mepc_i,

  // ---- Is this stage holding anything?  ID's serialisation asks -----------
  output logic                  busy_o,

  // ---- Trace ---------------------------------------------------------------
  input  priv_lvl_e             priv_i,         // the mode the committing instruction ran in
  input  logic [63:0]           order_i,
  output rvfi_t                 rvfi_o,

  // ---- Performance events --------------------------------------------------
  output logic                  perf_load_retired_o,
  output logic                  perf_store_retired_o
);

  // A FENCE arrives only once the store buffer has drained: s1_mem holds it
  // in MEM/WB until then, so WB never has to wait for it.

  // xRET legality.  This core has M- and U-mode only (no S-mode in v1, no
  // debug mode), so SRET and DRET are always illegal, and MRET only from M.
  // Checked here because nothing earlier is trusted to have: an xRET that
  // got this far would otherwise raise privilege.
  logic ret_illegal, exc;
  logic [5:0]      exccode;
  logic [XLEN-1:0] exctval;
  assign ret_illegal = !wb_i.exc
                    && ((wb_i.sys_op == SYS_SRET) || (wb_i.sys_op == SYS_DRET)
                        || ((wb_i.sys_op == SYS_MRET) && (priv_i != PRIV_M)));
  assign exc         = wb_i.exc || ret_illegal;
  assign exccode     = wb_i.exc ? wb_i.exccode : EXC_ILLEGAL_INSTR;
  assign exctval     = wb_i.exc ? wb_i.exctval : XLEN'(wb_i.instr);

  logic take_irq, commit_ok, trap_now;

  // An interrupt replaces a commit rather than following one, so mepc names an
  // instruction that has not executed.
  assign take_irq  = wb_valid_i && irq_valid_i;
  assign commit_ok = wb_valid_i && !take_irq;
  assign trap_now  = take_irq || (commit_ok && exc);

  assign busy_o = wb_valid_i;

  // ---------------------------------------------------------------------------
  // Redirecting commits
  // ---------------------------------------------------------------------------
  logic is_mret, is_refetch;

  assign is_mret    = commit_ok && !exc && (wb_i.sys_op == SYS_MRET);   // M-mode, by `exc`
  assign is_refetch = commit_ok && !exc
                   && ((wb_i.sys_op == SYS_FENCE_I) || (wb_i.sys_op == SYS_SFENCE_VMA));

  always_comb begin
    flush_cause_o = FLUSH_NONE;
    if      (trap_now)   flush_cause_o = FLUSH_TRAP;
    else if (is_mret)    flush_cause_o = FLUSH_MRET;
    else if (is_refetch) flush_cause_o = (wb_i.sys_op == SYS_FENCE_I) ? FLUSH_FENCE_I
                                                                      : FLUSH_SFENCE;
  end

  assign flush_o          = (flush_cause_o != FLUSH_NONE);
  assign redirect_valid_o = flush_o;

  always_comb begin
    unique case (flush_cause_o)
      FLUSH_TRAP: redirect_pc_o = trap_vec_i;
      FLUSH_MRET: redirect_pc_o = mepc_i;
      default:    redirect_pc_o = wb_i.next_pc;      // refetch the successor
    endcase
  end

  always_comb begin
    trap_req_o = '0;
    if (take_irq) begin
      trap_req_o.valid   = 1'b1;
      trap_req_o.is_irq  = 1'b1;
      trap_req_o.exccode = irq_code_i;
      trap_req_o.epc     = wb_i.pc;
      trap_req_o.tval    = '0;
    end else if (commit_ok && exc) begin
      trap_req_o.valid   = 1'b1;
      trap_req_o.is_irq  = 1'b0;
      trap_req_o.exccode = exccode;
      trap_req_o.epc     = wb_i.pc;
      trap_req_o.tval    = exctval;
    end
  end

  assign mret_o = is_mret;

  // ---------------------------------------------------------------------------
  // Architectural writes -- all suppressed by a trap
  // ---------------------------------------------------------------------------
  logic commit;
  assign commit = commit_ok && !exc;

  assign rf_wr_o.we   = commit && wb_i.rd_we && (wb_i.rd != '0);
  assign rf_wr_o.addr = wb_i.rd;
  assign rf_wr_o.data = wb_i.result;

  assign csr_commit_o.we    = commit && wb_i.csr_we;
  assign csr_commit_o.addr  = wb_i.csr_addr;
  assign csr_commit_o.wdata = wb_i.csr_wdata;

  // Ungated on purpose beyond the trap: gating it further would strand the
  // slot for ever, and MEM never allocates one for an access that faulted.
  assign sb_commit_o = commit && wb_i.sb_alloc;

  // A trapping instruction does not retire, so it does not count (RISC-V
  // privileged spec, minstret; ECALL and EBREAK "are not considered to
  // retire").  RVFI still reports it, with rvfi_trap set, and its rvfi_order
  // still advances -- that counter is s1_core's, driven by rvfi_o.valid.
  assign instret_o = commit;

  assign perf_load_retired_o  = commit && (wb_i.mem_rmask != '0);
  assign perf_store_retired_o = commit && (wb_i.mem_wmask != '0);

  // ---------------------------------------------------------------------------
  // RVFI (SPEC 28.2).  One committed instruction per cycle, a trapping one
  // included -- `trap` marks it and pc_wdata names the vector it went to.
  // ---------------------------------------------------------------------------
  always_comb begin
    rvfi_o           = '0;
    rvfi_o.valid     = commit_ok;
    rvfi_o.order     = order_i;
    rvfi_o.insn      = wb_i.instr;
    rvfi_o.trap      = exc;
    rvfi_o.halt      = 1'b0;
    rvfi_o.intr      = 1'b0;
    // Privilege changes only when a trap or xRET commits, and that flushes
    // everything younger, so the current mode is the committing instruction's.
    rvfi_o.mode      = priv_i;
    rvfi_o.ixl       = 2'd2;                      // XLEN = 64
    rvfi_o.rs1_addr  = wb_i.rs1_addr;
    rvfi_o.rs2_addr  = wb_i.rs2_addr;
    rvfi_o.rs1_rdata = wb_i.rs1_rdata;
    rvfi_o.rs2_rdata = wb_i.rs2_rdata;
    rvfi_o.rd_addr   = rf_wr_o.we ? wb_i.rd     : '0;
    rvfi_o.rd_wdata  = rf_wr_o.we ? wb_i.result : '0;
    rvfi_o.pc_rdata  = wb_i.pc;
    // Wherever the next instruction comes from: the trap vector, xepc for an
    // xRET, otherwise the successor EX resolved.
    rvfi_o.pc_wdata  = redirect_valid_o ? redirect_pc_o : wb_i.next_pc;
    rvfi_o.mem.addr  = wb_i.mem_addr;
    rvfi_o.mem.rmask = wb_i.mem_rmask;
    rvfi_o.mem.wmask = wb_i.mem_wmask;
    rvfi_o.mem.rdata = wb_i.mem_rdata;
    rvfi_o.mem.wdata = wb_i.mem_wdata;
  end

  // tag: s1_mem commits stores by count, in order, so no tag is passed on.
  logic unused_inputs;
  always_comb begin
    unused_inputs = ^{wb_i.tag};
  end

endmodule
