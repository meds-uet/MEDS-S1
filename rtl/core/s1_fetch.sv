// =============================================================================
// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// Author(s)    : Ayesha Anwar (ayesha.anwaar2005@gmail.com) (Sep,2026)
// Modified By  :
//
// s1_fetch     : IF stage -- PC generation, BTFN, realign, C expansion  [WIP -- T-01]
// Description  :
// Fetches 32-bit words from the I$ over I2 MEM-REQ, realigns 16/32-bit
// instructions, expands C, predicts BTFN and registers one instruction per
// cycle towards ID.  Contract and timing: docs/modules/s1_fetch.md.
//
// Reference: SPEC 6, 7.1, 8.2; INTERFACES.md 2.  Testbench: verif/unit/tb_s1_fetch.sv.
// =============================================================================

module s1_fetch
  import s1_pkg::*;
#(
  parameter logic [XLEN-1:0] RESET_PC     = BOOT_ADDR,
  parameter int unsigned     FETCH_BUF_HW = 6      // realign buffer, 16-bit parcels
) (
  input  logic            clk_i,
  input  logic            rst_ni,

  // Redirects
  input  logic            ex_redirect_valid_i,
  input  logic [XLEN-1:0] ex_redirect_pc_i,
  input  logic            retire_redirect_valid_i,  // beats EX
  input  logic [XLEN-1:0] retire_redirect_pc_i,
  input  priv_lvl_e       priv_i,

  // I$ port (I2 MEM-REQ)
  output logic            imem_req_valid_o,
  input  logic            imem_req_ready_i,
  output mem_req_t        imem_req_o,
  input  logic            imem_rsp_valid_i,
  output logic            imem_rsp_ready_o,
  input  mem_rsp_t        imem_rsp_i,

  // To ID
  output logic            fetch_rsp_valid_o,
  input  logic            fetch_rsp_ready_i,
  output fetch_rsp_t      fetch_rsp_o
);

  localparam int unsigned WORD_BYTES = ILEN / 8;
  localparam int unsigned OFF_W      = $clog2(WORD_BYTES);
  localparam int unsigned HW_BYTES   = CLEN / 8;
  localparam int unsigned HW_BIT     = $clog2(HW_BYTES);
  localparam int unsigned HW_PER_WD  = ILEN / CLEN;
  localparam int unsigned WORD_LANES = XLEN / ILEN;
  localparam int unsigned LANE_W     = (WORD_LANES > 1) ? $clog2(WORD_LANES) : 1;
  localparam int unsigned CNT_W      = $clog2(FETCH_BUF_HW + 1);

  // Smaller deadlocks on a word-straddling 32-bit instruction.
  if (FETCH_BUF_HW < 2 * HW_PER_WD) begin : g_bad_buf
    $error("s1_fetch: FETCH_BUF_HW=%0d is below the minimum of %0d", FETCH_BUF_HW, 2 * HW_PER_WD);
  end

  // IALIGN=16: bit 0 of a target is forced to zero rather than trusted.
  logic [XLEN-1:0] ex_pc, retire_pc;
  assign ex_pc     = {ex_redirect_pc_i[XLEN-1:HW_BIT],     {HW_BIT{1'b0}}};
  assign retire_pc = {retire_redirect_pc_i[XLEN-1:HW_BIT], {HW_BIT{1'b0}}};

  logic            fetch_rsp_valid_q;
  fetch_rsp_t      fetch_rsp_q;
  logic            bp_fire_q;            // IF/ID holds a predicted-taken branch
  logic [XLEN-1:0] bp_imm, bp_target;

  // BTFN target from the IF/ID register: keeps the adder off the I$ data->addr path.
  always_comb begin
    if (fetch_rsp_q.instr[6:0] == OPC_JAL) begin
      bp_imm = {{(XLEN-20){fetch_rsp_q.instr[31]}}, fetch_rsp_q.instr[19:12],
                fetch_rsp_q.instr[20], fetch_rsp_q.instr[30:21], 1'b0};
    end else begin
      bp_imm = {{(XLEN-12){fetch_rsp_q.instr[31]}}, fetch_rsp_q.instr[7],
                fetch_rsp_q.instr[30:25], fetch_rsp_q.instr[11:8], 1'b0};
    end
  end
  assign bp_target = fetch_rsp_q.pc + bp_imm;

  // kill_out flushes the IF/ID register too; kill_buf only what is younger.
  logic kill_out, kill_buf;
  assign kill_out = ex_redirect_valid_i || retire_redirect_valid_i;
  assign kill_buf = kill_out || bp_fire_q;

  // ---------------------------------------------------------------------------
  // Request side
  // ---------------------------------------------------------------------------
  logic [XLEN-1:0]   pc_q;               // next fetch address
  logic              hold_q;             // presented, not accepted: payload frozen
  mem_req_t          hold_req_q;
  logic              hold_skip_q;        // drop the word's low parcel
  logic              hold_stale_q;
  logic              outst_q;            // accepted, response pending
  logic              outst_skip_q;
  logic              outst_stale_q;      // response belongs to a flushed stream
  logic [LANE_W-1:0] outst_lane_q;
  logic              halt_q;             // faulting instruction delivered

  logic [CNT_W-1:0]  buf_cnt_q;

  // Retire redirects are registered (correct priv_i on the first request), so
  // only EX and BTFN redirect a request in the same cycle.
  logic [XLEN-1:0] next_pc;
  always_comb begin
    next_pc = pc_q;
    if (ex_redirect_valid_i) next_pc = ex_pc;
    else if (bp_fire_q)      next_pc = bp_target;
  end

  // I2 data is byte-lane aligned: pick the 32-bit lane of the XLEN beat.
  logic [LANE_W-1:0] next_lane, req_lane;
  assign next_lane = (WORD_LANES > 1) ? next_pc[OFF_W +: LANE_W]         : '0;
  assign req_lane  = (WORD_LANES > 1) ? imem_req_o.addr[OFF_W +: LANE_W] : '0;

  mem_req_t new_req;
  always_comb begin
    new_req      = '0;
    new_req.addr = {next_pc[XLEN-1:OFF_W], {OFF_W{1'b0}}};
    new_req.we   = 1'b0;
    new_req.be   = (XLEN/8)'({WORD_BYTES{1'b1}}) << (WORD_BYTES * 32'(next_lane));
    new_req.size = 3'(OFF_W);
    new_req.mode = priv_i;
    new_req.id   = '0;
  end

  // Reserve buffer space for the response before issuing.  Pops are not
  // credited, which keeps ID's stall out of the I$ request path.
  logic [CNT_W+1:0] credit_need;
  logic             credit_ok, slot_free, may_issue, req_fire, rsp_fire;

  assign credit_need = (CNT_W+2)'(buf_cnt_q)
                     + ((outst_q && !outst_stale_q) ? (CNT_W+2)'(HW_PER_WD) : '0)
                     + (CNT_W+2)'(HW_PER_WD);
  assign credit_ok   = kill_buf || (credit_need <= (CNT_W+2)'(FETCH_BUF_HW));
  assign slot_free   = !outst_q || imem_rsp_valid_i;          // one outstanding
  assign may_issue   = !hold_q && !retire_redirect_valid_i && (!halt_q || kill_buf)
                     && slot_free && credit_ok;

  assign imem_req_valid_o = hold_q || may_issue;               // R-C10: not a function of ready
  assign imem_req_o       = hold_q ? hold_req_q : new_req;
  assign imem_rsp_ready_o = 1'b1;                              // space reserved at issue

  assign req_fire = imem_req_valid_o && imem_req_ready_i;
  assign rsp_fire = outst_q && imem_rsp_valid_i;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      pc_q          <= RESET_PC;
      hold_q        <= 1'b0;
      hold_req_q    <= '0;
      hold_skip_q   <= 1'b0;
      hold_stale_q  <= 1'b0;
      outst_q       <= 1'b0;
      outst_skip_q  <= 1'b0;
      outst_stale_q <= 1'b0;
      outst_lane_q  <= '0;
    end else begin
      if (retire_redirect_valid_i)  pc_q <= retire_pc;
      else if (may_issue)           pc_q <= new_req.addr + XLEN'(WORD_BYTES);
      else if (ex_redirect_valid_i) pc_q <= ex_pc;
      else if (bp_fire_q)           pc_q <= bp_target;

      // A held request cannot be retargeted (R-C10); a redirect marks it stale.
      if (may_issue && !imem_req_ready_i) begin
        hold_q       <= 1'b1;
        hold_req_q   <= new_req;
        hold_skip_q  <= next_pc[HW_BIT];
        hold_stale_q <= 1'b0;
      end else if (hold_q && imem_req_ready_i) begin
        hold_q       <= 1'b0;
        hold_stale_q <= 1'b0;
      end else if (hold_q && kill_buf) begin
        hold_stale_q <= 1'b1;
      end

      if (req_fire) begin
        outst_q       <= 1'b1;
        outst_skip_q  <= hold_q ? hold_skip_q : next_pc[HW_BIT];
        outst_stale_q <= hold_q && (hold_stale_q || kill_buf);
        outst_lane_q  <= req_lane;
      end else if (rsp_fire) begin
        outst_q       <= 1'b0;
        outst_stale_q <= 1'b0;
      end else if (outst_q && kill_buf) begin
        outst_stale_q <= 1'b1;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Realign buffer.  Instructions are carved from the "window" (buffer plus
  // this cycle's response) so a response reaches IF/ID in the cycle it
  // arrives -- needed for the 2-cycle mispredict penalty.
  // ---------------------------------------------------------------------------
  logic [FETCH_BUF_HW-1:0][CLEN-1:0] buf_hw_q, win_hw;
  logic [FETCH_BUF_HW-1:0]           buf_err_q, win_err;
  logic [CNT_W-1:0]                  win_cnt, push_cnt, pop_cnt;
  logic [ILEN-1:0]                   rsp_word;
  logic                              push;

  // No flush gating needed: a flush empties the buffer at this edge anyway.
  assign rsp_word = imem_rsp_i.rdata[32'(outst_lane_q) * ILEN +: ILEN];
  assign push     = rsp_fire && !outst_stale_q;
  assign push_cnt = !push        ? '0
                  : outst_skip_q ? CNT_W'(1)
                  :                CNT_W'(HW_PER_WD);
  assign win_cnt  = buf_cnt_q + push_cnt;

  always_comb begin
    win_hw  = buf_hw_q;
    win_err = buf_err_q;
    for (int unsigned i = 0; i < FETCH_BUF_HW; i++) begin
      if (i == 32'(buf_cnt_q)) begin
        win_hw[i]  = outst_skip_q ? rsp_word[CLEN +: CLEN] : rsp_word[0 +: CLEN];
        win_err[i] = imem_rsp_i.err;
      end else if (i == 32'(buf_cnt_q) + 1) begin
        win_hw[i]  = rsp_word[CLEN +: CLEN];
        win_err[i] = imem_rsp_i.err;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Head instruction
  // ---------------------------------------------------------------------------
  logic [XLEN-1:0] head_pc_q;            // PC of win_hw[0]
  logic [ILEN-1:0] rvc_instr;
  logic            rvc_illegal;
  logic            is_rvc, ins_valid, ins_len2, load, out_free;
  fetch_rsp_t      ins;

  assign is_rvc = (win_hw[0][1:0] != 2'b11);

  s1_rvc_expand u_rvc_expand (
    .instr_i   (win_hw[0]),
    .instr_o   (rvc_instr),
    .illegal_o (rvc_illegal)
  );

  always_comb begin
    ins       = '0;
    ins.pc    = head_pc_q;
    ins_valid = 1'b0;
    ins_len2  = 1'b0;

    if (win_cnt != '0 && win_err[0]) begin
      // Faulted first parcel: length unknowable and irrelevant, report now.
      ins_valid   = 1'b1;
      ins.exc     = 1'b1;
      ins.exccode = EXC_INSTR_ACCESS_FAULT;
      ins.exctval = head_pc_q;
    end else if (win_cnt != '0 && is_rvc) begin
      ins_valid      = 1'b1;
      ins.instr      = rvc_instr;
      ins.instr_raw  = ILEN'(win_hw[0]);
      ins.compressed = 1'b1;
      if (rvc_illegal) begin
        ins.exc     = 1'b1;
        ins.exccode = EXC_ILLEGAL_INSTR;
        ins.exctval = XLEN'(win_hw[0]);
      end
    end else if (win_cnt >= CNT_W'(HW_PER_WD)) begin
      ins_valid = 1'b1;
      ins_len2  = 1'b1;
      if (win_err[1]) begin
        // mtval names the faulting portion; mepc (pc) still names the start.
        ins.exc     = 1'b1;
        ins.exccode = EXC_INSTR_ACCESS_FAULT;
        ins.exctval = head_pc_q + XLEN'(HW_BYTES);
      end else begin
        ins.instr     = {win_hw[1], win_hw[0]};
        ins.instr_raw = {win_hw[1], win_hw[0]};
      end
    end

    // BTFN: branch taken iff offset negative (inst[31]); JAL always taken
    // (unconditional); JALR never predicted (target unknown in IF).
    ins.pred_taken = ins_valid && !ins.exc
                   && ((ins.instr[6:0] == OPC_BRANCH && ins.instr[31])
                       || ins.instr[6:0] == OPC_JAL);
  end

  assign out_free = !fetch_rsp_valid_q || fetch_rsp_ready_i;
  assign load     = ins_valid && out_free && !kill_buf && !halt_q;
  assign pop_cnt  = !load    ? '0
                  : ins_len2 ? CNT_W'(HW_PER_WD)
                  :            CNT_W'(1);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      buf_cnt_q <= '0;
      buf_hw_q  <= '0;
      buf_err_q <= '0;
    end else if (kill_buf) begin
      buf_cnt_q <= '0;
    end else begin
      buf_cnt_q <= win_cnt - pop_cnt;
      buf_hw_q  <= win_hw  >> (CLEN * 32'(pop_cnt));
      buf_err_q <= win_err >> pop_cnt;
    end
  end

  // ---------------------------------------------------------------------------
  // IF/ID register
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      head_pc_q         <= RESET_PC;
      fetch_rsp_valid_q <= 1'b0;
      fetch_rsp_q       <= '0;
      bp_fire_q         <= 1'b0;
      halt_q            <= 1'b0;
    end else begin
      if (retire_redirect_valid_i)  head_pc_q <= retire_pc;
      else if (ex_redirect_valid_i) head_pc_q <= ex_pc;
      else if (bp_fire_q)           head_pc_q <= bp_target;
      else if (load)                head_pc_q <= head_pc_q + (ins_len2 ? XLEN'(WORD_BYTES)
                                                                      : XLEN'(HW_BYTES));

      // A redirect drops valid without a handshake; ID is flushed by it too.
      if (kill_out) begin
        fetch_rsp_valid_q <= 1'b0;
      end else if (load) begin
        fetch_rsp_valid_q <= 1'b1;
        fetch_rsp_q       <= ins;
      end else if (fetch_rsp_ready_i) begin
        fetch_rsp_valid_q <= 1'b0;
      end

      bp_fire_q <= load && ins.pred_taken;

      // Stop fetching past an instruction that will trap, until a redirect.
      if (kill_buf)                halt_q <= 1'b0;
      else if (load && ins.exc)    halt_q <= 1'b1;
    end
  end

  assign fetch_rsp_valid_o = fetch_rsp_valid_q;
  assign fetch_rsp_o       = fetch_rsp_q;

  // id: one outstanding request.  errcode: encoding undefined in I2.
  logic unused_inputs;
  assign unused_inputs = ^{imem_rsp_i.id, imem_rsp_i.errcode,
                           ex_redirect_pc_i[0], retire_redirect_pc_i[0]};

endmodule
