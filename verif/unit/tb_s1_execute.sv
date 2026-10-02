// =============================================================================
// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// Author(s)    : Ayesha Anwar (ayesha.anwaar2005@gmail.com) (Sep,2026)
// Modified By  :
//
// tb_s1_execute : unit testbench for s1_execute                     [WIP -- T-02]
// Description  :
// Instructions come from a perfect decoder (verif/common/rv64_golden.svh).
// Expected results come from an ISA model keyed on the mnemonic, independent
// of decoded_op_t routing and of s1_alu.  The TB plays ID, the CSR file,
// MUL/DIV and MEM with random backpressure, and checks every cycle.
//
// Run:  make test-unit TB=s1_execute
// =============================================================================

module tb_s1_execute
  import s1_pkg::*;
;

  `include "verif/common/rv64_golden.svh"

  localparam int unsigned     WATCHDOG = 200;
  localparam logic [XLEN-1:0] LEN32    = XLEN'(ILEN / 8);
  localparam logic [XLEN-1:0] LEN16    = XLEN'(2);

  logic                clk, rst_n, flush;
  priv_lvl_e           priv;
  logic                ex_valid, ex_ready;
  id_ex_t              ex_in;
  logic [XLEN-1:0]     memwb_fwd, cb1_fwd, cb2_fwd;
  logic [11:0]         csr_addr;
  logic                csr_re, csr_we, csr_illegal;
  logic [XLEN-1:0]     csr_rdata;
  logic                rd_valid;
  logic [XLEN-1:0]     rd_pc;
  logic [CB_IDX_W-1:0] rd_cb;
  logic                md_valid, md_ready;
  md_req_t             md_req;
  logic                mem_valid, mem_ready;
  ex_mem_t             mem_out;
  logic                perf_taken, perf_misp;

  s1_execute dut (
    .clk_i                (clk),
    .rst_ni               (rst_n),
    .flush_i              (flush),
    .priv_i               (priv),
    .ex_valid_i           (ex_valid),
    .ex_ready_o           (ex_ready),
    .ex_i                 (ex_in),
    .memwb_fwd_i          (memwb_fwd),
    .cb_rs1_fwd_i         (cb1_fwd),
    .cb_rs2_fwd_i         (cb2_fwd),
    .csr_addr_o           (csr_addr),
    .csr_re_o             (csr_re),
    .csr_we_o             (csr_we),
    .csr_rdata_i          (csr_rdata),
    .csr_illegal_i        (csr_illegal),
    .ex_redirect_valid_o  (rd_valid),
    .ex_redirect_pc_o     (rd_pc),
    .ex_redirect_cb_idx_o (rd_cb),
    .md_valid_o           (md_valid),
    .md_ready_i           (md_ready),
    .md_req_o             (md_req),
    .mem_valid_o          (mem_valid),
    .mem_ready_i          (mem_ready),
    .mem_o                (mem_out),
    .perf_br_taken_o      (perf_taken),
    .perf_br_mispredict_o (perf_misp)
  );

  int unsigned cycle = 0, checks = 0, errors = 0;

  task automatic check(input bit ok, input string what);
    checks++;
    if (!ok) begin
      errors++;
      if (errors <= 30) $display("  FAIL @%0d %s", cycle, what);
    end
  endtask

  // ---------------------------------------------------------------------------
  // Stimulus item: what ID would hold in ID/EX, plus the true register values.
  // ---------------------------------------------------------------------------
  typedef struct packed {
    logic [31:0]         instr;
    logic [31:0]         raw;
    logic [XLEN-1:0]     pc;
    logic                compressed;
    logic                pred;
    logic                fexc;
    logic [5:0]          fcode;
    logic [XLEN-1:0]     ftval;
    logic [XLEN-1:0]     v1, v2;
    fwd_src_e            s1, s2;
    logic [CB_IDX_W-1:0] cb;
    priv_lvl_e           priv;
    decoded_op_t         op;
  } item_t;

  typedef struct packed {
    logic            exc;
    logic            md;
    logic            redirect;
    logic            br_taken;
    logic            csr_re, csr_we;
    logic            res_valid;
    ex_mem_t         m;
    md_req_t         q;
  } exp_t;

  // CSR file model: fixed contents; illegal if nonexistent, above the current
  // privilege, or a write to the read-only space (addr[11:10] == 11).
  function automatic logic [XLEN-1:0] csr_val(input logic [11:0] a);
    return {20'h0, a, 20'h0, a} ^ 64'h5A5A_0000_A5A5_0000;
  endfunction
  function automatic bit csr_bad(input logic [11:0] a, input bit re, input bit we, input priv_lvl_e p);
    if (!re && !we) return 1'b0;
    return (a[3:0] == 4'hF) || (a[9:8] > p) || (we && a[11:10] == 2'b11);
  endfunction

  // ---------------------------------------------------------------------------
  // ISA model of one instruction in EX.
  // ---------------------------------------------------------------------------
  function automatic logic [XLEN-1:0] sx32(input logic [31:0] v);
    return 64'($signed(v));
  endfunction

  function automatic exp_t model(input item_t it, input logic [XLEN-1:0] a, input logic [XLEN-1:0] b);
    exp_t            e;
    gop_e            g;
    logic [31:0]     i;
    logic [XLEN-1:0] len, pc_len, res, tgt, nxt, fetch_to, old, src;
    logic            taken, ctrl_known, lsu, is_rw;
    e = '0; i = it.instr; g = g_classify(i);
    len    = it.compressed ? LEN16 : LEN32;
    pc_len = it.pc + len;
    res = '0; tgt = '0; taken = 1'b0; lsu = 1'b0;

    // Zicsr intents
    is_rw    = g inside {G_CSRRW, G_CSRRWI};
    e.csr_re = it.op.is_csr && !(is_rw && i[11:7] == 0);
    e.csr_we = it.op.is_csr && (is_rw || i[19:15] != 0);
    old      = csr_val(i[31:20]);

    if (it.fexc) begin
      e.exc = 1; e.m.exccode = it.fcode; e.m.exctval = it.ftval;
    end else if (it.op.illegal || (it.op.is_csr && csr_bad(i[31:20], e.csr_re, e.csr_we, it.priv))) begin
      e.exc = 1; e.m.exccode = EXC_ILLEGAL_INSTR; e.m.exctval = XLEN'(it.raw);
    end else if (g == G_ECALL) begin
      e.exc = 1;
      e.m.exccode = (it.priv == PRIV_U) ? EXC_ECALL_U : (it.priv == PRIV_S) ? EXC_ECALL_S : EXC_ECALL_M;
    end else if (g == G_EBREAK) begin
      e.exc = 1; e.m.exccode = EXC_BREAKPOINT; e.m.exctval = it.pc;
    end
    if (it.fexc || it.op.illegal) begin e.csr_re = 0; e.csr_we = 0; end

    case (g)
      G_LUI:   res = g_imm_u(i);
      G_AUIPC: res = it.pc + g_imm_u(i);
      G_ADDI:  res = a + g_imm_i(i);
      G_SLTI:  res = XLEN'($signed(a) < $signed(g_imm_i(i)));
      G_SLTIU: res = XLEN'(a < g_imm_i(i));
      G_XORI:  res = a ^ g_imm_i(i);
      G_ORI:   res = a | g_imm_i(i);
      G_ANDI:  res = a & g_imm_i(i);
      G_SLLI:  res = a << i[25:20];
      G_SRLI:  res = a >> i[25:20];
      G_SRAI:  res = $unsigned($signed(a) >>> i[25:20]);
      G_ADD:   res = a + b;
      G_SUB:   res = a - b;
      G_SLL:   res = a << b[5:0];
      G_SLT:   res = XLEN'($signed(a) < $signed(b));
      G_SLTU:  res = XLEN'(a < b);
      G_XOR:   res = a ^ b;
      G_SRL:   res = a >> b[5:0];
      G_SRA:   res = $unsigned($signed(a) >>> b[5:0]);
      G_OR:    res = a | b;
      G_AND:   res = a & b;
      G_ADDIW: res = sx32(32'(a + g_imm_i(i)));
      G_SLLIW: res = sx32(a[31:0] << i[24:20]);
      G_SRLIW: res = sx32(a[31:0] >> i[24:20]);
      G_SRAIW: res = sx32($unsigned($signed(a[31:0]) >>> i[24:20]));
      G_ADDW:  res = sx32(a[31:0] + b[31:0]);
      G_SUBW:  res = sx32(a[31:0] - b[31:0]);
      G_SLLW:  res = sx32(a[31:0] << b[4:0]);
      G_SRLW:  res = sx32(a[31:0] >> b[4:0]);
      G_SRAW:  res = sx32($unsigned($signed(a[31:0]) >>> b[4:0]));
      G_JAL:   begin taken = 1; tgt = it.pc + g_imm_j(i); res = pc_len; end
      G_JALR:  begin taken = 1; tgt = (a + g_imm_i(i)) & ~XLEN'(1); res = pc_len; end
      G_BEQ:   begin taken = (a == b);                    tgt = it.pc + g_imm_b(i); end
      G_BNE:   begin taken = (a != b);                    tgt = it.pc + g_imm_b(i); end
      G_BLT:   begin taken = ($signed(a) <  $signed(b));  tgt = it.pc + g_imm_b(i); end
      G_BGE:   begin taken = ($signed(a) >= $signed(b));  tgt = it.pc + g_imm_b(i); end
      G_BLTU:  begin taken = (a <  b);                    tgt = it.pc + g_imm_b(i); end
      G_BGEU:  begin taken = (a >= b);                    tgt = it.pc + g_imm_b(i); end
      G_CSRRW, G_CSRRS, G_CSRRC, G_CSRRWI, G_CSRRSI, G_CSRRCI: res = old;
      default: ;
    endcase
    e.res_valid = !e.exc && (it.op.unit == UNIT_CSR || (it.op.unit == UNIT_ALU && !it.op.is_branch));

    // Successor, and where fetch went (s1_fetch contract: pred_taken => pc+imm).
    nxt        = taken ? tgt : pc_len;
    ctrl_known = !it.pred || (g inside {G_JAL, G_BEQ, G_BNE, G_BLT, G_BGE, G_BLTU, G_BGEU});
    fetch_to   = !it.pred ? pc_len : (g == G_JAL) ? it.pc + g_imm_j(i) : it.pc + g_imm_b(i);
    e.redirect = !e.exc && (!ctrl_known || fetch_to != nxt);
    e.br_taken = !e.exc && taken && (g inside {G_BEQ, G_BNE, G_BLT, G_BGE, G_BLTU, G_BGEU});

    e.md = !e.exc && (it.op.unit == UNIT_MUL || it.op.unit == UNIT_DIV);
    e.q.unit = it.op.unit; e.q.op = it.op.muldiv_op; e.q.a = a; e.q.b = b;
    e.q.cb_idx = it.cb; e.q.rd = i[11:7];

    e.m.cb_idx   = it.cb;
    e.m.complete = e.exc || (it.op.unit != UNIT_MXIF);
    e.m.rd       = i[11:7];
    e.m.rd_we    = it.op.rd_we && !e.exc;
    e.m.result   = res;
    e.m.next_pc  = nxt;
    e.m.exc      = e.exc;
    if (!e.exc) begin
      lsu = 1'b1;
      case (g)
        G_LB, G_LBU, G_SB:                   e.m.mem_size = LS_BYTE;
        G_LH, G_LHU, G_SH:                   e.m.mem_size = LS_HALF;
        G_LW, G_LWU, G_SW:                   e.m.mem_size = LS_WORD;
        G_LD, G_SD:                          e.m.mem_size = LS_DOUBLE;
        default: begin
          if (i[6:0] == 7'h2f) e.m.mem_size = i[12] ? LS_DOUBLE : LS_WORD;
          else                 lsu = 1'b0;
        end
      endcase
      e.m.is_load    = g inside {G_LB, G_LH, G_LW, G_LD, G_LBU, G_LHU, G_LWU};
      e.m.is_store   = g inside {G_SB, G_SH, G_SW, G_SD};
      e.m.is_amo     = lsu && !e.m.is_load && !e.m.is_store;
      e.m.mem_signed = g inside {G_LB, G_LH, G_LW};
      e.m.mem_addr   = e.m.is_amo ? a : a + (e.m.is_store ? g_imm_s(i) : g_imm_i(i));
      e.m.mem_wdata  = b;
      e.m.amo_op     = it.op.amo_op;
      e.m.aq         = e.m.is_amo && i[26];
      e.m.rl         = e.m.is_amo && i[25];
      src            = (g inside {G_CSRRWI, G_CSRRSI, G_CSRRCI}) ? XLEN'(i[19:15]) : a;
      e.m.csr_we     = e.csr_we;
      e.m.csr_addr   = i[31:20];
      e.m.csr_wdata  = (g inside {G_CSRRW, G_CSRRWI}) ? src :
                       (g inside {G_CSRRS, G_CSRRSI}) ? (old | src) : (old & ~src);
    end
    return e;
  endfunction

  // Compare EX/MEM against the model, ignoring fields that are don't-care.
  task automatic check_mem(input ex_mem_t got, input exp_t e);
    ex_mem_t x;
    x = e.m;
    if (!e.res_valid) x.result = got.result;
    if (e.exc)        x.next_pc = got.next_pc;
    if (!(x.is_load || x.is_store || x.is_amo)) begin
      x.mem_addr = got.mem_addr; x.mem_wdata = got.mem_wdata; x.mem_size = got.mem_size;
      x.mem_signed = got.mem_signed; x.amo_op = got.amo_op; x.aq = got.aq; x.rl = got.rl;
    end
    if (x.is_load || (x.is_amo && x.amo_op == AMO_LR)) x.mem_wdata = got.mem_wdata;
    if (!x.csr_we) begin x.csr_addr = got.csr_addr; x.csr_wdata = got.csr_wdata; end
    checks++;
    if (got !== x) begin
      errors++;
      if (errors <= 30) begin
        $display("  FAIL @%0d EX/MEM mismatch cb=%0d", cycle, x.cb_idx);
        $display("       got res=%h nxt=%h ld/st/amo=%0d%0d%0d addr=%h wd=%h rd=%0d/%0d exc=%0d/%0d csr=%0d/%h/%h cmpl=%0d",
                 got.result, got.next_pc, got.is_load, got.is_store, got.is_amo, got.mem_addr,
                 got.mem_wdata, got.rd, got.rd_we, got.exc, got.exccode, got.csr_we, got.csr_addr,
                 got.csr_wdata, got.complete);
        $display("       exp res=%h nxt=%h ld/st/amo=%0d%0d%0d addr=%h wd=%h rd=%0d/%0d exc=%0d/%0d csr=%0d/%h/%h cmpl=%0d",
                 x.result, x.next_pc, x.is_load, x.is_store, x.is_amo, x.mem_addr,
                 x.mem_wdata, x.rd, x.rd_we, x.exc, x.exccode, x.csr_we, x.csr_addr,
                 x.csr_wdata, x.complete);
      end
    end
  endtask

  // ---------------------------------------------------------------------------
  // Generation
  // ---------------------------------------------------------------------------
  logic [CB_IDX_W-1:0] cb_next = '0;

  function automatic logic [XLEN-1:0] rnd_val();
    int unsigned r;
    r = $urandom_range(9);
    case (r)
      0: return '0;
      1: return '1;
      2: return {1'b1, {(XLEN-1){1'b0}}};
      3: return {1'b0, {(XLEN-1){1'b1}}};
      4: return 64'h0000_0000_8000_0000;
      5: return 64'hFFFF_FFFF_7FFF_FFFF;
      6: return XLEN'($urandom_range(63));
      default: return {$urandom, $urandom};
    endcase
  endfunction

  function automatic item_t make_item(input logic [31:0] instr);
    item_t       it;
    bit          gap;
    int unsigned pick_r;
    it            = '0;
    it.instr      = instr;
    it.pc         = {$urandom, $urandom} & ~XLEN'(1);
    it.compressed = ($urandom_range(3) == 0);
    it.raw        = it.compressed ? 32'($urandom_range(16'hFFFF)) : instr;
    it.op         = golden_decode(instr, it.pc, 1'b1, gap);
    pick_r        = $urandom_range(9);
    case (pick_r)
      0, 1, 2, 3: it.pred = 1'b0;
      4:          it.pred = 1'b1;                         // any predictor, any instruction
      default: begin                                      // BTFN
        it.pred = (instr[6:0] == 7'h6f) || (instr[6:0] == 7'h63 && instr[31]);
      end
    endcase
    it.fexc  = ($urandom_range(49) == 0);
    it.fcode = $urandom_range(1) ? EXC_INSTR_ACCESS_FAULT : EXC_ILLEGAL_INSTR;
    it.ftval = {$urandom, $urandom};
    it.v1    = rnd_val();
    it.v2    = rnd_val();
    it.s1    = fwd_src_e'($urandom_range(3));
    it.s2    = fwd_src_e'($urandom_range(3));
    if (it.s1 == FWD_MEMWB && it.s2 == FWD_MEMWB) it.v2 = it.v1;   // one MEM/WB producer
    it.cb    = cb_next++;
    it.priv  = ($urandom_range(2) == 0) ? PRIV_U : ($urandom_range(1) ? PRIV_S : PRIV_M);
    return it;
  endfunction

  function automatic item_t rnd_item();
    gop_e        g;
    logic [31:0] w;
    bit          gap;
    decoded_op_t d;
    do begin
      if ($urandom_range(19) == 0) w = $urandom;          // junk: illegal or MXIF
      else begin
        g = gop_e'($urandom_range(int'(G_NUM) - 1));
        w = g_encode_random(g);
      end
      d = golden_decode(w, '0, 1'b1, gap);
    end while (gap);
    return make_item(w);
  endfunction

  // ---------------------------------------------------------------------------
  // Environment state
  // ---------------------------------------------------------------------------
  item_t       dq [$];                  // directed items, presented first
  exp_t        memq [$];                // expected EX/MEM contents, in order
  bit          rnd_mode = 1'b0;
  bit          drv_flush = 1'b0;                       // one-shot
  int unsigned p_item = 80, p_flush = 0, md_rdy_pct = 100, mem_rdy_pct = 100;

  bit          have, first;
  item_t       cur;
  exp_t        ce;
  logic [XLEN-1:0] a_true, b_true;
  int unsigned wait_cyc;

  logic        p_md_valid, p_md_ready, p_mem_valid, p_mem_ready, p_flush_q;
  md_req_t     p_md_req;
  ex_mem_t     p_mem_out;

  int unsigned n_item, n_md, n_redir, n_exc, n_mxif, n_stall_cap, n_flush_kill, n_csrw, n_fire;
  int unsigned n_src [4];

  function automatic logic [XLEN-1:0] pick(input fwd_src_e s, input fwd_src_e want,
                                           input logic [XLEN-1:0] v);
    return (s == want) ? v : {$urandom, $urandom};
  endfunction

  task automatic tick();
    logic       v0, r0;
    md_req_t    q0;
    bit         fire, is_md, mem_hs;

    // ---- drive
    if (!have) begin
      if (dq.size() != 0)                                 begin cur = dq.pop_front(); have = 1; end
      else if (rnd_mode && $urandom_range(99) < p_item) begin cur = rnd_item();      have = 1; end
      first = have; wait_cyc = 0;
    end
    flush = drv_flush || (rnd_mode && ($urandom_range(999) < p_flush));
    drv_flush = 1'b0;
    ex_valid = have;
    ex_in    = {$urandom, $urandom, $urandom, $urandom, $urandom, $urandom, $urandom, $urandom,
                $urandom, $urandom, $urandom, $urandom, $urandom, $urandom, $urandom, $urandom};
    if (have) begin
      ex_in.op         = cur.op;
      ex_in.cb_idx     = cur.cb;
      ex_in.rs1_val    = (cur.s1 == FWD_RF) ? cur.v1 : cur.pc ^ 64'h1111;
      ex_in.rs2_val    = (cur.s2 == FWD_RF) ? cur.v2 : cur.pc ^ 64'h2222;
      ex_in.rs1_fwd    = cur.s1;
      ex_in.rs2_fwd    = cur.s2;
      ex_in.compressed = cur.compressed;
      ex_in.pred_taken = cur.pred;
      ex_in.instr_raw  = cur.raw;
      ex_in.exc        = cur.fexc;
      ex_in.exccode    = cur.fcode;
      ex_in.exctval    = cur.ftval;
      priv             = cur.priv;
    end
    // Bypass inputs carry the true value only in the first cycle.
    memwb_fwd = (have && first) ? pick(cur.s1, FWD_MEMWB, cur.v1) : {$urandom, $urandom};
    if (have && first && cur.s2 == FWD_MEMWB) memwb_fwd = cur.v2;
    cb1_fwd = (have && first) ? pick(cur.s1, FWD_CB, cur.v1) : {$urandom, $urandom};
    cb2_fwd = (have && first) ? pick(cur.s2, FWD_CB, cur.v2) : {$urandom, $urandom};

    // ---- settle, answer the CSR query, then probe ready-independence (R-C10)
    md_ready = 1'b0; mem_ready = 1'b0; #1;
    csr_rdata = csr_val(csr_addr); csr_illegal = csr_bad(csr_addr, csr_re, csr_we, priv); #1;
    v0 = md_valid; q0 = md_req; r0 = rd_valid;
    md_ready = 1'b1; mem_ready = 1'b1; #1;
    check(md_valid == v0 && (!v0 || md_req == q0), "md request depends on a ready input (R-C10)");
    check(rd_valid == r0, "redirect depends on a ready input");
    md_ready  = ($urandom_range(99) < md_rdy_pct);
    mem_ready = ($urandom_range(99) < mem_rdy_pct);
    #1;

    // First cycle: fix the true operands and the expectation.
    if (have && first) begin
      a_true = (cur.op.rs1 == 0) ? '0 : (cur.s1 == FWD_EXMEM) ? mem_out.result : cur.v1;
      b_true = (cur.op.rs2 == 0) ? '0 : (cur.s2 == FWD_EXMEM) ? mem_out.result : cur.v2;
      ce = model(cur, a_true, b_true);
      n_item++; n_src[cur.s1]++;
    end

    // ---- check
    mem_hs = mem_valid && mem_ready;
    if (p_mem_valid && !p_mem_ready && !p_flush_q)
      check(mem_valid && mem_out == p_mem_out, "EX/MEM withdrawn or changed before accept (R-C10)");
    if (p_md_valid && !p_md_ready && !p_flush_q && !flush && have)
      check(md_valid && md_req == p_md_req, "md request withdrawn or changed before accept (R-C10)");

    if (flush || !have) begin
      check(!rd_valid && !md_valid && !csr_re && !csr_we, "EX active while flushed or empty");
      check(!perf_taken && !perf_misp, "perf event while flushed or empty");
      check(ex_ready, "ex_ready_o low while flushed or empty");
    end else begin
      check(md_valid == ce.md, "md_valid_o wrong");
      if (ce.md) check(md_req == ce.q, $sformatf("md request payload wrong (cb %0d)", cur.cb));
      check(rd_valid == (first && ce.redirect), $sformatf("redirect %0d, want %0d (cb %0d)",
                                                           rd_valid, first && ce.redirect, cur.cb));
      if (rd_valid) check(rd_pc == ce.m.next_pc && rd_cb == cur.cb, "redirect pc or cb wrong");
      check(perf_taken == (first && ce.br_taken), "perf_br_taken_o wrong");
      check(perf_misp == rd_valid, "perf_br_mispredict_o differs from redirect");
      check(csr_re == ce.csr_re && csr_we == ce.csr_we, "CSR read/write intent wrong");
      if (csr_re || csr_we) check(csr_addr == cur.instr[31:20], "CSR address wrong");
      check(ex_ready == (ce.md ? md_ready : (!mem_valid || mem_ready)), "ex_ready_o wrong");
    end

    if (mem_hs) begin
      if (memq.size() == 0) check(1'b0, "EX/MEM valid with nothing expected");
      else check_mem(mem_out, memq.pop_front());
    end else if (flush && mem_valid && memq.size() != 0) begin
      void'(memq.pop_front());                            // flushed out of EX/MEM
    end

    fire = have && !flush && ex_ready;
    if (fire) begin
      is_md = ce.md;
      if (is_md) begin
        check(md_valid && md_ready, "fired without the dispatch handshake");
        n_md++;
      end else begin
        memq.push_back(ce);
      end
      if (ce.exc)                     n_exc++;
      if (cur.op.unit == UNIT_MXIF)   n_mxif++;
      if (ce.redirect)                n_redir++;
      if (ce.m.csr_we)                n_csrw++;
      if (!first && (cur.s1 != FWD_RF || cur.s2 != FWD_RF)) n_stall_cap++;
      n_fire++;
      have = 0;
    end else if (have && flush) begin
      n_flush_kill++;
      have = 0;
    end else if (have) begin
      wait_cyc++;
      if (wait_cyc > WATCHDOG) begin
        $display("  FAIL @%0d instruction stuck in EX for %0d cycles", cycle, WATCHDOG);
        $fatal(1, "tb_s1_execute: watchdog");
      end
    end

    p_md_valid = md_valid; p_md_ready = md_ready; p_md_req = md_req;
    p_mem_valid = mem_valid; p_mem_ready = mem_ready; p_mem_out = mem_out;
    p_flush_q = flush;

    // ---- clock
    clk = 1'b1; #1;
    clk = 1'b0; #1;
    first = 1'b0;
    cycle++;
  endtask

  task automatic run(input int unsigned n);
    repeat (n) tick();
  endtask

  task automatic drain();
    for (int unsigned n = 0; n < 200000 && (have || dq.size() != 0 || memq.size() != 0); n++) tick();
    check(!have && dq.size() == 0 && memq.size() == 0, "pipeline did not drain");
  endtask

  task automatic do_reset();
    clk = 0; flush = 0; ex_valid = 0; ex_in = '0; priv = PRIV_M;
    memwb_fwd = '0; cb1_fwd = '0; cb2_fwd = '0; csr_rdata = '0; csr_illegal = 0;
    md_ready = 0; mem_ready = 0;
    have = 0; first = 0; dq.delete(); memq.delete();
    p_md_valid = 0; p_md_ready = 0; p_mem_valid = 0; p_mem_ready = 0; p_flush_q = 0;
    p_md_req = '0; p_mem_out = '0;
    // Two-state sim: a reset low from time zero has no negedge; make one.
    rst_n = 1; #1; rst_n = 0; #1; clk = 1; #1; clk = 0; #1; rst_n = 1; #1;
    check(!mem_valid && !md_valid && !rd_valid, "outputs active out of reset");
  endtask

  // An item with chosen operands.  x0 is avoided so the values are used.
  function automatic item_t item_ab(input logic [31:0] w, input logic [XLEN-1:0] a,
                                    input logic [XLEN-1:0] b);
    item_t it;
    it = make_item(w);
    it.fexc = 0; it.v1 = a; it.v2 = b; it.s1 = FWD_RF; it.s2 = FWD_RF;
    return it;
  endfunction

  function automatic logic [31:0] with_regs(input logic [31:0] w, input int rd, input int r1,
                                            input int r2);
    w[11:7] = 5'(rd); w[19:15] = 5'(r1); w[24:20] = 5'(r2);
    return w;
  endfunction

  // ===========================================================================
  // Directed tests
  // ===========================================================================
  task automatic test_every_op();
    logic [XLEN-1:0] cv [8];
    cv = '{'0, '1, {1'b1, {(XLEN-1){1'b0}}}, {1'b0, {(XLEN-1){1'b1}}},
           64'h0000_0000_8000_0000, 64'hFFFF_FFFF_7FFF_FFFF, 64'd1, 64'h0123_4567_89AB_CDEF};
    for (int g = 0; g < int'(G_DRET); g++)
      foreach (cv[x]) foreach (cv[y]) begin
        item_t it;
        it = item_ab(g_encode_random(gop_e'(g)), cv[x], cv[y]);
        if (it.instr[6:0] != 7'h63) it.instr = with_regs(it.instr, 5, 6, 7);
        if (gop_e'(g) inside {G_ECALL, G_EBREAK, G_MRET, G_SRET, G_WFI, G_SFENCE_VMA, G_LR_W, G_LR_D})
          it.instr = g_encode_random(gop_e'(g));
        it.op = golden_decode(it.instr, it.pc, 1'b1, it.fexc);
        it.fexc = 0;
        dq.push_back(it);
      end
    drain();
  endtask

  task automatic test_branches();
    item_t it;
    logic [31:0] w;
    // Predicted-taken, not taken, target == fall-through: fetch was right.
    w = enc_beq(4, 5, 6);
    it = item_ab(w, 1, 2); it.pred = 1; it.compressed = 0; it.op = golden_decode(w, it.pc, 1'b1, it.fexc);
    it.fexc = 0; dq.push_back(it);
    // JALR to exactly pc+len, not predicted: no redirect.
    w = with_regs(32'h00000067, 1, 5, 0);
    it = item_ab(w, 0, 0); it.pred = 0; it.compressed = 1;
    it.v1 = it.pc + LEN16; it.op = golden_decode(w, it.pc, 1'b1, it.fexc); it.fexc = 0; dq.push_back(it);
    // JALR predicted taken: unverifiable, always redirected.
    it.pred = 1; it.cb = cb_next++; dq.push_back(it);
    // Non-branch predicted taken (a BTB alias): redirected to pc+len.
    w = with_regs(32'h00000013, 5, 6, 0);
    it = item_ab(w, 3, 0); it.pred = 1; it.op = golden_decode(w, it.pc, 1'b1, it.fexc); it.fexc = 0;
    dq.push_back(it);
    drain();
  endtask

  function automatic logic [31:0] enc_beq(input int imm, input int r1, input int r2);
    return {imm[12], imm[10:5], 5'(r2), 5'(r1), 3'b000, imm[4:1], imm[11], 7'h63};
  endfunction

  task automatic test_csr_and_system();
    item_t it;
    logic [31:0] w;
    logic [31:0] cases [7];
    cases = '{32'h34001073, 32'h34002073, 32'h34003073, 32'h34005073,    // csrrw x0; csrrs x0,..,x0; csrrc; csrrwi
              32'h3400E073, 32'h34007073, 32'hC0002073};                 // csrrsi uimm=0 w/ rd; csrrci; rdcycle (RO)
    foreach (cases[k]) foreach (cases[j]) begin
      w = cases[k]; w[19:15] = (j % 2) ? 5'd0 : 5'd9; w[11:7] = (j > 3) ? 5'd0 : 5'd3;
      it = item_ab(w, 64'hF0F0, 0); it.op = golden_decode(w, it.pc, 1'b1, it.fexc); it.fexc = 0;
      it.priv = priv_lvl_e'(j % 2 ? PRIV_U : PRIV_M);
      dq.push_back(it);
    end
    foreach (cases[k]) begin                                   // same CSRs from U-mode
      it = item_ab(cases[k], 1, 0); it.op = golden_decode(cases[k], it.pc, 1'b1, it.fexc);
      it.fexc = 0; it.priv = PRIV_U; dq.push_back(it);
    end
    for (int p = 0; p < 3; p++) begin                          // ECALL per privilege, EBREAK
      it = item_ab(32'h00000073, 0, 0); it.op = golden_decode(it.instr, it.pc, 1'b1, it.fexc);
      it.fexc = 0; it.priv = (p == 0) ? PRIV_U : (p == 1) ? PRIV_S : PRIV_M; dq.push_back(it);
    end
    it = item_ab(32'h00100073, 0, 0); it.op = golden_decode(it.instr, it.pc, 1'b1, it.fexc);
    it.fexc = 0; dq.push_back(it);
    drain();
  endtask

  task automatic test_exceptions();
    item_t it;
    // Fetch fault beats a decode-illegal encoding.
    it = item_ab(32'hFFFFFFFF, 0, 0); it.op = golden_decode(it.instr, it.pc, 1'b0, it.fexc);
    it.fexc = 1; it.fcode = EXC_INSTR_ACCESS_FAULT; it.ftval = 64'hDEAD; dq.push_back(it);
    // Illegal compressed-origin instruction: mtval is the 16-bit parcel.
    it = item_ab(32'h00001234, 0, 0); it.compressed = 1; it.raw = 32'h0000_1234;
    it.op = golden_decode(32'h00001234, it.pc, 1'b1, it.fexc); it.op.illegal = 1; it.fexc = 0;
    dq.push_back(it);
    // A decoder that flags illegal but leaves AMO side fields set must not reach memory.
    it = item_ab(32'h0000302f, 0, 0); it.op = golden_decode(32'h0000302f, it.pc, 1'b1, it.fexc);
    it.op.illegal = 1; it.fexc = 0; dq.push_back(it);
    // An AMO addresses with rs1 alone, even if the decoder left an immediate.
    it = item_ab(with_regs(32'h0000302f, 5, 6, 7), 64'h8000_1000, 1);
    it.op = golden_decode(it.instr, it.pc, 1'b1, it.fexc); it.op.imm = 64'h40; it.fexc = 0;
    dq.push_back(it);
    // Illegal DIV: no dispatch.
    it = item_ab(32'h02004033, 5, 0); it.op = golden_decode(32'h02004033, it.pc, 1'b1, it.fexc);
    it.op.illegal = 1; it.fexc = 0; dq.push_back(it);
    drain();
  endtask

  task automatic test_stalls();
    item_t it;
    // DIV held off for 10 cycles; bypass inputs change meanwhile.
    it = item_ab(with_regs(32'h02004033, 5, 6, 7), 100, 7);
    it.s1 = FWD_MEMWB; it.s2 = FWD_CB; it.op = golden_decode(it.instr, it.pc, 1'b1, it.fexc);
    it.fexc = 0; dq.push_back(it);
    md_rdy_pct = 0; run(10); md_rdy_pct = 100; drain();
    // Mispredicted branch held in EX by MEM: exactly one redirect.
    it = item_ab(enc_beq(8, 5, 6), 1, 1);
    it.pred = 0; it.s1 = FWD_CB; it.op = golden_decode(it.instr, it.pc, 1'b1, it.fexc); it.fexc = 0;
    dq.push_back(item_ab(32'h00a00293, 0, 0));                   // fill EX/MEM first
    dq.push_back(it);
    mem_rdy_pct = 0; run(12); mem_rdy_pct = 100; drain();
    // Flush a waiting DIV and a full EX/MEM.
    dq.push_back(item_ab(with_regs(32'h02004033, 5, 6, 7), 9, 3));
    md_rdy_pct = 0; run(3);
    drv_flush = 1; tick();
    md_rdy_pct = 100; drain();
  endtask

  task automatic test_throughput();
    int unsigned f0;
    for (int k = 0; k < 40; k++) dq.push_back(item_ab(with_regs(32'h00000033, 5, 6, 7), k, 1));
    run(1);
    f0 = n_fire;
    run(32);
    check(n_fire - f0 == 32, $sformatf("ALU throughput: %0d of 32 cycles", n_fire - f0));
    drain();
  endtask

  task automatic random_profile(input string name, input int unsigned cycles, input int unsigned pi,
                                input int unsigned mdr, input int unsigned memr, input int unsigned pf);
    int unsigned i0 = n_item;
    p_item = pi; md_rdy_pct = mdr; mem_rdy_pct = memr; p_flush = pf;
    rnd_mode = 1; run(cycles); rnd_mode = 0;
    md_rdy_pct = 100; mem_rdy_pct = 100; p_flush = 0;
    drain();
    $display("  random %-8s %6d cycles, %6d instructions", name, cycles, n_item - i0);
  endtask

  // ===========================================================================
  initial begin
    $display("=== tb_s1_execute : XLEN=%0d CB_DEPTH=%0d ===", XLEN, CB_DEPTH);
    do_reset();

    test_every_op();
    test_branches();
    test_csr_and_system();
    test_exceptions();
    test_stalls();
    do_reset();
    test_throughput();

    //             name     cycles  item md  mem flush(/1000)
    random_profile("ideal",   20000, 100, 100, 100,  0);
    random_profile("busy",    20000,  80,  50,  60,  5);
    random_profile("starved", 20000,  60,  20,  25, 10);

    check(n_item > 30000,    "too few instructions checked");
    check(n_md > 0,          "coverage: no MUL/DIV dispatch");
    check(n_redir > 0,       "coverage: no redirect");
    check(n_exc > 0,         "coverage: no exception");
    check(n_mxif > 0,        "coverage: no MXIF candidate");
    check(n_stall_cap > 0,   "coverage: no forwarded operand held across a stall");
    check(n_flush_kill > 0,  "coverage: no instruction killed by flush");
    check(n_csrw > 0,        "coverage: no CSR write");
    foreach (n_src[s]) check(n_src[s] > 0, $sformatf("coverage: forwarding source %0d unused", s));
    $display("  coverage: %0d instr, %0d md, %0d redirect, %0d exc, %0d mxif, %0d held-fwd, %0d flushed",
             n_item, n_md, n_redir, n_exc, n_mxif, n_stall_cap, n_flush_kill);

    if (errors == 0) begin
      $display("=== PASS : %0d checks ===", checks);
      $finish;
    end else begin
      $display("=== FAIL : %0d errors of %0d checks ===", errors, checks);
      $fatal(1, "tb_s1_execute failed");
    end
  end

endmodule
