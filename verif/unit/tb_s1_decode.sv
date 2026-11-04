// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// tb_s1_decode : unit testbench for s1_decode                        [COMPLETE]
//
// Covers all RV64IMAC_Zicsr_Zifencei instructions (RV64I, RV64I+,
// RVM, SYSTEM) plus the 11 RV64A atomics, reserved-encoding checks next to
// each legal one, both MXIF_EN configs, and the compressed-instruction guard.
// Compressed (C) encodings aren't tested directly -- they're expanded to
// 32-bit before IF/ID, so covering their 32-bit equivalents covers them too.
//
// The tests are grouped by extension, one `include file per group next to
// this file.  The instruction encoders are shared: verif/common/s1_instr_enc.svh.
//
// Run:  make test-unit               (all testbenches)
//       make test-unit TB=s1_decode  (just this one)
// =============================================================================

module tb_s1_decode;
  import s1_pkg::*;

  // ---------------------------------------------------------------------------
  // DUTs -- one per MXIF_EN configuration, since that parameter changes the
  // legality of unrecognised opcodes (SPEC 7.2 design note).
  // ---------------------------------------------------------------------------
  logic [ILEN-1:0] instr;
  logic [XLEN-1:0] pc;

  decoded_op_t dec_mxif_on;
  decoded_op_t dec_mxif_off;

  s1_decode #(.MXIF_EN(1'b1)) dut_mxif_on (
    .instr_i (instr),
    .pc_i    (pc),
    .decoded_o (dec_mxif_on)
  );

  s1_decode #(.MXIF_EN(1'b0)) dut_mxif_off (
    .instr_i (instr),
    .pc_i    (pc),
    .decoded_o (dec_mxif_off)
  );

  // ---------------------------------------------------------------------------
  // Scoreboard
  // ---------------------------------------------------------------------------
  int unsigned checks = 0;
  int unsigned errors = 0;
  int unsigned instr_count = 0;   // one bump per named instruction section below
  string       cur_test;

  task automatic check_field(string field_name, logic [XLEN-1:0] got,
                              logic [XLEN-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL [%0s] instr=%08h field=%0s got=%0h exp=%0h",
                cur_test, instr, field_name, got, exp);
    end
  endtask

  task automatic expect_common(exec_unit_e unit, logic illegal, logic rd_we,
                                logic rs1_re, logic rs2_re);
    check_field("unit",    dec_mxif_on.unit,    unit);
    check_field("illegal", dec_mxif_on.illegal, illegal);
    check_field("rd_we",   dec_mxif_on.rd_we,   rd_we);
    check_field("rs1_re",  dec_mxif_on.rs1_re,  rs1_re);
    check_field("rs2_re",  dec_mxif_on.rs2_re,  rs2_re);
  endtask

  // An encoding the base decoder does not recognise: offered to the coprocessor
  // when one is attached, illegal otherwise, and never a register read or write
  // of the core's own (SPEC 7.2 design note).
  task automatic expect_unrecognised();
    check_field("on.unit",           dec_mxif_on.unit,            UNIT_MXIF);
    check_field("on.mxif_candidate", dec_mxif_on.mxif_candidate,  1'b1);
    check_field("on.illegal",        dec_mxif_on.illegal,         1'b0);
    check_field("off.unit",          dec_mxif_off.unit,           UNIT_NONE);
    check_field("off.mxif_candidate", dec_mxif_off.mxif_candidate, 1'b0);
    check_field("off.illegal",       dec_mxif_off.illegal,        1'b1);
    check_field("off.rs1_re",        dec_mxif_off.rs1_re,         1'b0);
    check_field("off.rs2_re",        dec_mxif_off.rs2_re,         1'b0);
    check_field("off.rd_we",         dec_mxif_off.rd_we,          1'b0);
  endtask

  // One call per legal instruction
  task automatic named(string mnemonic);
    instr_count++;
  endtask

  // ---------------------------------------------------------------------------
  // Encoders, then the test groups: one file per extension, one task each.
  // ---------------------------------------------------------------------------
  `include "verif/common/s1_instr_enc.svh"
  `include "verif/unit/tb_s1_decode_rv64i.svh"
  `include "verif/unit/tb_s1_decode_m.svh"
  `include "verif/unit/tb_s1_decode_a.svh"
  `include "verif/unit/tb_s1_decode_system.svh"

  task automatic test_pseudo();
    // ==========================================================================
    // Pseudo-instruction spot checks (Table I.7). These are not a new decode
    // path -- each is one specific operand pattern of an instruction already
    // exhaustively tested above.
    // ==========================================================================

    cur_test = "nop == addi x0,x0,0"; named("nop");
    instr = enc_i(12'h000, 5'd0, 3'b000, 5'd0, OP_IMM); #1;
    check_field("alu_op", dec_mxif_on.alu_op, ALU_ADD);
    check_field("rd_we", dec_mxif_on.rd_we, 1'b1);   // decoder doesn't special-case x0; see note below
    check_field("rd", dec_mxif_on.rd, 5'd0);

    cur_test = "mv == addi rd,rs1,0"; named("mv");
    instr = enc_i(12'h000, 5'd9, 3'b000, 5'd10, OP_IMM); #1;
    check_field("alu_op", dec_mxif_on.alu_op, ALU_ADD);
    check_field("rs1_re", dec_mxif_on.rs1_re, 1'b1);

    cur_test = "not == xori rd,rs1,-1"; named("not");
    instr = enc_i(12'hFFF, 5'd9, 3'b100, 5'd10, OP_IMM); #1;
    check_field("alu_op", dec_mxif_on.alu_op, ALU_XOR);
    check_field("imm", dec_mxif_on.imm, {XLEN{1'b1}});

    cur_test = "neg == sub rd,x0,rs2"; named("neg");
    instr = enc_r(7'b0100000, 5'd9, 5'd0, 3'b000, 5'd10, OP_OP); #1;
    check_field("alu_op", dec_mxif_on.alu_op, ALU_SUB);
    check_field("rs1", dec_mxif_on.rs1, 5'd0);

    cur_test = "seqz == sltiu rd,rs1,1"; named("seqz");
    instr = enc_i(12'h001, 5'd9, 3'b011, 5'd10, OP_IMM); #1;
    check_field("alu_op", dec_mxif_on.alu_op, ALU_SLTU);

    cur_test = "j == jal x0,label"; named("j");
    instr = enc_j(21'sd32, 5'd0, OP_JAL); #1;
    check_field("is_jal", dec_mxif_on.is_jal, 1'b1);
    check_field("rd", dec_mxif_on.rd, 5'd0);
    check_field("rd_we", dec_mxif_on.rd_we, 1'b1);   // discarded by regfile, not gated here

    cur_test = "ret == jalr x0,0(ra)"; named("ret");
    instr = enc_i(12'h000, 5'd1, 3'b000, 5'd0, OP_JALR); #1;
    check_field("is_jalr", dec_mxif_on.is_jalr, 1'b1);
    check_field("rs1", dec_mxif_on.rs1, 5'd1);
    check_field("rd", dec_mxif_on.rd, 5'd0);

    cur_test = "csrr == csrrs rd,csr,x0"; named("csrr");
    instr = {12'hC01, 5'd0, 3'b010, 5'd15, OP_SYSTEM}; #1;  // csrr x15, time
    check_field("csr_op", dec_mxif_on.csr_op, CSR_RS);
    check_field("rs1", dec_mxif_on.rs1, 5'd0);

    cur_test = "csrw == csrrw x0,csr,rs1"; named("csrw");
    instr = {12'h300, 5'd12, 3'b001, 5'd0, OP_SYSTEM}; #1;  // csrw mstatus, x12
    check_field("csr_op", dec_mxif_on.csr_op, CSR_RW);
    check_field("rd", dec_mxif_on.rd, 5'd0);
    check_field("rd_we", dec_mxif_on.rd_we, 1'b1);   // discarded by regfile, not gated here
  endtask

  task automatic test_mxif_and_guards();
    // ==========================================================================
    // MXIF-candidate classification, both configurations, and the compressed-
    // instruction structural guard.
    // ==========================================================================

    cur_test = "unknown-opcode/MXIF_EN=1";
    instr = {25'b0, 7'b0101011};   // custom-1 opcode space, reserved by the ISA for this
    #1;
    check_field("unit_on",   dec_mxif_on.unit,            UNIT_MXIF);
    check_field("illegal_on", dec_mxif_on.illegal,        1'b0);
    check_field("candidate_on", dec_mxif_on.mxif_candidate, 1'b1);

    cur_test = "unknown-opcode/MXIF_EN=0";
    check_field("unit_off",   dec_mxif_off.unit,            UNIT_NONE);
    check_field("illegal_off", dec_mxif_off.illegal,        1'b1);
    check_field("candidate_off", dec_mxif_off.mxif_candidate, 1'b0);

    cur_test = "vector-opcode-0x57/MXIF_EN=1";
    // SPEC 4.2's own example: OP-V (MEDS-V), unimplemented by this base
    // decoder, must fall through to MXIF-candidate with no special-casing.
    instr = {25'b0, 7'b1010111};
    #1;
    check_field("unit", dec_mxif_on.unit, UNIT_MXIF);
    check_field("mxif_candidate", dec_mxif_on.mxif_candidate, 1'b1);

    cur_test = "load-fp-opcode-0x07/MXIF_EN=1";
    // Also SPEC 4.2's example set (MEDS-V vector load reuses LOAD-FP space).
    instr = {25'b0, 7'b0000111};
    #1;
    check_field("unit", dec_mxif_on.unit, UNIT_MXIF);

    cur_test = "compressed-leak-guard";
    // opcode[1:0] != 11 must never be legal, MXIF_EN or not (SPEC 7.1).
    instr = 32'h0000_0001;
    #1;
    check_field("illegal_on",    dec_mxif_on.illegal,         1'b1);
    check_field("illegal_off",   dec_mxif_off.illegal,        1'b1);
    check_field("unit_on",       dec_mxif_on.unit,            UNIT_NONE);
    check_field("candidate_on",  dec_mxif_on.mxif_candidate,  1'b0);

    // ==========================================================================
    // x0 bookkeeping: decoder does not special-case x0, per s1_pkg.sv note
    // 11.1 -- rd_we may be 1 for rd==0; regfile discards the write.
    // ==========================================================================
    cur_test = "x0-not-special-cased";
    instr = enc_i(12'h001, 5'd0, 3'b000, 5'd0, OP_IMM); #1;  // addi x0, x0, 1
    check_field("rd_we", dec_mxif_on.rd_we, 1'b1);
    check_field("rd",    dec_mxif_on.rd,    5'd0);
  endtask

  initial begin
    pc = XLEN'(32'h8000_0100);

    test_rv64i();
    test_rv64m();
    test_rv64a();
    test_system();
    test_pseudo();
    test_mxif_and_guards();

    // ==========================================================================
    // Summary
    // ==========================================================================
    #1;
    $display("---------------------------------------------------------------");
    $display("named instructions covered: %0d (37 RV64I + 12 RV64I+ + 13 RVM + 11 RV64A + 15 SYSTEM + 4 Zicbom/Zicboz = 92, + 9 pseudo-instruction spot checks)", instr_count);
    if (errors == 0)
      $display("=== PASS : %0d checks ===", checks);
    else
      $display("=== FAIL : %0d errors of %0d checks ===", errors, checks);
    $display("---------------------------------------------------------------");

    if (errors == 0) begin
      $finish;
    end else begin
      $fatal(1, "tb_s1_decode failed");
    end
  end

endmodule
