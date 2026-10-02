// =============================================================================
// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// Author(s)    : Ayesha Anwar (ayesha.anwaar2005@gmail.com) (Sep,2026)
// Modified By  :
//
// rv64_golden.svh : reference RV64IMAC_Zicsr_Zifencei decoder             [COMPLETE]
// Description  :
// Testbench-only, `include inside a module that imports s1_pkg.  A mask/match
// table (riscv-opcodes values) drives both a "perfect decoder" producing
// decoded_op_t in s1_decode's documented conventions, and a generator of legal
// encodings (match | random free bits).
// =============================================================================

typedef enum int {
  G_LUI, G_AUIPC, G_JAL, G_JALR,
  G_BEQ, G_BNE, G_BLT, G_BGE, G_BLTU, G_BGEU,
  G_LB, G_LH, G_LW, G_LD, G_LBU, G_LHU, G_LWU,
  G_SB, G_SH, G_SW, G_SD,
  G_ADDI, G_SLTI, G_SLTIU, G_XORI, G_ORI, G_ANDI, G_SLLI, G_SRLI, G_SRAI,
  G_ADD, G_SUB, G_SLL, G_SLT, G_SLTU, G_XOR, G_SRL, G_SRA, G_OR, G_AND,
  G_ADDIW, G_SLLIW, G_SRLIW, G_SRAIW,
  G_ADDW, G_SUBW, G_SLLW, G_SRLW, G_SRAW,
  G_MUL, G_MULH, G_MULHSU, G_MULHU, G_DIV, G_DIVU, G_REM, G_REMU,
  G_MULW, G_DIVW, G_DIVUW, G_REMW, G_REMUW,
  G_LR_W, G_SC_W, G_AMOSWAP_W, G_AMOADD_W, G_AMOXOR_W, G_AMOAND_W, G_AMOOR_W,
  G_AMOMIN_W, G_AMOMAX_W, G_AMOMINU_W, G_AMOMAXU_W,
  G_LR_D, G_SC_D, G_AMOSWAP_D, G_AMOADD_D, G_AMOXOR_D, G_AMOAND_D, G_AMOOR_D,
  G_AMOMIN_D, G_AMOMAX_D, G_AMOMINU_D, G_AMOMAXU_D,
  G_FENCE, G_FENCE_I,
  G_ECALL, G_EBREAK, G_MRET, G_SRET, G_WFI, G_SFENCE_VMA,
  G_CSRRW, G_CSRRS, G_CSRRC, G_CSRRWI, G_CSRRSI, G_CSRRCI,
  // In the ISA, but with no decoded_op_t field to express them (see docs).
  G_DRET, G_CBO_CLEAN, G_CBO_FLUSH, G_CBO_INVAL, G_CBO_ZERO,
  G_NUM,
  G_NONE = -1
} gop_e;

typedef struct packed {
  logic [31:0] mask;
  logic [31:0] match;
} gpat_t;

// Indexed by gop_e.
localparam gpat_t GPAT [G_NUM] = '{
  '{32'h0000007f, 32'h00000037}, '{32'h0000007f, 32'h00000017},   // lui auipc
  '{32'h0000007f, 32'h0000006f}, '{32'h0000707f, 32'h00000067},   // jal jalr
  '{32'h0000707f, 32'h00000063}, '{32'h0000707f, 32'h00001063},   // beq bne
  '{32'h0000707f, 32'h00004063}, '{32'h0000707f, 32'h00005063},   // blt bge
  '{32'h0000707f, 32'h00006063}, '{32'h0000707f, 32'h00007063},   // bltu bgeu
  '{32'h0000707f, 32'h00000003}, '{32'h0000707f, 32'h00001003},   // lb lh
  '{32'h0000707f, 32'h00002003}, '{32'h0000707f, 32'h00003003},   // lw ld
  '{32'h0000707f, 32'h00004003}, '{32'h0000707f, 32'h00005003},   // lbu lhu
  '{32'h0000707f, 32'h00006003},                                   // lwu
  '{32'h0000707f, 32'h00000023}, '{32'h0000707f, 32'h00001023},   // sb sh
  '{32'h0000707f, 32'h00002023}, '{32'h0000707f, 32'h00003023},   // sw sd
  '{32'h0000707f, 32'h00000013}, '{32'h0000707f, 32'h00002013},   // addi slti
  '{32'h0000707f, 32'h00003013}, '{32'h0000707f, 32'h00004013},   // sltiu xori
  '{32'h0000707f, 32'h00006013}, '{32'h0000707f, 32'h00007013},   // ori andi
  '{32'hfc00707f, 32'h00001013}, '{32'hfc00707f, 32'h00005013},   // slli srli
  '{32'hfc00707f, 32'h40005013},                                   // srai
  '{32'hfe00707f, 32'h00000033}, '{32'hfe00707f, 32'h40000033},   // add sub
  '{32'hfe00707f, 32'h00001033}, '{32'hfe00707f, 32'h00002033},   // sll slt
  '{32'hfe00707f, 32'h00003033}, '{32'hfe00707f, 32'h00004033},   // sltu xor
  '{32'hfe00707f, 32'h00005033}, '{32'hfe00707f, 32'h40005033},   // srl sra
  '{32'hfe00707f, 32'h00006033}, '{32'hfe00707f, 32'h00007033},   // or and
  '{32'h0000707f, 32'h0000001b}, '{32'hfe00707f, 32'h0000101b},   // addiw slliw
  '{32'hfe00707f, 32'h0000501b}, '{32'hfe00707f, 32'h4000501b},   // srliw sraiw
  '{32'hfe00707f, 32'h0000003b}, '{32'hfe00707f, 32'h4000003b},   // addw subw
  '{32'hfe00707f, 32'h0000103b}, '{32'hfe00707f, 32'h0000503b},   // sllw srlw
  '{32'hfe00707f, 32'h4000503b},                                   // sraw
  '{32'hfe00707f, 32'h02000033}, '{32'hfe00707f, 32'h02001033},   // mul mulh
  '{32'hfe00707f, 32'h02002033}, '{32'hfe00707f, 32'h02003033},   // mulhsu mulhu
  '{32'hfe00707f, 32'h02004033}, '{32'hfe00707f, 32'h02005033},   // div divu
  '{32'hfe00707f, 32'h02006033}, '{32'hfe00707f, 32'h02007033},   // rem remu
  '{32'hfe00707f, 32'h0200003b}, '{32'hfe00707f, 32'h0200403b},   // mulw divw
  '{32'hfe00707f, 32'h0200503b}, '{32'hfe00707f, 32'h0200603b},   // divuw remw
  '{32'hfe00707f, 32'h0200703b},                                   // remuw
  '{32'hf9f0707f, 32'h1000202f}, '{32'hf800707f, 32'h1800202f},   // lr.w sc.w
  '{32'hf800707f, 32'h0800202f}, '{32'hf800707f, 32'h0000202f},   // amoswap.w amoadd.w
  '{32'hf800707f, 32'h2000202f}, '{32'hf800707f, 32'h6000202f},   // amoxor.w amoand.w
  '{32'hf800707f, 32'h4000202f}, '{32'hf800707f, 32'h8000202f},   // amoor.w amomin.w
  '{32'hf800707f, 32'ha000202f}, '{32'hf800707f, 32'hc000202f},   // amomax.w amominu.w
  '{32'hf800707f, 32'he000202f},                                   // amomaxu.w
  '{32'hf9f0707f, 32'h1000302f}, '{32'hf800707f, 32'h1800302f},   // lr.d sc.d
  '{32'hf800707f, 32'h0800302f}, '{32'hf800707f, 32'h0000302f},   // amoswap.d amoadd.d
  '{32'hf800707f, 32'h2000302f}, '{32'hf800707f, 32'h6000302f},   // amoxor.d amoand.d
  '{32'hf800707f, 32'h4000302f}, '{32'hf800707f, 32'h8000302f},   // amoor.d amomin.d
  '{32'hf800707f, 32'ha000302f}, '{32'hf800707f, 32'hc000302f},   // amomax.d amominu.d
  '{32'hf800707f, 32'he000302f},                                   // amomaxu.d
  '{32'h0000707f, 32'h0000000f}, '{32'h0000707f, 32'h0000100f},   // fence fence.i (fields ignored)
  '{32'hffffffff, 32'h00000073}, '{32'hffffffff, 32'h00100073},   // ecall ebreak
  '{32'hffffffff, 32'h30200073}, '{32'hffffffff, 32'h10200073},   // mret sret
  '{32'hffffffff, 32'h10500073}, '{32'hfe007fff, 32'h12000073},   // wfi sfence.vma
  '{32'h0000707f, 32'h00001073}, '{32'h0000707f, 32'h00002073},   // csrrw csrrs
  '{32'h0000707f, 32'h00003073}, '{32'h0000707f, 32'h00005073},   // csrrc csrrwi
  '{32'h0000707f, 32'h00006073}, '{32'h0000707f, 32'h00007073},   // csrrsi csrrci
  '{32'hffffffff, 32'h7b200073},                                   // dret
  '{32'hfff07fff, 32'h0010200f}, '{32'hfff07fff, 32'h0020200f},   // cbo.clean cbo.flush
  '{32'hfff07fff, 32'h0000200f}, '{32'hfff07fff, 32'h0040200f}    // cbo.inval cbo.zero
};

// Major opcodes the base decoder owns; anything else is an MXIF candidate.
function automatic bit g_known_opcode(input logic [6:0] o);
  return o inside {7'h03, 7'h0f, 7'h13, 7'h17, 7'h1b, 7'h23, 7'h2f,
                   7'h33, 7'h37, 7'h3b, 7'h63, 7'h67, 7'h6f, 7'h73};
endfunction

function automatic gop_e g_classify(input logic [31:0] i);
  for (int k = 0; k < int'(G_NUM); k++)
    if ((i & GPAT[k].mask) == GPAT[k].match) return gop_e'(k);
  return G_NONE;
endfunction

// A legal encoding of `g` with every free bit random.
function automatic logic [31:0] g_encode_random(input gop_e g);
  return GPAT[g].match | ({$urandom} & ~GPAT[g].mask);
endfunction

function automatic logic [63:0] g_imm_i(input logic [31:0] i);
  return 64'($signed(i[31:20]));
endfunction
function automatic logic [63:0] g_imm_s(input logic [31:0] i);
  return 64'($signed({i[31:25], i[11:7]}));
endfunction
function automatic logic [63:0] g_imm_b(input logic [31:0] i);
  return 64'($signed({i[31], i[7], i[30:25], i[11:8], 1'b0}));
endfunction
function automatic logic [63:0] g_imm_u(input logic [31:0] i);
  return 64'($signed({i[31:12], 12'h000}));
endfunction
function automatic logic [63:0] g_imm_j(input logic [31:0] i);
  return 64'($signed({i[31], i[19:12], i[20], i[30:21], 1'b0}));
endfunction

// The perfect decoder.  `gap` flags ISA instructions decoded_op_t cannot
// express; they are returned as illegal.
function automatic decoded_op_t golden_decode(input logic [31:0] i, input logic [63:0] pc,
                                              input bit mxif_en, output bit gap);
  decoded_op_t d;
  gop_e        g;

  d           = '0;
  d.unit      = UNIT_NONE;
  d.illegal   = 1'b1;
  d.cmp_op    = CMP_NONE;
  d.alu_op    = ALU_ADD;
  d.mem_size  = LS_WORD;
  d.amo_op    = AMO_NONE;
  d.muldiv_op = MULDIV_NONE;
  d.csr_op    = CSR_NONE;
  d.sys_op    = SYS_NONE;
  d.rs1       = i[19:15];
  d.rs2       = i[24:20];
  d.rd        = i[11:7];
  d.pc        = pc;
  d.instr     = i;
  gap         = 1'b0;

  if (i[1:0] != 2'b11) return d;
  g = g_classify(i);

  if (g == G_NONE) begin
    if (!g_known_opcode(i[6:0]) && mxif_en) begin
      d.unit = UNIT_MXIF; d.mxif_candidate = 1'b1; d.illegal = 1'b0;
      d.rs1_re = 1'b1; d.rs2_re = 1'b1; d.rd_we = 1'b1;
    end
    return d;
  end
  if (g inside {G_DRET, G_CBO_CLEAN, G_CBO_FLUSH, G_CBO_INVAL, G_CBO_ZERO}) begin
    gap = 1'b1;
    return d;
  end

  d.illegal = 1'b0;
  case (g)
    G_LUI:   begin d.unit = UNIT_ALU; d.rd_we = 1; d.imm = g_imm_u(i); d.op2_is_imm = 1; d.alu_op = ALU_PASS_B; end
    G_AUIPC: begin d.unit = UNIT_ALU; d.rd_we = 1; d.imm = g_imm_u(i); d.op1_is_pc = 1; d.op2_is_imm = 1; end
    G_JAL:   begin d.unit = UNIT_ALU; d.rd_we = 1; d.imm = g_imm_j(i); d.op1_is_pc = 1; d.op2_is_imm = 1; d.is_jal = 1; end
    G_JALR:  begin d.unit = UNIT_ALU; d.rd_we = 1; d.rs1_re = 1; d.imm = g_imm_i(i); d.op2_is_imm = 1; d.is_jalr = 1; end

    G_BEQ, G_BNE, G_BLT, G_BGE, G_BLTU, G_BGEU: begin
      d.unit = UNIT_ALU; d.rs1_re = 1; d.rs2_re = 1; d.imm = g_imm_b(i); d.is_branch = 1;
      d.cmp_op = (g == G_BEQ) ? CMP_EQ : (g == G_BNE) ? CMP_NE : (g == G_BLT) ? CMP_LT :
                 (g == G_BGE) ? CMP_GE : (g == G_BLTU) ? CMP_LTU : CMP_GEU;
    end

    G_LB, G_LH, G_LW, G_LD, G_LBU, G_LHU, G_LWU: begin
      d.unit = UNIT_LSU; d.rs1_re = 1; d.rd_we = 1; d.imm = g_imm_i(i); d.op2_is_imm = 1; d.is_load = 1;
      d.mem_size   = (g inside {G_LB, G_LBU}) ? LS_BYTE : (g inside {G_LH, G_LHU}) ? LS_HALF :
                     (g inside {G_LW, G_LWU}) ? LS_WORD : LS_DOUBLE;
      d.mem_signed = g inside {G_LB, G_LH, G_LW};
    end

    G_SB, G_SH, G_SW, G_SD: begin
      d.unit = UNIT_LSU; d.rs1_re = 1; d.rs2_re = 1; d.imm = g_imm_s(i); d.op2_is_imm = 1; d.is_store = 1;
      d.mem_size = (g == G_SB) ? LS_BYTE : (g == G_SH) ? LS_HALF : (g == G_SW) ? LS_WORD : LS_DOUBLE;
    end

    G_ADDI, G_SLTI, G_SLTIU, G_XORI, G_ORI, G_ANDI, G_SLLI, G_SRLI, G_SRAI,
    G_ADDIW, G_SLLIW, G_SRLIW, G_SRAIW: begin
      d.unit = UNIT_ALU; d.rs1_re = 1; d.rd_we = 1; d.imm = g_imm_i(i); d.op2_is_imm = 1;
      case (g)
        G_ADDI:  d.alu_op = ALU_ADD;   G_SLTI:  d.alu_op = ALU_SLT;   G_SLTIU: d.alu_op = ALU_SLTU;
        G_XORI:  d.alu_op = ALU_XOR;   G_ORI:   d.alu_op = ALU_OR;    G_ANDI:  d.alu_op = ALU_AND;
        G_SLLI:  d.alu_op = ALU_SLL;   G_SRLI:  d.alu_op = ALU_SRL;   G_SRAI:  d.alu_op = ALU_SRA;
        G_ADDIW: d.alu_op = ALU_ADDW;  G_SLLIW: d.alu_op = ALU_SLLW;  G_SRLIW: d.alu_op = ALU_SRLW;
        default: d.alu_op = ALU_SRAW;
      endcase
    end

    G_ADD, G_SUB, G_SLL, G_SLT, G_SLTU, G_XOR, G_SRL, G_SRA, G_OR, G_AND,
    G_ADDW, G_SUBW, G_SLLW, G_SRLW, G_SRAW: begin
      d.unit = UNIT_ALU; d.rs1_re = 1; d.rs2_re = 1; d.rd_we = 1;
      case (g)
        G_ADD:  d.alu_op = ALU_ADD;   G_SUB:  d.alu_op = ALU_SUB;   G_SLL:  d.alu_op = ALU_SLL;
        G_SLT:  d.alu_op = ALU_SLT;   G_SLTU: d.alu_op = ALU_SLTU;  G_XOR:  d.alu_op = ALU_XOR;
        G_SRL:  d.alu_op = ALU_SRL;   G_SRA:  d.alu_op = ALU_SRA;   G_OR:   d.alu_op = ALU_OR;
        G_AND:  d.alu_op = ALU_AND;   G_ADDW: d.alu_op = ALU_ADDW;  G_SUBW: d.alu_op = ALU_SUBW;
        G_SLLW: d.alu_op = ALU_SLLW;  G_SRLW: d.alu_op = ALU_SRLW;  default: d.alu_op = ALU_SRAW;
      endcase
    end

    G_MUL, G_MULH, G_MULHSU, G_MULHU, G_MULW: begin
      d.unit = UNIT_MUL; d.is_mul = 1; d.rs1_re = 1; d.rs2_re = 1; d.rd_we = 1;
      d.muldiv_op = (g == G_MUL) ? MULDIV_MUL : (g == G_MULH) ? MULDIV_MULH :
                    (g == G_MULHSU) ? MULDIV_MULHSU : (g == G_MULHU) ? MULDIV_MULHU : MULDIV_MULW;
    end
    G_DIV, G_DIVU, G_REM, G_REMU, G_DIVW, G_DIVUW, G_REMW, G_REMUW: begin
      d.unit = UNIT_DIV; d.is_div = 1; d.rs1_re = 1; d.rs2_re = 1; d.rd_we = 1;
      case (g)
        G_DIV:   d.muldiv_op = MULDIV_DIV;   G_DIVU:  d.muldiv_op = MULDIV_DIVU;
        G_REM:   d.muldiv_op = MULDIV_REM;   G_REMU:  d.muldiv_op = MULDIV_REMU;
        G_DIVW:  d.muldiv_op = MULDIV_DIVW;  G_DIVUW: d.muldiv_op = MULDIV_DIVUW;
        G_REMW:  d.muldiv_op = MULDIV_REMW;  default: d.muldiv_op = MULDIV_REMUW;
      endcase
    end

    G_FENCE:   d.sys_op = SYS_FENCE;
    G_FENCE_I: d.sys_op = SYS_FENCE_I;
    G_ECALL:   d.sys_op = SYS_ECALL;
    G_EBREAK:  d.sys_op = SYS_EBREAK;
    G_MRET:    d.sys_op = SYS_MRET;
    G_SRET:    d.sys_op = SYS_SRET;
    G_WFI:     d.sys_op = SYS_WFI;
    G_SFENCE_VMA: begin d.sys_op = SYS_SFENCE_VMA; d.rs1_re = 1; d.rs2_re = 1; end

    G_CSRRW, G_CSRRS, G_CSRRC, G_CSRRWI, G_CSRRSI, G_CSRRCI: begin
      d.unit = UNIT_CSR; d.is_csr = 1; d.rd_we = 1; d.csr_addr = i[31:20];
      d.csr_imm = g inside {G_CSRRWI, G_CSRRSI, G_CSRRCI};
      d.rs1_re  = !d.csr_imm;
      d.imm     = 64'(i[19:15]);
      d.csr_op  = (g inside {G_CSRRW, G_CSRRWI}) ? CSR_RW :
                  (g inside {G_CSRRS, G_CSRRSI}) ? CSR_RS : CSR_RC;
    end

    default: begin   // RV64A
      d.unit = UNIT_LSU; d.is_amo = 1; d.rs1_re = 1; d.rd_we = 1;
      d.aq = i[26]; d.rl = i[25];
      d.mem_size = i[12] ? LS_DOUBLE : LS_WORD;
      d.rs2_re   = !(g inside {G_LR_W, G_LR_D});
      case (g)
        G_LR_W, G_LR_D:           d.amo_op = AMO_LR;
        G_SC_W, G_SC_D:           d.amo_op = AMO_SC;
        G_AMOSWAP_W, G_AMOSWAP_D: d.amo_op = AMO_SWAP;
        G_AMOADD_W, G_AMOADD_D:   d.amo_op = AMO_ADD;
        G_AMOXOR_W, G_AMOXOR_D:   d.amo_op = AMO_XOR;
        G_AMOAND_W, G_AMOAND_D:   d.amo_op = AMO_AND;
        G_AMOOR_W, G_AMOOR_D:     d.amo_op = AMO_OR;
        G_AMOMIN_W, G_AMOMIN_D:   d.amo_op = AMO_MIN;
        G_AMOMAX_W, G_AMOMAX_D:   d.amo_op = AMO_MAX;
        G_AMOMINU_W, G_AMOMINU_D: d.amo_op = AMO_MINU;
        default:                  d.amo_op = AMO_MAXU;
      endcase
    end
  endcase
  return d;
endfunction
