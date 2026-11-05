// =============================================================================
// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// Author(s)    : Ayesha Anwar (ayesha.anwaar2005@gmail.com) (Sep,2026)
// Modified By  :
//
// s1_rvc_expand : RV64C 16-bit -> 32-bit instruction expander        [COMPLETE]
// Description  :
// Purely combinational.  Only reserved encodings are illegal; HINTs expand
// normally.  C.FLD/FSD/FLDSP/FSDSP expand to FLD/FSD and are left to decode
// and MXIF (SPEC 7.2).  Details: docs/modules/s1_rvc_expand.md.
//
// Reference: SPEC 7.1; RISC-V Unprivileged ISA "C" chapter, RV64C.
// Testbench: verif/unit/tb_s1_rvc_expand.sv.
// =============================================================================

module s1_rvc_expand
  import s1_pkg::*;
(
  input  logic [CLEN-1:0] instr_i,
  output logic [ILEN-1:0] instr_o,     // don't-care when illegal_o; all-zero today
  output logic            illegal_o    // reserved encoding, or instr_i[1:0] == 2'b11
);

  localparam logic [4:0] REG_ZERO = 5'd0;
  localparam logic [4:0] REG_RA   = 5'd1;
  localparam logic [4:0] REG_SP   = 5'd2;

  // Primed (3-bit) fields address x8..x15.
  logic [4:0] rd, rs2, rdp, rs1p;

  assign rd   = instr_i[11:7];                 // also rs1 in CR/CI formats
  assign rs2  = instr_i[6:2];
  assign rdp  = {2'b01, instr_i[4:2]};         // also rs2' in CL/CS formats
  assign rs1p = {2'b01, instr_i[9:7]};         // also rd' in CB/CA formats

  // Immediates, one per field layout, widened to the 32-bit field they feed.
  logic [11:0] imm_ci;     // sext(imm[5:0])       C.ADDI C.ADDIW C.LI C.ANDI
  logic [11:0] imm_4spn;   // nzuimm[9:2]          C.ADDI4SPN
  logic [11:0] imm_w;      // uimm[6:2]            C.LW C.SW
  logic [11:0] imm_d;      // uimm[7:3]            C.LD C.SD C.FLD C.FSD
  logic [11:0] imm_lwsp;   // uimm[7:2]            C.LWSP
  logic [11:0] imm_ldsp;   // uimm[8:3]            C.LDSP C.FLDSP
  logic [11:0] imm_swsp;   // uimm[7:2]            C.SWSP
  logic [11:0] imm_sdsp;   // uimm[8:3]            C.SDSP C.FSDSP
  logic [11:0] imm_16sp;   // sext(nzimm[9:4])     C.ADDI16SP
  logic [19:0] imm_lui;    // sext(nzimm[17:12])   C.LUI, as the U-type field
  logic [20:1] imm_j;      // sext(offset[11:1])   C.J
  logic [12:1] imm_b;      // sext(offset[8:1])    C.BEQZ C.BNEZ
  logic [5:0]  shamt;      // RV64: full 6 bits    C.SLLI C.SRLI C.SRAI

  assign imm_ci   = {{6{instr_i[12]}}, instr_i[12], instr_i[6:2]};
  assign imm_4spn = {2'b0, instr_i[10:7], instr_i[12:11], instr_i[5], instr_i[6], 2'b0};
  assign imm_w    = {5'b0, instr_i[5], instr_i[12:10], instr_i[6], 2'b0};
  assign imm_d    = {4'b0, instr_i[6:5], instr_i[12:10], 3'b0};
  assign imm_lwsp = {4'b0, instr_i[3:2], instr_i[12], instr_i[6:4], 2'b0};
  assign imm_ldsp = {3'b0, instr_i[4:2], instr_i[12], instr_i[6:5], 3'b0};
  assign imm_swsp = {4'b0, instr_i[8:7], instr_i[12:9], 2'b0};
  assign imm_sdsp = {3'b0, instr_i[9:7], instr_i[12:10], 3'b0};
  assign imm_16sp = {{2{instr_i[12]}}, instr_i[12], instr_i[4:3], instr_i[5], instr_i[2],
                     instr_i[6], 4'b0};
  assign imm_lui  = {{14{instr_i[12]}}, instr_i[12], instr_i[6:2]};
  assign imm_j    = {{9{instr_i[12]}}, instr_i[12], instr_i[8], instr_i[10:9], instr_i[6],
                     instr_i[7], instr_i[2], instr_i[11], instr_i[5:3]};
  assign imm_b    = {{4{instr_i[12]}}, instr_i[12], instr_i[6:5], instr_i[2], instr_i[11:10],
                     instr_i[4:3]};
  assign shamt    = {instr_i[12], instr_i[6:2]};

  // Case on {quadrant, funct3}.  Defaults first (R-C3).
  always_comb begin
    instr_o   = '0;
    illegal_o = 1'b0;

    unique case ({instr_i[1:0], instr_i[15:13]})
      // ---------------------------------------------------------- quadrant 0
      5'b00_000: begin                                                       // C.ADDI4SPN
        instr_o   = {imm_4spn, REG_SP, 3'b000, rdp, OPC_OP_IMM};
        illegal_o = (imm_4spn == '0);         // covers the all-zero parcel
      end
      5'b00_001: instr_o = {imm_d, rs1p, 3'b011, rdp, OPC_LOAD_FP};           // C.FLD
      5'b00_010: instr_o = {imm_w, rs1p, 3'b010, rdp, OPC_LOAD};              // C.LW
      5'b00_011: instr_o = {imm_d, rs1p, 3'b011, rdp, OPC_LOAD};              // C.LD
      5'b00_101: instr_o = {imm_d[11:5], rdp, rs1p, 3'b011, imm_d[4:0], OPC_STORE_FP}; // C.FSD
      5'b00_110: instr_o = {imm_w[11:5], rdp, rs1p, 3'b010, imm_w[4:0], OPC_STORE};    // C.SW
      5'b00_111: instr_o = {imm_d[11:5], rdp, rs1p, 3'b011, imm_d[4:0], OPC_STORE};    // C.SD

      // ---------------------------------------------------------- quadrant 1
      5'b01_000: instr_o = {imm_ci, rd, 3'b000, rd, OPC_OP_IMM};              // C.ADDI, C.NOP
      5'b01_001: begin                                                       // C.ADDIW
        instr_o   = {imm_ci, rd, 3'b000, rd, OPC_OP_IMM_32};
        illegal_o = (rd == REG_ZERO);
      end
      5'b01_010: instr_o = {imm_ci, REG_ZERO, 3'b000, rd, OPC_OP_IMM};        // C.LI
      5'b01_011: begin
        if (rd == REG_SP) begin                                              // C.ADDI16SP
          instr_o   = {imm_16sp, REG_SP, 3'b000, REG_SP, OPC_OP_IMM};
          illegal_o = (imm_16sp == '0);
        end else begin                                                       // C.LUI
          // rd=x0 is a HINT, not reserved; only a zero immediate is reserved.
          instr_o   = {imm_lui, rd, OPC_LUI};
          illegal_o = (imm_lui == '0);
        end
      end
      5'b01_100: begin
        unique case (instr_i[11:10])
          2'b00: instr_o = {6'b000000, shamt, rs1p, 3'b101, rs1p, OPC_OP_IMM};  // C.SRLI
          2'b01: instr_o = {6'b010000, shamt, rs1p, 3'b101, rs1p, OPC_OP_IMM};  // C.SRAI
          2'b10: instr_o = {imm_ci, rs1p, 3'b111, rs1p, OPC_OP_IMM};            // C.ANDI
          2'b11: begin
            unique case ({instr_i[12], instr_i[6:5]})
              3'b000:  instr_o = {7'b0100000, rdp, rs1p, 3'b000, rs1p, OPC_OP};    // C.SUB
              3'b001:  instr_o = {7'b0000000, rdp, rs1p, 3'b100, rs1p, OPC_OP};    // C.XOR
              3'b010:  instr_o = {7'b0000000, rdp, rs1p, 3'b110, rs1p, OPC_OP};    // C.OR
              3'b011:  instr_o = {7'b0000000, rdp, rs1p, 3'b111, rs1p, OPC_OP};    // C.AND
              3'b100:  instr_o = {7'b0100000, rdp, rs1p, 3'b000, rs1p, OPC_OP_32}; // C.SUBW
              3'b101:  instr_o = {7'b0000000, rdp, rs1p, 3'b000, rs1p, OPC_OP_32}; // C.ADDW
              default: illegal_o = 1'b1;                                            // reserved
            endcase
          end
        endcase
      end
      5'b01_101: instr_o = {imm_j[20], imm_j[10:1], imm_j[11], imm_j[19:12],      // C.J
                            REG_ZERO, OPC_JAL};
      5'b01_110,                                                             // C.BEQZ
      5'b01_111: instr_o = {imm_b[12], imm_b[10:5], REG_ZERO, rs1p,          // C.BNEZ
                            {2'b00, instr_i[13]}, imm_b[4:1], imm_b[11], OPC_BRANCH};

      // ---------------------------------------------------------- quadrant 2
      5'b10_000: instr_o = {6'b000000, shamt, rd, 3'b001, rd, OPC_OP_IMM};    // C.SLLI
      5'b10_001: instr_o = {imm_ldsp, REG_SP, 3'b011, rd, OPC_LOAD_FP};       // C.FLDSP
      5'b10_010: begin                                                       // C.LWSP
        instr_o   = {imm_lwsp, REG_SP, 3'b010, rd, OPC_LOAD};
        illegal_o = (rd == REG_ZERO);
      end
      5'b10_011: begin                                                       // C.LDSP
        instr_o   = {imm_ldsp, REG_SP, 3'b011, rd, OPC_LOAD};
        illegal_o = (rd == REG_ZERO);
      end
      5'b10_100: begin
        if (!instr_i[12]) begin
          if (rs2 == REG_ZERO) begin                                         // C.JR
            instr_o   = {12'b0, rd, 3'b000, REG_ZERO, OPC_JALR};
            illegal_o = (rd == REG_ZERO);
          end else begin                                                     // C.MV
            instr_o   = {7'b0000000, rs2, REG_ZERO, 3'b000, rd, OPC_OP};
          end
        end else begin
          if (rd == REG_ZERO && rs2 == REG_ZERO) begin                       // C.EBREAK
            instr_o   = {12'b0000_0000_0001, REG_ZERO, 3'b000, REG_ZERO, OPC_SYSTEM};
          end else if (rs2 == REG_ZERO) begin                                // C.JALR
            instr_o   = {12'b0, rd, 3'b000, REG_RA, OPC_JALR};
          end else begin                                                     // C.ADD
            instr_o   = {7'b0000000, rs2, rd, 3'b000, rd, OPC_OP};
          end
        end
      end
      5'b10_101: instr_o = {imm_sdsp[11:5], rs2, REG_SP, 3'b011, imm_sdsp[4:0], OPC_STORE_FP}; // C.FSDSP
      5'b10_110: instr_o = {imm_swsp[11:5], rs2, REG_SP, 3'b010, imm_swsp[4:0], OPC_STORE};    // C.SWSP
      5'b10_111: instr_o = {imm_sdsp[11:5], rs2, REG_SP, 3'b011, imm_sdsp[4:0], OPC_STORE};    // C.SDSP

      // 00_100 is reserved; 11_xxx is not a compressed instruction at all.
      default:   illegal_o = 1'b1;
    endcase

    // Never hand an illegal parcel's partial expansion downstream.
    if (illegal_o) instr_o = '0;
  end

endmodule
