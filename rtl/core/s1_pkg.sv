// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// s1_pkg : MEDS-S1 core parameters and shared types                [COMPLETE]
//
// Every type the core passes between modules lives here.  Nothing in rtl/core/
// declares a struct of its own -- if two modules need to agree on a shape, that
// shape belongs in this file.
//
// Reference: SPEC Part II, INTERFACES.md sections 1 and 2.
// =============================================================================

package s1_pkg;

  // ---------------------------------------------------------------------------
  // Global parameters
  // ---------------------------------------------------------------------------
  parameter int unsigned XLEN      = 64;
  parameter int unsigned ILEN      = 32;
  parameter int unsigned PLEN      = 40;   // physical address width
  parameter int unsigned REG_ADDR_W = 5;

  parameter int unsigned CB_DEPTH  = 8;    // completion buffer entries (SPEC 9.3)
  parameter int unsigned CB_IDX_W  = $clog2(CB_DEPTH);
  parameter int unsigned MXIF_ID_W = 4;    // INTERFACES.md 1.3

  parameter int unsigned PMP_N     = 16;

  // Reset vector.  Overridable per config; the boot ROM lives here.
  parameter logic [XLEN-1:0] BOOT_ADDR = 64'h0000_0000_0000_1000;

  // ---------------------------------------------------------------------------
  // Privilege levels
  // ---------------------------------------------------------------------------
  typedef enum logic [1:0] {
    PRIV_U = 2'b00,
    PRIV_S = 2'b01,
    PRIV_M = 2'b11
  } priv_lvl_e;

  // ---------------------------------------------------------------------------
  // ALU
  //
  // The W-suffixed operations are the RV64 32-bit forms: compute on the low 32
  // bits and sign-extend the result.  Keeping them as distinct opcodes rather
  // than a width flag keeps the decoder flat.
  // ---------------------------------------------------------------------------
  typedef enum logic [4:0] {
    ALU_ADD, ALU_SUB, ALU_SLL, ALU_SLT, ALU_SLTU,
    ALU_XOR, ALU_SRL, ALU_SRA, ALU_OR,  ALU_AND,
    ALU_ADDW, ALU_SUBW, ALU_SLLW, ALU_SRLW, ALU_SRAW,
    ALU_PASS_B                      // LUI and friends: forward operand b
  } alu_op_e;

  // Branch conditions, evaluated by the ALU comparator.
  typedef enum logic [2:0] {
    CMP_NONE, CMP_EQ, CMP_NE, CMP_LT, CMP_GE, CMP_LTU, CMP_GEU
  } cmp_op_e;

  // ---------------------------------------------------------------------------
  // Where a completed instruction's result came from
  // ---------------------------------------------------------------------------
  typedef enum logic [2:0] {
    UNIT_ALU, UNIT_LSU, UNIT_MUL, UNIT_DIV, UNIT_CSR, UNIT_MXIF, UNIT_NONE
  } exec_unit_e;

  // ---------------------------------------------------------------------------
  // Decode-stage types (rtl/core/s1_decode.sv)
  // ---------------------------------------------------------------------------

  // Load/store operand width, ID-stage view. The LSU, not the
  // decoder, owns that translation.
  typedef enum logic [1:0] {
    LS_BYTE, LS_HALF, LS_WORD, LS_DOUBLE
  } ls_size_e;

  // Zicsr operation.  CSRRW/CSRRS/CSRRC and their *-immediate forms collapse
  // to the same three read-modify-write ops; `decoded_op_t.csr_imm` carries
  // whether the operand is rs1 or a zero-extended uimm[4:0].
  typedef enum logic [1:0] {
    CSR_RW, CSR_RS, CSR_RC, CSR_NONE
  } csr_op_e;

  // RV64A atomic-memory-operation, from funct7[6:2].
  typedef enum logic [3:0] {
    AMO_LR, AMO_SC, AMO_SWAP, AMO_ADD, AMO_XOR, AMO_AND, AMO_OR,
    AMO_MIN, AMO_MAX, AMO_MINU, AMO_MAXU, AMO_NONE
  } amo_op_e;

  // Zicbom/Zicboz cache-block operation, from imm[11:0] under OP_MISC_MEM
  // funct3==010. CBO_ZERO is Zicboz; the other
  // three are Zicbom. Address is rs1 alone, same as AMO -- no offset.
  typedef enum logic [2:0] {
    CBO_INVAL, CBO_CLEAN, CBO_FLUSH, CBO_ZERO, CBO_NONE
  } cbo_op_e;

  // RV64M operation.  W-suffixed forms are the OP-32 (word) encodings, kept as
  // distinct values for the same reason alu_op_e keeps ALU_ADDW distinct from
  // ALU_ADD: the multiply/divide unit needs to know the truncation width
  // without decoding funct7/opcode a second time.
  typedef enum logic [3:0] {
    MULDIV_MUL, MULDIV_MULH, MULDIV_MULHSU, MULDIV_MULHU,
    MULDIV_DIV, MULDIV_DIVU, MULDIV_REM, MULDIV_REMU,
    MULDIV_MULW, MULDIV_DIVW, MULDIV_DIVUW, MULDIV_REMW, MULDIV_REMUW,
    MULDIV_NONE
  } muldiv_op_e;

  // System/privileged/Zifencei micro-op (FENCE, FENCE.I, and SYSTEM funct3==000
  // instructions). MRET/SRET/WFI/DRET legality (privilege, debug mode) is
  // checked at retire, not here (SPEC 10.1, 13). SFENCE.VMA differs: rs1/rs2
  // are real operands (vaddr, asid), identified by funct7==0001001; only rd
  // is fixed to 0.
  typedef enum logic [3:0] {
    SYS_NONE, SYS_ECALL, SYS_EBREAK, SYS_MRET, SYS_SRET, SYS_WFI,
    SYS_FENCE, SYS_FENCE_I, SYS_SFENCE_VMA, SYS_DRET
  } sys_op_e;

  // ---------------------------------------------------------------------------
  // decoded_op_t -- ID-stage control bundle (SPEC 7.2). Produced only by
  // s1_decode.sv; consumed by s1_regfile, s1_alu, s1_lsu, s1_csr, and
  // s1_completion_buffer. Carries no register values and no privilege
  // checks -- those belong to s1_regfile.sv and s1_csr.sv respectively.
  // ---------------------------------------------------------------------------
  typedef struct packed {
    // -- classification ------------------------------------------------------
    exec_unit_e             unit;            // which unit/completion path owns this op
    logic                   illegal;         // no unit will ever accept this encoding
    logic                   mxif_candidate;  // unit==UNIT_MXIF: unrecognised or coprocessor-routed opcode

    // -- register addressing ---------------------------------------------------
    logic [REG_ADDR_W-1:0]  rs1;             // raw instr[19:15]; uimm[4:0] when csr_imm=1
    logic [REG_ADDR_W-1:0]  rs2;             // raw instr[24:20]
    logic                   rs1_re;          // rs1 is an operand -- read/forward/hazard-check it
    logic                   rs2_re;          // rs2 is an operand
    logic [REG_ADDR_W-1:0]  rd;              // raw instr[11:7]
    logic                   rd_we;           // writes rd (x0 writes are discarded downstream, not gated here)

    // -- immediate ---------------------------------------------------------------
    logic [XLEN-1:0]        imm;             // sign- or zero-extended, format already selected

    // -- ALU / branch / address operand routing (consumed by s1_alu.sv) -----------
    alu_op_e                alu_op;
    cmp_op_e                cmp_op;          // CMP_NONE unless is_branch
    logic                   op1_is_pc;       // ALU operand A is PC, not rs1 (AUIPC, JAL)
    logic                   op2_is_imm;      // ALU operand B is imm, not rs2
    logic                   is_branch;
    logic                   is_jal;
    logic                   is_jalr;

    // -- load / store / atomic / cache-block (consumed by s1_lsu.sv) ---------------
    logic                   is_load;
    logic                   is_store;
    logic                   is_amo;
    ls_size_e               mem_size;
    logic                   mem_signed;
    amo_op_e                amo_op;
    logic                   aq;
    logic                   rl;
    logic                   is_cbo;          // Zicbom/Zicboz; address = rs1, no offset
    cbo_op_e                cbo_op;

    // -- multiply / divide --------------------------------------------------------
    logic                   is_mul;
    logic                   is_div;
    muldiv_op_e             muldiv_op;

    // -- CSR (Zicsr), consumed by s1_csr.sv -----------------------------------------
    logic                   is_csr;
    csr_op_e                csr_op;
    logic                   csr_imm;         // operand is uimm[4:0] (rs1 field), not rs1
    logic [11:0]            csr_addr;

    // -- system / privileged / Zifencei ---------------------------------------------
    sys_op_e                sys_op;

    // -- bookkeeping, carried through to the completion buffer (SPEC 9.1) -----------
    logic [XLEN-1:0]        pc;
    logic [ILEN-1:0]        instr;
  } decoded_op_t;

  // ---------------------------------------------------------------------------
  // Completion buffer entry (SPEC 9.1)
  //
  // `norollback` is 1 for every main-pipe instruction and is driven by the
  // coprocessor for MXIF instructions -- it is the field that lets a long vector
  // operation retire while it is still executing (INTERFACES.md R1.9).
  // ---------------------------------------------------------------------------
  typedef struct packed {
    logic                   valid;
    logic                   done;
    logic                   norollback;
    logic [XLEN-1:0]        pc;
    logic [ILEN-1:0]        instr;
    logic [REG_ADDR_W-1:0]  rd;
    logic                   rd_we;
    logic [XLEN-1:0]        result;
    logic                   exc;
    logic [5:0]             exccode;
    logic [XLEN-1:0]        exctval;
    logic                   is_mxif;
    logic [MXIF_ID_W-1:0]   mxif_id;
    exec_unit_e             unit;
  } cb_entry_t;

  // ---------------------------------------------------------------------------
  // Standard exception codes (mcause, interrupt bit clear)
  // ---------------------------------------------------------------------------
  parameter logic [5:0] EXC_INSTR_ADDR_MISALIGNED = 6'd0;
  parameter logic [5:0] EXC_INSTR_ACCESS_FAULT    = 6'd1;
  parameter logic [5:0] EXC_ILLEGAL_INSTR         = 6'd2;
  parameter logic [5:0] EXC_BREAKPOINT            = 6'd3;
  parameter logic [5:0] EXC_LOAD_ADDR_MISALIGNED  = 6'd4;
  parameter logic [5:0] EXC_LOAD_ACCESS_FAULT     = 6'd5;
  parameter logic [5:0] EXC_STORE_ADDR_MISALIGNED = 6'd6;
  parameter logic [5:0] EXC_STORE_ACCESS_FAULT    = 6'd7;
  parameter logic [5:0] EXC_ECALL_U               = 6'd8;
  parameter logic [5:0] EXC_ECALL_S               = 6'd9;
  parameter logic [5:0] EXC_ECALL_M               = 6'd11;
  parameter logic [5:0] EXC_INSTR_PAGE_FAULT      = 6'd12;
  parameter logic [5:0] EXC_LOAD_PAGE_FAULT       = 6'd13;
  parameter logic [5:0] EXC_STORE_PAGE_FAULT      = 6'd15;

  // ---------------------------------------------------------------------------
  // Physical memory attributes (SPEC section 11, INTERFACES.md P1-P5)
  //
  // Generated into pma_decode.sv from soc.yaml; this is the shape it produces.
  // ---------------------------------------------------------------------------
  typedef struct packed {
    logic       cacheable;
    logic       idempotent;
    logic       strong_order;   // 1 = strongly-ordered I/O, 0 = RVWMO
    logic       atomic_lrsc;
    logic       atomic_amo;
    logic       align_natural;  // 1 = misaligned access faults
  } pma_t;

  // ---------------------------------------------------------------------------
  // MEM-REQ protocol payloads (INTERFACES.md section 2)
  // ---------------------------------------------------------------------------
  typedef struct packed {
    logic [XLEN-1:0]      addr;
    logic                 we;
    logic [XLEN/8-1:0]    be;
    logic [XLEN-1:0]      wdata;
    logic [2:0]           size;   // log2 bytes
    priv_lvl_e            mode;
    logic [3:0]           id;
  } mem_req_t;

  typedef struct packed {
    logic [3:0]           id;
    logic [XLEN-1:0]      rdata;
    logic                 err;
    logic [1:0]           errcode;
  } mem_rsp_t;

endpackage
