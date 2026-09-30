// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// s1_mem_stage_model.svh : reference models for tb_s1_mem_stage       [WIP -- R-02]
//
// Included inside tb_s1_mem_stage.  Everything here is written independently
// of the RTL: PMP matches byte by byte, AMO compares at the access width, and
// memory is a byte map.  The testbench must declare pmpcfg, pmpaddr and the
// pma_* nets before including this file.
// =============================================================================

  localparam int unsigned BB = XLEN / 8;                  // bytes per I2 beat
  localparam int unsigned OW = $clog2(BB);
  localparam logic [XLEN-1:0] DRAM = 64'h8000_0000, UNC = 64'h1_0000_0000, MMIO = 64'h2000_0000;
  localparam int unsigned DRAM_SPAN = 32 * BB, UNC_SPAN = 8 * BB, MMIO_SPAN = 8 * BB;
  localparam logic [XLEN-1:0] BAD = DRAM + XLEN'(DRAM_SPAN - BB);  // last DRAM beat: bus error

  localparam int K_OTHER = 0, K_LOAD = 1, K_STORE = 2, K_LR = 3, K_SC = 4, K_AMO = 5;

  // ---------------------------------------------------------------------------
  // PMA: DRAM (rvwmo, align any, LR/SC + AMO), UNC (strong, natural, AMO only),
  // MMIO (strong, non-idempotent, natural, widths 4/8, no atomics).
  // ---------------------------------------------------------------------------
  function automatic int region(logic [XLEN-1:0] a, int unsigned n);
    if (a >= DRAM && a + XLEN'(n) <= DRAM + XLEN'(DRAM_SPAN)) return 1;
    if (a >= UNC  && a + XLEN'(n) <= UNC  + XLEN'(UNC_SPAN))  return 2;
    if (a >= MMIO && a + XLEN'(n) <= MMIO + XLEN'(MMIO_SPAN)) return 3;
    return 0;
  endfunction

  function automatic pma_t pma_of(int r);
    pma_t p = '0;
    p.cacheable     = (r == 1);
    p.idempotent    = (r != 3);
    p.strong_order  = (r >= 2);
    p.atomic_lrsc   = (r == 1);
    p.atomic_amo    = (r == 1 || r == 2);
    p.align_natural = (r >= 2);
    return p;
  endfunction

  always_comb begin
    int r;
    r         = region(pma_addr, 1 << pma_size);
    pma       = pma_of(r);
    pma_fault = (r == 0) || (r == 3 && pma_size < 2);
  end

  // ---------------------------------------------------------------------------
  // PMP, byte by byte (privileged spec 3.7)
  // ---------------------------------------------------------------------------
  function automatic bit pmp_allows(logic [XLEN-1:0] a, int n, bit r, bit w, priv_lvl_e m);
    logic [127:0] lo, hi, ab;
    int  k;
    bit  any_b, all_b, inr;
    for (int i = 0; i < PMP_N; i++) begin
      lo = '0; hi = '0;
      unique case (pmpcfg[i][4:3])
        2'b00: continue;
        2'b01: begin lo = (i == 0) ? 0 : 128'(pmpaddr[i-1]) * 4; hi = 128'(pmpaddr[i]) * 4; end
        2'b10: begin lo = 128'(pmpaddr[i]) * 4; hi = lo + 4; end
        default: begin
          k = 0;
          while (k < PLEN - 2 && pmpaddr[i][k]) k++;
          lo = (128'(pmpaddr[i]) >> (k + 1) << (k + 1)) * 4;
          hi = lo + (128'(1) << (k + 3));
        end
      endcase
      any_b = 0; all_b = 1;
      for (int j = 0; j < n; j++) begin
        ab    = 128'(a) + j;
        inr   = ab >= lo && ab < hi;
        any_b |= inr;
        all_b &= inr;
      end
      if (any_b) return all_b && ((m == PRIV_M && !pmpcfg[i][7]) || ((!r || pmpcfg[i][0]) && (!w || pmpcfg[i][1])));
    end
    return m == PRIV_M;
  endfunction

  // ---------------------------------------------------------------------------
  // Memories: architectural (retired), program-order (presented), and the bus
  // ---------------------------------------------------------------------------
  byte unsigned arch[longint unsigned], pom[longint unsigned], busm[longint unsigned];

  function automatic byte unsigned init_byte(longint unsigned a);
    return 8'(a ^ (a >> 8) ^ (a >> 29) ^ 64'h5A);
  endfunction
  function automatic byte unsigned rd_arch(longint unsigned a);
    return arch.exists(a) != 0 ? arch[a] : init_byte(a);
  endfunction
  function automatic byte unsigned rd_pom(longint unsigned a);
    return pom.exists(a) != 0 ? pom[a] : init_byte(a);
  endfunction
  function automatic byte unsigned rd_bus(longint unsigned a);
    return busm.exists(a) != 0 ? busm[a] : init_byte(a);
  endfunction
  function automatic bit in_bad(longint unsigned a);
    return a >= BAD && a < BAD + BB;
  endfunction

  function automatic logic [XLEN-1:0] sext_w(logic [XLEN-1:0] v, int lg, bit s);
    int b = 8 << lg;
    if (lg == OW) return v;
    return s ? XLEN'($signed(v << (XLEN - b)) >>> (XLEN - b)) : (v & ((XLEN'(1) << b) - 1));
  endfunction

  // AMO at the access width; MINU/MAXU compare the width's unsigned value.
  function automatic logic [XLEN-1:0] amo_ref(amo_op_e op, logic [XLEN-1:0] a, logic [XLEN-1:0] b, int lg);
    longint signed   sa = $signed(sext_w(a, lg, 1)), sb = $signed(sext_w(b, lg, 1));
    longint unsigned ua = sext_w(a, lg, 0), ub = sext_w(b, lg, 0);
    logic [XLEN-1:0] r;
    unique case (op)
      AMO_ADD:  r = a + b;
      AMO_XOR:  r = a ^ b;
      AMO_AND:  r = a & b;
      AMO_OR:   r = a | b;
      AMO_MIN:  r = (sa < sb) ? a : b;
      AMO_MAX:  r = (sa > sb) ? a : b;
      AMO_MINU: r = (ua < ub) ? a : b;
      AMO_MAXU: r = (ua > ub) ? a : b;
      default:  r = b;
    endcase
    return sext_w(r, lg, 0);
  endfunction

  // ---------------------------------------------------------------------------
  // Records and instruction descriptions
  // ---------------------------------------------------------------------------
  typedef struct {
    ex_mem_t   ex;
    priv_lvl_e priv;
    int        seq, lg, kind;
    bit        fault, busrd_err, mmio, ordered, completed, sc_skip, alloc, pmp_deny, misalign, atomic;
    logic [5:0] code;
    logic [XLEN-1:0] tval, val, raw, wv;
    longint    t_acc, t_cmp;
  } rec_t;

  typedef struct { int kind, lg; bit sext; amo_op_e amo; logic [XLEN-1:0] addr, data;
                   priv_lvl_e priv; bit exc; } ins_t;

  function automatic rec_t blank_rec();
    rec_t r;
    r.ex = '0; r.priv = PRIV_M; r.seq = -1; r.lg = 0; r.kind = K_OTHER;
    r.fault = 0; r.busrd_err = 0; r.mmio = 0; r.ordered = 0; r.completed = 0; r.sc_skip = 0;
    r.alloc = 0; r.pmp_deny = 0; r.misalign = 0; r.atomic = 0;
    r.code = '0; r.tval = '0; r.val = '0; r.raw = '0; r.wv = '0; r.t_acc = -1; r.t_cmp = -1;
    return r;
  endfunction

  // Program-order reservation.  A flush clears it, as the stage does.
  bit              pres_valid = 0;
  logic [XLEN-1:0] pres_addr;
  int              pres_lg;

  int seq = 0, next_tag = 0;

  // Build the record for a newly presented instruction and apply its effect to
  // the program-order memory and reservation.
  function automatic rec_t make_rec(ins_t in);
    rec_t r = blank_rec();
    int   n = 1 << in.lg, reg_r;
    bit   rd, wr, pma_f;
    pma_t p;
    r.seq  = seq++;
    r.priv = in.priv;
    r.kind = in.kind;
    r.lg   = in.lg;
    r.ex.cb_idx     = CB_IDX_W'(next_tag);
    next_tag        = (next_tag + 1) % CB_DEPTH;
    r.ex.complete   = ($urandom % 8) != 0;
    r.ex.rd         = REG_ADDR_W'($urandom);
    r.ex.rd_we      = 1'($urandom);
    r.ex.result     = {$urandom, $urandom};
    r.ex.next_pc    = {$urandom, $urandom};
    r.ex.is_load    = in.kind == K_LOAD;
    r.ex.is_store   = in.kind == K_STORE;
    r.ex.is_amo     = in.kind inside {K_LR, K_SC, K_AMO};
    r.ex.mem_size   = ls_size_e'(in.lg);
    r.ex.mem_signed = in.sext;
    r.ex.amo_op     = in.kind == K_LR ? AMO_LR : in.kind == K_SC ? AMO_SC : in.kind == K_AMO ? in.amo : AMO_NONE;
    r.ex.aq         = 1'($urandom);
    r.ex.rl         = 1'($urandom);
    r.ex.mem_addr   = in.addr;
    r.ex.mem_wdata  = in.data;
    r.ex.csr_we     = in.kind == K_OTHER && 1'($urandom);
    r.ex.csr_addr   = 12'($urandom);
    r.ex.csr_wdata  = {$urandom, $urandom};
    r.ex.exc        = in.exc;
    r.ex.exccode    = in.exc ? EXC_ILLEGAL_INSTR : '0;
    r.ex.exctval    = in.exc ? {$urandom, $urandom} : '0;
    if (in.exc) begin
      r.code = r.ex.exccode;
      r.tval = r.ex.exctval;
      return r;
    end
    if (in.kind == K_OTHER) return r;

    rd      = in.kind inside {K_LOAD, K_LR, K_AMO};
    wr      = in.kind inside {K_STORE, K_SC, K_AMO};
    reg_r   = region(in.addr, n);
    p       = pma_of(reg_r);
    r.mmio    = reg_r == 3;
    r.ordered = reg_r >= 2;
    if (in.kind == K_SC) begin
      r.sc_skip  = !(pres_valid && pres_addr == in.addr && pres_lg == in.lg);
      pres_valid = 0;
      if (r.sc_skip) begin r.val = 1; return r; end
    end
    pma_f      = reg_r == 0 || (reg_r == 3 && in.lg < 2);
    r.misalign = reg_r >= 2 && (in.addr & XLEN'(n - 1)) != 0;
    r.atomic   = (in.kind inside {K_LR, K_SC} && !p.atomic_lrsc) || (in.kind == K_AMO && !p.atomic_amo);
    r.pmp_deny = !pmp_allows(in.addr, n, rd, wr, in.priv);
    if (pma_f || r.misalign || r.atomic || r.pmp_deny) begin
      r.fault = 1;
      r.code  = in.kind inside {K_LOAD, K_LR} ? EXC_LOAD_ACCESS_FAULT : EXC_STORE_ACCESS_FAULT;
      r.tval  = in.addr;
      return r;
    end
    if (rd && (in_bad(in.addr) || in_bad(in.addr + n - 1))) begin
      r.busrd_err = 1;
      r.code = in.kind == K_AMO ? EXC_STORE_ACCESS_FAULT : EXC_LOAD_ACCESS_FAULT;
      r.tval = in_bad(in.addr) ? in.addr : ((in.addr >> OW) + 1) << OW;
      return r;
    end
    if (rd) begin
      for (int k = 0; k < n; k++) r.raw[8*k +: 8] = rd_pom(in.addr + k);
      r.val = sext_w(r.raw, in.lg, in.kind == K_LOAD ? in.sext : 1'b1);
    end
    if (in.kind == K_LR) begin
      pres_valid = 1; pres_addr = in.addr; pres_lg = in.lg;
    end
    if (wr) begin
      r.alloc = 1;
      r.wv    = in.kind == K_AMO ? amo_ref(in.amo, r.raw, in.data, in.lg) : sext_w(in.data, in.lg, 0);
      if (in.kind == K_SC) r.val = 0;
      for (int k = 0; k < n; k++) pom[in.addr + k] = r.wv[8*k +: 8];
    end
    return r;
  endfunction

  function automatic ins_t rand_ins();
    ins_t in;
    int   k = $urandom % 100, rk = $urandom % 100, n;
    in.priv = ($urandom % 100 < 80) ? PRIV_M : PRIV_U;
    in.data = {$urandom, $urandom};
    in.exc  = k >= 95;
    in.kind = k < 36 ? K_LOAD : k < 60 ? K_STORE : k < 66 ? K_LR : k < 73 ? K_SC : k < 82 ? K_AMO
            : k < 95 ? K_OTHER : ($urandom % 2 ? K_LOAD : K_SC);
    in.lg   = in.kind inside {K_LR, K_SC, K_AMO} ? 2 + $urandom % 2 : $urandom % 4;
    in.sext = 1'($urandom);
    in.amo  = amo_op_e'(2 + $urandom % 9);
    n = 1 << in.lg;
    if (rk < 72) begin                                     // dense DRAM window for overlaps
      in.addr = DRAM + XLEN'(($urandom % 4 == 0) ? $urandom % DRAM_SPAN : 32 + $urandom % 40);
      if (in.kind inside {K_STORE, K_SC} && in.addr + XLEN'(n) > BAD) in.addr = DRAM + XLEN'($urandom % 60);
    end else if (rk < 81) begin
      in.addr = UNC  + XLEN'(($urandom % (UNC_SPAN / n)) * n  + (($urandom % 8 == 0) ? 1 : 0));
    end else if (rk < 92) begin
      in.addr = MMIO + XLEN'(($urandom % (MMIO_SPAN / n)) * n + (($urandom % 8 == 0) ? 2 : 0));
    end else if (rk < 96) begin
      in.addr = DRAM - XLEN'(1 + $urandom % 4);
    end else begin
      in.addr = 64'h9000_0000 + XLEN'($urandom % 64);
    end
    if (in.kind == K_SC && pres_valid && $urandom % 10 < 7) begin
      in.addr = pres_addr;
      in.lg   = pres_lg;
    end
    return in;
  endfunction
