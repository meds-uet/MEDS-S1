// =============================================================================
// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// Author(s)    : Ayesha Anwar (ayesha.anwaar2005@gmail.com) (Sep,2026)
// Modified By  :
//
// rvc_golden.svh : reference model of RV64C expansion and BTFN    [COMPLETE]
// Description  :
// Testbench-only, `include inside a module.  Written from the ISA manual in a
// different style from the RTL (VERIFICATION_GUIDE.md 3.2).
// =============================================================================

// Base-format encoders
function automatic logic [31:0] g_enc_r(input int f7, input int rs2, input int rs1,
                                        input int f3, input int rd, input int op);
  return {f7[6:0], rs2[4:0], rs1[4:0], f3[2:0], rd[4:0], op[6:0]};
endfunction

function automatic logic [31:0] g_enc_i(input int imm, input int rs1, input int f3,
                                        input int rd, input int op);
  return {imm[11:0], rs1[4:0], f3[2:0], rd[4:0], op[6:0]};
endfunction

function automatic logic [31:0] g_enc_s(input int imm, input int rs2, input int rs1,
                                        input int f3, input int op);
  return {imm[11:5], rs2[4:0], rs1[4:0], f3[2:0], imm[4:0], op[6:0]};
endfunction

function automatic logic [31:0] g_enc_b(input int imm, input int rs2, input int rs1,
                                        input int f3, input int op);
  return {imm[12], imm[10:5], rs2[4:0], rs1[4:0], f3[2:0], imm[4:1], imm[11], op[6:0]};
endfunction

function automatic logic [31:0] g_enc_u(input int imm20, input int rd, input int op);
  return {imm20[19:0], rd[4:0], op[6:0]};
endfunction

function automatic logic [31:0] g_enc_j(input int imm, input int rd, input int op);
  return {imm[20], imm[10:1], imm[11], imm[19:12], rd[4:0], op[6:0]};
endfunction

// c[n] as weight 2^w; immediates below are sums read off the spec tables.
function automatic int g_b(input logic [15:0] c, input int n, input int w);
  return c[n] ? (1 << w) : 0;
endfunction

// Sign-extend the low `bits` bits of v.
function automatic int g_sext(input int v, input int bits);
  int m;
  m = 1 << (bits - 1);
  return ((v & ((1 << bits) - 1)) ^ m) - m;
endfunction

// Returns {illegal, instr32}; c[1:0]==11 is illegal.
function automatic logic [32:0] rvc_golden(input logic [15:0] c);
  int q, f3, rd, rs2, rdp, rs1p, rs2p, imm, sh;
  logic [31:0] e;
  logic        ill;

  // Not taken from s1_pkg, so a typo there cannot hide here.
  localparam int OP_LOAD = 'h03, OP_LOAD_FP = 'h07, OP_IMM = 'h13, OP_IMM32 = 'h1B;
  localparam int OP_STORE = 'h23, OP_STORE_FP = 'h27, OP_OP = 'h33, OP_LUI = 'h37;
  localparam int OP_OP32 = 'h3B, OP_BRANCH = 'h63, OP_JALR = 'h67, OP_JAL = 'h6F;
  localparam int OP_SYSTEM = 'h73;

  q    = int'(c[1:0]);
  f3   = int'(c[15:13]);
  rd   = int'(c[11:7]);           // also rs1 in the CR/CI formats
  rs2  = int'(c[6:2]);
  rdp  = 8 + int'(c[4:2]);        // x8..x15
  rs1p = 8 + int'(c[9:7]);
  rs2p = rdp;
  ill  = 1'b0;
  e    = '0;

  if (q == 3) return {1'b1, 32'h0};

  case (q * 8 + f3)
    // ------------------------------------------------------------ quadrant 0
    0: begin  // C.ADDI4SPN  nzuimm[5:4|9:6|2|3] at c[12:5]
      imm = g_b(c,12,5) + g_b(c,11,4) + g_b(c,10,9) + g_b(c,9,8) + g_b(c,8,7)
          + g_b(c,7,6)  + g_b(c,6,2)  + g_b(c,5,3);
      ill = (imm == 0);                            // includes the all-zero word
      e   = g_enc_i(imm, 2, 0, rdp, OP_IMM);
    end
    1: begin  // C.FLD   uimm[5:3] at 12:10, uimm[7:6] at 6:5
      imm = g_b(c,12,5) + g_b(c,11,4) + g_b(c,10,3) + g_b(c,6,7) + g_b(c,5,6);
      e   = g_enc_i(imm, rs1p, 3, rdp, OP_LOAD_FP);
    end
    2: begin  // C.LW    uimm[5:3] at 12:10, uimm[2|6] at 6:5
      imm = g_b(c,12,5) + g_b(c,11,4) + g_b(c,10,3) + g_b(c,6,2) + g_b(c,5,6);
      e   = g_enc_i(imm, rs1p, 2, rdp, OP_LOAD);
    end
    3: begin  // C.LD
      imm = g_b(c,12,5) + g_b(c,11,4) + g_b(c,10,3) + g_b(c,6,7) + g_b(c,5,6);
      e   = g_enc_i(imm, rs1p, 3, rdp, OP_LOAD);
    end
    4: ill = 1'b1;                                 // reserved
    5: begin  // C.FSD
      imm = g_b(c,12,5) + g_b(c,11,4) + g_b(c,10,3) + g_b(c,6,7) + g_b(c,5,6);
      e   = g_enc_s(imm, rs2p, rs1p, 3, OP_STORE_FP);
    end
    6: begin  // C.SW
      imm = g_b(c,12,5) + g_b(c,11,4) + g_b(c,10,3) + g_b(c,6,2) + g_b(c,5,6);
      e   = g_enc_s(imm, rs2p, rs1p, 2, OP_STORE);
    end
    7: begin  // C.SD
      imm = g_b(c,12,5) + g_b(c,11,4) + g_b(c,10,3) + g_b(c,6,7) + g_b(c,5,6);
      e   = g_enc_s(imm, rs2p, rs1p, 3, OP_STORE);
    end

    // ------------------------------------------------------------ quadrant 1
    8: begin  // C.ADDI / C.NOP (rd=0 or imm=0 are HINTs, still legal)
      imm = g_sext(g_b(c,12,5) + int'(c[6:2]), 6);
      e   = g_enc_i(imm, rd, 0, rd, OP_IMM);
    end
    9: begin  // C.ADDIW (RV64)
      imm = g_sext(g_b(c,12,5) + int'(c[6:2]), 6);
      ill = (rd == 0);
      e   = g_enc_i(imm, rd, 0, rd, OP_IMM32);
    end
    10: begin // C.LI (rd=0 is a HINT)
      imm = g_sext(g_b(c,12,5) + int'(c[6:2]), 6);
      e   = g_enc_i(imm, 0, 0, rd, OP_IMM);
    end
    11: begin
      if (rd == 2) begin  // C.ADDI16SP  nzimm[9|4|6|8:7|5]
        imm = g_sext(g_b(c,12,9) + g_b(c,6,4) + g_b(c,5,6) + g_b(c,4,8) + g_b(c,3,7)
                     + g_b(c,2,5), 10);
        ill = (imm == 0);
        e   = g_enc_i(imm, 2, 0, 2, OP_IMM);
      end else begin      // C.LUI  nzimm[17|16:12]; rd=0 is a HINT
        imm = g_sext(g_b(c,12,5) + int'(c[6:2]), 6);
        ill = (imm == 0);
        e   = g_enc_u(imm & 'hFFFFF, rd, OP_LUI);
      end
    end
    12: begin
      sh = g_b(c,12,5) + int'(c[6:2]);
      case (int'(c[11:10]))
        0: e = g_enc_i(sh,              rs1p, 5, rs1p, OP_IMM);   // C.SRLI
        1: e = g_enc_i(sh + 'h400,      rs1p, 5, rs1p, OP_IMM);   // C.SRAI
        2: e = g_enc_i(g_sext(sh, 6),   rs1p, 7, rs1p, OP_IMM);   // C.ANDI
        default: begin
          case (int'({c[12], c[6:5]}))
            0: e = g_enc_r('h20, rs2p, rs1p, 0, rs1p, OP_OP);     // C.SUB
            1: e = g_enc_r('h00, rs2p, rs1p, 4, rs1p, OP_OP);     // C.XOR
            2: e = g_enc_r('h00, rs2p, rs1p, 6, rs1p, OP_OP);     // C.OR
            3: e = g_enc_r('h00, rs2p, rs1p, 7, rs1p, OP_OP);     // C.AND
            4: e = g_enc_r('h20, rs2p, rs1p, 0, rs1p, OP_OP32);   // C.SUBW
            5: e = g_enc_r('h00, rs2p, rs1p, 0, rs1p, OP_OP32);   // C.ADDW
            default: ill = 1'b1;                                  // reserved
          endcase
        end
      endcase
    end
    13: begin // C.J  offset[11|4|9:8|10|6|7|3:1|5]
      imm = g_sext(g_b(c,12,11) + g_b(c,11,4) + g_b(c,10,9) + g_b(c,9,8) + g_b(c,8,10)
                   + g_b(c,7,6) + g_b(c,6,7) + g_b(c,5,3) + g_b(c,4,2) + g_b(c,3,1)
                   + g_b(c,2,5), 12);
      e   = g_enc_j(imm, 0, OP_JAL);
    end
    14, 15: begin // C.BEQZ / C.BNEZ  offset[8|4:3] at 12:10, [7:6|2:1|5] at 6:2
      imm = g_sext(g_b(c,12,8) + g_b(c,11,4) + g_b(c,10,3) + g_b(c,6,7) + g_b(c,5,6)
                   + g_b(c,4,2) + g_b(c,3,1) + g_b(c,2,5), 9);
      e   = g_enc_b(imm, 0, rs1p, (f3 == 7) ? 1 : 0, OP_BRANCH);
    end

    // ------------------------------------------------------------ quadrant 2
    16: begin // C.SLLI (rd=0 and shamt=0 are HINTs)
      sh = g_b(c,12,5) + int'(c[6:2]);
      e  = g_enc_i(sh, rd, 1, rd, OP_IMM);
    end
    17: begin // C.FLDSP  uimm[5] at 12, uimm[4:3|8:6] at 6:2
      imm = g_b(c,12,5) + g_b(c,6,4) + g_b(c,5,3) + g_b(c,4,8) + g_b(c,3,7) + g_b(c,2,6);
      e   = g_enc_i(imm, 2, 3, rd, OP_LOAD_FP);
    end
    18: begin // C.LWSP   uimm[5] at 12, uimm[4:2|7:6] at 6:2
      imm = g_b(c,12,5) + g_b(c,6,4) + g_b(c,5,3) + g_b(c,4,2) + g_b(c,3,7) + g_b(c,2,6);
      ill = (rd == 0);
      e   = g_enc_i(imm, 2, 2, rd, OP_LOAD);
    end
    19: begin // C.LDSP
      imm = g_b(c,12,5) + g_b(c,6,4) + g_b(c,5,3) + g_b(c,4,8) + g_b(c,3,7) + g_b(c,2,6);
      ill = (rd == 0);
      e   = g_enc_i(imm, 2, 3, rd, OP_LOAD);
    end
    20: begin
      if (c[12] == 1'b0) begin
        if (rs2 == 0) begin     // C.JR
          ill = (rd == 0);
          e   = g_enc_i(0, rd, 0, 0, OP_JALR);
        end else begin          // C.MV (rd=0 is a HINT)
          e   = g_enc_r(0, rs2, 0, 0, rd, OP_OP);
        end
      end else begin
        if (rd == 0 && rs2 == 0) e = g_enc_i(1, 0, 0, 0, OP_SYSTEM);   // C.EBREAK
        else if (rs2 == 0)       e = g_enc_i(0, rd, 0, 1, OP_JALR);    // C.JALR
        else                     e = g_enc_r(0, rs2, rd, 0, rd, OP_OP); // C.ADD
      end
    end
    21: begin // C.FSDSP  uimm[5:3|8:6] at 12:7
      imm = g_b(c,12,5) + g_b(c,11,4) + g_b(c,10,3) + g_b(c,9,8) + g_b(c,8,7) + g_b(c,7,6);
      e   = g_enc_s(imm, rs2, 2, 3, OP_STORE_FP);
    end
    22: begin // C.SWSP   uimm[5:2|7:6] at 12:7
      imm = g_b(c,12,5) + g_b(c,11,4) + g_b(c,10,3) + g_b(c,9,2) + g_b(c,8,7) + g_b(c,7,6);
      e   = g_enc_s(imm, rs2, 2, 2, OP_STORE);
    end
    23: begin // C.SDSP
      imm = g_b(c,12,5) + g_b(c,11,4) + g_b(c,10,3) + g_b(c,9,8) + g_b(c,8,7) + g_b(c,7,6);
      e   = g_enc_s(imm, rs2, 2, 3, OP_STORE);
    end
    default: ill = 1'b1;
  endcase

  return {ill, ill ? 32'h0 : e};
endfunction

// BTFN on an expanded instruction: {taken, offset}.  JAL always taken, JALR never.
function automatic logic [64:0] btfn_golden(input logic [31:0] i);
  longint off;
  if (i[6:0] == 7'h63) begin
    off = longint'($signed({i[31], i[7], i[30:25], i[11:8], 1'b0}));
    return {off < 0, off};
  end
  if (i[6:0] == 7'h6F) begin
    off = longint'($signed({i[31], i[19:12], i[20], i[30:21], 1'b0}));
    return {1'b1, off};
  end
  return {1'b0, 64'h0};
endfunction
