// =============================================================================
// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// Author(s)    : Ammarah Wakeel (ammarahwakeel9@gmail.com) (Aug,2026)
// Modified By  :
//
// s1_decode    : ID-stage instruction decoder
// Description  :
// Purely combinational.  Takes one 32-bit, already-C-expanded instruction
// (SPEC section 7.1,everything downstream of IF/ID sees only 32-bit
// encodings) and produces one decoded_op_t control bundle (SPEC section 7.2,
// s1_pkg.sv).
//
// =============================================================================

module s1_decode
  import s1_pkg::*;
#(
  // Whether a coprocessor is attached at all (soc.yaml MXIF_EN, SPEC 5.3's
  // per-config MXIF column).  With this clear, every unrecognised opcode is
  // illegal instead of an MXIF candidate -- SPEC 7.2 design note.
  parameter bit MXIF_EN = 1'b1
) (
  input  logic [ILEN-1:0] instr_i,
  input  logic [XLEN-1:0] pc_i,

  output decoded_op_t     decoded_o
);

  // ---------------------------------------------------------------------------
  // Opcode-map constants (RV64IMAC_Zicsr_Zifencei).
  // ---------------------------------------------------------------------------
  localparam logic [6:0] OP_LOAD     = 7'b000_0011;
  localparam logic [6:0] OP_MISC_MEM = 7'b000_1111;
  localparam logic [6:0] OP_IMM      = 7'b001_0011;
  localparam logic [6:0] OP_AUIPC    = 7'b001_0111;
  localparam logic [6:0] OP_IMM_32   = 7'b001_1011;
  localparam logic [6:0] OP_STORE    = 7'b010_0011;
  localparam logic [6:0] OP_AMO      = 7'b010_1111;
  localparam logic [6:0] OP_OP       = 7'b011_0011;
  localparam logic [6:0] OP_LUI      = 7'b011_0111;
  localparam logic [6:0] OP_OP_32    = 7'b011_1011;
  localparam logic [6:0] OP_BRANCH   = 7'b110_0011;
  localparam logic [6:0] OP_JALR     = 7'b110_0111;
  localparam logic [6:0] OP_JAL      = 7'b110_1111;
  localparam logic [6:0] OP_SYSTEM   = 7'b111_0011;

  // funct7 values that pick a second meaning for an OP/OP-IMM/OP-32 funct3.
  localparam logic [6:0] FUNCT7_ALT     = 7'b010_0000;  // SUB/SRA/SUBW/SRAW
  localparam logic [6:0] FUNCT7_MULDIV  = 7'b000_0001;  // RV64M, in OP and OP-32

  // ---------------------------------------------------------------------------
  // Field extraction.
  // ---------------------------------------------------------------------------
  logic [6:0] opcode;
  logic [2:0] funct3;
  logic [6:0] funct7;
  logic [4:0] rd_f, rs1_f, rs2_f;

  assign opcode = instr_i[6:0];
  assign funct3 = instr_i[14:12];
  assign funct7 = instr_i[31:25];
  assign rd_f   = instr_i[11:7];
  assign rs1_f  = instr_i[19:15];
  assign rs2_f  = instr_i[24:20];

  // Immediates, sign-extended to XLEN.  Standard RV64 formulas: each replicates
  // instr_i[31] up to the low bit the format actually encodes.
  logic [XLEN-1:0] imm_i, imm_s, imm_b, imm_u, imm_j;

  assign imm_i = {{52{instr_i[31]}}, instr_i[31:20]};
  assign imm_s = {{52{instr_i[31]}}, instr_i[31:25], instr_i[11:7]};
  assign imm_b = {{51{instr_i[31]}}, instr_i[31], instr_i[7],
                  instr_i[30:25], instr_i[11:8], 1'b0};
  assign imm_u = {{32{instr_i[31]}}, instr_i[31:12], 12'b0};
  assign imm_j = {{43{instr_i[31]}}, instr_i[31], instr_i[19:12],
                  instr_i[20], instr_i[30:21], 1'b0};

  // ---------------------------------------------------------------------------
  // Classification.  One always_comb, one struct, default-first.
  // ---------------------------------------------------------------------------
  always_comb begin
    decoded_o          = '0;
    decoded_o.unit      = UNIT_NONE;
    decoded_o.illegal   = 1'b1;
    decoded_o.cmp_op    = CMP_NONE;
    decoded_o.alu_op    = ALU_ADD;
    decoded_o.mem_size  = LS_WORD;
    decoded_o.amo_op    = AMO_NONE;
    decoded_o.cbo_op    = CBO_NONE;
    decoded_o.muldiv_op = MULDIV_NONE;
    decoded_o.csr_op    = CSR_NONE;
    decoded_o.sys_op    = SYS_NONE;
    decoded_o.rs1       = rs1_f;
    decoded_o.rs2       = rs2_f;
    decoded_o.rd        = rd_f;
    decoded_o.pc        = pc_i;
    decoded_o.instr     = instr_i;

    unique case (opcode)

      // -- OP: register-register ALU, or RV64M when funct7 == FUNCT7_MULDIV --
      OP_OP: begin
        decoded_o.rs1_re = 1'b1;
        decoded_o.rs2_re = 1'b1;
        decoded_o.rd_we  = 1'b1;
        if (funct7 == FUNCT7_MULDIV) begin
          decoded_o.unit    = funct3[2] ? UNIT_DIV : UNIT_MUL;
          decoded_o.is_mul  = ~funct3[2];
          decoded_o.is_div  = funct3[2];
          decoded_o.illegal = 1'b0;
          unique case (funct3)
            3'b000: decoded_o.muldiv_op = MULDIV_MUL;
            3'b001: decoded_o.muldiv_op = MULDIV_MULH;
            3'b010: decoded_o.muldiv_op = MULDIV_MULHSU;
            3'b011: decoded_o.muldiv_op = MULDIV_MULHU;
            3'b100: decoded_o.muldiv_op = MULDIV_DIV;
            3'b101: decoded_o.muldiv_op = MULDIV_DIVU;
            3'b110: decoded_o.muldiv_op = MULDIV_REM;
            3'b111: decoded_o.muldiv_op = MULDIV_REMU;
          endcase
        end else if (funct7 == 7'b000_0000) begin
          decoded_o.unit    = UNIT_ALU;
          decoded_o.illegal = 1'b0;
          unique case (funct3)
            3'b000: decoded_o.alu_op = ALU_ADD;
            3'b001: decoded_o.alu_op = ALU_SLL;
            3'b010: decoded_o.alu_op = ALU_SLT;
            3'b011: decoded_o.alu_op = ALU_SLTU;
            3'b100: decoded_o.alu_op = ALU_XOR;
            3'b101: decoded_o.alu_op = ALU_SRL;
            3'b110: decoded_o.alu_op = ALU_OR;
            3'b111: decoded_o.alu_op = ALU_AND;
          endcase
        end else if (funct7 == FUNCT7_ALT && (funct3 == 3'b000 || funct3 == 3'b101)) begin
          decoded_o.unit    = UNIT_ALU;
          decoded_o.illegal = 1'b0;
          decoded_o.alu_op  = (funct3 == 3'b000) ? ALU_SUB : ALU_SRA;
        end else begin
          decoded_o.rs1_re = 1'b0;
          decoded_o.rs2_re = 1'b0;
          decoded_o.rd_we  = 1'b0;
        end
      end

      // -- OP-32: RV64 word ALU forms, or RV64M word forms -------------------
      OP_OP_32: begin
        decoded_o.rs1_re = 1'b1;
        decoded_o.rs2_re = 1'b1;
        decoded_o.rd_we  = 1'b1;
        if (funct7 == FUNCT7_MULDIV) begin
          decoded_o.unit   = (funct3 == 3'b000) ? UNIT_MUL : UNIT_DIV;
          decoded_o.is_mul = (funct3 == 3'b000);
          decoded_o.is_div = (funct3 == 3'b100) || (funct3 == 3'b101) ||
                              (funct3 == 3'b110) || (funct3 == 3'b111);
          unique case (funct3)
            3'b000: begin decoded_o.muldiv_op = MULDIV_MULW;  decoded_o.illegal = 1'b0; end
            3'b100: begin decoded_o.muldiv_op = MULDIV_DIVW;  decoded_o.illegal = 1'b0; end
            3'b101: begin decoded_o.muldiv_op = MULDIV_DIVUW; decoded_o.illegal = 1'b0; end
            3'b110: begin decoded_o.muldiv_op = MULDIV_REMW;  decoded_o.illegal = 1'b0; end
            3'b111: begin decoded_o.muldiv_op = MULDIV_REMUW; decoded_o.illegal = 1'b0; end
            default: begin
              decoded_o.rs1_re = 1'b0; decoded_o.rs2_re = 1'b0; decoded_o.rd_we = 1'b0;
              decoded_o.is_mul = 1'b0; decoded_o.is_div = 1'b0;
            end
          endcase
        end else if (funct7 == 7'b000_0000 &&
                     (funct3 == 3'b000 || funct3 == 3'b001 || funct3 == 3'b101)) begin
          decoded_o.unit    = UNIT_ALU;
          decoded_o.illegal = 1'b0;
          unique case (funct3)
            3'b000: decoded_o.alu_op = ALU_ADDW;
            3'b001: decoded_o.alu_op = ALU_SLLW;
            3'b101: decoded_o.alu_op = ALU_SRLW;
            default: decoded_o.alu_op = ALU_ADDW;  // unreachable: guarded above
          endcase
        end else if (funct7 == FUNCT7_ALT && (funct3 == 3'b000 || funct3 == 3'b101)) begin
          decoded_o.unit    = UNIT_ALU;
          decoded_o.illegal = 1'b0;
          decoded_o.alu_op  = (funct3 == 3'b000) ? ALU_SUBW : ALU_SRAW;
        end else begin
          decoded_o.rs1_re = 1'b0;
          decoded_o.rs2_re = 1'b0;
          decoded_o.rd_we  = 1'b0;
        end
      end

      // -- OP-IMM: register-immediate ALU -------------------------------------
      OP_IMM: begin
        decoded_o.rs1_re     = 1'b1;
        decoded_o.rd_we      = 1'b1;
        decoded_o.unit       = UNIT_ALU;
        decoded_o.imm        = imm_i;
        decoded_o.op2_is_imm = 1'b1;
        decoded_o.illegal    = 1'b0;
                unique case (funct3)
          3'b000: decoded_o.alu_op = ALU_ADD;
          3'b001: begin
            // SLLI: imm_i[11:6] must be 0.
            decoded_o.alu_op = ALU_SLL;
            if (instr_i[31:26] != 6'b000000) decoded_o.illegal = 1'b1;
          end
          3'b010: decoded_o.alu_op = ALU_SLT;
          3'b011: decoded_o.alu_op = ALU_SLTU;
          3'b100: decoded_o.alu_op = ALU_XOR;
          3'b101: begin
            // SRAI/SRLI: imm_i[11:6] must be 010000 (SRAI) or 000000 (SRLI).
            decoded_o.alu_op = instr_i[30] ? ALU_SRA : ALU_SRL;
            if (instr_i[31:26] != (instr_i[30] ? 6'b010000 : 6'b000000))
              decoded_o.illegal = 1'b1;
          end
          3'b110: decoded_o.alu_op = ALU_OR;
          3'b111: decoded_o.alu_op = ALU_AND;
        endcase
      end

      // -- OP-IMM-32: RV64 word register-immediate ALU ------------------------
      OP_IMM_32: begin
        decoded_o.rs1_re     = 1'b1;
        decoded_o.rd_we      = 1'b1;
        decoded_o.unit       = UNIT_ALU;
        decoded_o.imm        = imm_i;
        decoded_o.op2_is_imm = 1'b1;
                unique case (funct3)
          3'b000: begin decoded_o.alu_op = ALU_ADDW; decoded_o.illegal = 1'b0; end
          3'b001: begin
            // SLLIW: shamt is only 5 bits; imm_i[11:5] must be 0.
            decoded_o.alu_op  = ALU_SLLW;
            decoded_o.illegal = (instr_i[31:25] != 7'b0000000);
          end
          3'b101: begin
            // SRAIW/SRLIW: imm_i[11:5] must be 0100000 (SRAIW) or 0000000 (SRLIW).
            decoded_o.alu_op  = instr_i[30] ? ALU_SRAW : ALU_SRLW;
            decoded_o.illegal = (instr_i[31:25] != (instr_i[30] ? 7'b0100000 : 7'b0000000));
          end
          default: begin
            decoded_o.rs1_re = 1'b0;
            decoded_o.rd_we  = 1'b0;
          end
        endcase
      end

      // -- LUI: rd = sext(imm_u) ------------------------------------------------
      OP_LUI: begin
        decoded_o.rd_we      = 1'b1;
        decoded_o.unit       = UNIT_ALU;
        decoded_o.imm        = imm_u;
        decoded_o.op2_is_imm = 1'b1;
        decoded_o.alu_op     = ALU_PASS_B;
        decoded_o.illegal    = 1'b0;
      end

      // -- AUIPC: rd = pc + sext(imm_u) ------------------------------------------
      OP_AUIPC: begin
        decoded_o.rd_we      = 1'b1;
        decoded_o.unit       = UNIT_ALU;
        decoded_o.imm        = imm_u;
        decoded_o.op1_is_pc  = 1'b1;
        decoded_o.op2_is_imm = 1'b1;
        decoded_o.alu_op     = ALU_ADD;
        decoded_o.illegal    = 1'b0;
      end

      // -- JAL: rd = pc+4 (fixed pipeline adder, not this ALU op), target =
      //    pc + sext(imm_j) computed via the same ALU-operand routing AUIPC uses --
      OP_JAL: begin
        decoded_o.rd_we      = 1'b1;
        decoded_o.unit       = UNIT_ALU;
        decoded_o.imm        = imm_j;
        decoded_o.op1_is_pc  = 1'b1;
        decoded_o.op2_is_imm = 1'b1;
        decoded_o.alu_op     = ALU_ADD;
        decoded_o.is_jal     = 1'b1;
        decoded_o.illegal    = 1'b0;
      end

      // -- JALR: rd = pc+4, target = rs1 + sext(imm_i), bit 0 cleared by consumer --
      OP_JALR: begin
        if (funct3 == 3'b000) begin
          decoded_o.rs1_re     = 1'b1;
          decoded_o.rd_we      = 1'b1;
          decoded_o.unit       = UNIT_ALU;
          decoded_o.imm        = imm_i;
          decoded_o.op2_is_imm = 1'b1;
          decoded_o.alu_op     = ALU_ADD;
          decoded_o.is_jalr    = 1'b1;
          decoded_o.illegal    = 1'b0;
        end
      end

      // -- BRANCH: comparator reads rs1/rs2 directly ------------------------------
      OP_BRANCH: begin
        decoded_o.rs1_re    = 1'b1;
        decoded_o.rs2_re    = 1'b1;
        decoded_o.unit      = UNIT_ALU;
        decoded_o.imm       = imm_b;
        decoded_o.is_branch = 1'b1;
        unique case (funct3)
          3'b000: begin decoded_o.cmp_op = CMP_EQ;  decoded_o.illegal = 1'b0; end
          3'b001: begin decoded_o.cmp_op = CMP_NE;  decoded_o.illegal = 1'b0; end
          3'b100: begin decoded_o.cmp_op = CMP_LT;  decoded_o.illegal = 1'b0; end
          3'b101: begin decoded_o.cmp_op = CMP_GE;  decoded_o.illegal = 1'b0; end
          3'b110: begin decoded_o.cmp_op = CMP_LTU; decoded_o.illegal = 1'b0; end
          3'b111: begin decoded_o.cmp_op = CMP_GEU; decoded_o.illegal = 1'b0; end
          default: begin
            decoded_o.rs1_re    = 1'b0;
            decoded_o.rs2_re    = 1'b0;
            decoded_o.is_branch = 1'b0;
          end
        endcase
      end

      // -- LOAD: address = rs1 + sext(imm_i) -------------------------------------
      OP_LOAD: begin
        decoded_o.rs1_re     = 1'b1;
        decoded_o.rd_we      = 1'b1;
        decoded_o.unit       = UNIT_LSU;
        decoded_o.imm        = imm_i;
        decoded_o.op2_is_imm = 1'b1;
        decoded_o.alu_op     = ALU_ADD;
        decoded_o.is_load    = 1'b1;
        unique case (funct3)
          3'b000: begin decoded_o.mem_size = LS_BYTE;   decoded_o.mem_signed = 1'b1; decoded_o.illegal = 1'b0; end  // LB
          3'b001: begin decoded_o.mem_size = LS_HALF;   decoded_o.mem_signed = 1'b1; decoded_o.illegal = 1'b0; end  // LH
          3'b010: begin decoded_o.mem_size = LS_WORD;   decoded_o.mem_signed = 1'b1; decoded_o.illegal = 1'b0; end  // LW
          3'b011: begin decoded_o.mem_size = LS_DOUBLE; decoded_o.mem_signed = 1'b0; decoded_o.illegal = 1'b0; end  // LD
          3'b100: begin decoded_o.mem_size = LS_BYTE;   decoded_o.mem_signed = 1'b0; decoded_o.illegal = 1'b0; end  // LBU
          3'b101: begin decoded_o.mem_size = LS_HALF;   decoded_o.mem_signed = 1'b0; decoded_o.illegal = 1'b0; end  // LHU
          3'b110: begin decoded_o.mem_size = LS_WORD;   decoded_o.mem_signed = 1'b0; decoded_o.illegal = 1'b0; end  // LWU
          default: begin
            decoded_o.rs1_re  = 1'b0;
            decoded_o.rd_we   = 1'b0;
            decoded_o.is_load = 1'b0;
          end
        endcase
      end

      // -- STORE: address = rs1 + sext(imm_s), data = rs2 -------------------------
      OP_STORE: begin
        decoded_o.rs1_re     = 1'b1;
        decoded_o.rs2_re     = 1'b1;
        decoded_o.unit       = UNIT_LSU;
        decoded_o.imm        = imm_s;
        decoded_o.op2_is_imm = 1'b1;
        decoded_o.alu_op     = ALU_ADD;
        decoded_o.is_store   = 1'b1;
        unique case (funct3)
          3'b000: begin decoded_o.mem_size = LS_BYTE;   decoded_o.illegal = 1'b0; end  // SB
          3'b001: begin decoded_o.mem_size = LS_HALF;   decoded_o.illegal = 1'b0; end  // SH
          3'b010: begin decoded_o.mem_size = LS_WORD;   decoded_o.illegal = 1'b0; end  // SW
          3'b011: begin decoded_o.mem_size = LS_DOUBLE; decoded_o.illegal = 1'b0; end  // SD
          default: begin
            decoded_o.rs1_re   = 1'b0;
            decoded_o.rs2_re   = 1'b0;
            decoded_o.is_store = 1'b0;
          end
        endcase
      end

      // -- AMO: RV64A. Address = rs1 (no offset). LR takes no rs2. -----------------
      OP_AMO: begin
        decoded_o.rs1_re = 1'b1;
        decoded_o.rd_we  = 1'b1;
        decoded_o.unit   = UNIT_LSU;
        decoded_o.is_amo = 1'b1;
        decoded_o.aq     = funct7[1];
        decoded_o.rl     = funct7[0];
        if (funct3 == 3'b010 || funct3 == 3'b011) begin
          decoded_o.mem_size = (funct3 == 3'b011) ? LS_DOUBLE : LS_WORD;
          unique case (funct7[6:2])
            5'b00010: begin
              // LR.W/LR.D require rs2=0 (RVA, riscv-opcodes rv_a::lr.w); rs2!=0 is reserved.
              decoded_o.amo_op  = AMO_LR;
              decoded_o.illegal = (rs2_f != 5'b0);
            end
            5'b00011: begin decoded_o.amo_op = AMO_SC;    decoded_o.illegal = 1'b0; end
            5'b00001: begin decoded_o.amo_op = AMO_SWAP;  decoded_o.illegal = 1'b0; end
            5'b00000: begin decoded_o.amo_op = AMO_ADD;   decoded_o.illegal = 1'b0; end
            5'b00100: begin decoded_o.amo_op = AMO_XOR;   decoded_o.illegal = 1'b0; end
            5'b01100: begin decoded_o.amo_op = AMO_AND;   decoded_o.illegal = 1'b0; end
            5'b01000: begin decoded_o.amo_op = AMO_OR;    decoded_o.illegal = 1'b0; end
            5'b10000: begin decoded_o.amo_op = AMO_MIN;   decoded_o.illegal = 1'b0; end
            5'b10100: begin decoded_o.amo_op = AMO_MAX;   decoded_o.illegal = 1'b0; end
            5'b11000: begin decoded_o.amo_op = AMO_MINU;  decoded_o.illegal = 1'b0; end
            5'b11100: begin decoded_o.amo_op = AMO_MAXU;  decoded_o.illegal = 1'b0; end
            default: begin
              decoded_o.rs1_re = 1'b0;
              decoded_o.rd_we  = 1'b0;
            end
          endcase
          decoded_o.rs2_re = ~decoded_o.illegal && (decoded_o.amo_op != AMO_LR);
        end
      end

      // -- MISC-MEM: FENCE / FENCE.I / Zicbom+Zicboz cache-block operations.
      //    FENCE/FENCE.I: rs1 and rd are reserved for future finer-grain
      //    fences (riscv-opcodes rv_i::fence, rv_zifencei::fence.i show them
      //    as unconstrained fields, not fixed to 0)
      //    CBO.*: rd IS hard-fixed to 0
        decoded_o.unit = UNIT_NONE;
        unique case (funct3)
          3'b000: begin decoded_o.sys_op = SYS_FENCE;   decoded_o.illegal = 1'b0; end
          3'b001: begin decoded_o.sys_op = SYS_FENCE_I; decoded_o.illegal = 1'b0; end
          3'b010: begin
            // cbo.inval/clean/flush (Zicbom) and cbo.zero (Zicboz); imm[11:0]
            // selects the operation (riscv-opcodes rv_zicbo).
            if (rd_f == 5'b0) begin
              decoded_o.unit   = UNIT_LSU;
              decoded_o.is_cbo = 1'b1;
              decoded_o.rs1_re = 1'b1;
              unique case (instr_i[31:20])
                12'h000: begin decoded_o.cbo_op = CBO_INVAL; decoded_o.illegal = 1'b0; end
                12'h001: begin decoded_o.cbo_op = CBO_CLEAN; decoded_o.illegal = 1'b0; end
                12'h002: begin decoded_o.cbo_op = CBO_FLUSH; decoded_o.illegal = 1'b0; end
                12'h004: begin decoded_o.cbo_op = CBO_ZERO;  decoded_o.illegal = 1'b0; end
                default: begin
                  decoded_o.unit   = UNIT_NONE;
                  decoded_o.is_cbo = 1'b0;
                  decoded_o.rs1_re = 1'b0;
                end
              endcase
            end
          end
          default: ;  // illegal stays asserted
        endcase
      end

      // -- SYSTEM: Zicsr, or funct3==000 privileged instructions --------------------
      OP_SYSTEM: begin
        decoded_o.unit = UNIT_NONE;
        if (funct3 == 3'b000) begin
          if (funct7 == 7'b0001001) begin
            // SFENCE.VMA rs1=vaddr, rs2=asid (real operands -- not part of a
            // fixed 12-bit pattern the way ECALL/EBREAK/MRET/SRET/WFI are).
            // Only rd is architecturally required to be 0.
            if (rd_f == 5'b0) begin
              decoded_o.sys_op  = SYS_SFENCE_VMA;
              decoded_o.rs1_re  = 1'b1;
              decoded_o.rs2_re  = 1'b1;
              decoded_o.illegal = 1'b0;
            end
          end else if (rs1_f == 5'b0 && rd_f == 5'b0) begin
            unique case (instr_i[31:20])
              12'h000: begin decoded_o.sys_op = SYS_ECALL;  decoded_o.illegal = 1'b0; end
              12'h001: begin decoded_o.sys_op = SYS_EBREAK; decoded_o.illegal = 1'b0; end
              12'h102: begin decoded_o.sys_op = SYS_SRET;   decoded_o.illegal = 1'b0; end  // legality checked at retire, SPEC 10.1
              12'h302: begin decoded_o.sys_op = SYS_MRET;   decoded_o.illegal = 1'b0; end
              12'h105: begin decoded_o.sys_op = SYS_WFI;    decoded_o.illegal = 1'b0; end
              12'h7b2: begin decoded_o.sys_op = SYS_DRET;   decoded_o.illegal = 1'b0; end  // Debug spec; legality (must be in Debug Mode) checked at retire, SPEC 13
              default: ;  // illegal stays asserted
            endcase
          end
        end else begin
          decoded_o.unit     = UNIT_CSR;
          decoded_o.is_csr   = 1'b1;
          decoded_o.rd_we    = 1'b1;
          decoded_o.csr_addr = instr_i[31:20];
          decoded_o.csr_imm  = funct3[2];
          decoded_o.rs1_re   = ~funct3[2];   // register form reads rs1; *I forms reuse the rs1 field as uimm[4:0]
          decoded_o.imm      = {{(XLEN-REG_ADDR_W){1'b0}}, rs1_f};  // zero-extended uimm, valid only when csr_imm=1
          unique case (funct3[1:0])
            2'b01: begin decoded_o.csr_op = CSR_RW; decoded_o.illegal = 1'b0; end
            2'b10: begin decoded_o.csr_op = CSR_RS; decoded_o.illegal = 1'b0; end
            2'b11: begin decoded_o.csr_op = CSR_RC; decoded_o.illegal = 1'b0; end
            default: begin
              decoded_o.unit   = UNIT_NONE;
              decoded_o.is_csr = 1'b0;
              decoded_o.rd_we  = 1'b0;
              decoded_o.rs1_re = 1'b0;
            end
          endcase
        end
      end

      // -- unrecognised opcode: MXIF candidate, or illegal with no coprocessor
      //    attached (SPEC 7.2 design note) -----------------------------------------
      default: begin
        decoded_o.rs1_re = 1'b1;  // offered conservatively; the coprocessor may ignore either
        decoded_o.rs2_re = 1'b1;
        decoded_o.rd_we  = 1'b1;  // CB retire rule (SPEC 9.2) still gates on x_result_valid
        if (MXIF_EN) begin
          decoded_o.unit           = UNIT_MXIF;
          decoded_o.mxif_candidate = 1'b1;
          decoded_o.illegal        = 1'b0;
        end
      end
    endcase

    // Defensive structural check, not an ISA rule: a still-compressed
    // instruction must never reach this module (SPEC 7.1). Any op_class
    // decision above is void if this fires.
    if (instr_i[1:0] != 2'b11) begin
      decoded_o.illegal = 1'b1;
    end
  end

endmodule
