// =============================================================================
// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// Author(s)    : Eman Nasar (fatehulnasareman@gmail.com) (Sep 2026)
// Modified By  :
//
// s1_wb_stage : WB stage -- completion arbitration and bypass       [WIP -- T-02]
// Description  :
// Stage five of the pipeline.  Every result the core produces reaches the
// completion buffer through here: the main pipe's, over MEM/WB from
// s1_mem_stage (#18), and the multi-cycle units', over their own channels
// (SPEC 6, 8.2).  WB picks one per cycle, writes the entry it names, and
// answers ID's operand reads for that value in the same cycle.
//
// The main pipe always wins.  Its channel has no `ready` -- the completion
// buffer entry was allocated in ID, so MEM cannot be told to wait -- while a
// multi-cycle unit holds its result until WB takes it.  Between those units the
// grant rotates, so a unit that completes every cycle cannot starve one that
// does not.
// Contract and timing: docs/modules/s1_wb_stage.md.
//
// Reference: SPEC 6, 7.5, 8.1, 8.2, 9.1, 9.2, 28.2; INTERFACES.md 1.4a.
// Testbench: verif/unit/tb_s1_wb_stage.sv.
// =============================================================================

module s1_wb_stage
  import s1_pkg::*;
#(
  parameter int unsigned N_UC   = 2,    // multi-cycle completion channels (MUL, DIV)
  localparam int unsigned RR_W  = (N_UC > 1) ? $clog2(N_UC) : 1
) (
  input  logic                  clk_i,
  input  logic                  rst_ni,

  // Retire flush ONLY -- a trap, an mret or a fence.i at the retire pointer.
  //
  // Never the branch mispredict.  #15 resolves a mispredict in EX and frees the
  // completion-buffer entries younger than the branch (ex_redirect_cb_idx_o);
  // everything in MEM and in MEM/WB is OLDER than the branch and must survive.
  // Wiring that redirect here would discard an older instruction's completion
  // and drain a unit whose result is still wanted, and nothing downstream would
  // notice -- the entry simply never completes and the head never retires.
  input  logic                  flush_i,

  // MEM/WB.  No ready: the entry was allocated in ID, so WB cannot refuse.
  input  logic                  wb_valid_i,
  input  mem_wb_t               wb_i,

  // Multi-cycle units (MUL, DIV, ...).  These do have a ready: a unit holds its
  // result until WB takes it, which is what lets the main pipe win every time.
  input  logic                  uc_valid_i [N_UC],
  output logic                  uc_ready_o [N_UC],
  input  md_rsp_t               uc_i       [N_UC],

  // Completion buffer write port.  `cb_upd_o` is meaningful only with `cb_we_o`.
  output logic                  cb_we_o,
  output logic [CB_IDX_W-1:0]   cb_idx_o,
  output wb_upd_t               cb_upd_o,

  // SPEC 8.1's MEM/WB forwarding source: the value only.  s1_execute (#15)
  // takes this as memwb_fwd_i; which operand reads it is decided in ID, and
  // deliberately not here -- see the comment above the assignment.
  output logic [XLEN-1:0]       fwd_data_o,

  // Perf (SPEC 12): a multi-cycle result was held off by a busier channel.
  output logic                  uc_stall_o
);

  if (N_UC < 1) begin : g_bad_nuc
    $error("s1_wb_stage: N_UC must be at least 1; tie uc_valid_i[0] low if unused");
  end

  // ---------------------------------------------------------------------------
  // Has the main pipe finished with this instruction?
  //
  // An MXIF candidate travels the main pipe as a placeholder.  It carries
  // `complete = 0` and the MXIF port, not WB, marks its entry done and clears
  // its rollback once the coprocessor answers (INTERFACES.md 1.4a).  WB must
  // therefore leave that entry alone entirely: the rd and rd_we the decoder put
  // in it at ID are the live copy, and writing this placeholder's fields over
  // them would lose the register the coprocessor is going to write.
  //
  // The one exception is a candidate that trapped before it was ever offered to
  // a coprocessor -- a fetch or address fault carried down from IF or EX.  It
  // will never be offloaded, so it is resolved here like anything else.
  // ---------------------------------------------------------------------------
  logic resolved, main_takes;

  assign resolved   = wb_i.complete | wb_i.exc;
  assign main_takes = wb_valid_i & resolved & ~flush_i;

  // ---------------------------------------------------------------------------
  // Multi-cycle channels: rotate the grant
  //
  // Fixed priority would be smaller, but MUL completes far more often than DIV
  // and would starve it for as long as a multiply-heavy loop runs.  The rotation
  // costs one pointer and makes "no channel waits for ever" a property the
  // testbench can check rather than a claim about workloads.
  // ---------------------------------------------------------------------------
  logic [N_UC-1:0]  uc_req, uc_gnt;
  logic [RR_W-1:0]  rr_q, rr_d;
  logic             uc_port_free, uc_go;

  always_comb begin
    for (int unsigned k = 0; k < N_UC; k++) uc_req[k] = uc_valid_i[k];
  end

  // The port is free for a unit when the main pipe is not using it.  During a
  // flush it is free too, and every channel is drained at once -- see below.
  assign uc_port_free = ~main_takes & ~flush_i;

  // Ranked from rr_q upwards, wrapping.  Written as a compare against the rank
  // rather than as uc_req[rr_q + i] so that no signal is indexed by a variable
  // -- with N_UC channels this is N_UC*N_UC compares of a 2-bit number, and
  // N_UC is 2.
  always_comb begin
    uc_gnt = '0;
    for (int unsigned i = 0; i < N_UC; i++)
      for (int unsigned k = 0; k < N_UC; k++)
        if ((k == ((32'(rr_q) + i) % N_UC)) && uc_req[k] && (uc_gnt == '0))
          uc_gnt[k] = 1'b1;
  end

  assign uc_go = uc_port_free & (uc_gnt != '0);

  always_comb begin
    rr_d = rr_q;
    for (int unsigned k = 0; k < N_UC; k++)
      if (uc_gnt[k]) rr_d = RR_W'((k + 1) % N_UC);
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)     rr_q <= '0;
    else if (uc_go)  rr_q <= rr_d;
  end

  // A flush accepts and discards every result presented in that cycle.  A unit
  // holding a result for an entry the flush removed would otherwise wait for a
  // ready that will never mean anything, and the unit would never free itself.
  always_comb begin
    for (int unsigned k = 0; k < N_UC; k++)
      uc_ready_o[k] = flush_i | (uc_port_free & uc_gnt[k]);
  end

  // Any channel that wanted the port this cycle and did not get it -- whether
  // the main pipe took it or another channel's turn came first.  A flush is not
  // a stall: every channel is drained in that cycle.
  assign uc_stall_o = ~flush_i & ((uc_req & ~(uc_go ? uc_gnt : {N_UC{1'b0}})) != '0);

  // The granted channel's payload.
  md_rsp_t uc_sel;
  always_comb begin
    uc_sel = '0;
    for (int unsigned k = 0; k < N_UC; k++)
      if (uc_gnt[k]) uc_sel = uc_i[k];
  end

  // ---------------------------------------------------------------------------
  // Does the winning completion update an architectural register?
  //
  // A trapping instruction writes nothing: SPEC 9.2 step 6 skips steps 1-3.
  //
  // x0 is dropped here rather than at retire because the bypass is fed from the
  // same signal.  Retire writing x0 is harmless -- the register file discards
  // it -- but a bypass that answers with it turns `addi x0, x1, 1` into a
  // corrupted operand for the next reader of x0, and that reader is entitled to
  // zero.  One gate, at the only place that can get it wrong.
  // ---------------------------------------------------------------------------
  logic                  wr_reg;
  logic [REG_ADDR_W-1:0] sel_rd;
  logic [XLEN-1:0]       sel_result;

  assign sel_rd     = main_takes ? wb_i.rd     : uc_sel.rd;
  assign sel_result = main_takes ? wb_i.result : uc_sel.result;

  always_comb begin
    if      (main_takes) wr_reg = wb_i.rd_we & ~wb_i.exc & (wb_i.rd != '0);
    // RV64M raises no exceptions -- divide by zero and signed overflow are
    // defined results, not traps -- and every multiply and divide writes its
    // destination, so x0 is the only reason a unit result writes nothing.
    //
    // The uc_go term is load-bearing.  uc_gnt is computed from the requests
    // alone, without regard to who holds the port, so uc_sel carries a channel's
    // payload even in cycles when no unit is being accepted.  Without this the
    // forwarding bus would present that value while cb_we_o was low, and EX
    // would read a result for an instruction that had not completed.
    else if (uc_go)      wr_reg = (uc_sel.rd != '0);
    else                 wr_reg = 1'b0;
  end

  // ---------------------------------------------------------------------------
  // Completion buffer write port
  // ---------------------------------------------------------------------------
  assign cb_we_o  = main_takes | uc_go;
  assign cb_idx_o = main_takes ? wb_i.cb_idx : uc_sel.cb_idx;

  always_comb begin
    // Default first (R-C3): every field below is assigned on every path, but
    // the struct is wide and a field added to wb_upd_t later must not become a
    // latch because someone missed a line here.
    cb_upd_o            = '0;

    // Both constants, and both true by construction rather than by choice:
    // `cb_we_o` is asserted only for an instruction its producer has resolved,
    // and neither the main pipe nor a MUL/DIV result can fault afterwards
    // (SPEC 9.1).
    cb_upd_o.done       = 1'b1;
    cb_upd_o.norollback = 1'b1;
    cb_upd_o.from_main  = main_takes;

    cb_upd_o.rd         = wr_reg ? sel_rd     : '0;
    cb_upd_o.rd_we      = wr_reg;
    cb_upd_o.result     = wr_reg ? sel_result : '0;

    // Everything below belongs to the instruction, not to its result, and only
    // the main pipe carries it.  A multi-cycle unit never sees a branch target,
    // a CSR write, a store-buffer slot or a memory access, so for those
    // completions the fields stay zero and `from_main` tells the completion
    // buffer to keep what it already has.
    if (main_takes) begin
      cb_upd_o.next_pc    = wb_i.next_pc;

      cb_upd_o.exc        = wb_i.exc;
      cb_upd_o.exccode    = wb_i.exccode;
      cb_upd_o.exctval    = wb_i.exctval;

      // Suppressed for the same reason as the register write, and by the same
      // rule.  A CSR write that survived its instruction's trap would be
      // visible architectural state from an instruction that never executed.
      cb_upd_o.csr.we     = wb_i.csr_we & ~wb_i.exc;
      cb_upd_o.csr.addr   = wb_i.csr_addr;
      cb_upd_o.csr.wdata  = wb_i.csr_wdata;

      // Passed through unchanged, deliberately.  MEM allocates a store-buffer
      // entry only for an access that already passed every check, so
      // `sb_alloc` and `exc` are mutually exclusive at the source.  Gating it
      // here would look defensive but would strand the entry: allocated in
      // MEM, never committed at retire, never drained, and the buffer one slot
      // smaller for the rest of time.  If the two are ever seen together the
      // bug is upstream.
      cb_upd_o.sb_alloc   = wb_i.sb_alloc;

      cb_upd_o.rvfi.addr  = wb_i.mem_addr;
      cb_upd_o.rvfi.rmask = wb_i.mem_rmask;
      cb_upd_o.rvfi.wmask = wb_i.mem_wmask;
      cb_upd_o.rvfi.rdata = wb_i.mem_rdata;
      cb_upd_o.rvfi.wdata = wb_i.mem_wdata;
    end
  end

  // ---------------------------------------------------------------------------
  // Bypass to ID (SPEC 8.1, the MEM/WB source)
  //
  // The value, and only the value.  There is no "does this match rs1" output
  // here, and that omission is the contract:
  //
  //   cycle          t              t+1
  //   ID             consumer C     -
  //   EX/MEM reg     M              -
  //   this module    P              M        <- fwd_data_o at t+1 is M's
  //
  // s1_execute (#15) fixes the forwarding select in ID and applies it in the
  // consumer's first EX cycle, so a select made at t is spent at t+1, when this
  // bus carries M -- the instruction sitting in the EX/MEM register at t, not
  // the one this module completed at t.  A match computed here would compare
  // against P and be exactly one instruction stale.  The ID-stage MEM/WB match
  // belongs with the EX/MEM register, where M is visible.
  //
  // The value is already gated: it is the same signal the completion buffer is
  // told to write, so a trapping instruction, an instruction with no
  // destination and a destination of x0 all read as zero here.
  // ---------------------------------------------------------------------------
  assign fwd_data_o = cb_upd_o.result;

endmodule
