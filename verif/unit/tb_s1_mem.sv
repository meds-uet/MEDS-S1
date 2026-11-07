// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// Author(s)    : Eman Nasar <fatehulnasareman@gmail.com>, GitHub EmanNasar001 (Oct,2026)
// Modified By  :
//
// tb_s1_mem : unit testbench for s1_mem                           [WIP -- R-02]
//
// s1_mem is sequential, holds a store buffer and a reservation, and talks to a
// bus that answers late, so a cycle-by-cycle golden copy of it would be a
// second implementation of the same design -- and would agree with it about
// any shared mistake.  This testbench checks it against MEMORY instead, at two
// levels, which is what the design actually promises:
//
//   prog[]  what the program has stored.  Updated the moment an access is
//           accepted into MEM, in program order.  Every load, LR and AMO must
//           read exactly this, whether the bytes came from the bus, from the
//           store buffer by forwarding, or from both.
//   phys[]  what the bus has actually been told.  Updated only when a write
//           request fires.  This is allowed to lag prog[] -- that lag IS the
//           store buffer -- but the moment sb_empty_o goes high the two must
//           agree, byte for byte.
//
// That second property is the one worth having: it says a drained buffer has
// really drained, which is what FENCE rests on, and it catches a store that
// was dropped, duplicated, written at the wrong address, or written with the
// wrong byte enables, none of which a forwarding-only check would notice.
//
// The address map gives each 4 KiB page a different PMA so one random stream
// reaches every path: misaligned (beat-straddling) accesses, non-idempotent
// and strongly-ordered ordering stalls, regions that refuse atomics, a PMP
// that denies writes, an unmapped hole, and a bus that returns an error on a
// read, on a straddling read, or on a drained write.
//
// Two rules are checked directly rather than through a data effect, because
// neither has one: P1 (a non-idempotent read is never speculative) only
// changes timing, so the ordering rule itself is asserted; and store_err_o is
// imprecise by construction, so the write-error page is the one place the two
// models are MEANT to diverge and is excluded from the byte comparison.
//
// Because the stimulus is random, the coverage counts at the end are asserted
// rather than printed: "passed" and "did not run" must not look alike.
//
// This file holds the stimulus, the bus functional model and the protocol
// checks.  The environment it checks against is next door, so that a D$ or LSU
// testbench can reuse it and so that no file passes R-C6's 800 lines:
//   verif/common/s1_mem_model.svh   the address map, the two memory models
//   verif/common/s1_mem_golden.svh  the expectation model and the comparisons
//
// Run:  make test-unit            (all testbenches)
//       make test-unit TB=s1_mem  (just this one)
// =============================================================================

module tb_s1_mem
  import s1_pkg::*;
;

  localparam int unsigned SBN        = 4;            // store buffer entries
  localparam int unsigned BYTE_W     = 8;
  localparam int unsigned BEAT_BYTES = XLEN / BYTE_W;
  localparam int unsigned OFF_W      = $clog2(BEAT_BYTES);

  localparam int unsigned NPAGE = 10;                // see the page map below
  localparam int unsigned PGSZ  = 128;               // modelled bytes per page
  localparam int unsigned MAXOFF = PGSZ - BEAT_BYTES; // widest access still fits

  localparam logic [XLEN-1:0] BASE = 64'h0000_0000_8000_0000;

  localparam int unsigned PG_FAULT   = 6;            // unmapped
  localparam int unsigned PG_RDERR   = 7;            // bus errors on reads
  localparam int unsigned PG_WRERR   = 8;            // bus errors on drained writes
  localparam int unsigned PG_RDERR_M = 9;            // reads error, and may straddle
  localparam int unsigned PG_NOWRITE = 5;            // PMP denies W

  localparam int unsigned STALL_LIMIT = 500;         // a longer stall is a hang

  // ---------------------------------------------------------------------------
  // DUT connections
  // ---------------------------------------------------------------------------
  logic             clk, rst_n;
  logic             flush;
  priv_lvl_e        priv;

  logic             mem_valid;
  logic             mem_ready;
  ex_mem_t          mem_in;

  logic             wb_valid;
  mem_wb_t          wb_out;
  logic             wb_pend;

  logic             sb_commit;

  logic [XLEN-1:0]  chk_addr;
  logic [2:0]       chk_size;
  logic             chk_rd, chk_wr;
  priv_lvl_e        chk_priv;
  pma_t             pma;
  logic             pma_fault, pmp_allow;

  logic             req_valid, req_ready;
  mem_req_t         req;
  logic             rsp_valid, rsp_ready;
  mem_rsp_t         rsp;

  logic             sb_empty, sb_full, store_err;
  logic [XLEN-1:0]  store_err_addr;

  int unsigned checks = 0;
  int unsigned errors = 0;
  string       phase = "init";
  string       ctx   = "init";

  s1_mem #(.STORE_BUF_N(SBN)) dut (
    .clk_i             (clk),
    .rst_ni            (rst_n),
    .flush_i           (flush),
    .priv_i            (priv),
    .mem_valid_i       (mem_valid),
    .mem_ready_o       (mem_ready),
    .mem_i             (mem_in),
    .wb_valid_o        (wb_valid),
    .wb_o              (wb_out),
    .wb_pend_o         (wb_pend),
    .sb_commit_i       (sb_commit),
    .chk_addr_o        (chk_addr),
    .chk_size_o        (chk_size),
    .chk_rd_o          (chk_rd),
    .chk_wr_o          (chk_wr),
    .chk_priv_o        (chk_priv),
    .pma_i             (pma),
    .pma_fault_i       (pma_fault),
    .pmp_allow_i       (pmp_allow),
    .dmem_req_valid_o  (req_valid),
    .dmem_req_ready_i  (req_ready),
    .dmem_req_o        (req),
    .dmem_rsp_valid_i  (rsp_valid),
    .dmem_rsp_ready_o  (rsp_ready),
    .dmem_rsp_i        (rsp),
    .sb_empty_o        (sb_empty),
    .sb_full_o         (sb_full),
    .store_err_o       (store_err),
    .store_err_addr_o  (store_err_addr)
  );

  `include "verif/common/s1_mem_model.svh"

  // ---------------------------------------------------------------------------
  // The reservation, modelled independently of the DUT's copy
  // ---------------------------------------------------------------------------
  logic            res_valid;
  logic [XLEN-1:0] res_addr;
  int unsigned     res_lg;

  // MEM passes `tag` through without reading it; a running count is enough
  // to check that it does.
  int unsigned tag_ctr;

  // ---------------------------------------------------------------------------
  // Expectation for the instruction in MEM/WB.  MEM/WB is one register, so
  // there is only ever one, and completion is in order.
  // ---------------------------------------------------------------------------
  logic            e_live;            // shadow of mw_valid_q
  ex_mem_t         e_in;
  logic            e_exc;
  logic [5:0]      e_exccode;
  logic [XLEN-1:0] e_exctval;
  logic [XLEN-1:0] e_result;
  logic [XLEN-1:0] e_rdata, e_wdata;
  logic [7:0]      e_rmask, e_wmask;
  logic            e_sb_alloc;
  logic            e_is_read, e_amox, e_lr, e_sc;
  int unsigned     e_lg, e_pg, e_off;
  logic [XLEN-1:0] e_amo_new;
  logic            e_bus_err;         // this read will come back with err

  // Retire side: the testbench is WB, so it owns sb_commit.  Commit is in
  // order and carries no tag: pend_n counts completed stores not yet
  // committed.  A commit is sometimes issued in the very cycle the store
  // completes -- what s1_wb does -- and sometimes later, with jitter.
  int unsigned      pend_n;
  logic             commit_now;      // this cycle's completion was committed in-cycle

  int unsigned stall_cnt;
  int unsigned completions;

  // ---------------------------------------------------------------------------
  // Coverage.  A random testbench that passes without reaching the hard cases
  // has not tested them, and "passed" and "did not run" must not look alike --
  // so the counts below are asserted at the end, not merely printed.
  // ---------------------------------------------------------------------------
  int unsigned n_load, n_store, n_amo, n_lr, n_sc_ok, n_sc_fail;
  int unsigned n_straddle, n_fault, n_rderr, n_storeerr, n_sbfull, n_stall, n_fwd;
  int unsigned n_rderr_strad;      // a read that errored AND straddled two beats
  int unsigned n_fence, n_fence_wait;  // fences, and cycles one was held for the drain
  int unsigned n_commit_same;      // commits issued in the completion cycle

  logic [XLEN-1:0] last_st_beat;      // beat of the most recent allocation
  logic            last_st_valid;

  logic [XLEN-1:0] fwd_addr;          // reused by a later load, to force a hit
  int unsigned     fwd_lg;
  logic            fwd_valid;
  logic        scoreboard;            // data checking on (off during the flush phase)

  // ---------------------------------------------------------------------------
  // Clock
  // ---------------------------------------------------------------------------
  // An initial/forever block, not an always: 5.020 reports a blocking
  // assignment in an always with a delay as BLKSEQ, and the repo's waiver file
  // takes reasons, not suppressions for something this easy to write properly.
  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  // ---------------------------------------------------------------------------
  // Generation state
  // ---------------------------------------------------------------------------
  logic        gen_pending;           // mem_in is presented and not yet accepted
  logic        gen_off;               // stop issuing entirely, so a drain drains
  int unsigned gen_lo_page, gen_hi_page;
  logic        gen_atomics, gen_rderr, gen_wrerr, gen_pairs, gen_fences;
  int unsigned pair_state;            // 1 = an LR has been issued, SC next
  int unsigned pair_pg, pair_off, pair_lg;

  function automatic logic is_amox_op(input amo_op_e o);
    return (o != AMO_NONE) && (o != AMO_LR) && (o != AMO_SC);
  endfunction

  `include "verif/common/s1_mem_golden.svh"

  // ---------------------------------------------------------------------------
  // One cycle: look at what the cycle did, then set up the next one
  // ---------------------------------------------------------------------------
  task automatic observe();
    logic accept, did_complete, amo_wrote;

    // ---- the query is a pure function of the instruction in MEM ------------
    check ("chk_addr",  chk_addr, mem_in.mem_addr);
    check ("chk_size",  chk_size, mem_in.mem_size);
    check1("chk_rd",    chk_rd,   mem_in.is_load || (mem_in.amo_op == AMO_LR)
                                  || is_amox_op(mem_in.amo_op));
    check1("chk_wr",    chk_wr,   mem_in.is_store || (mem_in.amo_op == AMO_SC)
                                  || is_amox_op(mem_in.amo_op));
    check ("chk_priv",  chk_priv, priv);

    // ---- bus protocol -------------------------------------------------------
    check1("rsp_ready is constant 1", rsp_ready, 1'b1);
    if (prev_req_stalled) begin
      // R-C10: a presented request is frozen until it is taken.  A request
      // that changes under backpressure is the bug that corrupts one access
      // with another's address.
      check1("stalled req stays valid", req_valid, 1'b1);
      check ("stalled req addr held",   req.addr,  prev_req.addr);
      check ("stalled req be held",     req.be,    prev_req.be);
      check ("stalled req wdata held",  req.wdata, prev_req.wdata);
      check1("stalled req we held",     req.we,    prev_req.we);
    end
    if (req_valid && req_ready) begin
      check1("no second request outstanding", bus_busy && !rsp_valid, 1'b0);
    end
    if (rsp_valid) check1("response only when owed", bus_busy, 1'b1);

    // ---- service the bus ----------------------------------------------------
    if (rsp_valid) bus_busy = 1'b0;
    if (req_valid && req_ready) begin
      if (req.we) bus_apply_write(req);
      bus_busy  = 1'b1;
      bus_addr  = req.addr;
      bus_we    = req.we;
      bus_err   = req.we ? (page_of(req.addr) == PG_WRERR)
                         : page_rderr(page_of(req.addr));
      bus_delay = $urandom_range(3, 0);
    end

    // ---- store errors are reported, imprecisely, as a pulse ----------------
    if (store_err) begin
      check1("store_err only on a write", bus_we || rsp_valid, 1'b1);
      n_storeerr++;
    end
    if (sb_full) n_sbfull++;
    if (wb_pend && e_live && (e_in.sys_op == SYS_FENCE || e_in.sys_op == SYS_FENCE_I)) n_fence_wait++;
    if (mem_valid && !mem_ready) n_stall++;

    // ---- completion ---------------------------------------------------------
    did_complete = wb_valid;
    amo_wrote    = 1'b0;
    if (wb_valid) begin
      check1("flush blocks completion", flush, 1'b0);
      check1("something was in MEM/WB", e_live, 1'b1);
      if (scoreboard && e_live) check_completion();
      if (e_live && e_bus_err) begin
        n_rderr++;
        if ((e_off % BEAT_BYTES) + (32'(1) << e_lg) > BEAT_BYTES) n_rderr_strad++;
      end
      completions++;

      // Deferred AMO write: it happens only if the access did not fault, which
      // is exactly the condition the RTL allocates its buffer entry under.
      if (e_live && e_amox && e_is_read && !wb_out.exc) begin
        prog_write(e_pg, e_off, e_lg, e_amo_new);
        amo_wrote = 1'b1;
      end

      // LR arms the reservation; a clear from an SC accepted this cycle wins,
      // so the clear is applied after this in install_expectation().
      if (e_live && e_lr && !wb_out.exc) begin
        res_valid = 1'b1;
        res_addr  = e_in.mem_addr;
        res_lg    = e_lg;
      end

      // A FENCE is only ever shown to WB with the store buffer empty, so WB
      // never has a reason to refuse it.  One that arrived excepted traps
      // instead, and need not wait.
      if ((wb_out.sys_op == SYS_FENCE || wb_out.sys_op == SYS_FENCE_I) && !wb_out.exc) begin
        check1("fence completes only with the buffer empty", sb_empty, 1'b1);
        check1("fence completes only with no store on the bus", bus_busy && bus_we && !rsp_valid, 1'b0);
        n_fence++;
      end

      // Retire: a committed store is now owed a commit, unless drive() already
      // issued it in this cycle.
      if (e_live && wb_out.sb_alloc && !commit_now) begin
        pend_n++;
        // The value WB saw: in the flush phase prog[], and so e_amo_new,
        // no longer describe memory.  check_completion verifies it elsewhere.
        cq_push(e_pg, e_off, e_lg, wb_out.mem_wdata);
      end
      e_live = 1'b0;
    end

    // ---- an instruction past EX/MEM with no result yet must say so ---------
    if (scoreboard)
      check1("wb_pend", wb_pend, e_live && !did_complete);

    // ---- a drained buffer really is drained --------------------------------
    // Not in the cycle an AMO completes: prog[] has its write already, and
    // its buffer entry is only allocated on this edge.
    if (scoreboard && sb_empty && !bus_busy && pend_n == 0 && !e_live && !amo_wrote) begin
      check1("empty and full disagree", sb_empty && sb_full, 1'b0);
      check_drained();
    end

    // ---- accept from EX ----------------------------------------------------
    accept = mem_valid && mem_ready;
    if (accept) begin
      install_expectation();
      gen_pending = 1'b0;
      stall_cnt   = 0;
    end else if (mem_valid) begin
      stall_cnt++;
      if (stall_cnt > STALL_LIMIT) begin
        errors++;
        $display("  FAIL stalled %0d cycles with mem_valid high   [%s]", stall_cnt, ctx);
        $display("       sb_empty=%0b sb_full=%0b bus_busy=%0b wb_pend=%0b",
                 sb_empty, sb_full, bus_busy, wb_pend);
        $fatal(1, "tb_s1_mem: hang");
      end
    end
  endtask

  // ---------------------------------------------------------------------------
  // Drive the next cycle
  // ---------------------------------------------------------------------------
  task automatic drive();
    logic [31:0] r0, r1, r2, r3, r4, r5, r6, r7;
    int unsigned pg, off, lg, t;
    logic        want_store, want_atomic;

    // ---- bus response ------------------------------------------------------
    rsp_valid = 1'b0;
    rsp       = '0;
    if (bus_busy) begin
      if (bus_delay > 0) bus_delay--;
      else begin
        rsp_valid = 1'b1;
        rsp.id    = '0;
        rsp.err   = bus_err;
        rsp.rdata = bus_we ? '0 : bus_read_beat(bus_addr);
        if (bus_err) rsp.errcode = 2'd1;
      end
    end

    // ---- request backpressure ----------------------------------------------
    r0        = $urandom;
    req_ready = (r0[2:0] != 3'd0);                   // ready 7 cycles in 8

    // ---- WB's store-buffer commit ------------------------------------------
    // Settle first: wb_valid depends on the response driven above.  The
    // in-cycle commit is what s1_wb does, and is the case where an AMO
    // allocates and is committed on the same edge.  It is left out of the
    // flush phase, whose flush is decided after this point.
    #1;
    sb_commit  = 1'b0;
    commit_now = 1'b0;
    r1 = $urandom;
    if (pend_n > 0 && !flush) begin                  // WB commits nothing in a flush
      if (r1[1:0] != 2'd0) begin                     // a little jitter
        sb_commit = 1'b1;
        pend_n--;
        cq_commit();
      end
    end else if (scoreboard && wb_valid && wb_out.sb_alloc && r1[2]) begin
      sb_commit  = 1'b1;
      commit_now = 1'b1;
      n_commit_same++;
      cmem_write(e_pg, e_off, e_lg, wb_out.mem_wdata);
    end

    // ---- next instruction --------------------------------------------------
    // Responses and commits above keep flowing while generation is off, which
    // is what lets the stage actually drain.
    if (gen_off) begin
      mem_valid = 1'b0;
      return;
    end
    if (gen_pending) return;                         // frozen until accepted

    t = tag_ctr;
    tag_ctr++;

    r2 = $urandom; r3 = $urandom; r4 = $urandom;
    r5 = $urandom; r6 = $urandom; r7 = $urandom;

    mem_in = '0;
    mem_in.amo_op   = AMO_NONE;                      // never leave this at '0: that is AMO_LR
    mem_in.tag      = TAG_W'(t);
    mem_in.rd       = r2[4:0];
    mem_in.rd_we    = r2[5];
    mem_in.result   = {r3, r4};
    mem_in.next_pc  = {r4, r5} & ~64'h1;
    mem_in.pc       = {r5, r6} & ~64'h1;
    mem_in.instr    = r6;
    mem_in.sys_op   = SYS_NONE;
    mem_in.rs1_addr = r2[14:10];
    mem_in.rs2_addr = r2[19:15];
    mem_in.rs1_rdata = {r6, r7};
    mem_in.rs2_rdata = {r7, r2};
    mem_in.csr_we   = r2[20];
    mem_in.csr_addr = r3[11:0];
    mem_in.csr_wdata = {r4, r6};
    mem_in.mem_wdata = {r3, r7};

    // one instruction in 16 arrives already excepted, and must pass straight
    // through without touching memory
    if (r2[27:24] == 4'd0) begin
      mem_in.exc     = 1'b1;
      mem_in.exccode = EXC_ILLEGAL_INSTR;
      mem_in.exctval = {r5, r7};
    end

    // --- an LR/SC pair, so SC success is actually reached -------------------
    if (gen_pairs && pair_state == 1) begin
      mem_in.amo_op   = AMO_SC;
      mem_in.mem_size = ls_size_e'(pair_lg);
      mem_in.mem_addr = addr_of(pair_pg, pair_off);
      mem_in.exc      = 1'b0;
      pair_state      = 0;
      mem_valid       = 1'b1;
      gen_pending     = 1'b1;
      return;
    end

    // --- pick a region and a shape -----------------------------------------
    pg = gen_lo_page + (r2[23:16] % (gen_hi_page - gen_lo_page + 1));
    if (!gen_rderr && page_rderr(pg)) pg = 0;
    if (!gen_wrerr && pg == PG_WRERR) pg = 0;

    want_store  = r4[0];
    want_atomic = gen_atomics && (r4[3:1] == 3'd0);

    // The read-error page is read-only and is only read with the buffer empty:
    // nothing can then be forwarded, so the bus is certainly consulted and the
    // error is certain to appear.  The write-error page is plain-store-only,
    // so no access ever reads back a byte the bus refused to write.
    if (page_rderr(pg) && (want_store || !sb_empty)) pg = 0;
    if (pg == PG_WRERR && (want_atomic || !want_store)) pg = 0;

    lg = r3[17:16];
    // A misaligned offset only makes sense where the region allows it; keep
    // the widest access inside the modelled window either way.
    if (pma_of(pg).align_natural) off = (r3[25:19] << lg) % (MAXOFF + 1);
    else                          off = r3[25:19] % (MAXOFF + 1);
    off = off & ~((pma_of(pg).align_natural ? (32'(1) << lg) : 1) - 1);
    if (off > MAXOFF) off = MAXOFF & ~((32'(1) << lg) - 1);

    if (want_atomic) begin
      if (r5[0]) begin
        mem_in.amo_op = AMO_LR;
        if (gen_pairs) begin
          pair_state = 1; pair_pg = pg; pair_off = off; pair_lg = lg;
        end
      end else begin
        mem_in.amo_op = amo_op_e'(2 + (r5[7:1] % 9));   // SWAP..MAXU
      end
      // LR/SC and AMO are defined for 4- and 8-byte accesses only.
      if (lg < 2) lg = 2;
      if (page_rderr(pg) && !sb_empty) pg = 0;
      off = off & ~((32'(1) << lg) - 1);
      mem_in.mem_addr = addr_of(pg, off);
      mem_in.mem_size = ls_size_e'(lg);
    end else if (want_store) begin
      mem_in.is_store = 1'b1;
      mem_in.mem_addr = addr_of(pg, off);
      mem_in.mem_size = ls_size_e'(lg);
      fwd_addr  = mem_in.mem_addr;
      fwd_lg    = lg;
      fwd_valid = 1'b1;
    end else begin
      // Every so often, read exactly what the last store wrote.  While that
      // store is still in the buffer the read can only be answered by
      // forwarding, which is the path a purely random address rarely exercises
      // and the one that silently returns stale data when it is wrong.
      if (fwd_valid && r5[10:9] == 2'd0
          && page_of(fwd_addr) != PG_WRERR && !page_rderr(page_of(fwd_addr))) begin
        pg  = page_of(fwd_addr);
        off = off_of(fwd_addr);
        lg  = fwd_lg;
      end
      mem_in.is_load    = 1'b1;
      mem_in.mem_signed = r5[8];
      mem_in.mem_addr   = addr_of(pg, off);
      mem_in.mem_size   = ls_size_e'(lg);
    end

    // one instruction in 8 is neither a load nor a store, and when fences
    // are on, a quarter of those are FENCE or FENCE.I
    if (r4[6:4] == 3'd0) begin
      mem_in.is_load  = 1'b0;
      mem_in.is_store = 1'b0;
      mem_in.amo_op   = AMO_NONE;
      pair_state      = 0;
      if (gen_fences && r6[1:0] == 2'd0)
        mem_in.sys_op = r6[2] ? SYS_FENCE_I : SYS_FENCE;
    end

    mem_valid   = 1'b1;
    gen_pending = 1'b1;
  endtask

  task automatic step();
    @(posedge clk);
    prev_req_valid   = req_valid;
    prev_req         = req;
    prev_req_stalled = req_valid && !req_ready;
    observe();
    @(negedge clk);
    drive();
  endtask

  // ---------------------------------------------------------------------------
  // Stimulus
  // ---------------------------------------------------------------------------
  initial begin
    logic [31:0] seed;

    $display("=== tb_s1_mem : XLEN=%0d STORE_BUF_N=%0d ===", XLEN, SBN);

    // Both memories start identical, and not all zero: a load that returns 0
    // because nothing happened would otherwise look correct.
    for (int unsigned pg = 0; pg < NPAGE; pg++)
      for (int unsigned o = 0; o < PGSZ; o++) begin
        seed = $urandom;
        prog[pg][o] = seed[7:0];
        phys[pg][o] = seed[7:0];
        cmem[pg][o] = seed[7:0];
      end

    n_load = 0; n_store = 0; n_amo = 0; n_lr = 0; n_sc_ok = 0; n_sc_fail = 0;
    n_straddle = 0; n_fault = 0; n_rderr = 0; n_storeerr = 0;
    n_sbfull = 0; n_stall = 0; n_fwd = 0; n_rderr_strad = 0;
    last_st_beat  = '0;
    last_st_valid = 1'b0;
    fwd_addr      = '0;
    fwd_lg        = 0;
    fwd_valid     = 1'b0;
    gen_off     = 1'b0;
    rst_n       = 1'b0;
    flush       = 1'b0;
    priv        = PRIV_M;
    mem_valid   = 1'b0;
    mem_in      = '0;
    mem_in.amo_op = AMO_NONE;
    sb_commit   = 1'b0;
    commit_now  = 1'b0;
    cq_n        = 0;
    tag_ctr     = 0;
    n_fence = 0; n_fence_wait = 0; n_commit_same = 0;
    gen_fences  = 1'b0;
    req_ready   = 1'b1;
    rsp_valid   = 1'b0;
    rsp         = '0;
    bus_busy    = 1'b0;
    bus_delay   = 0;
    bus_addr    = '0;
    bus_we      = 1'b0;
    bus_err     = 1'b0;
    prev_req_valid   = 1'b0;
    prev_req         = '0;
    prev_req_stalled = 1'b0;
    res_valid   = 1'b0;
    res_addr    = '0;
    res_lg      = 0;
    e_live      = 1'b0;
    pend_n      = 0;
    stall_cnt   = 0;
    completions = 0;
    scoreboard  = 1'b1;
    gen_pending = 1'b0;
    pair_state  = 0;
    gen_atomics = 1'b0;
    gen_rderr   = 1'b0;
    gen_wrerr   = 1'b0;
    gen_pairs   = 1'b0;
    gen_lo_page = 0;
    gen_hi_page = 0;

    repeat (4) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    // Reset state: everything quiet, nothing owed.
    @(posedge clk);
    phase = "after reset";
    ctx   = "after reset";
    check1("reset: no request",  req_valid, 1'b0);
    check1("reset: no wb",       wb_valid,  1'b0);
    check1("reset: no wb_pend",  wb_pend,   1'b0);
    check1("reset: sb empty",    sb_empty,  1'b1);
    check1("reset: sb not full", sb_full,   1'b0);
    check1("reset: no store err", store_err, 1'b0);
    check1("reset: ready",       mem_ready, 1'b1);
    @(negedge clk);

    // --- phase 1: plain aligned RAM, loads and stores ------------------------
    phase = "phase1 aligned RAM";
    ctx   = "phase1 aligned RAM";
    gen_lo_page = 0; gen_hi_page = 0;
    repeat (3000) step();

    // --- phase 2: misaligned, so accesses straddle beats --------------------
    phase = "phase2 straddling";
    ctx   = "phase2 straddling";
    gen_lo_page = 1; gen_hi_page = 1;
    repeat (3000) step();

    // --- phase 3: atomics on a region that allows them ----------------------
    phase = "phase3 atomics";
    ctx   = "phase3 atomics";
    gen_lo_page = 0; gen_hi_page = 0; gen_atomics = 1'b1; gen_pairs = 1'b1;
    gen_fences  = 1'b1;
    repeat (4000) step();

    // --- phase 4: ordering regions, faults and PMP denial -------------------
    phase = "phase4 ordering and faults";
    ctx   = "phase4 ordering and faults";
    gen_lo_page = 0; gen_hi_page = 6;
    repeat (6000) step();

    // --- phase 5: everything, including both bus-error pages ----------------
    phase = "phase5 bus errors";
    ctx   = "phase5 bus errors";
    gen_lo_page = 0; gen_hi_page = 9; gen_rderr = 1'b1; gen_wrerr = 1'b1;
    repeat (10000) step();

    // --- drain and compare -------------------------------------------------
    phase = "drain";
    ctx   = "drain";
    gen_off = 1'b1;
    repeat (400) step();
    check1("drained: sb empty",   sb_empty, 1'b1);
    check1("drained: no wb_pend", wb_pend,  1'b0);
    check1("drained: no request", req_valid, 1'b0);
    check_drained();

    // --- phase 6: flush --------------------------------------------------
    // Data is not scoreboarded here: a flush discards uncommitted stores, so
    // the program-order model no longer describes the machine.  What is
    // checked is that nothing completes during a flush and that the stage
    // always comes back -- a stage that wedges after a flush is a dead core.
    phase = "phase6 flush";
    ctx   = "phase6 flush";
    for (int unsigned pg = 0; pg < NPAGE; pg++)
      for (int unsigned o = 0; o < PGSZ; o++) cmem[pg][o] = phys[pg][o];
    gen_off     = 1'b0;
    scoreboard  = 1'b0;
    gen_atomics = 1'b1;
    gen_lo_page = 0; gen_hi_page = 4;
    for (int unsigned n = 0; n < 4000; n++) begin
      logic [31:0] rf;
      rf    = $urandom;
      flush = (rf[5:0] == 6'd0);
      step();
      if (flush) begin
        check1("flush: nothing completes", wb_valid, 1'b0);
        // A flushed stage must accept work again, or the core is dead.
        flush = 1'b0;
        gen_pending = 1'b0;
        res_valid   = 1'b0;
        pend_n      = 0;
        cq_n        = 0;
        e_live      = 1'b0;
        begin
          int unsigned waited;
          waited = 0;
          while (!mem_ready && waited < STALL_LIMIT) begin
            step();
            waited++;
          end
          checks++;
          if (waited >= STALL_LIMIT) begin
            errors++;
            $display("  FAIL stage never became ready after a flush   [%s]", ctx);
          end
        end
      end
    end

    // Resynchronise and prove the stage still works after all that.
    phase = "phase6 recovery";
    ctx   = "phase6 recovery";
    flush = 1'b1; step(); flush = 1'b0;
    pend_n = 0;
    cq_n   = 0;
    gen_off = 1'b1;
    repeat (400) step();
    // Every store WB committed reached memory, and nothing it did not.
    check1("flushed: sb empty", sb_empty, 1'b1);
    check_committed();
    for (int unsigned pg = 0; pg < NPAGE; pg++)
      for (int unsigned o = 0; o < PGSZ; o++) prog[pg][o] = phys[pg][o];
    res_valid   = 1'b0;
    pend_n      = 0;
    e_live      = 1'b0;
    gen_pending = 1'b0;
    gen_atomics = 1'b1;
    gen_pairs   = 1'b1;
    gen_rderr   = 1'b0;
    gen_wrerr   = 1'b0;
    gen_lo_page = 0; gen_hi_page = 4;
    scoreboard  = 1'b1;
    gen_off     = 1'b0;
    repeat (3000) step();
    gen_off     = 1'b1;
    repeat (400) step();
    phase = "final";
    ctx   = "final";
    check1("final: sb empty", sb_empty, 1'b1);
    check_drained();

    $display("  coverage: ld=%0d st=%0d amo=%0d lr=%0d sc_ok=%0d sc_fail=%0d",
             n_load, n_store, n_amo, n_lr, n_sc_ok, n_sc_fail);
    $display("            straddle=%0d fault=%0d read_err=%0d (straddling %0d) store_err=%0d",
             n_straddle, n_fault, n_rderr, n_rderr_strad, n_storeerr);
    $display("            fwd_hit=%0d sb_full=%0d backpressure=%0d instr=%0d",
             n_fwd, n_sbfull, n_stall, completions);
    $display("            fence=%0d fence_wait_cycles=%0d same_cycle_commit=%0d",
             n_fence, n_fence_wait, n_commit_same);

    cover_min("instructions", completions, 2000);
    cover_min("loads",        n_load,      1000);
    cover_min("stores",       n_store,     1000);
    cover_min("AMOs",         n_amo,        200);
    cover_min("LRs",          n_lr,         100);
    cover_min("SC success",   n_sc_ok,       10);
    cover_min("SC failure",   n_sc_fail,     10);
    cover_min("straddling",   n_straddle,   200);
    cover_min("faults",       n_fault,      200);
    cover_min("read errors",  n_rderr,       10);
    cover_min("straddling read errors", n_rderr_strad, 3);
    cover_min("store errors", n_storeerr,     5);
    cover_min("forward hits", n_fwd,         50);
    cover_min("buffer full",  n_sbfull,      50);
    cover_min("backpressure", n_stall,      500);
    cover_min("fences",       n_fence,      100);
    cover_min("fence waits",  n_fence_wait,  50);
    cover_min("same-cycle commits", n_commit_same, 200);

    // ---------------------------------------------------------------------------
    if (errors == 0) begin
      $display("=== PASS : %0d checks, %0d instructions ===", checks, completions);
      $finish;
    end else begin
      $display("=== FAIL : %0d errors of %0d checks ===", errors, checks);
      $fatal(1, "tb_s1_mem failed");
    end
  end

endmodule
