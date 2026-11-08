// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// s1_id : ID stage -- decode, operand resolve, hazards, ID/EX register
//                                                                   [WIP -- T-02]
// Description  :
// Decodes the IF/ID instruction with s1_decode, resolves rs1/rs2 (register file
// read, EX/MEM bypass, or an EX-forward select), stalls on a load-use hazard,
// serialises CSR and SYSTEM instructions on an empty pipeline, and registers
// the result into ID/EX.  Contract: docs/modules/s1_id.md.
//
// Reference: SPEC 7.2, 8.1.  Testbench: verif/unit/tb_s1_id.sv.
// =============================================================================

module s1_id
  import s1_pkg::*;
#(
  parameter bit MXIF_EN = 1'b0
) (
  input  logic                  clk_i,
  input  logic                  rst_ni,

  input  logic                  flush_i,              // retire flush
  input  logic                  ex_redirect_valid_i,  // mispredict: block wrong-path issue

  // IF/ID
  input  logic                  fetch_rsp_valid_i,
  output logic                  fetch_rsp_ready_o,
  input  fetch_rsp_t            fetch_rsp_i,

  // Register file read data for the instruction in IF/ID (addressed a cycle ahead)
  input  logic [XLEN-1:0]       rs1_data_i,
  input  logic [XLEN-1:0]       rs2_data_i,

  // EX/MEM, for bypass and hazard checks
  input  logic                  exmem_valid_i,
  input  ex_mem_t               exmem_i,

  // MEM/WB entry not yet complete (load waiting on the D$)
  input  logic                  memwb_pend_i,
  input  logic [REG_ADDR_W-1:0] memwb_rd_i,
  input  logic                  memwb_rd_we_i,

  // EX/MEM, MEM/WB and WB all empty, store buffer drained
  input  logic                  downstream_busy_i,

  // ID/EX
  output logic                  ex_valid_o,
  input  logic                  ex_ready_i,
  output id_ex_t                ex_o,

  output logic                  perf_load_use_o,
  output logic                  perf_hazard_stall_o
);

  decoded_op_t op;

  s1_decode #(
    .MXIF_EN (MXIF_EN)
  ) u_decode (
    .instr_i   (fetch_rsp_i.instr),
    .pc_i      (fetch_rsp_i.pc),
    .decoded_o (op)
  );

  logic ex_valid_q;
  id_ex_t ex_q;

  // An instruction carrying a fetch exception reads nothing and writes nothing.
  logic rs1_re, rs2_re, serialise;
  assign rs1_re    = op.rs1_re && !fetch_rsp_i.exc;
  assign rs2_re    = op.rs2_re && !fetch_rsp_i.exc;
  assign serialise = !fetch_rsp_i.exc && (op.csr_op != CSR_NONE || op.sys_op != SYS_NONE);

  // ---------------------------------------------------------------------------
  // Hazards
  // ---------------------------------------------------------------------------
  logic from_ex_rs1, from_ex_rs2, from_mem_rs1, from_mem_rs2, load_use;

  s1_hazard u_hazard (
    .rs1_i          (op.rs1),
    .rs2_i          (op.rs2),
    .rs1_re_i       (rs1_re),
    .rs2_re_i       (rs2_re),
    .ex_wr_i        (ex_valid_q && ex_q.op.rd_we && (ex_q.op.rd != '0)),
    .ex_rd_i        (ex_q.op.rd),
    .ex_load_i      (ex_q.op.unit == UNIT_LSU),
    .mem_wr_i       (exmem_valid_i && exmem_i.rd_we),
    .mem_rd_i       (exmem_i.rd),
    .mem_load_i     (exmem_i.is_load || exmem_i.amo_op != AMO_NONE),
    .wbp_wr_i       (memwb_pend_i && memwb_rd_we_i),
    .wbp_rd_i       (memwb_rd_i),
    .from_ex_rs1_o  (from_ex_rs1),
    .from_ex_rs2_o  (from_ex_rs2),
    .from_mem_rs1_o (from_mem_rs1),
    .from_mem_rs2_o (from_mem_rs2),
    .stall_o        (load_use)
  );

  logic serial_stall, stall;
  assign serial_stall = serialise && (ex_valid_q || downstream_busy_i);
  assign stall        = load_use || serial_stall;

  // ---------------------------------------------------------------------------
  // ID/EX
  // ---------------------------------------------------------------------------
  logic slot_free, advance;
  assign slot_free = !ex_valid_q || ex_ready_i;
  assign advance   = fetch_rsp_valid_i && slot_free && !stall
                  && !flush_i && !ex_redirect_valid_i;

  assign fetch_rsp_ready_o = slot_free && !stall;

  id_ex_t nxt;
  always_comb begin
    nxt            = '0;
    nxt.op         = op;
    nxt.rs1_val    = from_mem_rs1 ? exmem_i.result : rs1_data_i;
    nxt.rs2_val    = from_mem_rs2 ? exmem_i.result : rs2_data_i;
    nxt.rs1_fwd    = from_ex_rs1 ? FWD_EXMEM : FWD_RF;
    nxt.rs2_fwd    = from_ex_rs2 ? FWD_EXMEM : FWD_RF;
    nxt.compressed = fetch_rsp_i.compressed;
    nxt.pred_taken = fetch_rsp_i.pred_taken;
    nxt.instr_raw  = fetch_rsp_i.instr_raw;
    nxt.exc        = fetch_rsp_i.exc;
    nxt.exccode    = fetch_rsp_i.exccode;
    nxt.exctval    = fetch_rsp_i.exctval;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      ex_valid_q <= 1'b0;
      ex_q       <= '0;
    end else if (ex_ready_i || !ex_valid_q) begin
      ex_valid_q <= advance;
      if (advance) ex_q <= nxt;
    end
  end

  assign ex_valid_o = ex_valid_q;
  assign ex_o       = ex_q;

  assign perf_load_use_o     = fetch_rsp_valid_i && load_use;
  assign perf_hazard_stall_o = fetch_rsp_valid_i && stall;

  // EX/MEM is read for rd, rd_we, is_load, amo_op and result only.
  logic unused_exmem;
  assign unused_exmem = ^{exmem_i};

endmodule
