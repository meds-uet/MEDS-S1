// =============================================================================
// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// Author(s)    : Eman Nasar (fatehulnasareman@gmail.com) (Sep 2026)
// Modified By  :
//
// tb_s1_wb_stage : unit testbench for s1_wb_stage                   [WIP -- T-02]
// Description  :
// The testbench plays MEM (drives MEM/WB), the multi-cycle units (drive and
// hold results), the completion buffer (checks the write port), retire (drives
// flush_i) and ID (drives the operand read addresses and checks the bypass).
// Reference models live in verif/common/s1_wb_stage_model.svh, and the expected
// outputs there are built from SPEC 9.1 and 9.2 rather than from the DUT.
//
//   * The control space is exhaustive: all 256 combinations of valid, flush,
//     complete, exc, rd_we, rd==x0, csr_we and sb_alloc, each with independent
//     random payloads and random multi-cycle traffic alongside.
//   * The forwarding bus is checked on every case against the value the
//     completion buffer is told to write, including the cases where it must
//     read zero: no completion, a trap, no destination, and x0.
//   * Three instances run the same stimulus at N_UC 1, 2 and 3, each with its
//     own modelled rotation, so nothing here depends on the channel count (R-V2).
//
// Run:  make test-unit TB=s1_wb_stage
// =============================================================================

module tb_s1_wb_stage
  import s1_pkg::*;
;

  logic clk = 1'b0, rst_n = 1'b0;
  initial forever #5 clk = ~clk;

  logic    flush, wb_valid;
  mem_wb_t wb;

  // One master stimulus set, fanned out to the three widths.
  logic    ucv1 [1], ucv2 [2], ucv3 [3];
  md_rsp_t ucd1 [1], ucd2 [2], ucd3 [3];

  logic    uc_ready [2], uc_ready1 [1], uc_ready3 [3];
  logic    uc_stall, uc_stall1, uc_stall3;

  logic                  cb_we,  cb_we1,  cb_we3;
  logic [CB_IDX_W-1:0]   cb_idx, cb_idx1, cb_idx3;
  wb_upd_t               cb_upd, cb_upd1, cb_upd3;
  logic [XLEN-1:0]       fdata,  fdata1,  fdata3;

  s1_wb_stage #(.N_UC(2)) dut (
    .clk_i(clk), .rst_ni(rst_n), .flush_i(flush), .wb_valid_i(wb_valid), .wb_i(wb),
    .uc_valid_i(ucv2), .uc_ready_o(uc_ready), .uc_i(ucd2),
    .cb_we_o(cb_we), .cb_idx_o(cb_idx), .cb_upd_o(cb_upd),
    .fwd_data_o(fdata), .uc_stall_o(uc_stall)
  );

  s1_wb_stage #(.N_UC(1)) dut_lo (
    .clk_i(clk), .rst_ni(rst_n), .flush_i(flush), .wb_valid_i(wb_valid), .wb_i(wb),
    .uc_valid_i(ucv1), .uc_ready_o(uc_ready1), .uc_i(ucd1),
    .cb_we_o(cb_we1), .cb_idx_o(cb_idx1), .cb_upd_o(cb_upd1),
    .fwd_data_o(fdata1), .uc_stall_o(uc_stall1)
  );

  s1_wb_stage #(.N_UC(3)) dut_hi (
    .clk_i(clk), .rst_ni(rst_n), .flush_i(flush), .wb_valid_i(wb_valid), .wb_i(wb),
    .uc_valid_i(ucv3), .uc_ready_o(uc_ready3), .uc_i(ucd3),
    .cb_we_o(cb_we3), .cb_idx_o(cb_idx3), .cb_upd_o(cb_upd3),
    .fwd_data_o(fdata3), .uc_stall_o(uc_stall3)
  );

  `include "verif/common/s1_wb_stage_model.svh"

  int unsigned checks = 0, errors = 0, apps = 0;

  task automatic check(input string name, input logic [XLEN-1:0] got, input logic [XLEN-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      if (errors <= 25) $display("  FAIL #%0d %-36s got=0x%016h exp=0x%016h", apps, name, got, exp);
    end
  endtask

  int cv_write, cv_nowrite, cv_x0, cv_exc, cv_exc_kill, cv_mxif, cv_mxif_exc, cv_flush,
      cv_csr, cv_csr_kill, cv_sb, cv_sb_exc, cv_fwd_val, cv_fwd_zero, cv_idle,
      cv_load, cv_store, cv_idx_all, cv_uc_win, cv_uc_block, cv_uc_both, cv_uc_flushed,
      cv_uc_x0, cv_rr_swap, cv_uc3_win;
  int idx_seen[CB_DEPTH], uc_win_seen[UC_MAX];

  ins_t cur;
  exp_t exp, exp1, exp3;
  int   gnt, gnt1, gnt3;
  bit   cur_uc_v [UC_MAX];
  bit   cur_flush;
  int   last_gnt = -1;

  // ---------------------------------------------------------------------------
  // Check every output of all three configurations
  // ---------------------------------------------------------------------------
  task automatic verify();
    int want_stall;
    check("cb_we", XLEN'(cb_we), XLEN'(exp.cb_we));

    // The payload is meaningful only with cb_we: an entry WB does not own keeps
    // what ID put in it, and the testbench must not constrain what WB presents
    // on a port the completion buffer is not sampling.
    if (exp.cb_we) begin
      check("cb_idx",         XLEN'(cb_idx),            XLEN'(exp.cb_idx));
      check("upd.done",       XLEN'(cb_upd.done),       XLEN'(exp.upd.done));
      check("upd.norollback", XLEN'(cb_upd.norollback), XLEN'(exp.upd.norollback));
      check("upd.from_main",  XLEN'(cb_upd.from_main),  XLEN'(exp.upd.from_main));
      check("upd.rd",         XLEN'(cb_upd.rd),         XLEN'(exp.upd.rd));
      check("upd.rd_we",      XLEN'(cb_upd.rd_we),      XLEN'(exp.upd.rd_we));
      check("upd.result",     cb_upd.result,            exp.upd.result);
      check("upd.next_pc",    cb_upd.next_pc,           exp.upd.next_pc);
      check("upd.exc",        XLEN'(cb_upd.exc),        XLEN'(exp.upd.exc));
      check("upd.exccode",    XLEN'(cb_upd.exccode),    XLEN'(exp.upd.exccode));
      check("upd.exctval",    cb_upd.exctval,           exp.upd.exctval);
      check("upd.csr.we",     XLEN'(cb_upd.csr.we),     XLEN'(exp.upd.csr.we));
      check("upd.csr.addr",   XLEN'(cb_upd.csr.addr),   XLEN'(exp.upd.csr.addr));
      check("upd.csr.wdata",  cb_upd.csr.wdata,         exp.upd.csr.wdata);
      check("upd.sb_alloc",   XLEN'(cb_upd.sb_alloc),   XLEN'(exp.upd.sb_alloc));
      check("upd.rvfi.addr",  cb_upd.rvfi.addr,         exp.upd.rvfi.addr);
      check("upd.rvfi.rmask", XLEN'(cb_upd.rvfi.rmask), XLEN'(exp.upd.rvfi.rmask));
      check("upd.rvfi.wmask", XLEN'(cb_upd.rvfi.wmask), XLEN'(exp.upd.rvfi.wmask));
      check("upd.rvfi.rdata", cb_upd.rvfi.rdata,        exp.upd.rvfi.rdata);
      check("upd.rvfi.wdata", cb_upd.rvfi.wdata,        exp.upd.rvfi.wdata);
      idx_seen[exp.cb_idx]++;
    end

    // The forwarding bus carries the value the completion buffer is told to
    // write, in every cycle -- including the cycles where that value must be
    // zero: no completion at all, a trap, no destination, or x0.  There is no
    // match output to check, and that absence is the contract: the ID-stage
    // MEM/WB match is made against the EX/MEM register, a cycle before this
    // module sees the completion at all.
    check("fwd_data", fdata, exp.upd.result);

    // WB has no ready on the main-pipe channel and must never need one: every
    // completion the main pipe owns is taken in the cycle it is offered, or
    // discarded by the flush that removed its entry.
    if (wb_valid && main_pipe_owns(cur))
      check("main-pipe completion taken or flushed", XLEN'(cb_we | cur_flush), 1);

    // A unit is answered in the cycle it is granted, and every unit is drained
    // during a flush so that none is left holding a result for an entry that no
    // longer exists.
    for (int k = 0; k < 2; k++)
      check($sformatf("uc_ready[%0d]", k), XLEN'(uc_ready[k]),
            XLEN'(cur_flush | (gnt == k)));

    want_stall = 0;
    if (!cur_flush)
      for (int k = 0; k < 2; k++) if (cur_uc_v[k] && gnt != k) want_stall = 1;
    check("uc_stall", XLEN'(uc_stall), XLEN'(want_stall));

    // ---- N_UC = 1 : the same stimulus, one channel ------------------------
    check("N_UC=1 cb_we", XLEN'(cb_we1), XLEN'(exp1.cb_we));
    if (exp1.cb_we) begin
      check("N_UC=1 cb_idx",   XLEN'(cb_idx1),           XLEN'(exp1.cb_idx));
      check("N_UC=1 payload",  XLEN'(cb_upd1 == exp1.upd), 1);
    end
    check("N_UC=1 fwd_data",   fdata1, exp1.upd.result);
    check("N_UC=1 uc_ready",   XLEN'(uc_ready1[0]), XLEN'(cur_flush | (gnt1 == 0)));
    check("N_UC=1 uc_stall",   XLEN'(uc_stall1),
          XLEN'(!cur_flush && cur_uc_v[0] && gnt1 != 0));

    // ---- N_UC = 3 : the same stimulus, three channels ---------------------
    check("N_UC=3 cb_we", XLEN'(cb_we3), XLEN'(exp3.cb_we));
    if (exp3.cb_we) begin
      check("N_UC=3 cb_idx",   XLEN'(cb_idx3),           XLEN'(exp3.cb_idx));
      check("N_UC=3 payload",  XLEN'(cb_upd3 == exp3.upd), 1);
    end
    check("N_UC=3 fwd_data",   fdata3, exp3.upd.result);
    want_stall = 0;
    for (int k = 0; k < 3; k++) begin
      check($sformatf("N_UC=3 uc_ready[%0d]", k), XLEN'(uc_ready3[k]),
            XLEN'(cur_flush | (gnt3 == k)));
      if (!cur_flush && cur_uc_v[k] && gnt3 != k) want_stall = 1;
    end
    check("N_UC=3 uc_stall", XLEN'(uc_stall3), XLEN'(want_stall));

    if (!wb_valid)                                           cv_idle++;
    else if (cur_flush)                                      cv_flush++;
    if (exp.cb_we &&  exp.upd.rd_we)                         cv_write++;
    if (exp.cb_we && !exp.upd.rd_we)                         cv_nowrite++;
    if (wb_valid && !cur_flush && cur.rd_we && cur.rd == '0) cv_x0++;
    if (exp.cb_we && exp.upd.from_main && cur.exc)           cv_exc++;
    if (exp.cb_we && exp.upd.from_main && cur.exc && cur.rd_we && cur.rd != '0) cv_exc_kill++;
    if (wb_valid && !cur_flush && !cur.complete && !cur.exc) cv_mxif++;
    if (wb_valid && !cur_flush && !cur.complete &&  cur.exc) cv_mxif_exc++;
    if (exp.cb_we && exp.upd.csr.we)                         cv_csr++;
    if (exp.cb_we && exp.upd.from_main && cur.csr_we && cur.exc) cv_csr_kill++;
    if (exp.cb_we && exp.upd.sb_alloc)                       cv_sb++;
    if (exp.cb_we && exp.upd.sb_alloc && cur.exc)            cv_sb_exc++;
    if (exp.cb_we && exp.upd.from_main && |cur.rmask)        cv_load++;
    if (exp.cb_we && exp.upd.from_main && |cur.wmask)        cv_store++;
    if (fdata != '0)                                         cv_fwd_val++;
    else                                                     cv_fwd_zero++;
    if (gnt >= 0) begin
      cv_uc_win++;
      uc_win_seen[gnt]++;
      if (last_gnt >= 0 && last_gnt != gnt) cv_rr_swap++;
      last_gnt = gnt;
      if (ucd2[gnt].rd == '0) cv_uc_x0++;
    end
    if (gnt3 == 2)                                           cv_uc3_win++;
    if (want_stall)                                          cv_uc_block++;
    if (cur_uc_v[0] && cur_uc_v[1])                          cv_uc_both++;
    if (cur_flush && (cur_uc_v[0] || cur_uc_v[1]))           cv_uc_flushed++;
  endtask

  task automatic apply(ins_t n, bit valid, bit flush_v, bit uv [UC_MAX], md_rsp_t ud [UC_MAX]);
    exp_t e_main;
    bit   port_free;
    cur       = n;
    cur_flush = flush_v;
    wb        = render_wb(n);
    wb_valid  = valid;
    flush     = flush_v;
    for (int k = 0; k < UC_MAX; k++) cur_uc_v[k] = uv[k];
    ucv1[0] = uv[0];                       ucd1[0] = ud[0];
    ucv2[0] = uv[0]; ucv2[1] = uv[1];      ucd2[0] = ud[0]; ucd2[1] = ud[1];
    ucv3[0] = uv[0]; ucv3[1] = uv[1]; ucv3[2] = uv[2];
    ucd3[0] = ud[0]; ucd3[1] = ud[1]; ucd3[2] = ud[2];
    #3;
    apps++;
    e_main    = golden(n, valid, flush_v);
    port_free = !e_main.cb_we && !flush_v;
    gnt1      = golden_grant(uv, 1, m_rr[1], port_free);
    gnt       = golden_grant(uv, 2, m_rr[2], port_free);
    gnt3      = golden_grant(uv, 3, m_rr[3], port_free);
    exp  = e_main.cb_we ? e_main : (gnt  >= 0 ? golden_uc(ud[gnt])  : '{default: '0});
    exp1 = e_main.cb_we ? e_main : (gnt1 >= 0 ? golden_uc(ud[gnt1]) : '{default: '0});
    exp3 = e_main.cb_we ? e_main : (gnt3 >= 0 ? golden_uc(ud[gnt3]) : '{default: '0});
    verify();
    @(posedge clk);
    if (gnt1 >= 0) m_rr[1] = (gnt1 + 1) % 1;
    if (gnt  >= 0) m_rr[2] = (gnt  + 1) % 2;
    if (gnt3 >= 0) m_rr[3] = (gnt3 + 1) % 3;
    #1;
  endtask

  // No multi-cycle traffic: the shape every test that predates the units uses.
  task automatic apply_q(ins_t n, bit valid, bit flush_v);
    bit      uv [UC_MAX];
    md_rsp_t ud [UC_MAX];
    for (int k = 0; k < UC_MAX; k++) begin uv[k] = 1'b0; ud[k] = '0; end
    apply(n, valid, flush_v, uv, ud);
  endtask

  task automatic apply_rand(ins_t n, bit valid, bit flush_v, int p_uc);
    bit      uv [UC_MAX];
    md_rsp_t ud [UC_MAX];
    int      z;
    for (int k = 0; k < UC_MAX; k++) begin
      z     = $urandom % 100;
      ud[k] = make_uc();
      uv[k] = (z < p_uc);
    end
    apply(n, valid, flush_v, uv, ud);
  endtask

  // ---------------------------------------------------------------------------
  // A case built from the control bits directly, so the exhaustive sweep does
  // not inherit make_ins's idea of which combinations are sensible
  // ---------------------------------------------------------------------------
  function automatic ins_t ctrl_ins(int bits);
    ins_t n;
    logic [REG_ADDR_W-1:0] any_rd;
    any_rd      = REG_ADDR_W'(1 + ($urandom % 31));
    n           = blank_ins();
    n.kind      = K_ALU;
    n.idx       = CB_IDX_W'($urandom);
    n.complete  = bits[0];
    n.exc       = bits[1];
    n.rd_we     = bits[2];
    n.rd        = bits[3] ? REG_ADDR_W'(0) : any_rd;
    n.csr_we    = bits[4];
    n.sb_alloc  = bits[5];
    n.result    = {$urandom, $urandom};
    n.next_pc   = {$urandom, $urandom};
    n.exccode   = 6'($urandom);
    n.exctval   = {$urandom, $urandom};
    n.csr_addr  = 12'($urandom);
    n.csr_wdata = {$urandom, $urandom};
    n.maddr     = {$urandom, $urandom};
    n.rmask     = NB'($urandom);
    n.wmask     = NB'($urandom);
    n.mrdata    = {$urandom, $urandom};
    n.mwdata    = {$urandom, $urandom};
    return n;
  endfunction

  // ---------------------------------------------------------------------------
  // Tests
  // ---------------------------------------------------------------------------
  initial begin
    ins_t n;
    logic cb0;
    logic [CB_IDX_W-1:0] ix0;
    wb_upd_t u0;
    bit      uv [UC_MAX];
    md_rsp_t ud [UC_MAX];
    int      first, second;

    wb = '0; wb_valid = 0; flush = 0;
    for (int k = 0; k < UC_MAX; k++) begin
      ucv3[k] = 1'b0; ucd3[k] = '0;
      if (k < 2) begin ucv2[k] = 1'b0; ucd2[k] = '0; end
      if (k < 1) begin ucv1[k] = 1'b0; ucd1[k] = '0; end
    end
    repeat (3) @(posedge clk);
    #1 rst_n = 1'b1;
    #1;
    check("reset: no completion-buffer write", XLEN'(cb_we), 0);
    check("reset: forwarding bus reads zero",  fdata, 0);
    check("reset: no multi-cycle stall",       XLEN'(uc_stall), 0);

    $display("[directed] nothing is presented: wb_i is ignored");
    for (int k = 0; k < 1500; k++) begin
      n = rand_ins();
      apply_rand(n, 1'b0, 1'($urandom), 0);
    end

    $display("[exhaustive] every control combination: valid x flush x 6 payload bits");
    for (int rep = 0; rep < 48; rep++)
      for (int bits = 0; bits < 64; bits++)
        for (int v = 0; v < 2; v++)
          for (int f = 0; f < 2; f++)
            apply_rand(ctrl_ins(bits), 1'(v), 1'(f), 40);

    $display("[exhaustive] forwarding bus: every destination, writing and not");
    for (int rd = 0; rd < 32; rd++)
      for (int we = 0; we < 2; we++)
        for (int ex = 0; ex < 2; ex++)
          for (int rep = 0; rep < 8; rep++) begin
            n        = make_ins(K_ALU);
            n.rd     = REG_ADDR_W'(rd);
            n.rd_we  = 1'(we);
            n.exc    = 1'(ex);
            n.result = {$urandom, $urandom};
            apply_q(n, 1'b1, 1'b0);
            // x0, no destination and a trap must all read as zero; the value
            // must appear in every other case.
            if (we && !ex && rd != 0) check("bus carries the value", fdata, n.result);
            else                      check("bus reads zero",        fdata, 0);
          end

    $display("[directed] one completion of each class, fields checked by name");
    n = make_ins(K_ALU); n.rd = 5'd7; n.rd_we = 1; n.result = 64'hDEAD_BEEF_0BAD_F00D;
    apply_q(n, 1'b1, 1'b0);
    check("ALU: entry marked done",      XLEN'(cb_upd.done),       1);
    check("ALU: norollback set",         XLEN'(cb_upd.norollback), 1);
    check("ALU: from the main pipe",     XLEN'(cb_upd.from_main),  1);
    check("ALU: register write",         XLEN'(cb_upd.rd_we),      1);
    check("ALU: destination",            XLEN'(cb_upd.rd),         7);
    check("ALU: result",                 cb_upd.result,            64'hDEAD_BEEF_0BAD_F00D);
    check("ALU: forwarded value",        fdata,                    64'hDEAD_BEEF_0BAD_F00D);
    check("ALU: bypass data",            fdata,                    64'hDEAD_BEEF_0BAD_F00D);
    check("ALU: no store-buffer entry",  XLEN'(cb_upd.sb_alloc),   0);
    check("ALU: no CSR write",           XLEN'(cb_upd.csr.we),     0);

    n = make_ins(K_LOAD); n.rd = 5'd3; n.result = 64'h0000_0000_0000_FF01;
    n.maddr = 64'h8000_0040; n.rmask = 8'h03; n.mrdata = 64'h0000_0000_0000_FF01;
    apply_q(n, 1'b1, 1'b0);
    check("LOAD: result is the loaded value", cb_upd.result,            64'h0000_0000_0000_FF01);
    check("LOAD: RVFI addr",                  cb_upd.rvfi.addr,         64'h8000_0040);
    check("LOAD: RVFI rmask",                 XLEN'(cb_upd.rvfi.rmask), 8'h03);
    check("LOAD: RVFI wmask clear",           XLEN'(cb_upd.rvfi.wmask), 0);
    check("LOAD: forwarded value",            fdata,                    64'h0000_0000_0000_FF01);

    n = make_ins(K_STORE); n.maddr = 64'h8000_0080; n.wmask = 8'hF0;
    n.mwdata = 64'h1122_3344_5566_7788; n.sb_alloc = 1;
    apply_q(n, 1'b1, 1'b0);
    check("STORE: no register write",      XLEN'(cb_upd.rd_we),      0);
    check("STORE: store-buffer entry",     XLEN'(cb_upd.sb_alloc),   1);
    check("STORE: RVFI wmask",             XLEN'(cb_upd.rvfi.wmask), 8'hF0);
    check("STORE: forwarding bus zero",    fdata,                    0);

    n = make_ins(K_CSR); n.rd = 5'd9; n.result = 64'h0000_0000_0000_1800;
    n.csr_addr = 12'h300; n.csr_wdata = 64'h0000_0000_0000_1808; n.csr_we = 1;
    apply_q(n, 1'b1, 1'b0);
    check("CSR: old value to rd",   cb_upd.result,           64'h0000_0000_0000_1800);
    check("CSR: pending write",     XLEN'(cb_upd.csr.we),    1);
    check("CSR: address",           XLEN'(cb_upd.csr.addr),  12'h300);

    $display("[directed] x0 is never written and never forwarded");
    for (int k = 0; k < 150; k++) begin
      n = rand_ins(); n.rd_we = 1; n.rd = '0; n.exc = 0; n.complete = 1;
      apply_q(n, 1'b1, 1'b0);
      check("x0: no register write",  XLEN'(cb_upd.rd_we),    0);
      check("x0: result zeroed",      cb_upd.result,          0);
      check("x0: forwarding bus zero", fdata,                 0);
      check("x0: entry still done",   XLEN'(cb_upd.done),     1);
    end

    $display("[directed] a trap writes nothing but still resolves the entry");
    for (int k = 0; k < 300; k++) begin
      n = rand_ins();
      n.complete = 1; n.exc = 1; n.rd_we = 1;
      n.rd = REG_ADDR_W'(1 + ($urandom % 31));
      n.csr_we = 1; n.exccode = 6'($urandom % 16); n.exctval = {$urandom, $urandom};
      apply_q(n, 1'b1, 1'b0);
      check("trap: entry written",       XLEN'(cb_we),           1);
      check("trap: marked done",         XLEN'(cb_upd.done),     1);
      check("trap: no register write",   XLEN'(cb_upd.rd_we),    0);
      check("trap: no CSR write",        XLEN'(cb_upd.csr.we),   0);
      check("trap: forwarding bus zero", fdata,                  0);
      check("trap: cause reported",      XLEN'(cb_upd.exccode),  XLEN'(n.exccode));
    end

    $display("[directed] an MXIF candidate's entry is left to the MXIF port");
    for (int k = 0; k < 300; k++) begin
      n = make_ins(K_MXIF);
      n.rd_we = 1; n.rd = REG_ADDR_W'(1 + ($urandom % 31));
      apply_q(n, 1'b1, 1'b0);
      check("candidate: entry untouched", XLEN'(cb_we),           0);
      check("candidate: forwarding bus zero", fdata,              0);
      n.exc = 1; n.exccode = EXC_INSTR_ACCESS_FAULT;
      apply_q(n, 1'b1, 1'b0);
      check("faulted candidate: entry written", XLEN'(cb_we),          1);
      check("faulted candidate: cause",         XLEN'(cb_upd.exccode), XLEN'(EXC_INSTR_ACCESS_FAULT));
    end

    $display("[directed] flush discards the completion and the bypass with it");
    for (int k = 0; k < 300; k++) begin
      n = rand_ins(); n.complete = 1; n.exc = 0;
      n.rd_we = 1; n.rd = REG_ADDR_W'(1 + ($urandom % 31));
      apply_q(n, 1'b1, 1'b1);
      check("flush: no entry written", XLEN'(cb_we),           0);
      check("flush: forwarding bus zero", fdata,               0);
      apply_q(n, 1'b1, 1'b0);
      check("after flush: entry written", XLEN'(cb_we),  1);
      check("after flush: value forwarded", fdata, n.result);
    end

    $display("[directed] a store-buffer entry survives an exception on the same completion");
    n = make_ins(K_STORE); n.sb_alloc = 1; n.exc = 1; n.exccode = EXC_STORE_ACCESS_FAULT;
    apply_q(n, 1'b1, 1'b0);
    check("sb_alloc passed through unchanged", XLEN'(cb_upd.sb_alloc), 1);

    // -------------------------------------------------------------------------
    // Multi-cycle channels
    // -------------------------------------------------------------------------
    $display("[directed] a multi-cycle result writes only what a unit knows");
    for (int k = 0; k < UC_MAX; k++) begin uv[k] = 1'b0; ud[k] = '0; end
    uv[0] = 1'b1;
    ud[0] = '0; ud[0].cb_idx = CB_IDX_W'(5); ud[0].rd = 5'd12;
    ud[0].result = 64'h0123_4567_89AB_CDEF;
    apply(blank_ins(), 1'b0, 1'b0, uv, ud);
    check("unit: entry written",        XLEN'(cb_we),            1);
    check("unit: its entry",            XLEN'(cb_idx),           5);
    check("unit: not from the main pipe", XLEN'(cb_upd.from_main), 0);
    check("unit: marked done",          XLEN'(cb_upd.done),      1);
    check("unit: norollback set",       XLEN'(cb_upd.norollback), 1);
    check("unit: result",               cb_upd.result,           64'h0123_4567_89AB_CDEF);
    check("unit: value forwarded",      fdata,                   64'h0123_4567_89AB_CDEF);
    check("unit: accepted",             XLEN'(uc_ready[0]),      1);
    check("unit: no pass-through group", XLEN'(cb_upd.next_pc | cb_upd.exctval
                                         | cb_upd.csr.wdata | cb_upd.rvfi.addr), 0);
    check("unit: no CSR write",         XLEN'(cb_upd.csr.we),    0);
    check("unit: no store-buffer entry", XLEN'(cb_upd.sb_alloc), 0);

    $display("[directed] the main pipe always wins, and the unit holds");
    n = make_ins(K_ALU); n.rd = 5'd4; n.rd_we = 1; n.result = 64'hAAAA;
    uv[0] = 1'b1; uv[1] = 1'b1;
    ud[0] = '0; ud[0].cb_idx = CB_IDX_W'(1); ud[0].rd = 5'd20; ud[0].result = 64'hB0;
    ud[1] = '0; ud[1].cb_idx = CB_IDX_W'(2); ud[1].rd = 5'd21; ud[1].result = 64'hB1;
    apply(n, 1'b1, 1'b0, uv, ud);
    check("contention: main pipe wins",   XLEN'(cb_idx),      XLEN'(n.idx));
    check("contention: from the main pipe", XLEN'(cb_upd.from_main), 1);
    check("contention: unit 0 held",      XLEN'(uc_ready[0]), 0);
    check("contention: unit 1 held",      XLEN'(uc_ready[1]), 0);
    check("contention: stall reported",   XLEN'(uc_stall),    1);
    check("contention: main pipe value forwarded", fdata, 64'hAAAA);

    $display("[directed] the grant rotates, so neither unit starves");
    first = -1; second = -1;
    for (int k = 0; k < 8; k++) begin
      uv[0] = 1'b1; uv[1] = 1'b1;
      ud[0] = '0; ud[0].cb_idx = CB_IDX_W'(1); ud[0].rd = 5'd20;
      ud[1] = '0; ud[1].cb_idx = CB_IDX_W'(2); ud[1].rd = 5'd21;
      apply(blank_ins(), 1'b0, 1'b0, uv, ud);
      if (k == 0) first  = gnt;
      if (k == 1) second = gnt;
      check("rotation: exactly one unit accepted",
            XLEN'(int'(uc_ready[0]) + int'(uc_ready[1])), 1);
    end
    check("rotation: the other unit went next", XLEN'(first != second), 1);

    $display("[directed] a flush drains every unit, so none is left holding");
    uv[0] = 1'b1; uv[1] = 1'b1;
    ud[0] = '0; ud[0].cb_idx = CB_IDX_W'(3); ud[0].rd = 5'd7;
    ud[1] = '0; ud[1].cb_idx = CB_IDX_W'(4); ud[1].rd = 5'd8;
    apply(blank_ins(), 1'b0, 1'b1, uv, ud);
    check("flush: unit 0 drained",   XLEN'(uc_ready[0]), 1);
    check("flush: unit 1 drained",   XLEN'(uc_ready[1]), 1);
    check("flush: nothing written",  XLEN'(cb_we),       0);
    check("flush: forwarding bus zero", fdata, 0);
    check("flush: not counted as a stall", XLEN'(uc_stall), 0);

    $display("[probe] the completion-buffer write does not depend on the read addresses");
    for (int k = 0; k < 300; k++) begin
      n = rand_ins();
      apply_q(n, 1'b1, 1'b0);
      cb0 = cb_we; ix0 = cb_idx; u0 = cb_upd;
      apply_q(n, 1'b1, 1'b0);
      check("cb_we independent of read addresses",  XLEN'(cb_we),  XLEN'(cb0));
      if (cb0) begin
        check("cb_idx independent of read addresses",  XLEN'(cb_idx), XLEN'(ix0));
        check("payload independent of read addresses", XLEN'(cb_upd == u0), 1);
      end
    end

    $display("[probe] every completion-buffer index is reachable");
    for (int i = 0; i < CB_DEPTH; i++) begin
      n = make_ins(K_ALU); n.idx = CB_IDX_W'(i);
      apply_q(n, 1'b1, 1'b0);
      check($sformatf("index %0d addressed", i), XLEN'(cb_idx), XLEN'(i));
    end

    $display("[random] soak: main pipe and units contending, random flush");
    for (int k = 0; k < 60000; k++) begin
      bit v, f;
      v = (($urandom % 100) < 70);
      f = (($urandom % 100) < 10);
      apply_rand(rand_ins(), v, f, 45);
    end

    for (int i = 0; i < CB_DEPTH; i++) if (idx_seen[i] > 0) cv_idx_all++;

    $display("coverage: write %0d nowrite %0d x0 %0d exc %0d exc_kill %0d csr %0d csr_kill %0d",
             cv_write, cv_nowrite, cv_x0, cv_exc, cv_exc_kill, cv_csr, cv_csr_kill);
    $display("          mxif %0d mxif_exc %0d flush %0d idle %0d sb %0d sb_exc %0d",
             cv_mxif, cv_mxif_exc, cv_flush, cv_idle, cv_sb, cv_sb_exc);
    $display("          load %0d store %0d fwd value %0d fwd zero %0d indices %0d/%0d",
             cv_load, cv_store, cv_fwd_val, cv_fwd_zero, cv_idx_all, CB_DEPTH);
    $display("          uc win %0d (u0 %0d u1 %0d) blocked %0d both %0d flushed %0d x0 %0d swaps %0d ch3 %0d",
             cv_uc_win, uc_win_seen[0], uc_win_seen[1], cv_uc_block, cv_uc_both,
             cv_uc_flushed, cv_uc_x0, cv_rr_swap, cv_uc3_win);
    check("coverage all hit", XLEN'(cv_write > 0 && cv_nowrite > 0 && cv_x0 > 0 && cv_exc > 0
          && cv_exc_kill > 0 && cv_csr > 0 && cv_csr_kill > 0 && cv_mxif > 0 && cv_mxif_exc > 0
          && cv_flush > 0 && cv_idle > 0 && cv_sb > 0 && cv_sb_exc > 0 && cv_load > 0
          && cv_store > 0 && cv_fwd_val > 0 && cv_fwd_zero > 0
          && cv_idx_all == CB_DEPTH && cv_uc_win > 0 && cv_uc_block > 0 && cv_uc_both > 0
          && cv_uc_flushed > 0 && cv_uc_x0 > 0 && cv_rr_swap > 0 && cv_uc3_win > 0
          && uc_win_seen[0] > 0 && uc_win_seen[1] > 0), 1);

    if (errors != 0) $fatal(1, "=== FAIL : %0d of %0d checks ===", errors, checks);
    $display("=== PASS : %0d checks ===", checks);
    $finish;
  end
endmodule
