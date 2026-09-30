// =============================================================================
// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// Author(s)    : Ammarah Wakeel (ammarahwakeel9@gmail.com) (Aug,2026)
// Modified By  :
// tb_s1_decode : directed unit test for s1_decode
//
// Description  :
// Covers all RV64IMAC_Zicsr_Zifencei instructions (RV64I, RV64I+,
// RVM, SYSTEM) plus the 11 RV64A atomics, reserved-encoding checks next to
// each legal one, both MXIF_EN configs, and the compressed-instruction guard.
// Compressed (C) encodings aren't tested directly -- they're expanded to
// 32-bit before IF/ID, so covering their 32-bit equivalents covers them too.
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
  // Instruction encoders -- the minimum an assembler would give us.
  // ---------------------------------------------------------------------------
  function automatic logic [31:0] enc_r(logic [6:0] f7, logic [4:0] rs2,
                                         logic [4:0] rs1, logic [2:0] f3,
                                         logic [4:0] rd, logic [6:0] op);
    return {f7, rs2, rs1, f3, rd, op};
  endfunction

  function automatic logic [31:0] enc_i(logic [11:0] imm, logic [4:0] rs1,
                                         logic [2:0] f3, logic [4:0] rd,
                                         logic [6:0] op);
    return {imm, rs1, f3, rd, op};
  endfunction

  function automatic logic [31:0] enc_s(logic [11:0] imm, logic [4:0] rs2,
                                         logic [4:0] rs1, logic [2:0] f3,
                                         logic [6:0] op);
    return {imm[11:5], rs2, rs1, f3, imm[4:0], op};
  endfunction

  function automatic logic [31:0] enc_b(logic signed [12:0] imm, logic [4:0] rs2,
                                         logic [4:0] rs1, logic [2:0] f3,
                                         logic [6:0] op);
    return {imm[12], imm[10:5], rs2, rs1, f3, imm[4:1], imm[11], op};
  endfunction

  function automatic logic [31:0] enc_u(logic [19:0] imm20, logic [4:0] rd,
                                         logic [6:0] op);
    return {imm20, rd, op};
  endfunction

  function automatic logic [31:0] enc_j(logic signed [20:0] imm, logic [4:0] rd,
                                         logic [6:0] op);
    return {imm[20], imm[10:1], imm[11], imm[19:12], rd, op};
  endfunction

  function automatic logic [31:0] enc_amo(logic [4:0] f5, logic aq, logic rl,
                                           logic [4:0] rs2, logic [4:0] rs1,
                                           logic [2:0] f3, logic [4:0] rd);
    return {f5, aq, rl, rs2, rs1, f3, rd, 7'b010_1111};
  endfunction

  function automatic logic [31:0] enc_sys12(logic [11:0] imm12, logic [4:0] rs1,
                                             logic [4:0] rd);
    return {imm12, rs1, 3'b000, rd, 7'b111_0011};
  endfunction

  function automatic logic [31:0] enc_fence(logic [3:0] fm, logic [3:0] pred,
                                             logic [3:0] succ, logic [2:0] f3);
    return {fm, pred, succ, 5'b0, f3, 5'b0, 7'b000_1111};
  endfunction

  // Opcodes, mirrored from the DUT for readability in the test body.
  localparam logic [6:0] OP_LOAD     = 7'b000_0011;
  localparam logic [6:0] OP_MISC_MEM = 7'b000_1111;
  localparam logic [6:0] OP_IMM      = 7'b001_0011;
  localparam logic [6:0] OP_AUIPC    = 7'b001_0111;
  localparam logic [6:0] OP_IMM_32   = 7'b001_1011;
  localparam logic [6:0] OP_STORE    = 7'b010_0011;
  localparam logic [6:0] OP_OP       = 7'b011_0011;
  localparam logic [6:0] OP_LUI      = 7'b011_0111;
  localparam logic [6:0] OP_OP_32    = 7'b011_1011;
  localparam logic [6:0] OP_BRANCH   = 7'b110_0011;
  localparam logic [6:0] OP_JALR     = 7'b110_0111;
  localparam logic [6:0] OP_JAL      = 7'b110_1111;
  localparam logic [6:0] OP_SYSTEM   = 7'b111_0011;

  // ---------------------------------------------------------------------------
  // Scoreboard
  // ---------------------------------------------------------------------------
  int unsigned checks = 0;
  int unsigned errors = 0;
  int unsigned instr_count = 0;   // one bump per named instruction section below
  string       cur_test;

  task automatic check_field(string field_name, logic [63:0] got, logic [63:0] exp);
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

  // One call per legal instruction
  task automatic named(string mnemonic);
    instr_count++;
  endtask

  initial begin
    pc = 64'h8000_0100;

    // ==========================================================================
    // RV64I (RV32I base, still the RV64I base). 37 instructions.
    // ==========================================================================

    cur_test = "lb"; named("lb");
    instr = enc_i(12'h000, 5'd10, 3'b000, 5'd11, OP_LOAD); #1;
    expect_common(UNIT_LSU, 1'b0, 1'b1, 1'b1, 1'b0);
    check_field("is_load", dec_mxif_on.is_load, 1'b1);
    check_field("mem_size", dec_mxif_on.mem_size, LS_BYTE);
    check_field("mem_signed", dec_mxif_on.mem_signed, 1'b1);
    check_field("alu_op", dec_mxif_on.alu_op, ALU_ADD);
    check_field("op2_is_imm", dec_mxif_on.op2_is_imm, 1'b1);

    cur_test = "lh"; named("lh");
    instr = enc_i(12'h000, 5'd10, 3'b001, 5'd11, OP_LOAD); #1;
    check_field("mem_size", dec_mxif_on.mem_size, LS_HALF);
    check_field("mem_signed", dec_mxif_on.mem_signed, 1'b1);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "lw"; named("lw");
    instr = enc_i(12'h000, 5'd10, 3'b010, 5'd11, OP_LOAD); #1;
    check_field("mem_size", dec_mxif_on.mem_size, LS_WORD);
    check_field("mem_signed", dec_mxif_on.mem_signed, 1'b1);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "lbu"; named("lbu");
    instr = enc_i(12'h000, 5'd10, 3'b100, 5'd11, OP_LOAD); #1;
    check_field("mem_size", dec_mxif_on.mem_size, LS_BYTE);
    check_field("mem_signed", dec_mxif_on.mem_signed, 1'b0);

    cur_test = "lhu"; named("lhu");
    instr = enc_i(12'h000, 5'd10, 3'b101, 5'd11, OP_LOAD); #1;
    check_field("mem_size", dec_mxif_on.mem_size, LS_HALF);
    check_field("mem_signed", dec_mxif_on.mem_signed, 1'b0);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "LOAD/reserved-funct3-111"; // no lwu at OP_LOAD 111 in RV32 base; see RV64I+ for lwu at 110
    instr = enc_i(12'h000, 5'd10, 3'b111, 5'd11, OP_LOAD); #1;
    check_field("illegal", dec_mxif_on.illegal, 1'b1);
    check_field("is_load", dec_mxif_on.is_load, 1'b0);

    cur_test = "addi"; named("addi");
    instr = enc_i(12'h7FF, 5'd5, 3'b000, 5'd6, OP_IMM); #1;
    expect_common(UNIT_ALU, 1'b0, 1'b1, 1'b1, 1'b0);
    check_field("alu_op", dec_mxif_on.alu_op, ALU_ADD);
    check_field("op2_is_imm", dec_mxif_on.op2_is_imm, 1'b1);
    check_field("imm", dec_mxif_on.imm, {{52{1'b0}}, 12'h7FF});

    cur_test = "addi/negative-imm";
    instr = enc_i(12'hFFF, 5'd5, 3'b000, 5'd6, OP_IMM); #1;   // imm = -1
    check_field("imm", dec_mxif_on.imm, 64'hFFFF_FFFF_FFFF_FFFF);

    cur_test = "slli"; named("slli");
    instr = enc_i({6'b000000, 6'd3}, 5'd5, 3'b001, 5'd6, OP_IMM); #1;
    check_field("alu_op", dec_mxif_on.alu_op, ALU_SLL);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "slti"; named("slti");
    instr = enc_i(12'h001, 5'd5, 3'b010, 5'd6, OP_IMM); #1;
    check_field("alu_op", dec_mxif_on.alu_op, ALU_SLT);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "sltiu"; named("sltiu");
    instr = enc_i(12'h001, 5'd5, 3'b011, 5'd6, OP_IMM); #1;
    check_field("alu_op", dec_mxif_on.alu_op, ALU_SLTU);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "xori"; named("xori");
    instr = enc_i(12'hFFF, 5'd5, 3'b100, 5'd6, OP_IMM); #1;   // xori rd,rs1,-1 == "not"
    check_field("alu_op", dec_mxif_on.alu_op, ALU_XOR);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "srli"; named("srli");
    instr = enc_i({7'b0000000, 5'd7}, 5'd5, 3'b101, 5'd6, OP_IMM); #1;
    check_field("alu_op", dec_mxif_on.alu_op, ALU_SRL);

    cur_test = "srai"; named("srai");
    instr = enc_i({7'b0100000, 5'd7}, 5'd5, 3'b101, 5'd6, OP_IMM); #1;
    check_field("alu_op", dec_mxif_on.alu_op, ALU_SRA);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "ori"; named("ori");
    instr = enc_i(12'h0F0, 5'd5, 3'b110, 5'd6, OP_IMM); #1;
    check_field("alu_op", dec_mxif_on.alu_op, ALU_OR);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "andi"; named("andi");
    instr = enc_i(12'h0F0, 5'd5, 3'b111, 5'd6, OP_IMM); #1;
    check_field("alu_op", dec_mxif_on.alu_op, ALU_AND);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "auipc"; named("auipc");
    instr = enc_u(20'h00001, 5'd9, OP_AUIPC); #1;
    expect_common(UNIT_ALU, 1'b0, 1'b1, 1'b0, 1'b0);
    check_field("alu_op", dec_mxif_on.alu_op, ALU_ADD);
    check_field("op1_is_pc", dec_mxif_on.op1_is_pc, 1'b1);
    check_field("op2_is_imm", dec_mxif_on.op2_is_imm, 1'b1);
    check_field("imm", dec_mxif_on.imm, 64'h0000_0000_0000_1000);

    cur_test = "sb"; named("sb");
    instr = enc_s(12'h000, 5'd12, 5'd10, 3'b000, OP_STORE); #1;
    expect_common(UNIT_LSU, 1'b0, 1'b0, 1'b1, 1'b1);
    check_field("is_store", dec_mxif_on.is_store, 1'b1);
    check_field("mem_size", dec_mxif_on.mem_size, LS_BYTE);

    cur_test = "sh"; named("sh");
    instr = enc_s(12'h000, 5'd12, 5'd10, 3'b001, OP_STORE); #1;
    check_field("mem_size", dec_mxif_on.mem_size, LS_HALF);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "sw"; named("sw");
    instr = enc_s(12'h000, 5'd12, 5'd10, 3'b010, OP_STORE); #1;
    check_field("mem_size", dec_mxif_on.mem_size, LS_WORD);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "STORE/reserved-funct3-111";
    instr = enc_s(12'h000, 5'd12, 5'd10, 3'b111, OP_STORE); #1;
    check_field("illegal", dec_mxif_on.illegal, 1'b1);

    cur_test = "add"; named("add");
    instr = enc_r(7'b0000000, 5'd3, 5'd2, 3'b000, 5'd1, OP_OP); #1;
    expect_common(UNIT_ALU, 1'b0, 1'b1, 1'b1, 1'b1);
    check_field("alu_op", dec_mxif_on.alu_op, ALU_ADD);
    check_field("op2_is_imm", dec_mxif_on.op2_is_imm, 1'b0);
    check_field("rd",  dec_mxif_on.rd,  5'd1);
    check_field("rs1", dec_mxif_on.rs1, 5'd2);
    check_field("rs2", dec_mxif_on.rs2, 5'd3);

    cur_test = "sub"; named("sub");
    instr = enc_r(7'b0100000, 5'd3, 5'd2, 3'b000, 5'd1, OP_OP); #1;
    check_field("alu_op", dec_mxif_on.alu_op, ALU_SUB);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "sll"; named("sll");
    instr = enc_r(7'b0000000, 5'd3, 5'd2, 3'b001, 5'd1, OP_OP); #1;
    check_field("alu_op", dec_mxif_on.alu_op, ALU_SLL);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "slt"; named("slt");
    instr = enc_r(7'b0000000, 5'd3, 5'd2, 3'b010, 5'd1, OP_OP); #1;
    check_field("alu_op", dec_mxif_on.alu_op, ALU_SLT);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "sltu"; named("sltu");
    instr = enc_r(7'b0000000, 5'd3, 5'd2, 3'b011, 5'd1, OP_OP); #1;
    check_field("alu_op", dec_mxif_on.alu_op, ALU_SLTU);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "xor"; named("xor");
    instr = enc_r(7'b0000000, 5'd3, 5'd2, 3'b100, 5'd1, OP_OP); #1;
    check_field("alu_op", dec_mxif_on.alu_op, ALU_XOR);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "srl"; named("srl");
    instr = enc_r(7'b0000000, 5'd3, 5'd2, 3'b101, 5'd1, OP_OP); #1;
    check_field("alu_op", dec_mxif_on.alu_op, ALU_SRL);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "sra"; named("sra");
    instr = enc_r(7'b0100000, 5'd3, 5'd2, 3'b101, 5'd1, OP_OP); #1;
    check_field("alu_op", dec_mxif_on.alu_op, ALU_SRA);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "or"; named("or");
    instr = enc_r(7'b0000000, 5'd3, 5'd2, 3'b110, 5'd1, OP_OP); #1;
    check_field("alu_op", dec_mxif_on.alu_op, ALU_OR);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "and"; named("and");
    instr = enc_r(7'b0000000, 5'd3, 5'd2, 3'b111, 5'd1, OP_OP); #1;
    check_field("alu_op", dec_mxif_on.alu_op, ALU_AND);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "OP/reserved-funct7-0000010";
    instr = enc_r(7'b0000010, 5'd3, 5'd2, 3'b000, 5'd1, OP_OP); #1;
    expect_common(UNIT_NONE, 1'b1, 1'b0, 1'b0, 1'b0);

    cur_test = "OP/reserved-0100000-on-SLL";
    // 0100000 is only a legal alternate for funct3 000/101; on SLL (001) it's reserved.
    instr = enc_r(7'b0100000, 5'd3, 5'd2, 3'b001, 5'd1, OP_OP); #1;
    check_field("illegal", dec_mxif_on.illegal, 1'b1);

    cur_test = "lui"; named("lui");
    instr = enc_u(20'hABCDE, 5'd9, OP_LUI); #1;
    expect_common(UNIT_ALU, 1'b0, 1'b1, 1'b0, 1'b0);
    check_field("alu_op", dec_mxif_on.alu_op, ALU_PASS_B);
    check_field("op1_is_pc", dec_mxif_on.op1_is_pc, 1'b0);
    check_field("imm", dec_mxif_on.imm, {{32{1'b1}}, 20'hABCDE, 12'h0});  // sign-extended, top imm bit is 1

    cur_test = "beq"; named("beq");
    instr = enc_b(13'sd8, 5'd6, 5'd5, 3'b000, OP_BRANCH); #1;
    expect_common(UNIT_ALU, 1'b0, 1'b0, 1'b1, 1'b1);
    check_field("is_branch", dec_mxif_on.is_branch, 1'b1);
    check_field("cmp_op", dec_mxif_on.cmp_op, CMP_EQ);
    check_field("op1_is_pc", dec_mxif_on.op1_is_pc, 1'b0);   // comparator reads rs1/rs2 raw
    check_field("op2_is_imm", dec_mxif_on.op2_is_imm, 1'b0);
    check_field("imm", dec_mxif_on.imm, 64'd8);

    cur_test = "bne"; named("bne");
    instr = enc_b(13'sd8, 5'd6, 5'd5, 3'b001, OP_BRANCH); #1;
    check_field("cmp_op", dec_mxif_on.cmp_op, CMP_NE);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "blt"; named("blt");
    instr = enc_b(13'sd8, 5'd6, 5'd5, 3'b100, OP_BRANCH); #1;
    check_field("cmp_op", dec_mxif_on.cmp_op, CMP_LT);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "bge"; named("bge");
    instr = enc_b(13'sd8, 5'd6, 5'd5, 3'b101, OP_BRANCH); #1;
    check_field("cmp_op", dec_mxif_on.cmp_op, CMP_GE);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "bltu"; named("bltu");
    instr = enc_b(13'sd8, 5'd6, 5'd5, 3'b110, OP_BRANCH); #1;
    check_field("cmp_op", dec_mxif_on.cmp_op, CMP_LTU);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "bgeu"; named("bgeu");
    instr = enc_b(13'sd8, 5'd6, 5'd5, 3'b111, OP_BRANCH); #1;
    check_field("cmp_op", dec_mxif_on.cmp_op, CMP_GEU);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "BRANCH/reserved-funct3-010";
    instr = enc_b(13'sd8, 5'd6, 5'd5, 3'b010, OP_BRANCH); #1;
    check_field("illegal", dec_mxif_on.illegal, 1'b1);
    check_field("is_branch", dec_mxif_on.is_branch, 1'b0);

    cur_test = "jalr"; named("jalr");
    instr = enc_i(12'h004, 5'd2, 3'b000, 5'd1, OP_JALR); #1;
    expect_common(UNIT_ALU, 1'b0, 1'b1, 1'b1, 1'b0);
    check_field("is_jalr", dec_mxif_on.is_jalr, 1'b1);
    check_field("op1_is_pc", dec_mxif_on.op1_is_pc, 1'b0);
    check_field("alu_op", dec_mxif_on.alu_op, ALU_ADD);

    cur_test = "JALR/reserved-funct3";
    instr = enc_i(12'h004, 5'd2, 3'b001, 5'd1, OP_JALR); #1;
    check_field("illegal", dec_mxif_on.illegal, 1'b1);

    cur_test = "jal"; named("jal");
    instr = enc_j(21'sd16, 5'd1, OP_JAL); #1;
    expect_common(UNIT_ALU, 1'b0, 1'b1, 1'b0, 1'b0);
    check_field("is_jal", dec_mxif_on.is_jal, 1'b1);
    check_field("op1_is_pc", dec_mxif_on.op1_is_pc, 1'b1);
    check_field("imm", dec_mxif_on.imm, 64'd16);

    cur_test = "jal/negative-offset";
    instr = enc_j(-21'sd4, 5'd1, OP_JAL); #1;
    check_field("imm", dec_mxif_on.imm, 64'hFFFF_FFFF_FFFF_FFFC);

    // ==========================================================================
    // RV64I extras + 12 instructions.
    // ==========================================================================

    cur_test = "ld"; named("ld");
    instr = enc_i(12'h000, 5'd10, 3'b011, 5'd11, OP_LOAD); #1;
    check_field("mem_size", dec_mxif_on.mem_size, LS_DOUBLE);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "lwu"; named("lwu");
    instr = enc_i(12'h000, 5'd10, 3'b110, 5'd11, OP_LOAD); #1;
    check_field("mem_size", dec_mxif_on.mem_size, LS_WORD);
    check_field("mem_signed", dec_mxif_on.mem_signed, 1'b0);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "addiw"; named("addiw");
    instr = enc_i(12'h010, 5'd5, 3'b000, 5'd6, OP_IMM_32); #1;
    check_field("alu_op", dec_mxif_on.alu_op, ALU_ADDW);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "slliw"; named("slliw");
    instr = enc_i({7'b0000000, 5'd3}, 5'd5, 3'b001, 5'd6, OP_IMM_32); #1;
    check_field("alu_op", dec_mxif_on.alu_op, ALU_SLLW);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "srliw"; named("srliw");
    instr = enc_i({7'b0000000, 5'd3}, 5'd5, 3'b101, 5'd6, OP_IMM_32); #1;
    check_field("alu_op", dec_mxif_on.alu_op, ALU_SRLW);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "sraiw"; named("sraiw");
    instr = enc_i({7'b0100000, 5'd3}, 5'd5, 3'b101, 5'd6, OP_IMM_32); #1;
    check_field("alu_op", dec_mxif_on.alu_op, ALU_SRAW);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "OPIMM32/reserved-funct3-010";
    instr = enc_i(12'h001, 5'd5, 3'b010, 5'd6, OP_IMM_32); #1;
    check_field("illegal", dec_mxif_on.illegal, 1'b1);

    cur_test = "sd"; named("sd");
    instr = enc_s(12'hFF0, 5'd12, 5'd10, 3'b011, OP_STORE); #1;
    expect_common(UNIT_LSU, 1'b0, 1'b0, 1'b1, 1'b1);   // stores never write rd
    check_field("is_store", dec_mxif_on.is_store, 1'b1);
    check_field("mem_size", dec_mxif_on.mem_size, LS_DOUBLE);
    check_field("imm", dec_mxif_on.imm, 64'hFFFF_FFFF_FFFF_FFF0);  // sext(-16)

    cur_test = "addw"; named("addw");
    instr = enc_r(7'b0000000, 5'd3, 5'd2, 3'b000, 5'd1, OP_OP_32); #1;
    check_field("alu_op", dec_mxif_on.alu_op, ALU_ADDW);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "subw"; named("subw");
    instr = enc_r(7'b0100000, 5'd3, 5'd2, 3'b000, 5'd1, OP_OP_32); #1;
    check_field("alu_op", dec_mxif_on.alu_op, ALU_SUBW);

    cur_test = "sllw"; named("sllw");
    instr = enc_r(7'b0000000, 5'd3, 5'd2, 3'b001, 5'd1, OP_OP_32); #1;
    check_field("alu_op", dec_mxif_on.alu_op, ALU_SLLW);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "srlw"; named("srlw");
    instr = enc_r(7'b0000000, 5'd3, 5'd2, 3'b101, 5'd1, OP_OP_32); #1;
    check_field("alu_op", dec_mxif_on.alu_op, ALU_SRLW);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "sraw"; named("sraw");
    instr = enc_r(7'b0100000, 5'd3, 5'd2, 3'b101, 5'd1, OP_OP_32); #1;
    check_field("alu_op", dec_mxif_on.alu_op, ALU_SRAW);

    cur_test = "OP32/reserved-SLTW";
    // funct3 010 has no OP-32 base-ISA meaning.
    instr = enc_r(7'b0000000, 5'd3, 5'd2, 3'b010, 5'd1, OP_OP_32); #1;
    check_field("illegal", dec_mxif_on.illegal, 1'b1);

    // ==========================================================================
    // RVM: 13 instructions (8 base + 5 RV64-only *w forms; mulhw/
    // mulhsuw/mulhuw do not exist).
    // ==========================================================================

    cur_test = "mul"; named("mul");
    instr = enc_r(7'b0000001, 5'd3, 5'd2, 3'b000, 5'd1, OP_OP); #1;
    expect_common(UNIT_MUL, 1'b0, 1'b1, 1'b1, 1'b1);
    check_field("muldiv_op", dec_mxif_on.muldiv_op, MULDIV_MUL);
    check_field("is_mul", dec_mxif_on.is_mul, 1'b1);
    check_field("is_div", dec_mxif_on.is_div, 1'b0);

    cur_test = "mulh"; named("mulh");
    instr = enc_r(7'b0000001, 5'd3, 5'd2, 3'b001, 5'd1, OP_OP); #1;
    check_field("muldiv_op", dec_mxif_on.muldiv_op, MULDIV_MULH);
    check_field("unit", dec_mxif_on.unit, UNIT_MUL);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "mulhsu"; named("mulhsu");
    instr = enc_r(7'b0000001, 5'd3, 5'd2, 3'b010, 5'd1, OP_OP); #1;
    check_field("muldiv_op", dec_mxif_on.muldiv_op, MULDIV_MULHSU);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "mulhu"; named("mulhu");
    instr = enc_r(7'b0000001, 5'd3, 5'd2, 3'b011, 5'd1, OP_OP); #1;
    check_field("muldiv_op", dec_mxif_on.muldiv_op, MULDIV_MULHU);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "div"; named("div");
    instr = enc_r(7'b0000001, 5'd3, 5'd2, 3'b100, 5'd1, OP_OP); #1;
    expect_common(UNIT_DIV, 1'b0, 1'b1, 1'b1, 1'b1);
    check_field("muldiv_op", dec_mxif_on.muldiv_op, MULDIV_DIV);
    check_field("is_div", dec_mxif_on.is_div, 1'b1);

    cur_test = "divu"; named("divu");
    instr = enc_r(7'b0000001, 5'd3, 5'd2, 3'b101, 5'd1, OP_OP); #1;
    check_field("muldiv_op", dec_mxif_on.muldiv_op, MULDIV_DIVU);
    check_field("unit", dec_mxif_on.unit, UNIT_DIV);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "rem"; named("rem");
    instr = enc_r(7'b0000001, 5'd3, 5'd2, 3'b110, 5'd1, OP_OP); #1;
    check_field("muldiv_op", dec_mxif_on.muldiv_op, MULDIV_REM);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "remu"; named("remu");
    instr = enc_r(7'b0000001, 5'd3, 5'd2, 3'b111, 5'd1, OP_OP); #1;
    check_field("muldiv_op", dec_mxif_on.muldiv_op, MULDIV_REMU);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "mulw"; named("mulw");   // RV64M, op=59 decimal == 0111011 == OP_OP_32
    instr = enc_r(7'b0000001, 5'd3, 5'd2, 3'b000, 5'd1, OP_OP_32); #1;
    check_field("muldiv_op", dec_mxif_on.muldiv_op, MULDIV_MULW);
    check_field("unit", dec_mxif_on.unit, UNIT_MUL);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "divw"; named("divw");
    instr = enc_r(7'b0000001, 5'd3, 5'd2, 3'b100, 5'd1, OP_OP_32); #1;
    check_field("muldiv_op", dec_mxif_on.muldiv_op, MULDIV_DIVW);
    check_field("unit", dec_mxif_on.unit, UNIT_DIV);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "divuw"; named("divuw");
    instr = enc_r(7'b0000001, 5'd3, 5'd2, 3'b101, 5'd1, OP_OP_32); #1;
    check_field("muldiv_op", dec_mxif_on.muldiv_op, MULDIV_DIVUW);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "remw"; named("remw");
    instr = enc_r(7'b0000001, 5'd3, 5'd2, 3'b110, 5'd1, OP_OP_32); #1;
    check_field("muldiv_op", dec_mxif_on.muldiv_op, MULDIV_REMW);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "remuw"; named("remuw");
    instr = enc_r(7'b0000001, 5'd3, 5'd2, 3'b111, 5'd1, OP_OP_32); #1;
    check_field("muldiv_op", dec_mxif_on.muldiv_op, MULDIV_REMUW);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "OP32/RVM-reserved-mulhw"; // no mulh/mulhsu/mulhu word forms
    instr = enc_r(7'b0000001, 5'd3, 5'd2, 3'b001, 5'd1, OP_OP_32); #1;
    check_field("illegal", dec_mxif_on.illegal, 1'b1);
    check_field("is_mul", dec_mxif_on.is_mul, 1'b0);
    check_field("is_div", dec_mxif_on.is_div, 1'b0);

    cur_test = "OP32/RVM-reserved-mulhsuw";
    instr = enc_r(7'b0000001, 5'd3, 5'd2, 3'b010, 5'd1, OP_OP_32); #1;
    check_field("illegal", dec_mxif_on.illegal, 1'b1);

    cur_test = "OP32/RVM-reserved-mulhuw";
    instr = enc_r(7'b0000001, 5'd3, 5'd2, 3'b011, 5'd1, OP_OP_32); #1;
    check_field("illegal", dec_mxif_on.illegal, 1'b1);

    // ==========================================================================
    // RV64A -- atomics
    // ==========================================================================

    cur_test = "lr.d"; named("lr.d");
    instr = enc_amo(5'b00010, 1'b0, 1'b0, 5'd0, 5'd10, 3'b011, 5'd11); #1;
    expect_common(UNIT_LSU, 1'b0, 1'b1, 1'b1, 1'b0);   // LR reads no rs2
    check_field("is_amo", dec_mxif_on.is_amo, 1'b1);
    check_field("amo_op", dec_mxif_on.amo_op, AMO_LR);
    check_field("mem_size", dec_mxif_on.mem_size, LS_DOUBLE);

    cur_test = "LR.D/reserved-rs2-nonzero";
    // RVA (riscv-opcodes rv_a::lr.w: "rd rs1 24..20=0 aq rl ...") requires
    // rs2=0 for LR; rs2!=0 is a reserved encoding, not an ordinary LR.
    instr = enc_amo(5'b00010, 1'b0, 1'b0, 5'd3, 5'd10, 3'b011, 5'd11); #1;
    check_field("illegal", dec_mxif_on.illegal, 1'b1);

    cur_test = "sc.w.aqrl"; named("sc.w");
    instr = enc_amo(5'b00011, 1'b1, 1'b1, 5'd12, 5'd10, 3'b010, 5'd11); #1;
    expect_common(UNIT_LSU, 1'b0, 1'b1, 1'b1, 1'b1);   // SC reads rs2 (value to write)
    check_field("amo_op", dec_mxif_on.amo_op, AMO_SC);
    check_field("aq", dec_mxif_on.aq, 1'b1);
    check_field("rl", dec_mxif_on.rl, 1'b1);
    check_field("mem_size", dec_mxif_on.mem_size, LS_WORD);

    cur_test = "amoswap.d"; named("amoswap.d");
    instr = enc_amo(5'b00001, 1'b0, 1'b0, 5'd12, 5'd10, 3'b011, 5'd11); #1;
    check_field("amo_op", dec_mxif_on.amo_op, AMO_SWAP);
    check_field("rs2_re", dec_mxif_on.rs2_re, 1'b1);

    cur_test = "amoadd.d"; named("amoadd.d");
    instr = enc_amo(5'b00000, 1'b0, 1'b0, 5'd12, 5'd10, 3'b011, 5'd11); #1;
    check_field("amo_op", dec_mxif_on.amo_op, AMO_ADD);

    cur_test = "amoxor.d"; named("amoxor.d");
    instr = enc_amo(5'b00100, 1'b0, 1'b0, 5'd12, 5'd10, 3'b011, 5'd11); #1;
    check_field("amo_op", dec_mxif_on.amo_op, AMO_XOR);

    cur_test = "amoand.d"; named("amoand.d");
    instr = enc_amo(5'b01100, 1'b0, 1'b0, 5'd12, 5'd10, 3'b011, 5'd11); #1;
    check_field("amo_op", dec_mxif_on.amo_op, AMO_AND);

    cur_test = "amoor.d"; named("amoor.d");
    instr = enc_amo(5'b01000, 1'b0, 1'b0, 5'd12, 5'd10, 3'b011, 5'd11); #1;
    check_field("amo_op", dec_mxif_on.amo_op, AMO_OR);

    cur_test = "amomin.d"; named("amomin.d");
    instr = enc_amo(5'b10000, 1'b0, 1'b0, 5'd12, 5'd10, 3'b011, 5'd11); #1;
    check_field("amo_op", dec_mxif_on.amo_op, AMO_MIN);

    cur_test = "amomax.d"; named("amomax.d");
    instr = enc_amo(5'b10100, 1'b0, 1'b0, 5'd12, 5'd10, 3'b011, 5'd11); #1;
    check_field("amo_op", dec_mxif_on.amo_op, AMO_MAX);

    cur_test = "amominu.w"; named("amominu.w");
    instr = enc_amo(5'b11000, 1'b0, 1'b0, 5'd12, 5'd10, 3'b010, 5'd11); #1;
    check_field("amo_op", dec_mxif_on.amo_op, AMO_MINU);
    check_field("mem_size", dec_mxif_on.mem_size, LS_WORD);

    cur_test = "amomaxu.w"; named("amomaxu.w");
    instr = enc_amo(5'b11100, 1'b0, 1'b0, 5'd12, 5'd10, 3'b010, 5'd11); #1;
    check_field("amo_op", dec_mxif_on.amo_op, AMO_MAXU);

    cur_test = "AMO/reserved-f5";
    instr = enc_amo(5'b01111, 1'b0, 1'b0, 5'd12, 5'd10, 3'b010, 5'd11); #1;
    check_field("illegal", dec_mxif_on.illegal, 1'b1);

    cur_test = "AMO/reserved-funct3-byte-width";
    instr = enc_amo(5'b00000, 1'b0, 1'b0, 5'd12, 5'd10, 3'b000, 5'd11); #1;
    check_field("illegal", dec_mxif_on.illegal, 1'b1);

    // ==========================================================================
    // MISC-MEM / SYSTEM -- 19 instructions: fence, fence.i, cbo.inval/clean/
    // flush/zero, ecall, ebreak, sret, mret, wfi, dret, sfence.vma,
    // csrrw/rs/rc, csrrwi/rsi/rci.
    // ==========================================================================

    cur_test = "fence"; named("fence");
    instr = enc_fence(4'b0000, 4'b1111, 4'b1111, 3'b000); #1;  // fence iorw, iorw
    expect_common(UNIT_NONE, 1'b0, 1'b0, 1'b0, 1'b0);
    check_field("sys_op", dec_mxif_on.sys_op, SYS_FENCE);

    cur_test = "fence.i"; named("fence.i");
    instr = enc_fence(4'b0000, 4'b0000, 4'b0000, 3'b001); #1;
    check_field("sys_op", dec_mxif_on.sys_op, SYS_FENCE_I);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "cbo.inval"; named("cbo.inval");
    // riscv-opcodes rv_zicbo: "cbo.inval rs1 31..20=0 14..12=2 11..7=0 6..2=0x03".
    instr = {12'h000, 5'd10, 3'b010, 5'b0, OP_MISC_MEM}; #1;
    expect_common(UNIT_LSU, 1'b0, 1'b0, 1'b1, 1'b0);
    check_field("is_cbo", dec_mxif_on.is_cbo, 1'b1);
    check_field("cbo_op", dec_mxif_on.cbo_op, CBO_INVAL);

    cur_test = "cbo.clean"; named("cbo.clean");
    instr = {12'h001, 5'd10, 3'b010, 5'b0, OP_MISC_MEM}; #1;
    check_field("cbo_op", dec_mxif_on.cbo_op, CBO_CLEAN);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "cbo.flush"; named("cbo.flush");
    instr = {12'h002, 5'd10, 3'b010, 5'b0, OP_MISC_MEM}; #1;
    check_field("cbo_op", dec_mxif_on.cbo_op, CBO_FLUSH);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "cbo.zero"; named("cbo.zero");
    instr = {12'h004, 5'd10, 3'b010, 5'b0, OP_MISC_MEM}; #1;
    check_field("cbo_op", dec_mxif_on.cbo_op, CBO_ZERO);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "CBO/reserved-imm12";
    // imm12 values other than 0/1/2/4 under funct3=010 are reserved.
    instr = {12'h003, 5'd10, 3'b010, 5'b0, OP_MISC_MEM}; #1;
    check_field("illegal", dec_mxif_on.illegal, 1'b1);
    check_field("is_cbo", dec_mxif_on.is_cbo, 1'b0);

    cur_test = "CBO/reserved-rd-nonzero";
    // Unlike FENCE, rd IS fixed to 0 for CBO (riscv-opcodes rv_zicbo: "11..7=0").
    instr = {12'h000, 5'd10, 3'b010, 5'd3, OP_MISC_MEM}; #1;
    check_field("illegal", dec_mxif_on.illegal, 1'b1);

    cur_test = "MISCMEM/rs1-nonzero-ignored";
    // riscv-opcodes rv_i::fence: "fm pred succ rs1 14..12=0 rd 6..2=0x03 1..0=3"
    // -- rs1 and rd are named fields, not fixed to 0. They are reserved for
    // future finer-grain fences, and base implementations must ignore them
    // rather than raise illegal instruction.
    instr = {12'b0, 5'd7, 3'b000, 5'b0, OP_MISC_MEM}; #1;
    check_field("illegal", dec_mxif_on.illegal, 1'b0);
    check_field("sys_op", dec_mxif_on.sys_op, SYS_FENCE);

    cur_test = "MISCMEM/rd-nonzero-ignored";
    instr = {12'b0, 5'b0, 3'b000, 5'd7, OP_MISC_MEM}; #1;
    check_field("illegal", dec_mxif_on.illegal, 1'b0);
    check_field("sys_op", dec_mxif_on.sys_op, SYS_FENCE);

    cur_test = "ecall"; named("ecall");
    instr = enc_sys12(12'h000, 5'd0, 5'd0); #1;
    expect_common(UNIT_NONE, 1'b0, 1'b0, 1'b0, 1'b0);
    check_field("sys_op", dec_mxif_on.sys_op, SYS_ECALL);

    cur_test = "ebreak"; named("ebreak");
    instr = enc_sys12(12'h001, 5'd0, 5'd0); #1;
    check_field("sys_op", dec_mxif_on.sys_op, SYS_EBREAK);

    cur_test = "sret"; named("sret");
    instr = enc_sys12(12'h102, 5'd0, 5'd0); #1;
    check_field("sys_op", dec_mxif_on.sys_op, SYS_SRET);

    cur_test = "mret"; named("mret");
    instr = enc_sys12(12'h302, 5'd0, 5'd0); #1;
    check_field("sys_op", dec_mxif_on.sys_op, SYS_MRET);

    cur_test = "wfi"; named("wfi");
    instr = enc_sys12(12'h105, 5'd0, 5'd0); #1;
    check_field("sys_op", dec_mxif_on.sys_op, SYS_WFI);

    cur_test = "dret"; named("dret");
    // riscv-opcodes rv_sdext::dret: "11..7=0 19..15=0 31..20=0x7b2 14..12=0
    // 6..2=0x1C 1..0=3" -- needed for FR-8 (debug exit); legality (must be in
    // Debug Mode) is checked at retire, SPEC 13.
    instr = enc_sys12(12'h7b2, 5'd0, 5'd0); #1;
    check_field("sys_op", dec_mxif_on.sys_op, SYS_DRET);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "DRET/reserved-rs1-nonzero";
    instr = enc_sys12(12'h7b2, 5'd9, 5'd0); #1;
    check_field("illegal", dec_mxif_on.illegal, 1'b1);

    cur_test = "SYSTEM/reserved-imm12";
    instr = enc_sys12(12'hABC, 5'd0, 5'd0); #1;
    check_field("illegal", dec_mxif_on.illegal, 1'b1);

    cur_test = "ECALL/reserved-rd-nonzero";
    // Gap: instr[31:20]==0x000 alone is not sufficient:
    // rs1 and rd must also be 0 (table: "rs1,rd=0"). rd=x5 here must be illegal.
    instr = enc_sys12(12'h000, 5'd0, 5'd5); #1;
    check_field("illegal", dec_mxif_on.illegal, 1'b1);
    check_field("sys_op", dec_mxif_on.sys_op, SYS_NONE);

    cur_test = "MRET/reserved-rs1-nonzero";
    instr = enc_sys12(12'h302, 5'd9, 5'd0); #1;
    check_field("illegal", dec_mxif_on.illegal, 1'b1);

    cur_test = "sfence.vma"; named("sfence.vma");
    // funct7=0001001, rs1=vaddr, rs2=asid, funct3=000, rd=0 (SPEC 10.1's Sv39
    // MMU: satp is writable from v1.0 even though translation is bypassed
    // until Phase 5, so this decode needs to exist now, not later).
    instr = enc_r(7'b0001001, 5'd6, 5'd5, 3'b000, 5'd0, OP_SYSTEM); #1;
    expect_common(UNIT_NONE, 1'b0, 1'b0, 1'b1, 1'b1);
    check_field("sys_op", dec_mxif_on.sys_op, SYS_SFENCE_VMA);

    cur_test = "sfence.vma/rs1=x0-rs2=x0-legal";
    // "sfence.vma x0, x0" (flush everything) is the common case -- rs1/rs2
    // being zero must NOT be confused with them being architecturally fixed.
    instr = enc_r(7'b0001001, 5'd0, 5'd0, 3'b000, 5'd0, OP_SYSTEM); #1;
    check_field("sys_op", dec_mxif_on.sys_op, SYS_SFENCE_VMA);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "SFENCEVMA/reserved-rd-nonzero";
    instr = enc_r(7'b0001001, 5'd6, 5'd5, 3'b000, 5'd3, OP_SYSTEM); #1;
    check_field("illegal", dec_mxif_on.illegal, 1'b1);
    check_field("sys_op", dec_mxif_on.sys_op, SYS_NONE);

    cur_test = "csrrw"; named("csrrw");
    instr = {12'h305, 5'd7, 3'b001, 5'd8, OP_SYSTEM}; #1;  // csrrw x8, mtvec, x7
    expect_common(UNIT_CSR, 1'b0, 1'b1, 1'b1, 1'b0);
    check_field("is_csr", dec_mxif_on.is_csr, 1'b1);
    check_field("csr_op", dec_mxif_on.csr_op, CSR_RW);
    check_field("csr_addr", dec_mxif_on.csr_addr, 12'h305);
    check_field("csr_imm", dec_mxif_on.csr_imm, 1'b0);

    cur_test = "csrrs"; named("csrrs");
    instr = {12'hC00, 5'd0, 3'b010, 5'd5, OP_SYSTEM}; #1;  // csrrs x5, cycle, x0 == "csrr x5, cycle"
    check_field("csr_op", dec_mxif_on.csr_op, CSR_RS);
    check_field("rs1_re", dec_mxif_on.rs1_re, 1'b1);  // still a register read, even though it's x0

    cur_test = "csrrc"; named("csrrc");
    instr = {12'h300, 5'd1, 3'b011, 5'd5, OP_SYSTEM}; #1;
    check_field("csr_op", dec_mxif_on.csr_op, CSR_RC);

    cur_test = "csrrwi"; named("csrrwi");
    instr = {12'h304, 5'd17, 3'b101, 5'd6, OP_SYSTEM}; #1;  // csrrwi x6, mie, 17
    expect_common(UNIT_CSR, 1'b0, 1'b1, 1'b0, 1'b0);   // rs1 field is uimm, not a register read
    check_field("csr_op", dec_mxif_on.csr_op, CSR_RW);
    check_field("csr_imm", dec_mxif_on.csr_imm, 1'b1);
    check_field("imm", dec_mxif_on.imm, 64'd17);

    cur_test = "csrrsi"; named("csrrsi");
    instr = {12'h304, 5'd1, 3'b110, 5'd6, OP_SYSTEM}; #1;
    check_field("csr_op", dec_mxif_on.csr_op, CSR_RS);
    check_field("csr_imm", dec_mxif_on.csr_imm, 1'b1);

    cur_test = "csrrci"; named("csrrci");
    instr = {12'h304, 5'd1, 3'b111, 5'd6, OP_SYSTEM}; #1;
    check_field("csr_op", dec_mxif_on.csr_op, CSR_RC);

    cur_test = "SYSTEM/reserved-funct3-100";
    instr = {12'h300, 5'd1, 3'b100, 5'd6, OP_SYSTEM}; #1;
    check_field("illegal", dec_mxif_on.illegal, 1'b1);
    check_field("is_csr", dec_mxif_on.is_csr, 1'b0);

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
    check_field("imm", dec_mxif_on.imm, 64'hFFFF_FFFF_FFFF_FFFF);

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
    check_field("illegal_on",  dec_mxif_on.illegal,  1'b1);
    check_field("illegal_off", dec_mxif_off.illegal, 1'b1);

    // ==========================================================================
    // x0 bookkeeping: decoder does not special-case x0, per s1_pkg.sv note
    // 11.1 -- rd_we may be 1 for rd==0; regfile discards the write.
    // ==========================================================================
    cur_test = "x0-not-special-cased";
    instr = enc_i(12'h001, 5'd0, 3'b000, 5'd0, OP_IMM); #1;  // addi x0, x0, 1
    check_field("rd_we", dec_mxif_on.rd_we, 1'b1);
    check_field("rd",    dec_mxif_on.rd,    5'd0);

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
