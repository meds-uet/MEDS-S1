// =============================================================================
// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// Author(s)    : Eman Nasar <fatehulnasareman@gmail.com>, GitHub EmanNasar001 (Oct,2026)
// Modified By  :
//
// s1_mem       : MEM stage -- D$ access, store buffer, AMO/LR/SC  [WIP -- R-02]
// Description  :
// Takes one instruction per cycle from EX/MEM.  Reads are fetched over I2
// MEM-REQ and merged byte-wise with pending stores; writes enter a commit-gated
// store buffer and reach memory only after WB commits them.  PMP and PMA are
// answered by checkers outside the core, through the chk_* query.  Owns the
// MEM/WB register: a read completes in the cycle its last response arrives,
// and a FENCE completes once the store buffer is empty.
// Contract and timing: docs/modules/s1_mem.md.
//
// Reference: SPEC 7.4, 11, 14; INTERFACES.md 1.5, 2, 9 (P1-P3); RISC-V A, PMP.
// Testbench: verif/unit/tb_s1_mem.sv.
// =============================================================================

module s1_mem
  import s1_pkg::*;
#(
  parameter int unsigned STORE_BUF_N = SB_DEPTH
) (
  input  logic                          clk_i,
  input  logic                          rst_ni,

  input  logic                          flush_i,          // retire flush
  input  priv_lvl_e                     priv_i,           // effective data privilege, after MPRV

  // EX/MEM
  input  logic                          mem_valid_i,
  output logic                          mem_ready_o,
  input  ex_mem_t                       mem_i,

  // MEM/WB.  No ready: WB commits whatever it is shown.  The one thing WB
  // used to wait for -- a FENCE with stores still buffered -- is held here
  // instead, because the store buffer is MEM's.
  output logic                          wb_valid_o,
  output mem_wb_t                       wb_o,
  output logic                          wb_pend_o,        // MEM/WB holds something not finished yet

  // From WB: a store committed.  Commit is in order, so it is always the
  // oldest uncommitted store-buffer entry; no tag is needed to find it.
  // Only for an instruction shown on wb_o with sb_alloc set, in that cycle
  // or later, and never in a cycle flush_i is high.
  input  logic                          sb_commit_i,

  // ---- Physical-memory checks, both external (SPEC 11) --------------------
  // One query describes the access in MEM; two independent checkers answer it
  // in the same cycle, in parallel with the D$ tag lookup.  Neither is in this
  // core -- see docs/modules/s1_core.md.
  output logic [XLEN-1:0]               chk_addr_o,
  output logic [2:0]                    chk_size_o,       // log2 bytes
  output logic                          chk_rd_o,         // needs R
  output logic                          chk_wr_o,         // needs W
  output priv_lvl_e                     chk_priv_o,       // effective mode, after MPRV

  input  pma_t                          pma_i,            // attributes of the region
  input  logic                          pma_fault_i,      // unmapped, or width not allowed
  input  logic                          pmp_allow_i,      // PMP permits this access

  // D$ port (I2 MEM-REQ)
  output logic                          dmem_req_valid_o,
  input  logic                          dmem_req_ready_i,
  output mem_req_t                      dmem_req_o,
  input  logic                          dmem_rsp_valid_i,
  output logic                          dmem_rsp_ready_o,
  input  mem_rsp_t                      dmem_rsp_i,

  // Status
  output logic                          sb_empty_o,       // fence waits for this
  output logic                          sb_full_o,        // perf event store_buffer_full
  output logic                          store_err_o,      // bus error draining a retired store
  output logic [XLEN-1:0]               store_err_addr_o
);

  localparam int unsigned BYTE_W     = 8;
  localparam int unsigned BEAT_BYTES = XLEN / BYTE_W;
  localparam int unsigned OFF_W      = $clog2(BEAT_BYTES);
  localparam int unsigned BEAT_W     = XLEN - OFF_W;
  localparam int unsigned WIN_BYTES  = 2 * BEAT_BYTES;    // an access spans at most two beats
  localparam int unsigned WIN_W      = 2 * XLEN;
  localparam int unsigned LG_W       = $clog2(OFF_W + 1);
  localparam int unsigned CNT_W      = $clog2(STORE_BUF_N + 1);
  localparam int unsigned PTR_W      = (STORE_BUF_N > 1) ? $clog2(STORE_BUF_N) : 1;

  if (STORE_BUF_N < 1) begin : g_bad_sb
    $error("s1_mem: STORE_BUF_N must be at least 1");
  end

  function automatic logic [WIN_BYTES-1:0] acc_mask(logic [OFF_W-1:0] off, logic [LG_W-1:0] lg);
    return ((WIN_BYTES'(1) << (32'(1) << lg)) - WIN_BYTES'(1)) << off;
  endfunction

  function automatic logic [WIN_W-1:0] byte_expand(logic [WIN_BYTES-1:0] m);
    logic [WIN_W-1:0] r;
    for (int unsigned k = 0; k < WIN_BYTES; k++) r[k*BYTE_W +: BYTE_W] = {BYTE_W{m[k]}};
    return r;
  endfunction

  function automatic logic [XLEN-1:0] size_mask(logic [LG_W-1:0] lg);
    return (lg == LG_W'(OFF_W)) ? '1 : (XLEN'(1) << ((32'(1) << lg) * BYTE_W)) - XLEN'(1);
  endfunction

  function automatic logic [XLEN-1:0] extend(logic [XLEN-1:0] raw, logic [LG_W-1:0] lg, logic sext);
    logic [XLEN-1:0] val;
    val = raw;
    unique case (lg)
      LG_W'(0): val = {{(XLEN-8){sext & raw[7]}},   raw[7:0]};
      LG_W'(1): val = {{(XLEN-16){sext & raw[15]}}, raw[15:0]};
      LG_W'(2): val = {{(XLEN-32){sext & raw[31]}}, raw[31:0]};
      default:  val = raw;
    endcase
    return val;
  endfunction

  // I2 lanes are AXI-style: byte A travels on lane A mod BEAT_BYTES.  The high
  // part of a beat-straddling access is a second request at the next beat.
  function automatic mem_req_t mk_req(logic [BEAT_W-1:0] beat, logic [OFF_W-1:0] off, logic hi,
                                      logic [WIN_BYTES-1:0] mask, logic [WIN_W-1:0] data,
                                      logic [LG_W-1:0] lg, logic we, priv_lvl_e mode);
    mem_req_t r;
    r       = '0;
    r.addr  = hi ? {beat + BEAT_W'(1), OFF_W'(0)} : {beat, off};
    r.we    = we;
    r.be    = hi ? mask[WIN_BYTES-1:BEAT_BYTES] : mask[BEAT_BYTES-1:0];
    r.wdata = hi ? data[WIN_W-1:XLEN]           : data[XLEN-1:0];
    r.size  = 3'(lg);
    r.mode  = mode;
    r.id    = '0;
    return r;
  endfunction

  // Store-buffer pointer arithmetic, modulo STORE_BUF_N (which need not be a
  // power of two).  Both operands are below STORE_BUF_N wherever it is used.
  function automatic logic [PTR_W-1:0] ptr_add(logic [PTR_W-1:0] p, logic [CNT_W-1:0] n);
    logic [CNT_W:0] s;
    s = (CNT_W+1)'(p) + (CNT_W+1)'(n);
    if (s >= (CNT_W+1)'(STORE_BUF_N)) s = s - (CNT_W+1)'(STORE_BUF_N);
    return PTR_W'(s);
  endfunction

  // ---------------------------------------------------------------------------
  // The instruction in MEM
  // ---------------------------------------------------------------------------
  logic                 is_lr, is_sc, is_amox, rd_acc, wr_acc, in_sext;
  logic [LG_W-1:0]      in_lg;
  logic [XLEN-1:0]      in_addr;
  logic [BEAT_W-1:0]    in_beat;
  logic [OFF_W-1:0]     in_off;
  logic [WIN_BYTES-1:0] in_mask;
  logic [WIN_W-1:0]     in_wdata;

  assign is_lr   = (mem_i.amo_op == AMO_LR);
  assign is_sc   = (mem_i.amo_op == AMO_SC);
  assign is_amox = (mem_i.amo_op != AMO_NONE) && !is_lr && !is_sc;
  logic is_fence;
  assign is_fence = !mem_i.exc && ((mem_i.sys_op == SYS_FENCE) || (mem_i.sys_op == SYS_FENCE_I));
  assign rd_acc  = mem_i.is_load  || is_lr || is_amox;
  assign wr_acc  = mem_i.is_store || is_sc || is_amox;
  assign in_sext = mem_i.is_load ? mem_i.mem_signed : 1'b1;   // LR and AMO results sign-extend
  assign in_lg   = LG_W'(mem_i.mem_size);
  assign in_addr = mem_i.mem_addr;
  assign in_beat = in_addr[XLEN-1:OFF_W];
  assign in_off  = in_addr[OFF_W-1:0];
  assign in_mask = acc_mask(in_off, in_lg);
  // Mask at XLEN, then widen.  As one expression the cast propagates into the
  // AND and 5.020 calls both operands too narrow.
  logic [XLEN-1:0]      in_wdata_masked;
  assign in_wdata_masked = mem_i.mem_wdata & size_mask(in_lg);
  assign in_wdata        = WIN_W'(in_wdata_masked) << (32'(in_off) * BYTE_W);

  // SC without a matching reservation fails without touching memory, as Sail does.
  logic            res_valid_q;
  logic [XLEN-1:0] res_addr_q;
  logic [LG_W-1:0] res_lg_q;
  logic            sc_skip;
  assign sc_skip = is_sc && !(res_valid_q && res_addr_q == in_addr && res_lg_q == in_lg);

  // The access being checked.  Combinational, and the answers are expected in
  // the same cycle: SPEC 11 requires both checks to run in parallel with the
  // D$ tag lookup, because the result decides whether the access may proceed
  // at all.  `ex` is not in the query because MEM never fetches.
  assign chk_addr_o = in_addr;
  assign chk_size_o = 3'(in_lg);
  assign chk_rd_o   = rd_acc;
  assign chk_wr_o   = wr_acc;
  assign chk_priv_o = priv_i;

  logic pmp_ok;
  assign pmp_ok = pmp_allow_i;

  logic in_mem, misalign, atomic_bad, in_fault, in_ok_read, in_ok_write;
  logic [5:0] fault_code;
  assign in_mem      = mem_valid_i && !mem_i.exc && (rd_acc || wr_acc) && !sc_skip;
  assign misalign    = pma_i.align_natural && ((in_addr & ((XLEN'(1) << in_lg) - XLEN'(1))) != '0);
  assign atomic_bad  = ((is_lr || is_sc) && !pma_i.atomic_lrsc) || (is_amox && !pma_i.atomic_amo);
  assign in_fault    = in_mem && (pma_fault_i || misalign || atomic_bad || !pmp_ok);
  assign fault_code  = (mem_i.is_load || is_lr) ? EXC_LOAD_ACCESS_FAULT : EXC_STORE_ACCESS_FAULT;
  assign in_ok_read  = in_mem && !in_fault && rd_acc;
  assign in_ok_write = in_mem && !in_fault && (mem_i.is_store || is_sc);

  // ---------------------------------------------------------------------------
  // Store buffer.  A circular buffer: sb_head_q is the oldest entry and the
  // live entries are the sb_cnt_q that follow it.  Entries are written once,
  // when allocated, and never move.  Commit is in order, so the committed
  // entries are always the oldest sb_ncom_q of them -- a count is all that
  // records it.
  // ---------------------------------------------------------------------------
  logic [STORE_BUF_N-1:0][BEAT_W-1:0]    sb_beat_q;
  logic [STORE_BUF_N-1:0][OFF_W-1:0]     sb_off_q;
  logic [STORE_BUF_N-1:0][LG_W-1:0]      sb_lg_q;
  logic [STORE_BUF_N-1:0][WIN_BYTES-1:0] sb_mask_q;
  logic [STORE_BUF_N-1:0][WIN_W-1:0]     sb_data_q;
  logic [STORE_BUF_N-1:0][1:0]           sb_mode_q;
  logic [PTR_W-1:0]                      sb_head_q;
  logic [CNT_W-1:0]                      sb_cnt_q;        // live entries
  logic [CNT_W-1:0]                      sb_ncom_q;       // ... of which committed
  logic                                  dr_lo_sent_q, dr_hi_sent_q;

  // Is physical entry i live?  Its age is its distance from the head.
  logic [STORE_BUF_N-1:0] sb_live;
  always_comb begin
    for (int unsigned i = 0; i < STORE_BUF_N; i++) begin
      if (i >= 32'(sb_head_q)) sb_live[i] = (i - 32'(sb_head_q)) < 32'(sb_cnt_q);
      else                     sb_live[i] = (i + STORE_BUF_N - 32'(sb_head_q)) < 32'(sb_cnt_q);
    end
  end

  // Merge every older pending store into the read's two-beat window, oldest
  // first so the youngest writer of each byte wins.  Only idempotent regions
  // merge; the others wait for an empty buffer (order_wait).
  //
  // Age order without a rotator: entries at or above the head are older than
  // the ones that wrapped below it, and inside each run physical order is age
  // order.  So two passes over the physical entries -- first [head, N), then
  // [0, head) -- visit the live ones oldest first.
  logic [WIN_BYTES-1:0] fwd_mask;
  logic [WIN_W-1:0]     fwd_data;

  always_comb begin
    logic [WIN_BYTES-1:0] m;
    logic [WIN_W-1:0]     d;
    logic [BEAT_W:0]      eb, lb;
    logic                 in_run;
    fwd_mask = '0;
    fwd_data = '0;
    lb       = {1'b0, in_beat};
    for (int unsigned pass = 0; pass < 2; pass++) begin
      for (int unsigned i = 0; i < STORE_BUF_N; i++) begin
        in_run = (pass == 0) ? (i >= 32'(sb_head_q)) : (i < 32'(sb_head_q));
        eb = {1'b0, sb_beat_q[i]};
        m  = '0;
        d  = '0;
        if (eb == lb) begin
          m = sb_mask_q[i];
          d = sb_data_q[i];
        end else if (eb == lb + (BEAT_W+1)'(1)) begin
          m = sb_mask_q[i] << BEAT_BYTES;
          d = sb_data_q[i] << XLEN;
        end else if (eb + (BEAT_W+1)'(1) == lb) begin
          m = sb_mask_q[i] >> BEAT_BYTES;
          d = sb_data_q[i] >> XLEN;
        end
        if (in_run && sb_live[i]) begin
          m        = m & in_mask;
          fwd_mask = fwd_mask | m;
          fwd_data = (fwd_data & ~byte_expand(m)) | (d & byte_expand(m));
        end
      end
    end
  end

  // The head entry, which is the one that drains.
  logic [BEAT_W-1:0]    hd_beat;
  logic [OFF_W-1:0]     hd_off;
  logic [LG_W-1:0]      hd_lg;
  logic [WIN_BYTES-1:0] hd_mask;
  logic [WIN_W-1:0]     hd_data;
  logic [1:0]           hd_mode;
  assign hd_beat = sb_beat_q[sb_head_q];
  assign hd_off  = sb_off_q[sb_head_q];
  assign hd_lg   = sb_lg_q[sb_head_q];
  assign hd_mask = sb_mask_q[sb_head_q];
  assign hd_data = sb_data_q[sb_head_q];
  assign hd_mode = sb_mode_q[sb_head_q];

  logic                 mw_valid_q;      // MEM/WB register, below

  logic need_lo, need_hi, bus_need, order_wait, head_wait;
  assign need_lo  = |(in_mask[BEAT_BYTES-1:0]         & ~fwd_mask[BEAT_BYTES-1:0]);
  assign need_hi  = |(in_mask[WIN_BYTES-1:BEAT_BYTES] & ~fwd_mask[WIN_BYTES-1:BEAT_BYTES]);
  assign bus_need = need_lo || need_hi;

  // P2: a strongly-ordered read follows every older store onto the bus.
  // P1: a non-idempotent read is never speculative, so it waits until it is
  // the oldest instruction in flight.  Issue is in order and WB holds no
  // state, so the only thing that can be older is the MEM/WB entry -- even one
  // completing this cycle, which can still trap.
  assign order_wait = in_ok_read && (!pma_i.idempotent || pma_i.strong_order) && (sb_cnt_q != '0);
  assign head_wait  = in_ok_read && !pma_i.idempotent && mw_valid_q;

  // ---------------------------------------------------------------------------
  // MEM/WB register
  // ---------------------------------------------------------------------------
  mem_wb_t              mw_q;
  logic                 mw_read_q;       // load, LR or AMO whose value is assembled at completion
  logic                 mw_bus_q;        // ... and still waiting on I2
  logic                 mw_fence_q;      // FENCE / FENCE.I: completes once the buffer is empty
  logic                 mw_amox_q, mw_lr_q;
  logic                 mw_need_hi_q, mw_hi_sent_q, mw_lo_got_q;
  logic [XLEN-1:0]      mw_lo_rdata_q, mw_wdata_q;
  logic [WIN_BYTES-1:0] mw_mask_q, mw_fwd_mask_q;
  logic [WIN_W-1:0]     mw_fwd_data_q;
  logic [LG_W-1:0]      mw_lg_q;
  logic                 mw_sext_q;
  priv_lvl_e            mw_mode_q;
  amo_op_e              mw_amo_op_q;

  // ---------------------------------------------------------------------------
  // I2 port.  One request outstanding (I2 v1).  Three requesters, in priority:
  //   A  the high part of the read in MEM/WB (the pipeline is waiting on it)
  //   C  the store-buffer head, once committed (starving it would keep an MMIO
  //      write off the bus while loads run)
  //   B  the read in MEM
  // A presented request is frozen (R-C10) and completes even if flushed.  Its
  // response needs no stale mark: a read enters MEM/WB only in the cycle its
  // request is presented, and that cannot happen while an older response is
  // still owed, so a response with MEM/WB not waiting on the bus is dropped.
  // ---------------------------------------------------------------------------
  logic     hold_q, hold_drain_q, hold_hi_q;
  mem_req_t hold_req_q;
  logic     outst_q, outst_drain_q, outst_hi_q;

  logic rsp_fire, rsp_read, rsp_drain, lo_rsp_now, hi_rsp_now, read_err_now;
  assign rsp_fire     = outst_q && dmem_rsp_valid_i;
  assign rsp_read     = rsp_fire && !outst_drain_q;
  assign rsp_drain    = rsp_fire && outst_drain_q;
  assign lo_rsp_now   = rsp_read && !outst_hi_q;
  assign hi_rsp_now   = rsp_read &&  outst_hi_q;
  assign read_err_now = mw_bus_q && rsp_read && dmem_rsp_i.err;

  // AMO and LR change state MEM itself reads (a store-buffer entry, the
  // reservation) at their completion edge, so nothing enters behind them then.
  //
  // A FENCE is not shown to WB until every older store has reached memory.
  // Everything older than it has already committed, so the buffer only holds
  // entries that are draining, and nothing younger can allocate while the
  // fence occupies MEM/WB -- the wait always ends.  Holding it here rather
  // than in WB is what lets MEM/WB have no ready: WB commits whatever it is
  // shown.
  logic mw_done, mw_free;
  assign mw_done = mw_valid_q && (mw_fence_q ? (sb_cnt_q == '0)
                                             : (!mw_bus_q || read_err_now
                                                || (mw_need_hi_q ? hi_rsp_now : lo_rsp_now)));
  assign mw_free = !mw_valid_q || (mw_done && !mw_amox_q && !mw_lr_q);

  logic dr_need_hi, pop_now;
  assign dr_need_hi = |hd_mask[WIN_BYTES-1:BEAT_BYTES];
  assign pop_now    = rsp_drain && (outst_hi_q || !dr_need_hi);

  logic sb_space;
  assign sb_space = (32'(sb_cnt_q) < STORE_BUF_N) || pop_now;

  logic port_free, a_want, b_want, c_want, a_go, b_go, c_go, new_hi;
  assign port_free = !hold_q && (!outst_q || dmem_rsp_valid_i);
  assign a_want    = mw_valid_q && mw_bus_q && mw_need_hi_q && !mw_hi_sent_q && !flush_i
                     && (mw_lo_got_q || (lo_rsp_now && !dmem_rsp_i.err));
  assign c_want    = (sb_ncom_q != '0)
                     && (!dr_lo_sent_q || (dr_need_hi && !dr_hi_sent_q));
  assign b_want    = in_ok_read && bus_need && !order_wait && !head_wait
                     && (!is_amox || sb_space) && mw_free && !flush_i;
  assign a_go      = port_free && a_want;
  assign c_go      = port_free && !a_want && c_want;
  assign b_go      = port_free && !a_want && !c_want && b_want;
  assign new_hi    = a_go || (c_go ? dr_lo_sent_q : !need_lo);

  mem_req_t new_req;
  always_comb begin
    new_req = mk_req(in_beat, in_off, new_hi, in_mask, '0, in_lg, 1'b0, priv_i);
    if (a_go) begin
      new_req = mk_req(mw_q.mem_addr[XLEN-1:OFF_W], mw_q.mem_addr[OFF_W-1:0], 1'b1, mw_mask_q, '0,
                       mw_lg_q, 1'b0, mw_mode_q);
    end else if (c_go) begin
      new_req = mk_req(hd_beat, hd_off, new_hi, hd_mask, hd_data,
                       hd_lg, 1'b1, priv_lvl_e'(hd_mode));
    end
  end

  logic req_fire;
  assign dmem_req_valid_o = hold_q || a_go || b_go || c_go;       // R-C10: not a function of ready
  assign dmem_req_o       = hold_q ? hold_req_q : new_req;
  assign dmem_rsp_ready_o = 1'b1;                                 // one outstanding, always consumed
  assign req_fire         = dmem_req_valid_o && dmem_req_ready_i;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      hold_q        <= 1'b0;
      hold_req_q    <= '0;
      hold_drain_q  <= 1'b0;
      hold_hi_q     <= 1'b0;
      outst_q       <= 1'b0;
      outst_drain_q <= 1'b0;
      outst_hi_q    <= 1'b0;
    end else begin
      if (!hold_q && dmem_req_valid_o && !dmem_req_ready_i) begin
        hold_q       <= 1'b1;
        hold_req_q   <= new_req;
        hold_drain_q <= c_go;
        hold_hi_q    <= new_hi;
      end else if (hold_q && dmem_req_ready_i) begin
        hold_q       <= 1'b0;
      end

      if (req_fire) begin
        outst_q       <= 1'b1;
        outst_drain_q <= hold_q ? hold_drain_q : c_go;
        outst_hi_q    <= hold_q ? hold_hi_q    : new_hi;
      end else if (rsp_fire) begin
        outst_q       <= 1'b0;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Accept from EX
  // ---------------------------------------------------------------------------
  logic accept;
  always_comb begin
    mem_ready_o = !flush_i && mw_free;
    if (in_mem && !in_fault) begin
      if (!rd_acc)          mem_ready_o = mem_ready_o && sb_space;
      else if (bus_need)    mem_ready_o = b_go;
      else                  mem_ready_o = mem_ready_o && !order_wait && !head_wait
                                          && (!is_amox || sb_space);
    end
  end
  assign accept = mem_valid_i && mem_ready_o;

  logic [BYTE_W-1:0] acc_bytes;
  assign acc_bytes = BYTE_W'((9'd1 << (32'(1) << in_lg)) - 9'd1);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      mw_valid_q    <= 1'b0;
      mw_q          <= '0;
      mw_read_q     <= 1'b0;
      mw_bus_q      <= 1'b0;
      mw_fence_q    <= 1'b0;
      mw_amox_q     <= 1'b0;
      mw_lr_q       <= 1'b0;
      mw_need_hi_q  <= 1'b0;
      mw_hi_sent_q  <= 1'b0;
      mw_lo_got_q   <= 1'b0;
      mw_lo_rdata_q <= '0;
      mw_wdata_q    <= '0;
      mw_mask_q     <= '0;
      mw_fwd_mask_q <= '0;
      mw_fwd_data_q <= '0;
      mw_lg_q       <= '0;
      mw_sext_q     <= 1'b0;
      mw_mode_q     <= PRIV_M;
      mw_amo_op_q   <= AMO_NONE;
    end else if (accept) begin
      mw_valid_q          <= 1'b1;
      mw_q.rd             <= mem_i.rd;
      mw_q.rd_we          <= mem_i.rd_we;
      mw_q.result         <= is_sc ? XLEN'(sc_skip || in_fault) : mem_i.result;
      mw_q.next_pc        <= mem_i.next_pc;
      mw_q.pc             <= mem_i.pc;
      mw_q.instr          <= mem_i.instr;
      mw_q.sys_op         <= mem_i.sys_op;
      mw_q.rs1_addr       <= mem_i.rs1_addr;
      mw_q.rs2_addr       <= mem_i.rs2_addr;
      mw_q.rs1_rdata      <= mem_i.rs1_rdata;
      mw_q.rs2_rdata      <= mem_i.rs2_rdata;
      mw_q.csr_we         <= mem_i.csr_we;
      mw_q.csr_addr       <= mem_i.csr_addr;
      mw_q.csr_wdata      <= mem_i.csr_wdata;
      mw_q.sb_alloc       <= in_mem && !in_fault && wr_acc;
      mw_q.exc            <= mem_i.exc || in_fault;
      mw_q.exccode        <= mem_i.exc ? mem_i.exccode : fault_code;
      mw_q.exctval        <= mem_i.exc ? mem_i.exctval : in_addr;
      mw_q.mem_addr       <= in_addr;
      mw_q.mem_rmask      <= (in_mem && !in_fault && rd_acc) ? acc_bytes : '0;
      mw_q.mem_wmask      <= (in_mem && !in_fault && wr_acc) ? acc_bytes : '0;
      mw_q.mem_rdata      <= '0;
      mw_q.mem_wdata      <= mem_i.mem_wdata & size_mask(in_lg);
      mw_read_q     <= in_ok_read;
      mw_bus_q      <= in_ok_read && bus_need;
      mw_fence_q    <= is_fence;
      mw_amox_q     <= in_ok_read && is_amox;
      mw_lr_q       <= in_ok_read && is_lr;
      mw_need_hi_q  <= need_hi;
      mw_hi_sent_q  <= !(need_lo && need_hi);
      mw_lo_got_q   <= 1'b0;
      mw_wdata_q    <= mem_i.mem_wdata;
      mw_mask_q     <= in_mask;
      mw_fwd_mask_q <= fwd_mask;
      mw_fwd_data_q <= fwd_data;
      mw_lg_q       <= in_lg;
      mw_sext_q     <= in_sext;
      mw_mode_q     <= priv_i;
      mw_amo_op_q   <= mem_i.amo_op;
    end else begin
      if (mw_done || flush_i) mw_valid_q <= 1'b0;
      if (a_go)               mw_hi_sent_q <= 1'b1;
      if (lo_rsp_now) begin
        mw_lo_got_q   <= 1'b1;
        mw_lo_rdata_q <= dmem_rsp_i.rdata;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Completion
  // ---------------------------------------------------------------------------
  logic [WIN_W-1:0] bus_win, fwd_bytes, merged;
  logic [XLEN-1:0]  raw, old_val, opa, opb, new_val;
  logic             word;
  assign bus_win   = {hi_rsp_now ? dmem_rsp_i.rdata : XLEN'(0),
                      lo_rsp_now ? dmem_rsp_i.rdata : mw_lo_rdata_q};
  assign fwd_bytes = byte_expand(mw_fwd_mask_q);
  assign merged    = (mw_fwd_data_q & fwd_bytes) | (bus_win & ~fwd_bytes);
  assign raw       = XLEN'(merged >> (32'(mw_q.mem_addr[OFF_W-1:0]) * BYTE_W)) & size_mask(mw_lg_q);
  assign old_val   = extend(raw, mw_lg_q, mw_sext_q);

  // AMO: operands at the access width, sign-extended for MIN/MAX (RV64A).
  assign word = (mw_lg_q != LG_W'(OFF_W));
  assign opa  = old_val;
  assign opb  = word ? extend(mw_wdata_q, mw_lg_q, 1'b1) : mw_wdata_q;
  always_comb begin
    new_val = opb;
    unique case (mw_amo_op_q)
      AMO_ADD:  new_val = opa + opb;
      AMO_XOR:  new_val = opa ^ opb;
      AMO_AND:  new_val = opa & opb;
      AMO_OR:   new_val = opa | opb;
      AMO_MIN:  new_val = ($signed(opa) < $signed(opb)) ? opa : opb;
      AMO_MAX:  new_val = ($signed(opa) > $signed(opb)) ? opa : opb;
      AMO_MINU: new_val = (opa < opb) ? opa : opb;
      AMO_MAXU: new_val = (opa > opb) ? opa : opb;
      default:  new_val = opb;                                    // AMO_SWAP
    endcase
    new_val = new_val & size_mask(mw_lg_q);
  end

  logic amo_alloc, lr_set;
  always_comb begin
    wb_o       = mw_q;
    // Do not gate the completion handshake with flush_i.  WB uses this valid
    // together with the instruction fields to generate the retire flush.  If
    // wb_valid_o disappears while flush_i rises, the combinational path can
    // oscillate between valid and flush; keep the completion independent.
    wb_valid_o = mw_done;
    if (mw_read_q) begin
      wb_o.result    = old_val;
      wb_o.mem_rdata = raw;
      if (mw_amox_q) wb_o.mem_wdata = new_val;
      if (read_err_now) begin
        // mtval names the faulting part, as for a straddling fetch.
        wb_o.exc       = 1'b1;
        wb_o.exccode   = mw_amox_q ? EXC_STORE_ACCESS_FAULT : EXC_LOAD_ACCESS_FAULT;
        wb_o.exctval   = outst_hi_q ? {mw_q.mem_addr[XLEN-1:OFF_W] + BEAT_W'(1), OFF_W'(0)}
                                    : mw_q.mem_addr;
        wb_o.sb_alloc  = 1'b0;
        wb_o.mem_rmask = '0;
        wb_o.mem_wmask = '0;
      end
    end
  end
  // An instruction in MEM/WB that is not completing this cycle.  It is past
  // EX/MEM, so ID cannot see it there, yet it has not finished: ID must stall
  // a consumer of its rd, and treat the pipeline as busy for serialisation.
  // Only a read waiting on the bus, or a FENCE waiting for the store buffer
  // to drain, can be in this state.
  assign wb_pend_o = mw_valid_q && !mw_done;

  assign amo_alloc = wb_valid_o && mw_amox_q && !wb_o.exc;
  assign lr_set    = wb_valid_o && mw_lr_q   && !wb_o.exc;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      res_valid_q <= 1'b0;
      res_addr_q  <= '0;
      res_lg_q    <= '0;
    end else if (flush_i || (accept && is_sc && !mem_i.exc)) begin
      res_valid_q <= 1'b0;
    end else if (lr_set) begin
      res_valid_q <= 1'b1;
      res_addr_q  <= mw_q.mem_addr;
      res_lg_q    <= mw_lg_q;
    end
  end

  // ---------------------------------------------------------------------------
  // Store buffer update.  Allocation is a store or SC in MEM, or an AMO
  // completing in MEM/WB -- never both in one cycle, and never during a flush
  // (mem_ready_o is low then, and wb_valid_o remains an independent result
  // handshake for WB to generate the retire flush).
  //
  //   pop     the head drained: advance the head
  //   commit  one more of the oldest entries is committed.  A count, so an
  //           AMO that allocates and is committed by WB in the same cycle is
  //           not lost -- the commit needs no delay to find its entry.  WB only
  //           commits an instruction MEM gave it with sb_alloc set, so there
  //           is always an uncommitted entry for it (contract on sb_commit_i).
  //   flush   drop the uncommitted tail: the committed ones are the oldest,
  //           so that is just cnt = ncom
  //   alloc   write the entry at the tail; nothing else moves
  // ---------------------------------------------------------------------------
  logic                 alloc;
  logic [BEAT_W-1:0]    al_beat;
  logic [OFF_W-1:0]     al_off;
  logic [LG_W-1:0]      al_lg;
  logic [WIN_BYTES-1:0] al_mask;
  logic [WIN_W-1:0]     al_data;
  logic [1:0]           al_mode;

  always_comb begin
    alloc   = accept && in_ok_write;
    al_beat = in_beat;
    al_off  = in_off;
    al_lg   = in_lg;
    al_mask = in_mask;
    al_data = in_wdata;
    al_mode = priv_i;
    if (amo_alloc) begin
      alloc   = 1'b1;
      al_beat = mw_q.mem_addr[XLEN-1:OFF_W];
      al_off  = mw_q.mem_addr[OFF_W-1:0];
      al_lg   = mw_lg_q;
      al_mask = mw_mask_q;
      al_data = WIN_W'(new_val) << (32'(mw_q.mem_addr[OFF_W-1:0]) * BYTE_W);
      al_mode = mw_mode_q;
    end
  end

  logic [PTR_W-1:0] sb_head_d, sb_tail;
  logic [CNT_W-1:0] sb_cnt_d, sb_ncom_d, cnt_pop, ncom_pop;

  always_comb begin
    cnt_pop   = sb_cnt_q  - CNT_W'(pop_now);
    ncom_pop  = sb_ncom_q - CNT_W'(pop_now);
    sb_head_d = pop_now ? ptr_add(sb_head_q, CNT_W'(1)) : sb_head_q;
    sb_tail   = ptr_add(sb_head_q, sb_cnt_q);           // a pop moves both ends of this sum

    sb_ncom_d = ncom_pop + CNT_W'(sb_commit_i);

    if (flush_i) sb_cnt_d = sb_ncom_d;
    else         sb_cnt_d = cnt_pop + CNT_W'(alloc);
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      sb_beat_q    <= '0;
      sb_off_q     <= '0;
      sb_lg_q      <= '0;
      sb_mask_q    <= '0;
      sb_data_q    <= '0;
      sb_mode_q    <= '0;
      sb_head_q    <= '0;
      sb_cnt_q     <= '0;
      sb_ncom_q    <= '0;
      dr_lo_sent_q <= 1'b0;
      dr_hi_sent_q <= 1'b0;
    end else begin
      if (alloc) begin
        sb_beat_q[sb_tail] <= al_beat;
        sb_off_q[sb_tail]  <= al_off;
        sb_lg_q[sb_tail]   <= al_lg;
        sb_mask_q[sb_tail] <= al_mask;
        sb_data_q[sb_tail] <= al_data;
        sb_mode_q[sb_tail] <= al_mode;
      end
      sb_head_q <= sb_head_d;
      sb_cnt_q  <= sb_cnt_d;
      sb_ncom_q <= sb_ncom_d;
      if (pop_now) begin
        dr_lo_sent_q <= 1'b0;
        dr_hi_sent_q <= 1'b0;
      end else if (c_go) begin
        if (new_hi) dr_hi_sent_q <= 1'b1;
        else        dr_lo_sent_q <= 1'b1;
      end
    end
  end

  assign sb_empty_o       = (sb_cnt_q == '0);
  assign sb_full_o        = (32'(sb_cnt_q) == STORE_BUF_N);
  assign store_err_o      = rsp_drain && dmem_rsp_i.err;
  assign store_err_addr_o = outst_hi_q ? {hd_beat + BEAT_W'(1), OFF_W'(0)}
                                       : {hd_beat, hd_off};

  // id: one outstanding request.  errcode: encoding undefined in I2.  aq/rl
  // need no action: one access in flight and a FIFO store buffer already
  // order every access as they ask.  cacheable: no D$ here to bypass.
  logic unused_inputs;
  always_comb begin
    unused_inputs = ^{dmem_rsp_i.id, dmem_rsp_i.errcode, mem_i.aq, mem_i.rl, pma_i.cacheable};
  end

endmodule
