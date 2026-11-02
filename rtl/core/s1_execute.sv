// =============================================================================
// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// Author(s)    : Ayesha Anwar (ayesha.anwaar2005@gmail.com) (Sep,2026)
// Modified By  :
//
// s1_execute   : EX stage -- forwarding, ALU, branch resolution, AGU, CSR RMW  [WIP -- T-02]
// Description  :
// Resolves operands (SPEC 8.1), executes on s1_alu, resolves branches and
// redirects fetch on a mispredict, computes load/store addresses and CSR
// read-modify-write values (committed in WB), and runs MUL and DIV in place.
// Registers everything else into EX/MEM.  Contract: docs/modules/s1_execute.md.
//
// Reference: SPEC 6, 7.3, 8.1, 8.2, 9, 12.  Testbench: verif/unit/tb_s1_execute.sv.
// =============================================================================

module s1_execute
  import s1_pkg::*;
(
  input  logic                 clk_i,
  input  logic                 rst_ni,

  input  logic                 flush_i,             // retire flush: kills EX and EX/MEM
  input  priv_lvl_e            priv_i,              // selects the ECALL cause

  // ID/EX
  input  logic                 ex_valid_i,
  output logic                 ex_ready_o,
  input  id_ex_t               ex_i,

  // CSR read and access check; side-effect free, the write commits at retire
  output logic [11:0]          csr_addr_o,
  output logic                 csr_re_o,
  output logic                 csr_we_o,
  input  logic [XLEN-1:0]      csr_rdata_i,
  input  logic                 csr_illegal_i,

  // Mispredict: to fetch (flush IF) and ID (block the wrong-path issue)
  output logic                 ex_redirect_valid_o,
  output logic [XLEN-1:0]      ex_redirect_pc_o,

  // EX/MEM
  output logic                 mem_valid_o,
  input  logic                 mem_ready_i,
  output ex_mem_t              mem_o,

  // ---- RV64M, external (SPEC 2.1) -----------------------------------------
  output logic                 md_start_o,
  output muldiv_op_e           md_op_o,
  output logic [XLEN-1:0]      md_a_o,
  output logic [XLEN-1:0]      md_b_o,
  output logic                 md_flush_o,
  input  logic                 md_done_i,
  input  logic [XLEN-1:0]      md_result_i,

  // Performance events (SPEC 12)
  output logic                 perf_br_taken_o,
  output logic                 perf_br_mispredict_o,
  output logic                 perf_muldiv_stall_o
);

  localparam int unsigned RVC_BYTES   = 2;
  localparam int unsigned INSTR_BYTES = ILEN / 8;

  decoded_op_t op;
  assign op = ex_i.op;

  logic            mem_valid_q;
  ex_mem_t         mem_q;
  logic            busy_q;               // current instruction has been in EX >= 1 cycle
  logic [XLEN-1:0] rs1_q, rs2_q;         // operands captured in its first cycle
  logic            live, first, fire;

  assign live  = ex_valid_i && !flush_i;
  assign first = live && !busy_q;

  // ---------------------------------------------------------------------------
  // Operands.  Forwarding selects are valid for an instruction's first EX
  // cycle only; producers ahead keep moving while EX stalls, so the resolved
  // values are captured then and reused.
  // ---------------------------------------------------------------------------
  logic [XLEN-1:0] rs1_fwd, rs2_fwd, rs1, rs2;

  always_comb begin
    // FWD_RF carries a value ID already resolved; FWD_EXMEM is the one source
    // whose value does not exist until this cycle, so it is read here.
    rs1_fwd = ex_i.rs1_val;
    unique case (ex_i.rs1_fwd)
      FWD_RF:    rs1_fwd = ex_i.rs1_val;
      FWD_EXMEM: rs1_fwd = mem_q.result;
    endcase
    rs2_fwd = ex_i.rs2_val;
    unique case (ex_i.rs2_fwd)
      FWD_RF:    rs2_fwd = ex_i.rs2_val;
      FWD_EXMEM: rs2_fwd = mem_q.result;
    endcase
  end

  // x0 reads zero whatever the select says.
  assign rs1 = (op.rs1 == '0) ? '0 : busy_q ? rs1_q : rs1_fwd;
  assign rs2 = (op.rs2 == '0) ? '0 : busy_q ? rs2_q : rs2_fwd;

  // ---------------------------------------------------------------------------
  // ALU.  Branches always compare rs1 with rs2.
  // ---------------------------------------------------------------------------
  logic [XLEN-1:0] alu_a, alu_b, alu_res;
  logic            cmp_res;

  assign alu_a = (op.op1_is_pc  && !op.is_branch) ? op.pc  : rs1;
  assign alu_b = (op.op2_is_imm && !op.is_branch) ? op.imm : rs2;

  s1_alu u_alu (
    .op_i         (op.alu_op),
    .cmp_op_i     (op.is_branch ? op.cmp_op : CMP_NONE),
    .a_i          (alu_a),
    .b_i          (alu_b),
    .result_o     (alu_res),
    .cmp_result_o (cmp_res)
  );

  // ---------------------------------------------------------------------------
  // Address and target adders
  // ---------------------------------------------------------------------------
  logic [XLEN-1:0] pc_len, pc_imm, agu, jalr_tgt;

  assign pc_len   = op.pc + (ex_i.compressed ? XLEN'(RVC_BYTES) : XLEN'(INSTR_BYTES));
  assign pc_imm   = op.pc + op.imm;
  assign agu      = rs1 + ((op.amo_op != AMO_NONE) ? '0 : op.imm);      // AMO/LR/SC: rs1 only
  assign jalr_tgt = {agu[XLEN-1:1], 1'b0};

  // ---------------------------------------------------------------------------
  // CSR read-modify-write.  RS/RC write only if the rs1 field (or uimm) is
  // non-zero; RW with rd=x0 does not read (Zicsr).
  // ---------------------------------------------------------------------------
  logic [XLEN-1:0] csr_src, csr_wdata;
  logic            csr_write, csr_read, csr_ok, is_csr;

  assign is_csr    = (op.csr_op != CSR_NONE);

  assign csr_src   = op.csr_imm ? op.imm : rs1;
  assign csr_write = (op.csr_op == CSR_RW) || (op.rs1 != '0);
  assign csr_read  = !(op.csr_op == CSR_RW && op.rd == '0);
  assign csr_ok    = live && is_csr && !ex_i.exc && !op.illegal;

  always_comb begin
    csr_wdata = csr_rdata_i;
    unique case (op.csr_op)
      CSR_RW:   csr_wdata = csr_src;
      CSR_RS:   csr_wdata = csr_rdata_i | csr_src;
      CSR_RC:   csr_wdata = csr_rdata_i & ~csr_src;
      CSR_NONE: csr_wdata = csr_rdata_i;
    endcase
  end

  assign csr_addr_o = op.csr_addr;
  assign csr_re_o   = csr_ok && csr_read;
  assign csr_we_o   = csr_ok && csr_write;

  // ---------------------------------------------------------------------------
  // Exceptions, in priority order.  An excepting instruction has no side
  // effects here: no redirect, no dispatch, no memory access, no CSR write.
  // ---------------------------------------------------------------------------
  logic            exc;
  logic [5:0]      exccode;
  logic [XLEN-1:0] exctval;

  always_comb begin
    exc     = 1'b0;
    exccode = '0;
    exctval = '0;
    if (ex_i.exc) begin
      exc     = 1'b1;
      exccode = ex_i.exccode;
      exctval = ex_i.exctval;
    end else if (op.illegal || op.mxif_candidate || (is_csr && csr_illegal_i)) begin
      // An MXIF candidate is illegal unless a coprocessor accepts it (SPEC
      // 7.2).  This core has no MXIF port, so nobody can.
      exc     = 1'b1;
      exccode = EXC_ILLEGAL_INSTR;
      exctval = XLEN'(ex_i.instr_raw);
    end else if (op.sys_op == SYS_ECALL) begin
      exc     = 1'b1;
      unique case (priv_i)
        PRIV_U:  exccode = EXC_ECALL_U;
        PRIV_S:  exccode = EXC_ECALL_S;
        default: exccode = EXC_ECALL_M;
      endcase
    end else if (op.sys_op == SYS_EBREAK) begin
      exc     = 1'b1;
      exccode = EXC_BREAKPOINT;
      exctval = op.pc;
    end
  end

  // ---------------------------------------------------------------------------
  // Branch resolution.  Fetch contract: pred_taken means it went to pc+imm,
  // which is checkable only for a branch or JAL; otherwise it went to pc+len.
  // Redirect iff where fetch went differs from the real successor.
  // ---------------------------------------------------------------------------
  logic            taken, mispredict;
  logic [XLEN-1:0] next_pc;

  assign taken      = op.is_jal || op.is_jalr || (op.is_branch && cmp_res);
  assign next_pc    = !taken     ? pc_len
                    : op.is_jalr ? jalr_tgt
                    :              pc_imm;
  assign mispredict = ex_i.pred_taken ? (!(op.is_branch || op.is_jal) || next_pc != pc_imm)
                                      : (next_pc != pc_len);

  // Once per instruction, in its first cycle: a stalled branch must not
  // restart fetch every cycle.
  assign ex_redirect_valid_o  = first && !exc && mispredict;
  assign ex_redirect_pc_o     = next_pc;

  assign perf_br_taken_o      = first && !exc && op.is_branch && cmp_res;
  assign perf_br_mispredict_o = ex_redirect_valid_o;

  // ---------------------------------------------------------------------------
  // RV64M.  Multiply and divide run here and hold EX until they answer; their
  // result is EX's result and travels on through EX/MEM like any other.
  //
  // This is the whole of what the 5-stage core gives up relative to the
  // decoupled design: nothing overlaps a divide.  What it buys is that every
  // instruction leaves EX in program order, so there is no completion buffer,
  // no second write port anywhere, and no way for a result to arrive out of
  // turn.  A divide costs XLEN cycles of pipeline, which is honest and
  // measurable -- EV_MULDIV_STALL counts it.
  // ---------------------------------------------------------------------------
  logic            is_md, md_start, md_done;
  logic [XLEN-1:0] md_result;

  assign is_md    = live && !exc && (op.unit == UNIT_MUL || op.unit == UNIT_DIV);
  // Starts once, in the instruction's first EX cycle; `first` is already
  // "valid, not flushed, and not already busy here".
  assign md_start = is_md && first;

  // The multiplier/divider is external (SPEC 2.1).
  // It is not a pipeline unit: `start_o` is this instruction's first EX cycle,
  // EX holds the instruction until `done_i`, and the answer is EX's result.
  assign md_start_o = md_start;
  assign md_op_o    = op.muldiv_op;
  assign md_a_o     = rs1;
  assign md_b_o     = rs2;
  assign md_flush_o = flush_i;

  assign md_done   = md_done_i;
  assign md_result = md_result_i;

  logic to_mem, mem_free;

  // An RV64M instruction may move on only once its answer is ready.
  assign to_mem   = live && (!is_md || md_done);
  assign mem_free = !mem_valid_q || mem_ready_i;
  assign fire     = to_mem && mem_free;

  assign ex_ready_o = !ex_valid_i || flush_i || fire;

  assign perf_muldiv_stall_o = is_md && !md_done;

  ex_mem_t out;
  always_comb begin
    out          = '0;
    out.amo_op   = AMO_NONE;   // not '0, which is AMO_LR
    out.tag   = ex_i.tag;
    out.rd       = op.rd;
    out.rd_we    = op.rd_we && !exc;
    out.result   = is_md                       ? md_result
                 : (op.is_jal || op.is_jalr)   ? pc_len
                 : is_csr                      ? csr_rdata_i
                 :                               alu_res;
    out.next_pc  = next_pc;
    // Carried for WB, which is the commit point now that there is no buffer.
    out.pc       = op.pc;
    out.instr    = ex_i.instr_raw;
    out.sys_op   = op.sys_op;
    out.rs1_addr = op.rs1_re ? op.rs1 : '0;
    out.rs2_addr = op.rs2_re ? op.rs2 : '0;
    out.rs1_rdata = op.rs1_re ? rs1 : '0;  // after forwarding: what EX used
    out.rs2_rdata = op.rs2_re ? rs2 : '0;
    out.exc      = exc;
    out.exccode  = exccode;
    out.exctval  = exctval;
    if (!exc) begin
      out.is_load    = op.is_load;
      out.is_store   = op.is_store;
      out.mem_size   = op.mem_size;
      out.mem_signed = op.mem_signed;
      out.amo_op     = op.amo_op;
      out.aq         = op.aq;
      out.rl         = op.rl;
      out.mem_addr   = agu;
      out.mem_wdata  = rs2;
      out.csr_we     = is_csr && csr_write;
      out.csr_addr   = op.csr_addr;
      out.csr_wdata  = csr_wdata;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      mem_valid_q <= 1'b0;
      mem_q       <= '0;
      mem_q.amo_op <= AMO_NONE;
      busy_q      <= 1'b0;
      rs1_q       <= '0;
      rs2_q       <= '0;
    end else begin
      if (flush_i) begin
        mem_valid_q <= 1'b0;
      end else if (to_mem && mem_free) begin
        mem_valid_q <= 1'b1;
        mem_q       <= out;
      end else if (mem_ready_i) begin
        mem_valid_q <= 1'b0;
      end

      busy_q <= live && !fire;
      if (first && !fire) begin
        rs1_q <= rs1;
        rs2_q <= rs2;
      end
    end
  end

  assign mem_valid_o = mem_valid_q;
  assign mem_o       = mem_q;

  // cbo_op has no consumer: Zicbom/Zicboz are decoded but not executed, so a
  // CBO retires as a no-op today.  instr: EX uses instr_raw, the encoding as
  // fetched, for RVFI and mtval.
  logic unused_op;
  assign unused_op = ^{op.cbo_op, op.instr};

endmodule
