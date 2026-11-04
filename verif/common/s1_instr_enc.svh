// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// s1_instr_enc : RISC-V instruction encoders and opcodes for testbenches
//
// The minimum an assembler would give us: one function per instruction format,
// and the major opcodes by name.  The opcodes are written out here and NOT
// imported from the RTL, so a testbench does not inherit a decoder mistake.
//
// Include inside a testbench module:  `include "verif/common/s1_instr_enc.svh"
// =============================================================================

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
