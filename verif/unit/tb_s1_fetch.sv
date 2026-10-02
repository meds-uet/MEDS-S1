// =============================================================================
// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// Author(s)    : Ayesha Anwar (ayesha.anwaar2005@gmail.com) (Sep,2026)
// Modified By  :
//
// tb_s1_fetch  : unit testbench for s1_fetch                       [WIP -- T-01]
// Description  :
// Every delivered instruction is scoreboarded against a reference model that
// walks the memory image (verif/common/rvc_golden.svh); handshake properties
// are checked every cycle.  Directed tests, then a random soak.
//
// Run:  make test-unit TB=s1_fetch
// =============================================================================

module tb_s1_fetch
  import s1_pkg::*;
;

  `include "verif/common/rvc_golden.svh"

  // Expectations derive from these (R-V2).
  localparam int unsigned     BUF_HW     = 6;            // DUT FETCH_BUF_HW
  localparam int unsigned     WORD_BYTES = ILEN / 8;
  localparam int unsigned     PARCEL     = CLEN / 8;
  localparam int unsigned     LANES      = XLEN / ILEN;
  localparam logic [XLEN-1:0] BASE       = BOOT_ADDR;
  localparam int unsigned     IMG_BYTES  = 4096;         // random-image window
  localparam int unsigned     WATCHDOG   = 400;          // cycles without progress = hang

  // Cycles from redirect to target at ID, with an I$ answering MIN_LAT after accept.
  localparam int unsigned     MIN_LAT    = 1;
  localparam int unsigned     PEN_EX     = MIN_LAT + 1;  // SPEC 8.2 mispredict penalty 2
  localparam int unsigned     PEN_RETIRE = MIN_LAT + 2;
  localparam int unsigned     PEN_BTFN   = MIN_LAT + 1;

  logic            clk, rst_n;
  logic            ex_valid, retire_valid;
  logic [XLEN-1:0] ex_pc, retire_pc;
  priv_lvl_e       priv;
  logic            req_valid, req_ready, rsp_valid, rsp_ready;
  mem_req_t        req;
  mem_rsp_t        rsp;
  logic            out_valid, out_ready;
  fetch_rsp_t      out;

  s1_fetch #(
    .RESET_PC     (BASE),
    .FETCH_BUF_HW (BUF_HW)
  ) dut (
    .clk_i                   (clk),
    .rst_ni                  (rst_n),
    .ex_redirect_valid_i     (ex_valid),
    .ex_redirect_pc_i        (ex_pc),
    .retire_redirect_valid_i (retire_valid),
    .retire_redirect_pc_i    (retire_pc),
    .priv_i                  (priv),
    .imem_req_valid_o        (req_valid),
    .imem_req_ready_i        (req_ready),
    .imem_req_o              (req),
    .imem_rsp_valid_i        (rsp_valid),
    .imem_rsp_ready_o        (rsp_ready),
    .imem_rsp_i              (rsp),
    .fetch_rsp_valid_o       (out_valid),
    .fetch_rsp_ready_i       (out_ready),
    .fetch_rsp_o             (out)
  );

  int unsigned cycle  = 0;
  int unsigned checks = 0;
  int unsigned errors = 0;

  task automatic check(input bit ok, input string what);
    checks++;
    if (!ok) begin
      errors++;
      if (errors <= 30) $display("  FAIL @%0d %s", cycle, what);
    end
  endtask

  // Memory image.  Unwritten parcels come from a fixed hash of the address, so
  // the model and the BFM agree wherever the stream wanders.
  logic [CLEN-1:0] img [longint unsigned];   // parcel address -> parcel
  bit              bad [longint unsigned];   // word address   -> access fault

  function automatic logic [XLEN-1:0] word_of(input logic [XLEN-1:0] a);
    return a & ~XLEN'(WORD_BYTES - 1);
  endfunction

  function automatic logic [CLEN-1:0] mem_hw(input logic [XLEN-1:0] a);
    logic [XLEN-1:0] h;
    if (img.exists(a)) return img[a];
    h = (a ^ 64'h9E37_79B9_7F4A_7C15) * 64'hBF58_476D_1CE4_E5B9;
    return h[47:32];
  endfunction

  function automatic bit mem_bad(input logic [XLEN-1:0] a);
    return bad.exists(word_of(a));
  endfunction

  task automatic put16(input logic [XLEN-1:0] a, input logic [CLEN-1:0] v);
    img[a] = v;
  endtask

  task automatic put32(input logic [XLEN-1:0] a, input logic [ILEN-1:0] v);
    img[a]          = v[CLEN-1:0];
    img[a + PARCEL] = v[ILEN-1:CLEN];
  endtask

  function automatic logic [ILEN-1:0] nop32();
    return g_enc_i(0, 0, 0, 0, 'h13);                    // addi x0, x0, 0
  endfunction

  task automatic fill_nop32(input logic [XLEN-1:0] a, input int unsigned bytes);
    for (int unsigned o = 0; o < bytes; o += WORD_BYTES) put32(a + o, nop32());
  endtask

  // Reference model: the instruction at `pc`, from the image alone.
  function automatic fetch_rsp_t model_at(input logic [XLEN-1:0] pc);
    fetch_rsp_t  e;
    logic [CLEN-1:0] h0, h1;
    logic [32:0] g;
    logic [64:0] p;
    e    = '0;
    e.pc = pc;
    h0   = mem_hw(pc);
    if (mem_bad(pc)) begin
      e.exc = 1'b1; e.exccode = EXC_INSTR_ACCESS_FAULT; e.exctval = pc;
      return e;
    end
    if (h0[1:0] != 2'b11) begin
      g            = rvc_golden(h0);
      e.compressed = 1'b1;
      e.instr      = g[ILEN-1:0];
      e.instr_raw  = ILEN'(h0);
      if (g[ILEN]) begin
        e.exc = 1'b1; e.exccode = EXC_ILLEGAL_INSTR; e.exctval = XLEN'(h0);
      end
    end else begin
      h1 = mem_hw(pc + PARCEL);
      if (mem_bad(pc + PARCEL)) begin
        e.exc = 1'b1; e.exccode = EXC_INSTR_ACCESS_FAULT; e.exctval = pc + PARCEL;
        return e;
      end
      e.instr     = {h1, h0};
      e.instr_raw = {h1, h0};
    end
    if (!e.exc) begin
      p            = btfn_golden(e.instr);
      e.pred_taken = p[64];
    end
    return e;
  endfunction

  function automatic logic [XLEN-1:0] model_next(input fetch_rsp_t e);
    logic [64:0] p;
    p = btfn_golden(e.instr);
    if (e.pred_taken) return e.pc + p[63:0];
    return e.pc + (e.compressed ? PARCEL : WORD_BYTES);
  endfunction

  int unsigned ready_pct = 100, id_ready_pct = 100;
  int unsigned lat_min = MIN_LAT, lat_max = MIN_LAT;
  int unsigned p_ex = 0, p_rt = 0;                     // random redirect rates, per mille
  bit          rnd_redirects = 1'b0;

  bit              drv_ex = 1'b0, drv_rt = 1'b0;       // one-shot: applied for one cycle
  logic [XLEN-1:0] drv_ex_pc = '0, drv_rt_pc = '0;
  priv_lvl_e       cur_priv = PRIV_M, next_priv = PRIV_M;

  typedef struct packed {
    logic [XLEN-1:0] addr;
    logic [31:0]     due;
  } pend_t;
  pend_t pend [$];                                     // BFM: accepted, not yet answered

  logic       prev_req_valid, prev_req_ready, prev_out_valid, prev_out_ready, prev_redirect;
  mem_req_t   prev_req;
  fetch_rsp_t prev_out;

  logic [XLEN-1:0] m_pc;                               // model: next expected PC
  bit              m_halted;                           // model: a fault was delivered
  int unsigned     last_progress;

  bit              obs_valid, obs_hs;                  // what the last tick saw
  logic [XLEN-1:0] obs_pc;
  int unsigned     obs_cycle, n_req_acc;

  // coverage: each must be non-zero by the end
  int unsigned n_instr, n_rvc, n_straddle, n_taken, n_fault, n_illegal, n_ex, n_rt;
  int unsigned n_hold_redirect, n_stale, n_both;

  function automatic logic [XLEN-1:0] rnd_target();
    return BASE + XLEN'(PARCEL) * XLEN'($urandom_range(IMG_BYTES / PARCEL - 1));
  endfunction

  function automatic logic [XLEN/8-1:0] exp_be(input logic [XLEN-1:0] a);
    int unsigned lane;
    lane = int'((a / WORD_BYTES) % LANES);
    return (XLEN/8)'((1 << WORD_BYTES) - 1) << (lane * WORD_BYTES);
  endfunction

  // Fetch word on its lane, junk on the others.
  function automatic logic [XLEN-1:0] beat_for(input logic [XLEN-1:0] a);
    logic [XLEN-1:0] b;
    int unsigned     lane;
    b    = {$urandom, $urandom};
    lane = int'((a / WORD_BYTES) % LANES);
    b[lane*ILEN +: ILEN] = {mem_hw(a + PARCEL), mem_hw(a)};
    return b;
  endfunction

  task automatic compare(input fetch_rsp_t got, input fetch_rsp_t exp);
    checks++;
    if (got !== exp) begin
      errors++;
      if (errors <= 30) begin
        $display("  FAIL @%0d fetch_rsp mismatch", cycle);
        $display("       got pc=%h instr=%h raw=%h c=%0d pt=%0d exc=%0d/%0d tval=%h",
                 got.pc, got.instr, got.instr_raw, got.compressed, got.pred_taken,
                 got.exc, got.exccode, got.exctval);
        $display("       exp pc=%h instr=%h raw=%h c=%0d pt=%0d exc=%0d/%0d tval=%h",
                 exp.pc, exp.instr, exp.instr_raw, exp.compressed, exp.pred_taken,
                 exp.exc, exp.exccode, exp.exctval);
      end
    end
  endtask

  // One cycle: drive, probe, check, clock.
  task automatic tick();
    logic       v0, ov0;
    mem_req_t   q0;
    fetch_rsp_t o0, e;
    bit         redirect_now, req_hs, rsp_hs, out_hs, new_req, stale_pending;
    pend_t      p;

    // ---- drive
    if (rnd_redirects && !drv_ex && !drv_rt) begin
      // after a delivered fault the pipeline traps soon
      if ($urandom_range(999) < p_rt || (m_halted && $urandom_range(7) == 0)) begin
        drv_rt    = 1'b1;
        drv_rt_pc = rnd_target();
        next_priv = $urandom_range(1) ? PRIV_M : PRIV_U;
      end
      if ($urandom_range(999) < p_ex) begin
        drv_ex    = 1'b1;
        drv_ex_pc = rnd_target();
      end
    end
    ex_valid     = drv_ex;
    ex_pc        = drv_ex_pc;
    retire_valid = drv_rt;
    retire_pc    = drv_rt_pc;
    priv         = cur_priv;
    if (pend.size() != 0 && pend[0].due <= cycle) begin
      rsp_valid   = 1'b1;
      rsp.id      = '0;
      rsp.rdata   = beat_for(pend[0].addr);
      rsp.err     = mem_bad(pend[0].addr);
      rsp.errcode = 2'($urandom);
    end else begin
      rsp_valid   = 1'b0;
      rsp.id      = 4'($urandom);
      rsp.rdata   = {$urandom, $urandom};
      rsp.err     = 1'($urandom);
      rsp.errcode = 2'($urandom);
    end

    // ---- probe: toggle ready within the cycle; valid/payload must not move (R-C10)
    req_ready = 1'b0; out_ready = 1'b0; #1;
    v0 = req_valid; q0 = req; ov0 = out_valid; o0 = out;
    req_ready = 1'b1; out_ready = 1'b1; #1;
    check(req_valid == v0 && (!v0 || req == q0),
          "imem request depends combinationally on a ready input (R-C10)");
    check(out_valid == ov0 && (!ov0 || out == o0),
          "fetch_rsp depends combinationally on a ready input (R-C10)");
    req_ready = ($urandom_range(99) < ready_pct);
    out_ready = ($urandom_range(99) < id_ready_pct);
    #1;

    // ---- check
    redirect_now  = ex_valid || retire_valid;
    req_hs        = req_valid && req_ready;
    rsp_hs        = rsp_valid && rsp_ready;
    out_hs        = out_valid && out_ready;
    new_req       = req_valid && !(prev_req_valid && !prev_req_ready);
    stale_pending = (pend.size() > (rsp_hs ? 1 : 0));

    if (prev_req_valid && !prev_req_ready)
      check(req_valid && req == prev_req, "imem request withdrawn or changed before accept (R-C10)");
    if (new_req) begin
      check(req.addr == word_of(req.addr), "imem request address not word aligned");
      check(!req.we && req.size == 3'($clog2(WORD_BYTES)) && req.id == '0,
            "imem request we/size/id wrong");
      check(req.be == exp_be(req.addr), "imem request byte enables do not select the word");
      check(req.mode == cur_priv, "imem request mode is not the current privilege");
      if (m_halted && !redirect_now) check(1'b0, "new fetch request issued past a delivered fault");
    end
    if (rsp_valid) check(rsp_ready, "imem_rsp_ready_o low while a response is presented");
    if (prev_out_valid && !prev_out_ready && !prev_redirect)
      check(out_valid && out == prev_out, "fetch_rsp withdrawn or changed before accept (R-C10)");

    if (rsp_hs) void'(pend.pop_front());
    if (req_hs) begin
      p.addr = req.addr;
      p.due  = cycle + $urandom_range(lat_max, lat_min);
      pend.push_back(p);
      n_req_acc++;
    end
    check(pend.size() <= 1, "more than one I2 request outstanding (INTERFACES.md 2)");

    // A transfer in a redirect cycle is wrong-path (ID is flushed too): ignore it.
    if (out_hs && !redirect_now) begin
      if (m_halted) begin
        check(1'b0, "instruction delivered after a faulting one");
      end else begin
        e = model_at(m_pc);
        compare(out, e);
        n_instr++;
        if (e.compressed)                         n_rvc++;
        if (!e.compressed && e.pc[1])             n_straddle++;
        if (e.pred_taken)                         n_taken++;
        if (e.exc && e.exccode == EXC_INSTR_ACCESS_FAULT) n_fault++;
        if (e.exc && e.exccode == EXC_ILLEGAL_INSTR)      n_illegal++;
        m_pc     = model_next(e);
        m_halted = e.exc;
      end
      last_progress = cycle;
    end
    if (redirect_now) begin
      if (prev_req_valid && !prev_req_ready) n_hold_redirect++;
      if (stale_pending)                     n_stale++;
      if (ex_valid && retire_valid)          n_both++;
      if (retire_valid) n_rt++; else n_ex++;
      m_pc          = retire_valid ? retire_pc : ex_pc;
      m_halted      = 1'b0;
      last_progress = cycle;
    end
    if (!m_halted && cycle - last_progress > WATCHDOG) begin
      $display("  FAIL @%0d no progress for %0d cycles -- frontend hung", cycle, WATCHDOG);
      $fatal(1, "tb_s1_fetch: watchdog");
    end

    obs_cycle = cycle;
    obs_valid = out_valid;
    obs_pc    = out.pc;
    obs_hs    = out_hs && !redirect_now;

    prev_req_valid = req_valid;
    prev_req_ready = req_ready;
    prev_req       = req;
    prev_out_valid = out_valid;
    prev_out_ready = out_ready;
    prev_out       = out;
    prev_redirect  = redirect_now;

    // ---- clock
    clk = 1'b1; #1;
    clk = 1'b0; #1;
    if (retire_valid) cur_priv = next_priv;           // CSR commits at this edge
    drv_ex = 1'b0;
    drv_rt = 1'b0;
    cycle++;
  endtask

  task automatic run(input int unsigned n);
    repeat (n) tick();
  endtask

  task automatic count_hs(input int unsigned n, output int unsigned k);
    k = 0;
    repeat (n) begin tick(); if (obs_hs) k++; end
  endtask

  // Cycle at which `pc` is next presented to ID.
  task automatic wait_pc(input logic [XLEN-1:0] pc, output int unsigned at);
    for (int unsigned n = 0; n < 64; n++) begin
      tick();
      if (obs_valid && obs_pc == pc) begin at = obs_cycle; return; end
    end
    check(1'b0, $sformatf("pc %h never reached ID", pc));
    at = obs_cycle;
  endtask

  // Restart the stream at `pc`, as a trap would.
  task automatic jump_to(input logic [XLEN-1:0] pc);
    drv_rt = 1'b1; drv_rt_pc = pc; next_priv = cur_priv;
    tick();
  endtask

  task automatic ideal_bus();
    ready_pct = 100; id_ready_pct = 100; lat_min = MIN_LAT; lat_max = MIN_LAT;
  endtask

  task automatic do_reset();
    clk = 1'b0; rst_n = 1'b0;
    ex_valid = 1'b0; retire_valid = 1'b0; ex_pc = '0; retire_pc = '0;
    req_ready = 1'b0; rsp_valid = 1'b0; rsp = '0; out_ready = 1'b0;
    priv = PRIV_M; cur_priv = PRIV_M;
    pend.delete();
    prev_req_valid = 1'b0; prev_req_ready = 1'b0; prev_out_valid = 1'b0;
    prev_out_ready = 1'b0; prev_redirect = 1'b0; prev_req = '0; prev_out = '0;
    m_pc = BASE; m_halted = 1'b0; last_progress = cycle;
    // Two-state sim: a reset low from time zero has no negedge; make one.
    rst_n = 1'b1; #1;
    rst_n = 1'b0; #1;
    clk   = 1'b1; #1;
    clk   = 1'b0; #1;
    rst_n = 1'b1; #1;
  endtask

  // ===========================================================================
  // Directed tests
  // ===========================================================================
  task automatic test_reset();
    do_reset();
    check(req_valid, "no fetch request out of reset");
    check(req.addr == word_of(BASE), "first request is not the reset vector");
    check(req.mode == PRIV_M, "first request is not M-mode");
    check(!out_valid, "fetch_rsp_valid_o high out of reset");
  endtask

  task automatic test_throughput();
    int unsigned n, win;
    win = 32;
    img.delete(); bad.delete(); ideal_bus();

    fill_nop32(BASE, 1024);
    jump_to(BASE); run(8);
    count_hs(win, n);
    check(n == win, $sformatf("aligned 32-bit: %0d of %0d cycles delivered", n, win));

    for (int unsigned o = 0; o < 1024; o += PARCEL) put16(BASE + 'h1000 + o, 16'h0001); // c.nop
    jump_to(BASE + 'h1000); run(8);
    count_hs(win, n);
    check(n == win, $sformatf("compressed: %0d of %0d cycles delivered", n, win));

    // every 32-bit instruction straddles two words
    put16(BASE + 'h2000, 16'h0001);
    fill_nop32(BASE + 'h2000 + PARCEL, 1024);
    jump_to(BASE + 'h2000 + PARCEL); run(8);
    count_hs(win, n);
    if (BUF_HW >= 3 * (ILEN / CLEN))
      check(n == win, $sformatf("straddling 32-bit: %0d of %0d cycles delivered", n, win));
  endtask

  task automatic test_penalties();
    int unsigned t0, t1, tb;
    logic [XLEN-1:0] a;
    img.delete(); bad.delete(); ideal_bus();
    fill_nop32(BASE, 'h1000);

    // EX mispredict
    jump_to(BASE); run(8);
    drv_ex = 1'b1; drv_ex_pc = BASE + 'h200; t0 = cycle; tick();
    wait_pc(BASE + 'h200, t1);
    check(t1 - t0 == PEN_EX, $sformatf("EX redirect reached ID after %0d, want %0d", t1 - t0, PEN_EX));

    // retire redirect
    run(4);
    drv_rt = 1'b1; drv_rt_pc = BASE + 'h300; t0 = cycle; tick();
    wait_pc(BASE + 'h300, t1);
    check(t1 - t0 == PEN_RETIRE,
          $sformatf("retire redirect reached ID after %0d, want %0d", t1 - t0, PEN_RETIRE));

    // backward branch: taken
    a = BASE + 'h440;
    put32(a, g_enc_b(-'h40, 0, 0, 0, 'h63));                 // beq x0, x0, -64
    jump_to(a - 'h10); wait_pc(a, tb); wait_pc(a - 'h40, t1);
    check(t1 - tb == PEN_BTFN, $sformatf("BTFN backward branch: %0d cycles, want %0d", t1 - tb, PEN_BTFN));

    // forward branch: not taken
    a = BASE + 'h540;
    put32(a, g_enc_b('h40, 0, 0, 0, 'h63));                  // beq x0, x0, +64
    jump_to(a - 'h10); wait_pc(a, tb); wait_pc(a + WORD_BYTES, t1);
    check(t1 - tb == 1, "BTFN forward branch should fall through with no bubble");

    // forward JAL: taken
    a = BASE + 'h640;
    put32(a, g_enc_j('h80, 0, 'h6f));                        // jal x0, +128
    jump_to(a - 'h10); wait_pc(a, tb); wait_pc(a + 'h80, t1);
    check(t1 - tb == PEN_BTFN, $sformatf("forward JAL: %0d cycles, want %0d", t1 - tb, PEN_BTFN));

    // JALR: not predicted
    a = BASE + 'h740;
    put32(a, g_enc_i(0, 1, 0, 0, 'h67));                     // jalr x0, 0(x1)
    jump_to(a - 'h10); wait_pc(a, tb); wait_pc(a + WORD_BYTES, t1);
    check(t1 - tb == 1, "JALR must not be predicted");

    // compressed backward branch: taken
    a = BASE + 'h900;
    put16(a, 16'hd001);                                      // c.beqz x8, -256
    put16(a + PARCEL, 16'h0001);
    jump_to(a - 'h10); wait_pc(a, tb); wait_pc(a - 'h100, t1);
    check(t1 - tb == PEN_BTFN, $sformatf("C.BEQZ backward: %0d cycles, want %0d", t1 - tb, PEN_BTFN));
  endtask

  task automatic test_faults();
    int unsigned t;
    logic [XLEN-1:0] a;
    img.delete(); bad.delete(); ideal_bus();
    fill_nop32(BASE, 'h1000);

    // illegal parcel, then nothing more
    a = BASE + 'h100;
    put16(a, 16'h0000); put16(a + PARCEL, 16'h0001);
    jump_to(a - 'h8); wait_pc(a, t);
    for (int unsigned n = 0; n < 30; n++) begin
      tick();
      check(!obs_valid, "fetch_rsp valid after a delivered illegal instruction");
    end

    // fault on first parcel: mtval = pc
    a = BASE + 'h200;
    bad[a] = 1'b1;
    jump_to(a - 'h8); wait_pc(a, t); run(20);

    // straddling 32-bit, second parcel faults: mtval = pc+2
    a = BASE + 'h300 + PARCEL;
    put32(a, nop32());
    bad[word_of(a + PARCEL)] = 1'b1;
    jump_to(a); wait_pc(a, t); run(20);

    // straddling 32-bit, first parcel faults: mtval = pc
    a = BASE + 'h400 + PARCEL;
    put32(a, nop32());
    bad[word_of(a)] = 1'b1;
    jump_to(a); wait_pc(a, t); run(20);

    // a redirect restarts fetch
    jump_to(BASE); wait_pc(BASE + 'h10, t);
    check(n_fault >= 3 && n_illegal >= 1, "fault cases were not all delivered");
  endtask

  task automatic test_hold_and_stale();
    int unsigned t;
    img.delete(); bad.delete(); ideal_bus();
    fill_nop32(BASE, 'h2000);

    // redirect while a request is held: its response must be dropped
    jump_to(BASE); run(6);
    ready_pct = 0; run(3);
    check(prev_req_valid && !prev_req_ready, "no request held while the I$ refuses");
    drv_ex = 1'b1; drv_ex_pc = BASE + 'h1000; tick();
    run(4);
    ready_pct = 100;
    wait_pc(BASE + 'h1000, t);

    // redirect with a response in flight
    lat_min = 6; lat_max = 6;
    jump_to(BASE); run(10);
    drv_ex = 1'b1; drv_ex_pc = BASE + 'h1800; tick();
    wait_pc(BASE + 'h1800, t);
    ideal_bus();

    // EX and retire together: retire wins
    run(4);
    drv_ex = 1'b1; drv_ex_pc = BASE + 'h400;
    drv_rt = 1'b1; drv_rt_pc = BASE + 'h800; tick();
    wait_pc(BASE + 'h800, t);

    // back-to-back redirects: later wins
    drv_ex = 1'b1; drv_ex_pc = BASE + 'h100; tick();
    drv_ex = 1'b1; drv_ex_pc = BASE + 'h600; tick();
    wait_pc(BASE + 'h600, t);
  endtask

  task automatic test_stall_bound();
    int unsigned a0, n;
    img.delete(); bad.delete(); ideal_bus();
    fill_nop32(BASE, 'h1000);
    jump_to(BASE); run(8);

    // long ID stall: requests must stop once the buffer is full
    id_ready_pct = 0;
    a0 = n_req_acc;
    run(50);
    check(n_req_acc - a0 <= BUF_HW / (ILEN / CLEN) + 1,
          $sformatf("%0d requests accepted during a full ID stall", n_req_acc - a0));
    id_ready_pct = 100;
    count_hs(16, n);
    check(n == 16, "did not resume at full rate after the stall");
  endtask

  // ===========================================================================
  // Random soak
  // ===========================================================================
  task automatic random_profile(input string name, input int unsigned cycles,
                                input int unsigned rdy, input int unsigned lmax,
                                input int unsigned idr, input int unsigned pex,
                                input int unsigned prt, input int unsigned bad_pct);
    int unsigned i0 = n_instr;
    img.delete(); bad.delete();
    for (int unsigned o = 0; o < IMG_BYTES; o += PARCEL) put16(BASE + o, CLEN'($urandom));
    for (int unsigned o = 0; o < IMG_BYTES; o += WORD_BYTES)
      if ($urandom_range(99) < bad_pct) bad[BASE + o] = 1'b1;
    ready_pct = rdy; lat_min = MIN_LAT; lat_max = lmax; id_ready_pct = idr;
    p_ex = pex; p_rt = prt;
    jump_to(BASE);
    rnd_redirects = 1'b1;
    run(cycles);
    rnd_redirects = 1'b0;
    $display("  random %-10s %6d cycles, %6d instructions checked", name, cycles, n_instr - i0);
  endtask

  // ===========================================================================
  initial begin
    $display("=== tb_s1_fetch : XLEN=%0d FETCH_BUF_HW=%0d I$ latency>=%0d ===",
             XLEN, BUF_HW, MIN_LAT);

    test_reset();
    test_throughput();
    test_penalties();
    test_faults();
    test_hold_and_stale();
    test_stall_bound();

    //              name        cycles  rdy lat  id  ex  rt  bad%
    random_profile("ideal",      20000, 100,  1, 100, 20,  5,  1);
    random_profile("busy",       20000,  60,  4,  70, 30, 10,  2);
    random_profile("starved",    20000,  20,  8,  30, 10,  5,  2);

    check(n_instr    > 10000, "too few instructions checked");
    check(n_rvc      > 0, "coverage: no compressed instruction");
    check(n_straddle > 0, "coverage: no word-straddling instruction");
    check(n_taken    > 0, "coverage: no predicted-taken branch");
    check(n_fault    > 0, "coverage: no access fault");
    check(n_illegal  > 0, "coverage: no illegal compressed instruction");
    check(n_hold_redirect > 0, "coverage: no redirect while a request was held");
    check(n_stale    > 0, "coverage: no redirect with a response in flight");
    check(n_both     > 0, "coverage: no simultaneous EX + retire redirect");
    $display("  coverage: %0d instr, %0d rvc, %0d straddle, %0d taken, %0d fault, %0d illegal",
             n_instr, n_rvc, n_straddle, n_taken, n_fault, n_illegal);
    $display("            %0d ex, %0d retire, %0d both, %0d redirect-while-held, %0d stale-response",
             n_ex, n_rt, n_both, n_hold_redirect, n_stale);

    // ---------------------------------------------------------------------------
    if (errors == 0) begin
      $display("=== PASS : %0d checks ===", checks);
      $finish;
    end else begin
      $display("=== FAIL : %0d errors of %0d checks ===", errors, checks);
      $fatal(1, "tb_s1_fetch failed");
    end
  end

endmodule
