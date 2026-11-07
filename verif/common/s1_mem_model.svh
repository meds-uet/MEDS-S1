// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// Author(s)    : Eman Nasar <fatehulnasareman@gmail.com>, GitHub EmanNasar001 (Oct,2026)
// Modified By  :
//
// s1_mem_model.svh : the environment tb_s1_mem checks s1_mem against.
//
// Included textually into the testbench module.  It holds the pieces that
// describe MEMORY and the bus rather than the stage: the address map and the
// two physical-memory checks, the program-order and physical memory models,
// the access-width helpers they need, and the check and coverage reporting.
//
// It lives here rather than in the testbench because a D$ or LSU testbench
// wants exactly this environment, and because R-C6 caps a file at 800 lines.
// =============================================================================

  // ---------------------------------------------------------------------------
  // Check helpers
  // ---------------------------------------------------------------------------
  task automatic check(input string name,
                       input logic [XLEN-1:0] got,
                       input logic [XLEN-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      if (errors < 25)
        $display("  FAIL %-22s got=0x%016h exp=0x%016h   [%s]", name, got, exp, ctx);
    end
  endtask

  task automatic check1(input string name, input logic got, input logic exp);
    checks++;
    if (got !== exp) begin
      errors++;
      if (errors < 25)
        $display("  FAIL %-22s got=%0d exp=%0d   [%s]", name, got, exp, ctx);
    end
  endtask

  // ---------------------------------------------------------------------------
  // Address map and the two physical-memory checks, answered combinationally
  // in the cycle they are asked -- SPEC 11.
  // ---------------------------------------------------------------------------
  function automatic pma_t pma_of(input int unsigned pg);
    pma_t p;
    p.cacheable     = 1'b1;
    p.idempotent    = 1'b1;
    p.strong_order  = 1'b0;
    p.atomic_lrsc   = 1'b1;
    p.atomic_amo    = 1'b1;
    p.align_natural = 1'b1;
    case (pg)
      1: p.align_natural = 1'b0;                     // misaligned allowed: straddles beats
      2: begin                                       // non-idempotent I/O
           p.cacheable = 1'b0; p.idempotent = 1'b0;
           p.atomic_lrsc = 1'b0; p.atomic_amo = 1'b0;
         end
      3: begin                                       // strongly ordered
           p.cacheable = 1'b0; p.strong_order = 1'b1;
           p.atomic_lrsc = 1'b0; p.atomic_amo = 1'b0;
         end
      4: begin                                       // no atomics, misaligned allowed
           p.align_natural = 1'b0;
           p.atomic_lrsc = 1'b0; p.atomic_amo = 1'b0;
         end
      9: p.align_natural = 1'b0;                     // read errors, and straddling
      default: ;                                     // plain RAM
    endcase
    return p;
  endfunction

  // Both pages whose READS come back with an error.
  function automatic logic page_rderr(input int unsigned pg);
    return (pg == PG_RDERR) || (pg == PG_RDERR_M);
  endfunction

  function automatic int unsigned page_of(input logic [XLEN-1:0] a);
    return int'(a[15:12]);
  endfunction

  function automatic int unsigned off_of(input logic [XLEN-1:0] a);
    return int'(a[11:0]);
  endfunction

  function automatic logic [XLEN-1:0] addr_of(input int unsigned pg, input int unsigned off);
    return BASE + (XLEN'(pg) << 12) + XLEN'(off);
  endfunction

  always_comb begin
    int unsigned pg;
    pg        = page_of(chk_addr);
    pma       = pma_of(pg);
    pma_fault = (pg == PG_FAULT);
    pmp_allow = !((pg == PG_NOWRITE) && chk_wr);
  end

  // ---------------------------------------------------------------------------
  // The two memories
  // ---------------------------------------------------------------------------
  logic [7:0] prog [NPAGE][PGSZ];
  logic [7:0] phys [NPAGE][PGSZ];

  function automatic logic [XLEN-1:0] size_mask(input int unsigned lg);
    if (lg >= OFF_W) return '1;
    return (XLEN'(1) << ((32'(1) << lg) * BYTE_W)) - XLEN'(1);
  endfunction

  function automatic logic [XLEN-1:0] extend(input logic [XLEN-1:0] raw,
                                             input int unsigned lg,
                                             input logic sext);
    case (lg)
      0: return {{(XLEN-8){sext & raw[7]}},   raw[7:0]};
      1: return {{(XLEN-16){sext & raw[15]}}, raw[15:0]};
      2: return {{(XLEN-32){sext & raw[31]}}, raw[31:0]};
      default: return raw;
    endcase
  endfunction

  // What the program has stored at this address, at the access width.
  function automatic logic [XLEN-1:0] prog_read(input int unsigned pg,
                                                input int unsigned off,
                                                input int unsigned lg);
    logic [XLEN-1:0] v;
    v = '0;
    for (int unsigned k = 0; k < (32'(1) << lg); k++) v[k*BYTE_W +: BYTE_W] = prog[pg][off + k];
    return v;
  endfunction

  task automatic prog_write(input int unsigned pg, input int unsigned off,
                            input int unsigned lg, input logic [XLEN-1:0] data);
    for (int unsigned k = 0; k < (32'(1) << lg); k++) prog[pg][off + k] = data[k*BYTE_W +: BYTE_W];
  endtask

  // ---------------------------------------------------------------------------
  // Commit-order memory.  prog[] stops describing the machine once a flush
  // discards uncommitted stores, so the flush phase checks this instead:
  // every store WB commits, applied in commit order.  Completed but
  // uncommitted stores wait in cq[]; a commit applies the oldest, a flush
  // drops the rest.  After a drain, phys[] must equal cmem[] -- which is what
  // says a flush kept every committed store and nothing else.
  // ---------------------------------------------------------------------------
  logic [7:0]      cmem [NPAGE][PGSZ];
  int unsigned     cq_pg [16], cq_off [16], cq_lg [16];
  logic [XLEN-1:0] cq_data [16];
  int unsigned     cq_n;

  task automatic cmem_write(input int unsigned pg, input int unsigned off,
                            input int unsigned lg, input logic [XLEN-1:0] data);
    if (pg == PG_WRERR) return;                      // the bus refuses these
    for (int unsigned k = 0; k < (32'(1) << lg); k++) cmem[pg][off + k] = data[k*BYTE_W +: BYTE_W];
  endtask

  task automatic cq_push(input int unsigned pg, input int unsigned off,
                         input int unsigned lg, input logic [XLEN-1:0] data);
    if (cq_n < 16) begin
      cq_pg[cq_n] = pg; cq_off[cq_n] = off; cq_lg[cq_n] = lg; cq_data[cq_n] = data;
      cq_n++;
    end
  endtask

  task automatic cq_commit();
    if (cq_n == 0) return;
    cmem_write(cq_pg[0], cq_off[0], cq_lg[0], cq_data[0]);
    for (int unsigned i = 0; i + 1 < 16; i++) begin
      cq_pg[i] = cq_pg[i+1]; cq_off[i] = cq_off[i+1]; cq_lg[i] = cq_lg[i+1]; cq_data[i] = cq_data[i+1];
    end
    cq_n--;
  endtask

  task automatic check_committed();
    for (int unsigned pg = 0; pg < NPAGE; pg++)
      for (int unsigned o = 0; o < PGSZ; o++) begin
        checks++;
        if (phys[pg][o] !== cmem[pg][o]) begin
          errors++;
          $display("  FAIL committed p%0d[%0d] phys=0x%h committed=0x%h   [%s]",
                   pg, o, phys[pg][o], cmem[pg][o], ctx);
        end
      end
  endtask

  // ---------------------------------------------------------------------------
  // Bus model.  One request outstanding, a random 1-4 cycle answer, random
  // backpressure on the request side.
  // ---------------------------------------------------------------------------
  logic            bus_busy;          // a response is owed
  int unsigned     bus_delay;
  logic [XLEN-1:0] bus_addr;
  logic            bus_we;
  logic            bus_err;

  logic            prev_req_valid;
  mem_req_t        prev_req;
  logic            prev_req_stalled;

  task automatic bus_apply_write(input mem_req_t r);
    int unsigned pg, off;
    pg  = page_of(r.addr);
    off = off_of(r.addr) & ~(PGSZ'(BEAT_BYTES - 1));
    if (pg == PG_WRERR) return;                      // the error case writes nothing
    for (int unsigned k = 0; k < BEAT_BYTES; k++)
      if (r.be[k]) phys[pg][off + k] = r.wdata[k*BYTE_W +: BYTE_W];
  endtask

  function automatic logic [XLEN-1:0] bus_read_beat(input logic [XLEN-1:0] a);
    logic [XLEN-1:0] v;
    int unsigned pg, off;
    pg  = page_of(a);
    off = off_of(a) & ~(PGSZ'(BEAT_BYTES - 1));
    v   = '0;
    for (int unsigned k = 0; k < BEAT_BYTES; k++) v[k*BYTE_W +: BYTE_W] = phys[pg][off + k];
    return v;
  endfunction

  task automatic cover_min(input string what, input int unsigned got, input int unsigned least);
    checks++;
    if (got < least) begin
      errors++;
      $display("  FAIL coverage: %s reached %0d times, needed %0d", what, got, least);
    end
  endtask

