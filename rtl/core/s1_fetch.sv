// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
// Written by : Ayesha Anwar ayesha.anwaar2005@gmail.com
// =============================================================================

module s1_fetch
  import s1_pkg::*;
(
  input  logic              clk_i,
  input  logic              rst_ni,
  input  logic [XLEN-1:0]   boot_addr_i,
  input  logic              branch_redirect_valid_i,  // from EX, mispredict
  input  logic [XLEN-1:0]   branch_redirect_pc_i,
  input  logic              retire_redirect_valid_i,  // from retire pointer
  input  logic [XLEN-1:0]   retire_redirect_pc_i,
  input  logic              icache_inval_i,           // fence.i pulse, from retire
  input  logic              debug_halt_req_i,
  input  logic              id_stall_i,

  output logic              instr_req_o,
  output logic [XLEN-1:0]   instr_addr_o,
  output logic              icache_inval_o,
  input  logic              instr_gnt_i,
  input  logic [XLEN-1:0]   instr_rdata_i,
  input  logic              instr_rvalid_i,
  input  logic              instr_err_i,

  // To ID -- the fetch_req/fetch_rsp handoff .
  output logic [XLEN-1:0]   if_pc_o,
  output logic [ILEN-1:0]   if_instr_o,
  output logic              if_valid_o,
  output logic              if_fault_o,
  output logic [5:0]        if_exccode_o,
  output logic              if_pred_taken_o
);

  logic redirect_valid;
  assign redirect_valid = branch_redirect_valid_i || retire_redirect_valid_i;
  logic [XLEN-1:0] pc_q, pc_d;
  logic            outstanding_q;
  logic [XLEN-1:0] req_pc_q;
  logic            flush_pending_q;
  logic            req_active_q;
  logic [XLEN-1:0] req_addr_q;
  logic first_fetch_q;
  logic rvc_fetch_ready;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      pc_q          <= boot_addr_i;
      outstanding_q <= 1'b0;
      req_pc_q      <= '0;
      req_active_q  <= 1'b0;
      req_addr_q    <= '0;
      first_fetch_q <= 1'b1;
    end else begin
      pc_q <= pc_d;

      if (instr_req_o && !instr_gnt_i) begin
        req_active_q <= 1'b1;
        req_addr_q   <= instr_addr_o;
      end else begin
        req_active_q <= 1'b0;
      end

      if (instr_req_o && instr_gnt_i) begin
        outstanding_q <= 1'b1;
        req_pc_q      <= instr_addr_o;
        first_fetch_q <= 1'b0;
      end else if (instr_rvalid_i) begin
        outstanding_q <= 1'b0;
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      flush_pending_q <= 1'b0;
    end else if (outstanding_q && redirect_valid) begin
      flush_pending_q <= 1'b1;
    end else if (instr_rvalid_i) begin
      flush_pending_q <= 1'b0;
    end
  end

  logic issuing_new_req;
  assign issuing_new_req = !req_active_q && !outstanding_q &&
                            !debug_halt_req_i && !id_stall_i && rvc_fetch_ready;

  logic            pending_redirect_valid_q;
  logic [XLEN-1:0] pending_redirect_pc_q;
  logic            pending_redirect_is_retire_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      pending_redirect_valid_q     <= 1'b0;
      pending_redirect_pc_q        <= '0;
      pending_redirect_is_retire_q <= 1'b0;
    end else if (issuing_new_req && pending_redirect_valid_q) begin
      // Consumed: this cycle's pc_d (below) is driving instr_addr_o from
      // the pending target, and the outstanding_q/req_active_q chain will
      // preserve that address from here on.
      pending_redirect_valid_q     <= 1'b0;
      pending_redirect_is_retire_q <= 1'b0;
    end else if (retire_redirect_valid_i && !issuing_new_req) begin
      pending_redirect_valid_q     <= 1'b1;
      pending_redirect_pc_q        <= retire_redirect_pc_i;
      pending_redirect_is_retire_q <= 1'b1;
    end else if (branch_redirect_valid_i && !issuing_new_req &&
                 !pending_redirect_is_retire_q) begin
      // Don't let a lower-priority branch redirect clobber a still-pending
      // higher-priority retire redirect that hasn't been consumed yet.
      pending_redirect_valid_q     <= 1'b1;
      pending_redirect_pc_q        <= branch_redirect_pc_i;
      pending_redirect_is_retire_q <= 1'b0;
    end
    // else: hold. Covers "nothing happened" and "blocked, nothing new to
    // latch" cycles alike.
  end

  logic            redirect_retire_eff;
  logic            redirect_branch_eff;
  logic [XLEN-1:0] redirect_retire_pc_eff;
  logic [XLEN-1:0] redirect_branch_pc_eff;

  assign redirect_retire_eff    = retire_redirect_valid_i ||
                                   (pending_redirect_valid_q && pending_redirect_is_retire_q);
  assign redirect_retire_pc_eff = retire_redirect_valid_i ? retire_redirect_pc_i
                                                            : pending_redirect_pc_q;

  assign redirect_branch_eff    = branch_redirect_valid_i ||
                                   (pending_redirect_valid_q && !pending_redirect_is_retire_q);
  assign redirect_branch_pc_eff = branch_redirect_valid_i ? branch_redirect_pc_i
                                                             : pending_redirect_pc_q;

  logic [XLEN-1:0] seq_pc;
  assign seq_pc = req_pc_q + XLEN'(4);

  always_comb begin
    pc_d = first_fetch_q ? pc_q : seq_pc;
    if (debug_halt_req_i) begin
      pc_d = pc_q;
    end else if (redirect_retire_eff) begin
      pc_d = redirect_retire_pc_eff;
    end else if (redirect_branch_eff) begin
      pc_d = redirect_branch_pc_eff;
    end else if (btfn_taken) begin
      pc_d = btfn_target;
    end
  end

  assign instr_req_o  = req_active_q || issuing_new_req;

  assign instr_addr_o = req_active_q ? req_addr_q : pc_d;

  assign icache_inval_o = icache_inval_i;

  // ---------------------------------------------------------------------------
  // s1_rvc_expand -- owns realign, skid buffer, per-instruction PC, and (as
  // of the fetch_err_i/err_o addition) per-instruction fault carry, since a
  // skid-buffered second instruction is drained a cycle after instr_err_i
  // for the word it came from has already moved on.
  // ---------------------------------------------------------------------------
  logic [ILEN-1:0] exp_instr;
  logic [XLEN-1:0] exp_pc;
  logic            exp_valid;
  logic            exp_illegal;
  logic            exp_err;

  s1_rvc_expand u_rvc_expand (
    .clk_i          (clk_i),
    .rst_ni         (rst_ni),
    .fetch_valid_i  (instr_rvalid_i && !flush_pending_q),
    .fetch_pc_i     (req_pc_q),
    .fetch_data_i   (instr_rdata_i[31:0]),
    .fetch_err_i    (instr_err_i),
    .stall_i        (id_stall_i),
    .flush_i        (redirect_valid),
    .instr_pc_o     (exp_pc),
    .instr_o        (exp_instr),
    .instr_valid_o  (exp_valid),
    .illegal_o      (exp_illegal),
    .err_o          (exp_err),
    .is_compressed_o(),               // informational only, not wired further
    .fetch_ready_o  (rvc_fetch_ready)
  );

  // ---------------------------------------------------------------------------
  // BTFN -- Backward Taken, Forward Not-Taken.
  //
  // Runs on s1_rvc_expand's already-expanded 32-bit instruction, so a
  // compressed branch is just as predictable as an uncompressed one.
  //
  // Static prediction, no predictor storage (SPEC 7.1):
  //   negative displacement -> backward -> TAKEN
  //   non-negative displacement -> forward -> NOT TAKEN
  //
  // JAL is NOT unconditionally predicted taken. Its J-type immediate
  // determines whether it is a backward or forward control transfer.
  // ---------------------------------------------------------------------------
  localparam logic [6:0] OPCODE_BRANCH = 7'b1100011;
  localparam logic [6:0] OPCODE_JAL    = 7'b1101111;

  logic [6:0]      exp_opcode;
  logic            is_branch;
  logic            is_jal;
  logic [XLEN-1:0] imm_b;
  logic [XLEN-1:0] imm_j;
  logic            btfn_taken;
  logic [XLEN-1:0] btfn_target;

  assign exp_opcode = exp_instr[6:0];

  assign is_branch = exp_valid && (exp_opcode == OPCODE_BRANCH);
  assign is_jal    = exp_valid && (exp_opcode == OPCODE_JAL);

  // B-type immediate:
  // imm[12|10:5|4:1|11|0]
  assign imm_b = {{51{exp_instr[31]}},
                  exp_instr[31],
                  exp_instr[7],
                  exp_instr[30:25],
                  exp_instr[11:8],
                  1'b0};

  // J-type immediate:
  // imm[20|10:1|11|19:12|0]
  assign imm_j = {{43{exp_instr[31]}},
                  exp_instr[31],
                  exp_instr[19:12],
                  exp_instr[20],
                  exp_instr[30:21],
                  1'b0};

  assign btfn_taken =
      is_branch ? imm_b[XLEN-1] :
      is_jal    ? imm_j[XLEN-1] :
                  1'b0;

  assign btfn_target = exp_pc + (is_jal ? imm_j : imm_b);
  assign if_valid_o     = exp_valid;
  assign if_pc_o        = exp_pc;
  assign if_instr_o     = exp_instr;

  assign if_fault_o =
      exp_valid && (exp_err || exp_illegal);

  assign if_exccode_o =
      exp_err
        ? EXC_INSTR_ACCESS_FAULT
        : exp_illegal
          ? EXC_ILLEGAL_INSTR
          : 6'd0;

  assign if_pred_taken_o = btfn_taken;

endmodule
