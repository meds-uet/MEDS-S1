// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// Author(s)    : Eman Nasar <fatehulnasareman@gmail.com>, GitHub EmanNasar001 (Oct,2026)
// Modified By  :
//
// tb_s1_wb : unit testbench for s1_wb                             [WIP -- T-02]
//
// s1_wb is combinational and is the architectural commit point, so every check
// here is a check on what an instruction's arrival is allowed to change.  The
// golden model is written from the commit rules in SPEC 7.5 / 10.3 / 28.2, not
// from the RTL: it decides independently whether this cycle commits, traps, or
// stalls, and then what each output must be.
//
// Three things it goes after specifically, because they are the failures that
// corrupt architectural state rather than merely producing a wrong number:
//
//   1. A trap must suppress ALL THREE writes -- register file, CSR and the
//      store-buffer commit.  Letting the store commit through is the bug the
//      whole buffer-in-MEM-release-in-WB design exists to prevent.
//   2. An xRET must never raise privilege: SRET and DRET are illegal (no S-
//      or debug mode), MRET only from M.  An illegal one traps, with the
//      instruction in tval, and never jumps to mepc.
//   3. An interrupt REPLACES a commit, it does not follow one, so mepc must
//      name an instruction that has not executed and instret must not count.
//
// Run:  make test-unit           (all testbenches)
//       make test-unit TB=s1_wb  (just this one)
// =============================================================================

module tb_s1_wb
  import s1_pkg::*;
;

  // ---------------------------------------------------------------------------
  // DUT connections
  // ---------------------------------------------------------------------------
  logic             wb_valid;
  mem_wb_t          wb;
  logic             irq_valid;
  logic [5:0]       irq_code;
  logic [XLEN-1:0]  trap_vec, mepc;
  priv_lvl_e        priv;
  logic [63:0]      order;

  rf_wr_t           rf_wr;
  csr_upd_t         csr_commit;
  logic             instret;
  logic             sb_commit;
  logic             flush;
  flush_cause_e     flush_cause;
  logic             redirect_valid;
  logic [XLEN-1:0]  redirect_pc;
  trap_req_t        trap_req;
  logic             mret;
  logic             busy;
  rvfi_t            rvfi;
  logic             perf_load_retired, perf_store_retired;

  int unsigned checks = 0;
  int unsigned errors = 0;

  s1_wb dut (
    .wb_valid_i           (wb_valid),
    .wb_i                 (wb),
    .irq_valid_i          (irq_valid),
    .irq_code_i           (irq_code),
    .rf_wr_o              (rf_wr),
    .csr_commit_o         (csr_commit),
    .instret_o            (instret),
    .sb_commit_o          (sb_commit),
    .flush_o              (flush),
    .flush_cause_o        (flush_cause),
    .redirect_valid_o     (redirect_valid),
    .redirect_pc_o        (redirect_pc),
    .trap_req_o           (trap_req),
    .mret_o               (mret),
    .trap_vec_i           (trap_vec),
    .mepc_i               (mepc),
    .busy_o               (busy),
    .priv_i               (priv),
    .order_i              (order),
    .rvfi_o               (rvfi),
    .perf_load_retired_o  (perf_load_retired),
    .perf_store_retired_o (perf_store_retired)
  );

  // ---------------------------------------------------------------------------
  // Check helpers
  // ---------------------------------------------------------------------------
  string ctx = "";

  task automatic check(input string name,
                       input logic [XLEN-1:0] got,
                       input logic [XLEN-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      if (errors < 20)
        $display("  FAIL %-22s got=0x%016h exp=0x%016h   [%s]", name, got, exp, ctx);
    end
  endtask

  task automatic check1(input string name, input logic got, input logic exp);
    checks++;
    if (got !== exp) begin
      errors++;
      if (errors < 20)
        $display("  FAIL %-22s got=%0d exp=%0d   [%s]", name, got, exp, ctx);
    end
  endtask

  // ---------------------------------------------------------------------------
  // Golden model.  Derived from the commit rules, not from the RTL.
  //
  // An interrupt outranks the instruction's own commit.  A FENCE never waits
  // here: s1_mem only shows one once its store buffer is empty.
  //
  // xRET: privilege may only be returned from where it is held.  Modelled as
  // a table of what is legal, not as the RTL's expression of what is not.
  // ---------------------------------------------------------------------------
  logic             g_take_irq, g_commit_ok, g_trap_now, g_commit;
  logic             g_ret_ok, g_ret_bad, g_exc;
  logic [5:0]       g_exccode;
  logic [XLEN-1:0]  g_exctval;
  logic             g_is_mret, g_is_refetch;
  flush_cause_e     g_cause;
  logic [XLEN-1:0]  g_redirect_pc;
  logic             g_rf_we;
  rvfi_t            g_rvfi;
  trap_req_t        g_trap_req;

  task automatic golden();
    // Legal xRETs on an M+U core: MRET from M.  Nothing else.
    case (wb.sys_op)
      SYS_MRET:           g_ret_ok = (priv == PRIV_M);
      SYS_SRET, SYS_DRET: g_ret_ok = 1'b0;
      default:            g_ret_ok = 1'b1;               // not an xRET
    endcase
    g_ret_bad    = !wb.exc && !g_ret_ok;
    g_exc        = wb.exc || g_ret_bad;
    g_exccode    = wb.exc ? wb.exccode : EXC_ILLEGAL_INSTR;
    g_exctval    = wb.exc ? wb.exctval : XLEN'(wb.instr);

    g_take_irq   = wb_valid && irq_valid;
    g_commit_ok  = wb_valid && !g_take_irq;
    g_trap_now   = g_take_irq || (g_commit_ok && g_exc);
    g_commit     = g_commit_ok && !g_exc;

    g_is_mret    = g_commit && (wb.sys_op == SYS_MRET);
    g_is_refetch = g_commit && ((wb.sys_op == SYS_FENCE_I)
                                || (wb.sys_op == SYS_SFENCE_VMA));

    if      (g_trap_now)   g_cause = FLUSH_TRAP;
    else if (g_is_mret)    g_cause = FLUSH_MRET;
    else if (g_is_refetch) g_cause = (wb.sys_op == SYS_FENCE_I) ? FLUSH_FENCE_I : FLUSH_SFENCE;
    else                   g_cause = FLUSH_NONE;

    case (g_cause)
      FLUSH_TRAP: g_redirect_pc = trap_vec;
      FLUSH_MRET: g_redirect_pc = mepc;
      default:    g_redirect_pc = wb.next_pc;
    endcase

    g_rf_we = g_commit && wb.rd_we && (wb.rd != '0);

    g_trap_req = '0;
    if (g_take_irq) begin
      g_trap_req.valid   = 1'b1;
      g_trap_req.is_irq  = 1'b1;
      g_trap_req.exccode = irq_code;
      g_trap_req.epc     = wb.pc;
      g_trap_req.tval    = '0;
    end else if (g_commit_ok && g_exc) begin
      g_trap_req.valid   = 1'b1;
      g_trap_req.is_irq  = 1'b0;
      g_trap_req.exccode = g_exccode;
      g_trap_req.epc     = wb.pc;
      g_trap_req.tval    = g_exctval;
    end

    // The RVFI payload is driven every cycle; `valid` alone says whether a
    // consumer should look at it.  Modelling it as gated would hide a real
    // difference, so it is modelled the way the port is specified.
    g_rvfi           = '0;
    g_rvfi.valid     = g_commit_ok;
    g_rvfi.order     = order;
    g_rvfi.insn      = wb.instr;
    g_rvfi.trap      = g_exc;
    g_rvfi.halt      = 1'b0;
    g_rvfi.intr      = 1'b0;
    g_rvfi.mode      = priv;
    g_rvfi.ixl       = 2'd2;
    g_rvfi.rs1_addr  = wb.rs1_addr;
    g_rvfi.rs2_addr  = wb.rs2_addr;
    g_rvfi.rs1_rdata = wb.rs1_rdata;
    g_rvfi.rs2_rdata = wb.rs2_rdata;
    g_rvfi.rd_addr   = g_rf_we ? wb.rd     : '0;
    g_rvfi.rd_wdata  = g_rf_we ? wb.result : '0;
    g_rvfi.pc_rdata  = wb.pc;
    g_rvfi.pc_wdata  = (g_cause != FLUSH_NONE) ? g_redirect_pc : wb.next_pc;
    g_rvfi.mem.addr  = wb.mem_addr;
    g_rvfi.mem.rmask = wb.mem_rmask;
    g_rvfi.mem.wmask = wb.mem_wmask;
    g_rvfi.mem.rdata = wb.mem_rdata;
    g_rvfi.mem.wdata = wb.mem_wdata;
  endtask

  // ---------------------------------------------------------------------------
  // Compare every output against the model
  // ---------------------------------------------------------------------------
  task automatic check_all();
    golden();

    check1("busy",            busy,               wb_valid);
    check1("instret",         instret,            g_commit);

    check1("rf_wr.we",        rf_wr.we,           g_rf_we);
    check ("rf_wr.addr",      rf_wr.addr,         wb.rd);
    check ("rf_wr.data",      rf_wr.data,         wb.result);

    check1("csr.we",          csr_commit.we,      g_commit && wb.csr_we);
    check ("csr.addr",        csr_commit.addr,    wb.csr_addr);
    check ("csr.wdata",       csr_commit.wdata,   wb.csr_wdata);

    check1("sb_commit",       sb_commit,          g_commit && wb.sb_alloc);

    check1("flush",           flush,              g_cause != FLUSH_NONE);
    check ("flush_cause",     flush_cause,        g_cause);
    check1("redirect_valid",  redirect_valid,     g_cause != FLUSH_NONE);
    check ("redirect_pc",     redirect_pc,        g_redirect_pc);
    check1("mret",            mret,               g_is_mret);

    check1("trap.valid",      trap_req.valid,     g_trap_req.valid);
    check1("trap.is_irq",     trap_req.is_irq,    g_trap_req.is_irq);
    check ("trap.exccode",    trap_req.exccode,   g_trap_req.exccode);
    check ("trap.epc",        trap_req.epc,       g_trap_req.epc);
    check ("trap.tval",       trap_req.tval,      g_trap_req.tval);

    check1("perf_load",       perf_load_retired,  g_commit && (wb.mem_rmask != '0));
    check1("perf_store",      perf_store_retired, g_commit && (wb.mem_wmask != '0));

    check1("rvfi.valid",      rvfi.valid,         g_rvfi.valid);
    check ("rvfi.order",      rvfi.order,         g_rvfi.order);
    check ("rvfi.insn",       rvfi.insn,          g_rvfi.insn);
    check1("rvfi.trap",       rvfi.trap,          g_rvfi.trap);
    check1("rvfi.halt",       rvfi.halt,          g_rvfi.halt);
    check1("rvfi.intr",       rvfi.intr,          g_rvfi.intr);
    check ("rvfi.mode",       rvfi.mode,          g_rvfi.mode);
    check ("rvfi.ixl",        rvfi.ixl,           g_rvfi.ixl);
    check ("rvfi.rs1_addr",   rvfi.rs1_addr,      g_rvfi.rs1_addr);
    check ("rvfi.rs2_addr",   rvfi.rs2_addr,      g_rvfi.rs2_addr);
    check ("rvfi.rs1_rdata",  rvfi.rs1_rdata,     g_rvfi.rs1_rdata);
    check ("rvfi.rs2_rdata",  rvfi.rs2_rdata,     g_rvfi.rs2_rdata);
    check ("rvfi.rd_addr",    rvfi.rd_addr,       g_rvfi.rd_addr);
    check ("rvfi.rd_wdata",   rvfi.rd_wdata,      g_rvfi.rd_wdata);
    check ("rvfi.pc_rdata",   rvfi.pc_rdata,      g_rvfi.pc_rdata);
    check ("rvfi.pc_wdata",   rvfi.pc_wdata,      g_rvfi.pc_wdata);
    check ("rvfi.mem.addr",   rvfi.mem.addr,      g_rvfi.mem.addr);
    check ("rvfi.mem.rmask",  rvfi.mem.rmask,     g_rvfi.mem.rmask);
    check ("rvfi.mem.wmask",  rvfi.mem.wmask,     g_rvfi.mem.wmask);
    check ("rvfi.mem.rdata",  rvfi.mem.rdata,     g_rvfi.mem.rdata);
    check ("rvfi.mem.wdata",  rvfi.mem.wdata,     g_rvfi.mem.wdata);

    // ---- properties, not values --------------------------------------------
    // These restate the commit contract, so they fail even if the model and
    // the RTL have made the same mistake.
    if (g_exc && g_commit_ok) begin
      check1("trap kills rf write",  rf_wr.we,     1'b0);
      check1("trap kills csr write", csr_commit.we, 1'b0);
      check1("trap kills sb commit", sb_commit,    1'b0);
      check1("trap does not retire", instret,      1'b0);
    end
    // Privilege only returns from M-mode, and only through MRET.
    if (mret) begin
      check ("mret only from MRET",  wb.sys_op,    SYS_MRET);
      check ("mret only from M",     priv,         PRIV_M);
    end
    if (flush_cause == FLUSH_MRET) check1("xRET redirect means mret", mret, 1'b1);
    if (g_ret_bad && g_commit_ok) begin
      check1("bad xRET: no mret",     mret,          1'b0);
      check1("bad xRET: traps",       trap_req.valid, 1'b1);
      check ("bad xRET: illegal",     trap_req.exccode, EXC_ILLEGAL_INSTR);
      check ("bad xRET: tval=instr",  trap_req.tval, XLEN'(wb.instr));
      check ("bad xRET: to vector",   redirect_pc,   trap_vec);
    end
    if (g_take_irq) begin
      check1("irq: no retire",       instret,      1'b0);
      check1("irq: no rf",           rf_wr.we,     1'b0);
      check1("irq: no sb",           sb_commit,    1'b0);
      check1("irq: is_irq",          trap_req.is_irq, 1'b1);
      check ("irq: epc is this pc",  trap_req.epc, wb.pc);
      check ("irq: redirect to vec", redirect_pc,  trap_vec);
    end
    if (!wb_valid) begin
      check1("idle: no rf",          rf_wr.we,     1'b0);
      check1("idle: no csr",         csr_commit.we, 1'b0);
      check1("idle: no sb",          sb_commit,    1'b0);
      check1("idle: no flush",       flush,        1'b0);
      check1("idle: no trap",        trap_req.valid, 1'b0);
      check1("idle: no retire",      instret,      1'b0);
      check1("idle: not busy",       busy,         1'b0);
      check1("idle: no rvfi",        rvfi.valid,   1'b0);
    end
    check1("flush == redirect", flush, redirect_valid);
    check1("x0 is never written", rf_wr.we && (rf_wr.addr == '0), 1'b0);
  endtask

  // ---------------------------------------------------------------------------
  // Stimulus helpers
  // ---------------------------------------------------------------------------
  // Each 32-bit draw goes into a named variable first.  Drawing inside a wider
  // expression lets the tool hoist the call, and then two "independent" random
  // fields become the same number -- the stimulus silently collapses.
  task automatic rand_payload();
    logic [31:0] r0, r1, r2, r3, r4, r5, r6, r7, r8, r9, ra, rb;
    r0 = $urandom; r1 = $urandom; r2 = $urandom; r3 = $urandom;
    r4 = $urandom; r5 = $urandom; r6 = $urandom; r7 = $urandom;
    r8 = $urandom; r9 = $urandom; ra = $urandom; rb = $urandom;

    wb.result    = {r0, r1};
    wb.next_pc   = {r2, r3} & ~64'h1;
    wb.pc        = {r4, r5} & ~64'h1;
    wb.csr_wdata = {r6, r7};
    wb.exctval   = {r8, r9};
    wb.mem_addr  = {ra, rb};
    wb.instr     = $urandom;
    wb.csr_addr  = $urandom;
    wb.exccode   = $urandom;
    wb.tag       = $urandom;
    wb.rs1_addr  = $urandom;
    wb.rs2_addr  = $urandom;
    wb.mem_rmask = $urandom;
    wb.mem_wmask = $urandom;
    begin
      logic [31:0] s0, s1, s2, s3, s4, s5;
      s0 = $urandom; s1 = $urandom; s2 = $urandom;
      s3 = $urandom; s4 = $urandom; s5 = $urandom;
      wb.rs1_rdata = {s0, s1};
      wb.rs2_rdata = {s2, s3};
      wb.mem_rdata = {s4, s5};
      wb.mem_wdata = {$urandom, $urandom};
    end
    trap_vec = {$urandom, $urandom} & ~64'h3;
    mepc     = {$urandom, $urandom} & ~64'h1;
    order    = {$urandom, $urandom};
    irq_code = $urandom;
  endtask

  task automatic settle();
    #1;
  endtask

  // ---------------------------------------------------------------------------
  // Stimulus
  // ---------------------------------------------------------------------------
  int unsigned n_sys;

  initial begin
    $display("=== tb_s1_wb : XLEN=%0d ===", XLEN);

    wb        = '0;
    wb_valid  = 1'b0;
    irq_valid = 1'b0;
    irq_code  = '0;
    trap_vec  = '0;
    mepc      = '0;
    priv      = PRIV_M;
    order     = '0;
    settle();

    n_sys = int'(SYS_DRET) + 1;

    // --- exhaustive over the control space -----------------------------------
    // Nine binary or small-enumerated inputs decide what this stage does; the
    // data payload only decides what it writes.  So the control space is swept
    // exhaustively with a fresh random payload each time, which is both a
    // complete control sweep and a random data sweep.
    for (int unsigned v = 0; v < 2; v++)
    for (int unsigned q = 0; q < 2; q++)
    for (int unsigned e = 0; e < 2; e++)
    for (int unsigned s = 0; s < n_sys; s++)
    for (int unsigned rw = 0; rw < 2; rw++)
    for (int unsigned rz = 0; rz < 2; rz++)
    for (int unsigned cw = 0; cw < 2; cw++)
    for (int unsigned sa = 0; sa < 2; sa++)
    for (int unsigned pm = 0; pm < 3; pm++) begin
      logic [31:0] rd_draw;
      rand_payload();
      wb_valid   = v[0];
      irq_valid  = q[0];
      wb.exc     = e[0];
      wb.sys_op  = sys_op_e'(s);
      wb.rd_we   = rw[0];
      rd_draw    = $urandom_range(31, 1);
      wb.rd      = (rz[0] != 0) ? 5'd0 : rd_draw[4:0];
      wb.csr_we  = cw[0];
      wb.sb_alloc = sa[0];
      priv       = (pm == 0) ? PRIV_U : ((pm == 1) ? PRIV_S : PRIV_M);
      ctx = $sformatf("v=%0d irq=%0d exc=%0d %s rd_we=%0d rd0=%0d csr=%0d sb=%0d %s",
                      v, q, e, wb.sys_op.name(), rw, rz, cw, sa, priv.name());
      settle();
      check_all();
    end

    // --- directed: the cases worth naming ------------------------------------
    ctx = "directed";

    // A FENCE commits when it arrives: s1_mem only shows it once the store
    // buffer is empty, so WB has nothing to wait for.  FENCE (not FENCE.I)
    // does not redirect -- redirecting on a plain FENCE would refetch on
    // every one.
    rand_payload();
    wb_valid = 1'b1; irq_valid = 1'b0; wb.exc = 1'b0; priv = PRIV_M;
    wb.sys_op = SYS_FENCE; wb.rd_we = 1'b0; wb.csr_we = 1'b0; wb.sb_alloc = 1'b0;
    settle(); check_all();
    check1("FENCE retires",  instret, 1'b1);
    check1("FENCE no flush", flush,   1'b0);

    // An interrupt on a FENCE is taken in its place, like any instruction.
    irq_valid = 1'b1;
    settle(); check_all();
    check1("irq on FENCE taken",  trap_req.is_irq, 1'b1);
    check1("irq on FENCE: no retire", instret, 1'b0);
    irq_valid = 1'b0;

    // FENCE.I does redirect, to the successor, which is what refreshes the
    // frontend.  It must not go to the trap vector or to mepc.
    wb.sys_op = SYS_FENCE_I;
    settle(); check_all();
    check ("FENCE.I cause", flush_cause, FLUSH_FENCE_I);
    check ("FENCE.I -> next_pc", redirect_pc, wb.next_pc);

    wb.sys_op = SYS_SFENCE_VMA;
    settle(); check_all();
    check ("SFENCE cause", flush_cause, FLUSH_SFENCE);

    // xRET in every mode.  Only MRET from M returns to mepc; every other
    // combination is an illegal-instruction trap that must not raise
    // privilege.  This is the privilege-escalation case, named one by one.
    begin
      sys_op_e   rets[3];
      priv_lvl_e modes[3];
      rets[0]  = SYS_MRET; rets[1]  = SYS_SRET; rets[2]  = SYS_DRET;
      modes[0] = PRIV_U;   modes[1] = PRIV_S;   modes[2] = PRIV_M;
      for (int unsigned i = 0; i < 3; i++)
        for (int unsigned m = 0; m < 3; m++) begin
          logic legal;
          rand_payload();
          wb_valid = 1'b1; irq_valid = 1'b0; wb.exc = 1'b0;
          wb.sys_op = rets[i]; priv = modes[m];
          wb.rd_we = 1'b1; wb.rd = 5'd5; wb.csr_we = 1'b1; wb.sb_alloc = 1'b0;
          legal = (rets[i] == SYS_MRET) && (modes[m] == PRIV_M);
          ctx = $sformatf("%s from %s", rets[i].name(), modes[m].name());
          settle(); check_all();
          check1("xRET mret_o",    mret,           legal);
          check1("xRET traps",     trap_req.valid, !legal);
          check ("xRET redirect",  redirect_pc,    legal ? mepc : trap_vec);
          check1("xRET retires",   instret,        legal);
          check1("xRET no rf/csr", rf_wr.we || csr_commit.we, legal);
          if (!legal) begin
            check ("illegal xRET code", trap_req.exccode, EXC_ILLEGAL_INSTR);
            check ("illegal xRET tval", trap_req.tval,    XLEN'(wb.instr));
            check1("illegal xRET rvfi.trap", rvfi.trap,   1'b1);
          end
        end
      ctx = "directed";
    end

    // A trapping xRET is a trap, not a return: the exception wins, so mret
    // must drop and the redirect must go to the vector.
    rand_payload();
    wb_valid = 1'b1; irq_valid = 1'b0; wb.exc = 1'b1; priv = PRIV_M;
    wb.sys_op = SYS_MRET;
    settle(); check_all();
    check1("trapping MRET drops mret", mret, 1'b0);
    check ("trapping MRET -> vec", redirect_pc, trap_vec);

    // An interrupt on a trapping instruction: the interrupt wins and reports
    // its own code, not the exception's.  Getting this backwards reports an
    // exception that never happened.
    irq_valid = 1'b1; irq_code = 6'd11; wb.exccode = EXC_ILLEGAL_INSTR;
    settle(); check_all();
    check1("irq beats exception", trap_req.is_irq, 1'b1);
    check ("irq code reported", trap_req.exccode, 64'd11);
    check ("irq tval is zero",  trap_req.tval,    '0);

    // A store that faulted must not commit its buffer entry, even though MEM
    // set sb_alloc before it knew.  This is the state-corrupting case.
    rand_payload();
    wb_valid = 1'b1; irq_valid = 1'b0; wb.exc = 1'b1;
    wb.sys_op = SYS_NONE; wb.sb_alloc = 1'b1; wb.mem_wmask = 8'hFF;
    settle(); check_all();
    check1("faulting store does not commit", sb_commit, 1'b0);
    check1("faulting store is not counted",  perf_store_retired, 1'b0);

    // x0 is hardwired: a committed instruction with rd_we and rd=0 must not
    // write, and RVFI must report rd_addr 0 with rd_wdata 0 rather than the
    // value that was dropped.
    rand_payload();
    wb_valid = 1'b1; irq_valid = 1'b0; wb.exc = 1'b0;
    wb.sys_op = SYS_NONE; wb.rd_we = 1'b1; wb.rd = 5'd0;
    settle(); check_all();
    check1("rd=x0 suppressed", rf_wr.we, 1'b0);
    check ("rd=x0 rvfi wdata", rvfi.rd_wdata, '0);

    // RVFI reports a trapping instruction with trap set, and pc_wdata naming
    // the vector it actually went to -- not the successor it never reached.
    rand_payload();
    wb_valid = 1'b1; irq_valid = 1'b0; wb.exc = 1'b1;
    wb.sys_op = SYS_NONE;
    settle(); check_all();
    check1("rvfi reports the trap", rvfi.valid, 1'b1);
    check1("rvfi.trap set",         rvfi.trap,  1'b1);
    check ("rvfi.pc_wdata = vec",   rvfi.pc_wdata, trap_vec);

    // --- random ---------------------------------------------------------------
    for (int unsigned n = 0; n < 4000; n++) begin
      logic [31:0] d0, d1, d2, d3, d4, d5, d6;
      rand_payload();
      d0 = $urandom; d1 = $urandom; d2 = $urandom; d3 = $urandom;
      d4 = $urandom; d5 = $urandom; d6 = $urandom;
      wb_valid    = d0[0];
      irq_valid   = d1[0];
      wb.exc      = d2[0];
      wb.rd_we    = d3[0];
      wb.csr_we   = d3[1];
      wb.sb_alloc = d3[2];
      wb.rd       = d4[4:0];
      wb.sys_op   = sys_op_e'(d5 % n_sys);
      priv        = priv_lvl_e'((d6[1:0] == 2'b10) ? 2'b11 : d6[1:0]);
      ctx = $sformatf("rand %0d", n);
      settle();
      check_all();
    end

    // ---------------------------------------------------------------------------
    if (errors == 0) begin
      $display("=== PASS : %0d checks ===", checks);
      $finish;
    end else begin
      $display("=== FAIL : %0d errors of %0d checks ===", errors, checks);
      $fatal(1, "tb_s1_wb failed");
    end
  end

endmodule
