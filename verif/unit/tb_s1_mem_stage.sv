// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// tb_s1_mem_stage : unit testbench for s1_mem_stage                  [WIP -- R-02]
//
// The testbench plays EX (drives EX/MEM), the completion buffer (head, commit,
// flush), the CSR file (PMP), the PMA decoder and the D$ (an I2 slave).
// Reference models live in verif/common/s1_mem_stage_model.svh.
//
//   * Every completion is scoreboarded against a program-order memory model:
//     architectural memory plus every older, unflushed store, AMO and SC.
//   * Every bus write is compared, in order, with the writes that retired.
//   * Every cycle: valid/payload independent of ready, payload stability, one
//     outstanding request, store-buffer occupancy, P1/P2 on every new read.
//
// Run:  make test-unit TB=s1_mem_stage
// =============================================================================

module tb_s1_mem_stage
  import s1_pkg::*;
;
  logic clk = 1'b0, rst_n = 1'b0;
  initial forever #5 clk = ~clk;

  ex_mem_t   ex;
  logic      ex_valid, ex_ready, wb_valid;
  priv_lvl_e priv;
  mem_wb_t   wb;
  logic [CB_IDX_W-1:0] head_idx, commit_idx;
  logic      commit, flush, mx_busy;
  logic [PMP_N-1:0][7:0]      pmpcfg;
  logic [PMP_N-1:0][PLEN-3:0] pmpaddr;
  logic [XLEN-1:0] pma_addr;
  logic [2:0] pma_size;
  pma_t      pma;
  logic      pma_fault;
  logic      rq_valid, rq_ready, rs_valid, rs_ready;
  mem_req_t  rq;
  mem_rsp_t  rs;
  logic      sb_empty, sb_full, store_err;
  logic [XLEN-1:0] store_err_addr;

  s1_mem_stage dut (
    .clk_i(clk), .rst_ni(rst_n), .flush_i(flush), .priv_i(priv),
    .mem_valid_i(ex_valid), .mem_ready_o(ex_ready), .mem_i(ex), .wb_valid_o(wb_valid), .wb_o(wb),
    .cb_head_idx_i(head_idx), .sb_commit_i(commit), .sb_commit_idx_i(commit_idx),
    .mxif_mem_busy_i(mx_busy), .pmpcfg_i(pmpcfg), .pmpaddr_i(pmpaddr),
    .pma_addr_o(pma_addr), .pma_size_o(pma_size), .pma_i(pma), .pma_fault_i(pma_fault),
    .dmem_req_valid_o(rq_valid), .dmem_req_ready_i(rq_ready), .dmem_req_o(rq),
    .dmem_rsp_valid_i(rs_valid), .dmem_rsp_ready_o(rs_ready), .dmem_rsp_i(rs),
    .sb_empty_o(sb_empty), .sb_full_o(sb_full), .store_err_o(store_err), .store_err_addr_o(store_err_addr)
  );

  `include "verif/common/s1_mem_stage_model.svh"

  int unsigned checks = 0, errors = 0;
  longint cyc = 0;

  task automatic check(input string name, input logic [XLEN-1:0] got, input logic [XLEN-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      if (errors <= 25) $display("  FAIL @%0d %-34s got=0x%016h exp=0x%016h", cyc, name, got, exp);
    end
  endtask

  rec_t cb[$], done_log[$];
  typedef struct { logic [XLEN-1:0] addr; logic [7:0] be; logic [XLEN-1:0] wdata;
                   priv_lvl_e mode; bit last; } drain_t;
  drain_t drq[$];
  ins_t   script[$];

  bit  gen_random = 0, serial = 0, force_busy = 0;
  int  p_rdy = 100, lat_max = 1, p_retire = 100, p_irq = 0, p_block = 0, force_irq_seq = -1;
  int  sb_unc = 0, sb_com = 0;
  int  n_rd = 0, n_wr = 0, n_store_err = 0;
  longint last_drain_done = -1;
  int  last_read_seq = -1;
  logic [XLEN-1:0] last_read_addr = '0;

  int cv_fwd_full, cv_fwd_part, cv_cross_load, cv_cross_store, cv_sb_full, cv_order, cv_head,
      cv_stale, cv_c_over_b, cv_flush_unc, cv_err_lo, cv_err_hi, cv_fault, cv_block, cv_hold,
      cv_upexc, cv_lr, cv_sc_ok, cv_sc_skip, cv_amo, cv_pmp, cv_misalign, cv_atomic;

  function automatic bit exp_exc(rec_t r);
    return r.ex.exc || r.fault || r.busrd_err;
  endfunction
  function automatic bit is_read(rec_t r);
    return r.kind inside {K_LOAD, K_LR, K_AMO};
  endfunction

  // ---------------------------------------------------------------------------
  // Sample just before the edge, probing that nothing depends on I2 ready
  // ---------------------------------------------------------------------------
  bit sl_busy, sl_err, sl_we, sl_last;
  longint sl_due;
  logic [XLEN-1:0] sl_rdata, sl_addr;
  bit ex_on = 0, flush_pending = 0;
  int stall_cycles = 0;

  logic s_rq_valid, s_rq_ready, s_rs_valid, s_ex_valid, s_ex_ready, s_flush, s_commit, s_wb_valid;
  logic p_rq_valid = 0, p_rq_ready = 0;
  mem_req_t s_rq, p_rq;
  mem_wb_t s_wb;
  logic s_sb_empty, s_sb_full, s_store_err;
  logic [XLEN-1:0] s_store_err_addr;
  logic [CB_IDX_W-1:0] s_head;

  task automatic sample_and_probe();
    logic v0, e0, w0;
    mem_req_t r0;
    #3;
    v0 = rq_valid; r0 = rq; e0 = ex_ready; w0 = wb_valid;
    rq_ready = ~rq_ready; #1;
    check("R-C10 req_valid vs ready", XLEN'(rq_valid), XLEN'(v0));
    if (v0) check("R-C10 req payload vs ready", XLEN'(rq == r0), 1);
    check("mem_ready vs I2 ready", XLEN'(ex_ready), XLEN'(e0));
    check("wb_valid vs I2 ready", XLEN'(wb_valid), XLEN'(w0));
    rq_ready = ~rq_ready; #3;
    s_rq_valid = rq_valid; s_rq_ready = rq_ready; s_rq = rq; s_rs_valid = rs_valid;
    s_ex_valid = ex_valid; s_ex_ready = ex_ready; s_wb_valid = wb_valid; s_wb = wb;
    s_flush = flush; s_commit = commit; s_sb_empty = sb_empty; s_sb_full = sb_full;
    s_store_err = store_err; s_store_err_addr = store_err_addr; s_head = head_idx;
    if (dut.accept && dut.in_ok_read && !dut.bus_need) cv_fwd_full++;
    if (dut.accept && dut.in_ok_read && dut.bus_need && |dut.fwd_mask) cv_fwd_part++;
    if (dut.a_go) cv_cross_load++;
    if (dut.c_go && dut.new_hi) cv_cross_store++;
    if (sb_full && ex_valid && dut.in_ok_write && !ex_ready) cv_sb_full++;
    if (ex_valid && dut.order_wait) cv_order++;
    if (ex_valid && dut.head_wait) cv_head++;
    if (dut.rsp_fire && !dut.outst_drain_q && !(dut.mw_valid_q && dut.mw_bus_q)) cv_stale++;
    if (dut.c_go && dut.b_want) cv_c_over_b++;
    if (mx_busy && dut.in_mem && !dut.in_fault) cv_block++;
    if (dut.hold_q) cv_hold++;
  endtask

  // ---------------------------------------------------------------------------
  // After each edge: account for what happened in the sampled cycle
  // ---------------------------------------------------------------------------
  task automatic account();
    bit progress = 0;
    int lowest;
    logic [XLEN-1:0] bmask;
    check("rsp_ready constant 1", XLEN'(rs_ready), 1);
    check("sampled sb_empty", XLEN'(s_sb_empty), XLEN'(sb_unc + sb_com == 0));
    check("sampled sb_full", XLEN'(s_sb_full), XLEN'(sb_unc + sb_com == SB_DEPTH));

    if (s_rs_valid) begin
      sl_busy = 0; progress = 1;
      check("store_err on drain error", XLEN'(s_store_err), XLEN'(sl_we && sl_err));
      if (sl_we && sl_err) begin
        n_store_err++;
        check("store_err_addr", s_store_err_addr, sl_addr);
      end
      if (sl_we && sl_last) begin sb_com--; last_drain_done = cyc - 1; end
    end else begin
      check("no store_err without response", XLEN'(s_store_err), 0);
    end
    if (s_commit) begin sb_unc--; sb_com++; end
    if (s_flush) begin
      if (sb_unc > 0) cv_flush_unc++;
      sb_unc = 0;
    end

    if (p_rq_valid && !p_rq_ready) begin
      check("R-C10 valid held", XLEN'(s_rq_valid), 1);
      check("R-C10 payload held", XLEN'(s_rq == p_rq), 1);
    end

    // A new read presentation: owner, P1 and P2.
    if (s_rq_valid && !(p_rq_valid && !p_rq_ready) && !s_rq.we) begin
      if (s_ex_valid && s_ex_ready && cb.size() > 0) begin
        rec_t o = cb[cb.size() - 1];
        check("read owner is a legal read", XLEN'(is_read(o) && !o.fault && !o.ex.exc), 1);
        check("read beat is the owner's", XLEN'((s_rq.addr >> OW) - (o.ex.mem_addr >> OW) <= 1), 1);
        if (o.ordered) check("P2: ordered read after older writes drain", XLEN'(sb_unc + sb_com), 0);
        if (o.mmio)    check("P1: non-idempotent read at head", XLEN'(s_head), XLEN'(o.ex.cb_idx));
      end else begin
        check("hi part follows a straddling read", XLEN'(last_read_seq >= 0), 1);
        check("hi part address", s_rq.addr, ((last_read_addr >> OW) + 1) << OW);
      end
    end

    if (s_rq_valid && s_rq_ready) begin
      progress = 1;
      check("one outstanding I2 request", XLEN'(sl_busy), 0);
      lowest = 0;
      while (lowest < 8 && !s_rq.be[lowest]) lowest++;
      check("be non-zero, addr on its lane", XLEN'(s_rq.be != 0 && s_rq.addr[OW-1:0] == OW'(lowest)), 1);
      check("id 0", XLEN'(s_rq.id), 0);
      sl_addr = s_rq.addr; sl_we = s_rq.we; sl_err = in_bad(s_rq.addr);
      sl_busy = 1; sl_due = cyc + ($urandom % lat_max);
      bmask = '0;
      for (int k = 0; k < 8; k++) bmask[8*k +: 8] = {8{s_rq.be[k]}};
      for (int k = lowest; k < 8; k++)
        if (s_rq.be[k]) check("bus access mapped", XLEN'(region(s_rq.addr + k - lowest, 1) != 0), 1);
      if (s_rq.we) begin
        n_wr++;
        check("bus write only for a retired write", XLEN'(drq.size() > 0), 1);
        if (drq.size() > 0) begin
          drain_t d = drq.pop_front();
          check("drain addr (retire order)", s_rq.addr, d.addr);
          check("drain be", XLEN'(s_rq.be), XLEN'(d.be));
          check("drain wdata", s_rq.wdata & bmask, d.wdata);
          check("drain mode", XLEN'(s_rq.mode), XLEN'(d.mode));
          sl_last = d.last;
        end
        if (!sl_err)
          for (int k = lowest; k < 8; k++)
            if (s_rq.be[k]) busm[s_rq.addr + k - lowest] = s_rq.wdata[8*k +: 8];
      end else begin
        n_rd++;
        sl_rdata = {$urandom, $urandom};
        for (int k = lowest; k < 8; k++)
          if (s_rq.be[k]) sl_rdata[8*k +: 8] = rd_bus(s_rq.addr + k - lowest);
      end
    end

    if (s_wb_valid) begin
      int i = 0;
      progress = 1;
      while (i < cb.size() && cb[i].completed) i++;
      check("completion has an owner", XLEN'(i < cb.size()), 1);
      if (i < cb.size()) begin
        rec_t r = cb[i];
        logic [7:0] bytes = 8'((9'd1 << (1 << r.lg)) - 1);
        bit ok = !exp_exc(r) && r.kind != K_OTHER && !r.sc_skip;
        check("completion order (cb_idx)", XLEN'(s_wb.cb_idx), XLEN'(r.ex.cb_idx));
        check("completion after accept", XLEN'(r.t_acc >= 0), 1);
        check("passthrough rd/complete/csr", XLEN'({s_wb.rd, s_wb.rd_we, s_wb.complete, s_wb.csr_we,
              s_wb.csr_addr}), XLEN'({r.ex.rd, r.ex.rd_we, r.ex.complete, r.ex.csr_we, r.ex.csr_addr}));
        check("passthrough next_pc", s_wb.next_pc, r.ex.next_pc);
        check("passthrough csr_wdata", s_wb.csr_wdata, r.ex.csr_wdata);
        check("exc", XLEN'(s_wb.exc), XLEN'(exp_exc(r)));
        if (exp_exc(r)) begin
          check("exccode", XLEN'(s_wb.exccode), XLEN'(r.code));
          check("exctval", s_wb.exctval, r.tval);
          if (r.fault)     cv_fault++;
          if (r.pmp_deny)  cv_pmp++;
          if (r.misalign)  cv_misalign++;
          if (r.atomic)    cv_atomic++;
          if (r.ex.exc)    cv_upexc++;
          if (r.busrd_err && r.tval == r.ex.mem_addr) cv_err_lo++;
          if (r.busrd_err && r.tval != r.ex.mem_addr) cv_err_hi++;
        end else begin
          check("result", s_wb.result, (r.kind == K_OTHER || r.kind == K_STORE) ? r.ex.result : r.val);
        end
        check("sb_alloc", XLEN'(s_wb.sb_alloc), XLEN'(r.alloc && !exp_exc(r)));
        check("rvfi rmask", XLEN'(s_wb.mem_rmask), XLEN'((ok && is_read(r)) ? bytes : 0));
        check("rvfi wmask", XLEN'(s_wb.mem_wmask), XLEN'((ok && r.alloc) ? bytes : 0));
        if (ok) check("rvfi addr", s_wb.mem_addr, r.ex.mem_addr);
        if (ok && is_read(r)) check("rvfi rdata", s_wb.mem_rdata, r.raw);
        if (ok && r.alloc)    check("rvfi wdata", s_wb.mem_wdata, r.wv);
        if (r.kind == K_LR && ok) cv_lr++;
        if (r.kind == K_SC && ok) cv_sc_ok++;
        if (r.sc_skip) cv_sc_skip++;
        if (r.kind == K_AMO && ok) begin cv_amo++; sb_unc++; end
        cb[i].completed = 1;
        cb[i].t_cmp     = cyc - 1;
        done_log.push_back(cb[i]);
        if (r.seq == last_read_seq) last_read_seq = -1;
      end
    end

    if (s_ex_valid && s_ex_ready) begin
      progress = 1;
      check("no transfer during flush", XLEN'(s_flush), 0);
      if (cb.size() > 0) begin
        rec_t r = cb[cb.size() - 1];
        cb[cb.size() - 1].t_acc = cyc - 1;
        if (r.alloc && r.kind != K_AMO && !exp_exc(r)) sb_unc++;
        if (is_read(r) && !r.fault && !r.ex.exc) begin
          last_read_seq  = r.seq;
          last_read_addr = r.ex.mem_addr;
        end
      end
      ex_on = 0;
    end

    p_rq_valid = s_rq_valid; p_rq_ready = s_rq_ready; p_rq = s_rq;
    stall_cycles = progress ? 0 : stall_cycles + 1;
    if (stall_cycles > 4000) $fatal(1, "tb_s1_mem_stage: no progress for 4000 cycles at %0d", cyc);
  endtask

  // ---------------------------------------------------------------------------
  // Drive the inputs for the cycle that has just started
  // ---------------------------------------------------------------------------
  task automatic drive();
    rs         = '0;
    rs.rdata   = {$urandom, $urandom};
    rs.errcode = 2'($urandom);
    rs_valid   = sl_busy && cyc >= sl_due;
    if (rs_valid) begin
      rs.err   = sl_err;
      rs.rdata = sl_we ? {$urandom, $urandom} : sl_rdata;
    end
    rq_ready = ($urandom % 100) < p_rdy;
    mx_busy  = force_busy || (($urandom % 100) < p_block);

    if (flush_pending) begin ex_on = 0; flush_pending = 0; end

    commit     = 1'b0;
    flush      = 1'b0;
    commit_idx = CB_IDX_W'($urandom);
    head_idx   = cb.size() > 0 ? cb[0].ex.cb_idx : CB_IDX_W'(next_tag);
    if (cb.size() > 0 && cb[0].completed && ($urandom % 100) < p_retire) begin
      rec_t h = cb[0];
      if (exp_exc(h) || (!(h.mmio && is_read(h)) && (h.seq == force_irq_seq || ($urandom % 1000) < p_irq))) begin
        flush = 1'b1;
        cb.delete();
        pom = arch;
        pres_valid = 0;
        flush_pending = 1;
        last_read_seq = -1;
        if (h.seq == force_irq_seq) force_irq_seq = -1;
      end else begin
        if (h.alloc) begin
          int unsigned n = 1 << h.lg, off = int'(h.ex.mem_addr[OW-1:0]);
          logic [2*XLEN-1:0] w;
          logic [2*BB-1:0]   bm;
          commit     = 1'b1;
          commit_idx = h.ex.cb_idx;
          for (int unsigned k = 0; k < n; k++) arch[h.ex.mem_addr + k] = h.wv[8*k +: 8];
          bm = (((2*BB)'(1) << n) - 1) << off;
          w  = (2*XLEN)'(h.wv) << (8*off);
          drq.push_back('{h.ex.mem_addr, bm[BB-1:0], w[XLEN-1:0], h.priv, bm[2*BB-1:BB] == 0});
          if (bm[2*BB-1:BB] != 0)
            drq.push_back('{((h.ex.mem_addr >> OW) + 1) << OW, bm[2*BB-1:BB], w[2*XLEN-1:XLEN], h.priv, 1});
        end
        void'(cb.pop_front());
      end
    end

    if (!ex_on && !flush && cb.size() < CB_DEPTH && (!serial || cb.size() == 0)
        && (script.size() > 0 || (gen_random && ($urandom % 100) < 80))) begin
      ins_t in = (script.size() > 0) ? script.pop_front() : rand_ins();
      rec_t r  = make_rec(in);
      cb.push_back(r);
      ex    = r.ex;
      priv  = in.priv;
      ex_on = 1;
    end
    ex_valid = ex_on;
    if (!ex_on) begin
      ex        = '0;
      ex.is_load = 1'($urandom); ex.is_amo = 1'($urandom); ex.amo_op = amo_op_e'($urandom % 12);
      ex.mem_addr = {$urandom, $urandom};
    end
  endtask

  task automatic step();
    sample_and_probe();
    @(posedge clk); #1;
    cyc++;
    account();
    drive();
  endtask

  // ---------------------------------------------------------------------------
  // Test helpers
  // ---------------------------------------------------------------------------
  function automatic ins_t I(int kind, int lg, logic [XLEN-1:0] addr, logic [XLEN-1:0] data = '0,
                             priv_lvl_e pv = PRIV_M, bit sext = 1, amo_op_e amo = AMO_SWAP, bit exc = 0);
    ins_t in;
    in.kind = kind; in.lg = lg; in.addr = addr; in.data = data; in.priv = pv; in.sext = sext;
    in.amo = amo; in.exc = exc;
    return in;
  endfunction

  function automatic rec_t find(int s);
    foreach (done_log[i]) if (done_log[i].seq == s) return done_log[i];
    foreach (cb[i])       if (cb[i].seq == s)       return cb[i];
    return blank_rec();
  endfunction

  function automatic int lat(int s);
    rec_t r = find(s);
    return (r.t_cmp < 0 || r.t_acc < 0) ? -1 : int'(r.t_cmp - r.t_acc);
  endfunction

  task automatic ideal();
    p_rdy = 100; lat_max = 1; p_retire = 100; p_irq = 0; p_block = 0;
    force_busy = 0; gen_random = 0; serial = 0;
  endtask

  task automatic run(int n);
    repeat (n) step();
  endtask

  task automatic drain();
    int i = 0;
    gen_random = 0; p_retire = 100; p_irq = 0; p_block = 0; force_busy = 0; p_rdy = (p_rdy < 20) ? 20 : p_rdy;
    while ((cb.size() > 0 || script.size() > 0 || ex_on || sb_unc + sb_com > 0 || sl_busy
            || drq.size() > 0) && i < 20000) begin
      step(); i++;
    end
    check("drained to idle", XLEN'(i < 20000), 1);
    run(2);
  endtask

  task automatic preload(logic [XLEN-1:0] a, byte unsigned v);
    arch[a] = v; pom[a] = v; busm[a] = v;
  endtask

  // PMP: 0 locked NA4 read-only, 1 TOR [DRAM, DRAM+128) RW, 2 NAPOT UNC RW,
  // 3 NAPOT MMIO read-only; anything else is M-only.
  task automatic pmp_default();
    pmpcfg = '0; pmpaddr = '0;
    pmpaddr[0] = (DRAM + 64'hC0) >> 2;             pmpcfg[0] = 8'h91;
    pmpaddr[1] = DRAM >> 2;
    pmpaddr[2] = (DRAM + 128) >> 2;                pmpcfg[2] = 8'h0B;
    pmpaddr[3] = (UNC >> 2) | ((UNC_SPAN >> 3) - 1); pmpcfg[3] = 8'h1B;
    pmpaddr[4] = (MMIO >> 2) | ((MMIO_SPAN >> 3) - 1); pmpcfg[4] = 8'h19;
  endtask

  task automatic pmp_fuzz();
    pmp_default();
    for (int i = 5; i < 9; i++) begin
      pmpaddr[i] = (PLEN-2)'(((DRAM + $urandom % DRAM_SPAN) >> 2) | ($urandom % 2 ? ((1 << ($urandom % 5)) - 1) : 0));
      pmpcfg[i]  = 8'($urandom) & 8'h9F;
    end
    pmpaddr[15] = '1; pmpcfg[15] = 8'h1F;          // everything else: RWX for U
  endtask

  // ---------------------------------------------------------------------------
  // Tests
  // ---------------------------------------------------------------------------
  typedef struct { int rdy, lat, ret, irq, blk, fuzz; } soak_t;

  initial begin
    int s0, rd0, wr0, e0;
    soak_t soaks[3] = '{'{100, 1, 70, 5, 0, 0}, '{60, 3, 40, 10, 3, 1}, '{25, 6, 15, 5, 5, 1}};
    amo_op_e amos[9] = '{AMO_SWAP, AMO_ADD, AMO_XOR, AMO_AND, AMO_OR, AMO_MIN, AMO_MAX, AMO_MINU, AMO_MAXU};

    ex = '0; ex_valid = 0; priv = PRIV_M; head_idx = '0; commit = 0; commit_idx = '0; flush = 0;
    mx_busy = 0; rq_ready = 0; rs_valid = 0; rs = '0;
    pmp_default();
    repeat (3) @(posedge clk);
    #1 rst_n = 1'b1;
    check("reset: no request", XLEN'(rq_valid), 0);
    check("reset: no completion", XLEN'(wb_valid), 0);
    check("reset: store buffer empty", XLEN'(sb_empty), 1);
    ideal();
    drive();

    $display("[directed] load widths and extension at every offset");
    for (int b = 0; b < 3*BB; b++) preload(DRAM + XLEN'(64 + b), (b % 2) ? 8'(8'h7F - b) : 8'(8'h80 + b));
    s0 = seq;
    for (int lg = 0; lg < 4; lg++) for (int sx = 0; sx < 2; sx++) for (int off = 0; off < BB; off++)
      script.push_back(I(K_LOAD, lg, DRAM + XLEN'(64 + off), 0, PRIV_M, sx[0]));
    drain();
    for (int k = 0; k < 8*BB; k++)
      check($sformatf("latency load #%0d", k), XLEN'(lat(s0 + k)), XLEN'((k % BB) + (1 << (k / (2*BB))) > BB ? 2 : 1));

    $display("[directed] one load per cycle");
    s0 = seq;
    for (int k = 0; k < 16; k++) script.push_back(I(K_LOAD, 3, DRAM + XLEN'(64 + BB*(k % 3))));
    drain();
    for (int k = 1; k < 16; k++) check("back-to-back accept", XLEN'(find(s0+k).t_acc - find(s0+k-1).t_acc), 1);

    $display("[directed] store-to-read forwarding, including AMO");
    ideal(); p_retire = 0; s0 = seq; rd0 = n_rd;
    script.push_back(I(K_STORE, 3, DRAM + 64'h40, 64'h1122_3344_5566_7788));
    script.push_back(I(K_LOAD, 3, DRAM + 64'h40));                 // fully forwarded
    script.push_back(I(K_LOAD, 2, DRAM + 64'h3E));                 // bus lo beat + forwarded hi beat
    script.push_back(I(K_LOAD, 2, DRAM + 64'h46, 0, PRIV_M, 0));   // forwarded lo beat + bus hi beat
    if (SB_DEPTH >= 2) begin
      script.push_back(I(K_AMO, 3, DRAM + 64'h40, 64'h10, PRIV_M, 1, AMO_ADD));  // forwarded, then stored
      script.push_back(I(K_LOAD, 3, DRAM + 64'h40));               // sees the AMO result
    end
    run(30);
    check("forwarding: bus reads", XLEN'(n_rd - rd0), 2);
    for (int k = 1; k < seq - s0; k++) if (k != 2 && k != 3) check("forwarded latency", XLEN'(lat(s0 + k)), 1);
    drain();

    $display("[directed] LR/SC");
    ideal();
    script.push_back(I(K_LR, 3, DRAM + 64'h58));
    script.push_back(I(K_SC, 3, DRAM + 64'h58, 64'hCAFE));        // succeeds: 0
    script.push_back(I(K_SC, 3, DRAM + 64'h58, 64'hBEEF));        // no reservation: 1
    script.push_back(I(K_LR, 2, DRAM + 64'h58));
    script.push_back(I(K_SC, 2, DRAM + 64'h5C, 64'h1));           // address mismatch: 1
    script.push_back(I(K_LR, 2, DRAM + 64'h58));
    script.push_back(I(K_SC, 3, DRAM + 64'h58, 64'h1));           // size mismatch: 1
    script.push_back(I(K_SC, 2, 64'h9000_0000, 64'h1));           // unmapped, but no reservation: 1
    script.push_back(I(K_LR, 2, UNC));                             // no atomic_lrsc: load fault
    drain();

    $display("[directed] AMO operations at both widths");
    ideal();
    foreach (amos[k]) for (int lg = 2; lg < 4; lg++) begin
      script.push_back(I(K_STORE, 3, DRAM + 64'h70, 64'h8000_0001_FFFF_FFFE));
      script.push_back(I(K_AMO, lg, DRAM + 64'h70, 64'h0000_0002_7FFF_FFFF, PRIV_M, 1, amos[k]));
      script.push_back(I(K_AMO, lg, DRAM + 64'h70, 64'hFFFF_FFFF_8000_0000, PRIV_M, 1, amos[k]));
      script.push_back(I(K_LOAD, 3, DRAM + 64'h70));
    end
    drain();
    serial = 1;
    script.push_back(I(K_AMO, 3, MMIO, 64'h1));                    // no atomic_amo: store fault
    script.push_back(I(K_AMO, 3, BAD, 64'h1));                     // read bus error: store fault
    drain();

    $display("[directed] PMP, alignment, faults, upstream exceptions, bus errors");
    ideal(); serial = 1; rd0 = n_rd; wr0 = n_wr;
    script.push_back(I(K_STORE, 2, DRAM + 64'hC0, 64'h1));          // locked read-only, even for M
    script.push_back(I(K_LOAD,  2, DRAM + 64'hC0, 0, PRIV_U));      // locked read-only allows the read ...
    script.push_back(I(K_LOAD,  3, DRAM + 64'hBE, 0, PRIV_U));      // ... but a partial match fails
    script.push_back(I(K_LOAD,  3, DRAM + 64'hD0, 0, PRIV_U));      // no entry: U fails
    script.push_back(I(K_STORE, 3, MMIO, 64'h1, PRIV_U));           // read-only MMIO for U
    script.push_back(I(K_LOAD,  2, MMIO + 64'h1));                  // misaligned
    script.push_back(I(K_LOAD,  0, MMIO));                          // width
    script.push_back(I(K_STORE, 2, UNC + 64'h2, 64'h1));            // misaligned
    script.push_back(I(K_LOAD,  3, 64'h9000_0000));                 // unmapped
    script.push_back(I(K_LOAD,  3, DRAM + XLEN'(DRAM_SPAN - 4)));  // past the region end
    script.push_back(I(K_LOAD,  2, MMIO + 64'h4, 0, PRIV_M, 1, AMO_SWAP, 1));
    script.push_back(I(K_STORE, 3, DRAM + 64'h8, 64'h1, PRIV_M, 1, AMO_SWAP, 1));
    drain();
    check("bus access only for the allowed U read", XLEN'((n_rd - rd0) + (n_wr - wr0)), 1);
    serial = 1;
    script.push_back(I(K_LOAD, 3, BAD));
    script.push_back(I(K_LOAD, 3, BAD - 4));
    script.push_back(I(K_LOAD, 2, BAD - 2));
    drain();
    e0 = n_store_err;
    script.push_back(I(K_STORE, 3, BAD, 64'hDEAD));
    drain();
    check("store drain error reported", XLEN'(n_store_err - e0), 1);

    $display("[directed] store buffer full, flush, ordering");
    ideal(); p_retire = 0; s0 = seq;
    for (int k = 0; k <= SB_DEPTH; k++) script.push_back(I(K_STORE, 3, DRAM + XLEN'(BB*k), {$urandom, $urandom}));
    run(30);
    check("write beyond depth waits", XLEN'(find(s0 + SB_DEPTH).t_acc), XLEN'(-1));
    drain();
    ideal(); p_retire = 0; s0 = seq; wr0 = n_wr;
    script.push_back(I(K_STORE, 3, DRAM + 64'h60, 64'hA5A5_A5A5_A5A5_A5A5));
    script.push_back(I(K_OTHER, 0, 0));
    run(6);
    force_irq_seq = s0; p_retire = 100;
    run(3);
    script.push_back(I(K_LOAD, 3, DRAM + 64'h60));
    drain();
    check("flushed store never written", XLEN'(n_wr - wr0), 0);
    ideal(); lat_max = 3; s0 = seq;
    script.push_back(I(K_STORE, 3, DRAM + 64'h20, {$urandom, $urandom}));
    script.push_back(I(K_LOAD, 2, MMIO + 64'h10));
    drain();
    check("MMIO load after the store drains", XLEN'(find(s0+1).t_acc > last_drain_done), 1);

    $display("[directed] coprocessor interlock, flush with a held request");
    ideal(); force_busy = 1; s0 = seq;
    script.push_back(I(K_OTHER, 0, 0));
    script.push_back(I(K_STORE, 3, DRAM + 64'h28, 64'h77));
    run(20);
    check("write waits while coprocessor busy", XLEN'(find(s0+1).t_acc), XLEN'(-1));
    drain();
    ideal(); p_retire = 0; wr0 = n_wr;
    script.push_back(I(K_STORE, 3, DRAM + 64'h30, 64'h99));
    run(5);
    force_busy = 1; p_retire = 100;
    run(20);
    check("drain waits while coprocessor busy", XLEN'(n_wr - wr0), 0);
    drain();
    check("drain after interlock", XLEN'(n_wr - wr0), 1);
    ideal(); p_retire = 0; p_rdy = 0; s0 = seq;
    script.push_back(I(K_OTHER, 0, 0));
    script.push_back(I(K_LOAD, 3, DRAM + 64'h50));
    run(6);
    check("load request held", XLEN'(dut.hold_q), 1);
    force_irq_seq = s0; p_retire = 100;
    run(3);
    p_rdy = 100;
    script.push_back(I(K_LOAD, 3, DRAM + 64'h50));
    drain();

    foreach (soaks[k]) begin
      $display("[random] soak %0d: ready %0d%%, latency <=%0d, retire %0d%%, irq %0d/1000, block %0d%%, pmp %s",
               k, soaks[k].rdy, soaks[k].lat, soaks[k].ret, soaks[k].irq, soaks[k].blk,
               soaks[k].fuzz ? "fuzzed" : "default");
      ideal();
      if (soaks[k].fuzz) pmp_fuzz(); else pmp_default();
      p_rdy = soaks[k].rdy; lat_max = soaks[k].lat; p_retire = soaks[k].ret;
      p_irq = soaks[k].irq; p_block = soaks[k].blk; gen_random = 1;
      run(20000);
      drain();
    end

    foreach (arch[a]) if (!in_bad(a)) check("final memory (arch vs bus)", XLEN'(rd_bus(a)), XLEN'(arch[a]));
    foreach (busm[a]) check("no stray bus write", XLEN'(busm[a]), XLEN'(rd_arch(a)));

    $display("coverage: fwd_full %0d fwd_part %0d cross_load %0d cross_store %0d sb_full %0d order %0d head %0d",
             cv_fwd_full, cv_fwd_part, cv_cross_load, cv_cross_store, cv_sb_full, cv_order, cv_head);
    $display("          stale %0d drain_over_read %0d flush_uncommitted %0d err_lo %0d err_hi %0d hold %0d",
             cv_stale, cv_c_over_b, cv_flush_unc, cv_err_lo, cv_err_hi, cv_hold);
    $display("          fault %0d pmp %0d misalign %0d atomic %0d upexc %0d block %0d",
             cv_fault, cv_pmp, cv_misalign, cv_atomic, cv_upexc, cv_block);
    $display("          lr %0d sc_ok %0d sc_skip %0d amo %0d reads %0d writes %0d",
             cv_lr, cv_sc_ok, cv_sc_skip, cv_amo, n_rd, n_wr);
    check("coverage all hit", XLEN'(cv_fwd_full > 0 && cv_fwd_part > 0 && cv_cross_load > 0
          && cv_cross_store > 0 && cv_sb_full > 0 && cv_order > 0 && cv_head > 0 && cv_stale > 0
          && cv_c_over_b > 0 && cv_flush_unc > 0 && cv_err_lo > 0 && cv_err_hi > 0 && cv_fault > 0
          && cv_pmp > 0 && cv_misalign > 0 && cv_atomic > 0 && cv_upexc > 0 && cv_block > 0
          && cv_hold > 0 && cv_lr > 0 && cv_sc_ok > 0 && cv_sc_skip > 0 && cv_amo > 0), 1);

    if (errors != 0) $fatal(1, "=== FAIL : %0d of %0d checks ===", errors, checks);
    $display("=== PASS : %0d checks ===", checks);
    $finish;
  end
endmodule
