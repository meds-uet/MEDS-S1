// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// tb_s1_decode_rv64i : RV64I base-ISA decode tests
//
// The 37 RV32I-heritage instructions and the 12 RV64I-only ones (ld, lwu, sd and
// the *w forms), each with the reserved encodings that sit next to it.
//
// Included by verif/unit/tb_s1_decode.sv inside the testbench module; it uses
// that module's DUT outputs, encoders and scoreboard tasks.
// =============================================================================

  task automatic test_rv64i();
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
    expect_unrecognised();
    check_field("is_load", dec_mxif_on.is_load, 1'b0);

    cur_test = "addi"; named("addi");
    instr = enc_i(12'h7FF, 5'd5, 3'b000, 5'd6, OP_IMM); #1;
    expect_common(UNIT_ALU, 1'b0, 1'b1, 1'b1, 1'b0);
    check_field("alu_op", dec_mxif_on.alu_op, ALU_ADD);
    check_field("op2_is_imm", dec_mxif_on.op2_is_imm, 1'b1);
    check_field("imm", dec_mxif_on.imm, XLEN'(12'h7FF));

    cur_test = "addi/negative-imm";
    instr = enc_i(12'hFFF, 5'd5, 3'b000, 5'd6, OP_IMM); #1;   // imm = -1
    check_field("imm", dec_mxif_on.imm, {XLEN{1'b1}});

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
    check_field("imm", dec_mxif_on.imm, XLEN'(13'h1000));

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
    expect_unrecognised();

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
    expect_unrecognised();

    cur_test = "OP/reserved-0100000-on-SLL";
    // 0100000 is only a legal alternate for funct3 000/101; on SLL (001) it's reserved.
    instr = enc_r(7'b0100000, 5'd3, 5'd2, 3'b001, 5'd1, OP_OP); #1;
    expect_unrecognised();

    cur_test = "lui"; named("lui");
    instr = enc_u(20'hABCDE, 5'd9, OP_LUI); #1;
    expect_common(UNIT_ALU, 1'b0, 1'b1, 1'b0, 1'b0);
    check_field("alu_op", dec_mxif_on.alu_op, ALU_PASS_B);
    check_field("op1_is_pc", dec_mxif_on.op1_is_pc, 1'b0);
    check_field("imm", dec_mxif_on.imm, XLEN'($signed({20'hABCDE, 12'h0})));  // sign-extended, top imm bit is 1

    cur_test = "beq"; named("beq");
    instr = enc_b(13'sd8, 5'd6, 5'd5, 3'b000, OP_BRANCH); #1;
    expect_common(UNIT_ALU, 1'b0, 1'b0, 1'b1, 1'b1);
    check_field("is_branch", dec_mxif_on.is_branch, 1'b1);
    check_field("cmp_op", dec_mxif_on.cmp_op, CMP_EQ);
    check_field("op1_is_pc", dec_mxif_on.op1_is_pc, 1'b0);   // comparator reads rs1/rs2 raw
    check_field("op2_is_imm", dec_mxif_on.op2_is_imm, 1'b0);
    check_field("imm", dec_mxif_on.imm, XLEN'(8));

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
    expect_unrecognised();
    check_field("is_branch", dec_mxif_on.is_branch, 1'b0);

    cur_test = "jalr"; named("jalr");
    instr = enc_i(12'h004, 5'd2, 3'b000, 5'd1, OP_JALR); #1;
    expect_common(UNIT_ALU, 1'b0, 1'b1, 1'b1, 1'b0);
    check_field("is_jalr", dec_mxif_on.is_jalr, 1'b1);
    check_field("op1_is_pc", dec_mxif_on.op1_is_pc, 1'b0);
    check_field("alu_op", dec_mxif_on.alu_op, ALU_ADD);

    cur_test = "JALR/reserved-funct3";
    instr = enc_i(12'h004, 5'd2, 3'b001, 5'd1, OP_JALR); #1;
    expect_unrecognised();

    cur_test = "jal"; named("jal");
    instr = enc_j(21'sd16, 5'd1, OP_JAL); #1;
    expect_common(UNIT_ALU, 1'b0, 1'b1, 1'b0, 1'b0);
    check_field("is_jal", dec_mxif_on.is_jal, 1'b1);
    check_field("op1_is_pc", dec_mxif_on.op1_is_pc, 1'b1);
    check_field("imm", dec_mxif_on.imm, XLEN'(16));

    cur_test = "jal/negative-offset";
    instr = enc_j(-21'sd4, 5'd1, OP_JAL); #1;
    check_field("imm", dec_mxif_on.imm, -XLEN'(4));

    // ==========================================================================
    // RV64I extras + 12 instructions.
    // ==========================================================================

    cur_test = "ld"; named("ld");
    instr = enc_i(12'h000, 5'd10, 3'b011, 5'd11, OP_LOAD); #1;
    check_field("mem_size", dec_mxif_on.mem_size, LS_DOUBLE);
    check_field("mem_signed", dec_mxif_on.mem_signed, 1'b1);
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
    expect_unrecognised();

    cur_test = "sd"; named("sd");
    instr = enc_s(12'hFF0, 5'd12, 5'd10, 3'b011, OP_STORE); #1;
    expect_common(UNIT_LSU, 1'b0, 1'b0, 1'b1, 1'b1);   // stores never write rd
    check_field("is_store", dec_mxif_on.is_store, 1'b1);
    check_field("mem_size", dec_mxif_on.mem_size, LS_DOUBLE);
    check_field("imm", dec_mxif_on.imm, -XLEN'(16));  // sext(-16)

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
    expect_unrecognised();
  endtask
