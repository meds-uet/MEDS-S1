// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// Author(s)    : Eman Nasar <fatehulnasareman@gmail.com>, GitHub EmanNasar001 (Oct,2026)
// Modified By  :
//
// s1_mem_golden.svh : the expectation model for tb_s1_mem.
//
// Included textually into the testbench module, after the expectation state it
// writes is declared.  Two tasks and a comparison:
//
//   install_expectation()  at the cycle an access is ACCEPTED, works out what
//                          its completion must look like and applies its
//                          program-order effect on memory.  It is written from
//                          the access rules -- faults, widths, extension, the
//                          AMO operation, the reservation -- not from the RTL.
//   check_completion()     compares every field of the completing MEM/WB entry
//                          against that expectation.
//   check_drained()        the two memory models must agree byte for byte
//                          whenever the store buffer reports itself empty.
// =============================================================================

  // ---------------------------------------------------------------------------
  // Compute the expectation at ACCEPT time.  It has to be here rather than at
  // presentation: an instruction can wait at EX/MEM for many cycles, and an LR
  // completing in that window changes what an SC behind it must do.
  // ---------------------------------------------------------------------------
  task automatic install_expectation();
    int unsigned pg, off, lg;
    logic        is_lr, is_sc, amox, rd_acc, wr_acc, sext;
    logic        in_mem, misalign, atomic_bad, fault, sc_skip;
    logic [XLEN-1:0] raw, old_val, opa, opb, nv;
    pma_t        p;

    pg  = page_of(mem_in.mem_addr);
    off = off_of(mem_in.mem_addr);
    lg  = int'(mem_in.mem_size);
    p   = pma_of(pg);

    is_lr  = (mem_in.amo_op == AMO_LR);
    is_sc  = (mem_in.amo_op == AMO_SC);
    amox   = is_amox_op(mem_in.amo_op);
    rd_acc = mem_in.is_load || is_lr || amox;
    wr_acc = mem_in.is_store || is_sc || amox;
    sext   = mem_in.is_load ? mem_in.mem_signed : 1'b1;

    sc_skip = is_sc && !(res_valid && res_addr == mem_in.mem_addr && res_lg == lg);

    in_mem     = !mem_in.exc && (rd_acc || wr_acc) && !sc_skip;
    misalign   = p.align_natural && ((mem_in.mem_addr & ((XLEN'(1) << lg) - XLEN'(1))) != '0);
    atomic_bad = ((is_lr || is_sc) && !p.atomic_lrsc) || (amox && !p.atomic_amo);
    fault      = in_mem && ((pg == PG_FAULT) || misalign || atomic_bad
                            || ((pg == PG_NOWRITE) && wr_acc));

    e_in       = mem_in;
    e_lg       = lg;
    e_pg       = pg;
    e_off      = off;
    e_amox     = amox;
    e_lr       = is_lr;
    e_sc       = is_sc;
    e_is_read  = in_mem && !fault && rd_acc;
    e_sb_alloc = in_mem && !fault && wr_acc;

    e_exc     = mem_in.exc || fault;
    e_exccode = mem_in.exc ? mem_in.exccode
                           : ((mem_in.is_load || is_lr) ? EXC_LOAD_ACCESS_FAULT
                                                        : EXC_STORE_ACCESS_FAULT);
    e_exctval = mem_in.exc ? mem_in.exctval : mem_in.mem_addr;

    e_rmask = (in_mem && !fault && rd_acc) ? 8'((16'd1 << (32'(1) << lg)) - 16'd1) : 8'd0;
    e_wmask = (in_mem && !fault && wr_acc) ? 8'((16'd1 << (32'(1) << lg)) - 16'd1) : 8'd0;

    // A read whose bytes must come off the bus from the error page is going to
    // come back with err.  Reads to that page are only generated when the
    // store buffer is empty, so nothing can be forwarded and the bus is always
    // consulted -- that keeps this prediction exact rather than approximate.
    e_bus_err = e_is_read && page_rderr(pg);

    raw     = e_is_read ? prog_read(pg, off, lg) : '0;
    old_val = extend(raw, lg, sext);

    e_rdata = e_is_read ? raw : '0;
    e_wdata = mem_in.mem_wdata & size_mask(lg);

    // AMO operands are taken at the access width and sign-extended for the
    // signed MIN/MAX forms (RV64A), which is the trap this recomputes rather
    // than copies.
    opa = old_val;
    opb = (lg != OFF_W) ? extend(mem_in.mem_wdata, lg, 1'b1) : mem_in.mem_wdata;
    case (mem_in.amo_op)
      AMO_ADD:  nv = opa + opb;
      AMO_XOR:  nv = opa ^ opb;
      AMO_AND:  nv = opa & opb;
      AMO_OR:   nv = opa | opb;
      AMO_MIN:  nv = ($signed(opa) < $signed(opb)) ? opa : opb;
      AMO_MAX:  nv = ($signed(opa) > $signed(opb)) ? opa : opb;
      AMO_MINU: nv = (opa < opb) ? opa : opb;
      AMO_MAXU: nv = (opa > opb) ? opa : opb;
      default:  nv = opb;                            // SWAP
    endcase
    e_amo_new = nv & size_mask(lg);

    if (e_is_read)      e_result = old_val;
    else if (is_sc)     e_result = XLEN'(sc_skip || fault);
    else                e_result = mem_in.result;

    // ---- program-order memory effects ---------------------------------------
    // A store or a successful SC takes effect now.  An AMO's write is deferred
    // to its completion, because until then it has not read, and prog[] must
    // stay equal to phys[] whenever the buffer reports itself empty.
    if (e_sb_alloc && !amox)
      prog_write(pg, off, lg, mem_in.mem_wdata & size_mask(lg));

    // The reservation is cleared by an accepted SC even when it fails, and a
    // clear in the same cycle as an LR's completion wins.
    if (is_sc && !mem_in.exc) res_valid = 1'b0;

    if (mem_in.is_load)  n_load++;
    if (mem_in.is_store) n_store++;
    if (amox)            n_amo++;
    if (is_lr)           n_lr++;
    if (is_sc && !sc_skip && !fault) n_sc_ok++;
    if (is_sc && sc_skip)            n_sc_fail++;
    if (fault)                       n_fault++;
    if (in_mem && !fault && ((off % BEAT_BYTES) + (32'(1) << lg) > BEAT_BYTES))
      n_straddle++;
    ctx = $sformatf("%s | pg%0d off=%0d lg=%0d %s%s%s%s addr=0x%h",
                    phase, pg, off, lg,
                    mem_in.is_load ? "LD " : "", mem_in.is_store ? "ST " : "",
                    mem_in.amo_op.name(), mem_in.exc ? " EXCIN" : "",
                    mem_in.mem_addr);

    // P1 (INTERFACES.md 9): a non-idempotent read is never speculative, so it
    // may only be accepted when it is the oldest instruction in the machine:
    // MEM/WB must have been empty -- not completing, not pending.
    if (scoreboard && e_is_read && !p.idempotent)
      check1("P1: non-idempotent read not speculative", wb_valid || wb_pend, 1'b0);

    if (e_is_read && !sb_empty && last_st_valid
        && (mem_in.mem_addr >> OFF_W) == last_st_beat)
      n_fwd++;
    if (e_sb_alloc) begin
      last_st_beat  = mem_in.mem_addr >> OFF_W;
      last_st_valid = 1'b1;
    end


    e_live = 1'b1;
  endtask

  // ---------------------------------------------------------------------------
  // Check a completing instruction
  // ---------------------------------------------------------------------------
  task automatic check_completion();
    logic exp_exc;
    logic [5:0] exp_code;

    // Pass-through fields:
    check ("wb.rd",         wb_out.rd,        e_in.rd);
    check1("wb.rd_we",      wb_out.rd_we,     e_in.rd_we);
    check ("wb.next_pc",    wb_out.next_pc,   e_in.next_pc);
    check ("wb.pc",         wb_out.pc,        e_in.pc);
    check ("wb.instr",      wb_out.instr,     e_in.instr);
    check ("wb.sys_op",     wb_out.sys_op,    e_in.sys_op);
    check ("wb.rs1_addr",   wb_out.rs1_addr,  e_in.rs1_addr);
    check ("wb.rs2_addr",   wb_out.rs2_addr,  e_in.rs2_addr);
    check ("wb.rs1_rdata",  wb_out.rs1_rdata, e_in.rs1_rdata);
    check ("wb.rs2_rdata",  wb_out.rs2_rdata, e_in.rs2_rdata);
    check1("wb.csr_we",     wb_out.csr_we,    e_in.csr_we);
    check ("wb.csr_addr",   wb_out.csr_addr,  e_in.csr_addr);
    check ("wb.csr_wdata",  wb_out.csr_wdata, e_in.csr_wdata);
    check ("wb.mem_addr",   wb_out.mem_addr,  e_in.mem_addr);

    if (e_bus_err) begin
      // A read that errored on the bus becomes an access fault at completion,
      // and an AMO reports a STORE fault because its write will not happen.
      exp_exc  = 1'b1;
      exp_code = e_amox ? EXC_STORE_ACCESS_FAULT : EXC_LOAD_ACCESS_FAULT;
      check1("err: exc",        wb_out.exc,       exp_exc);
      check ("err: exccode",    wb_out.exccode,   exp_code);
      check ("err: exctval",    wb_out.exctval,   e_in.mem_addr);
      check1("err: no sb entry", wb_out.sb_alloc, 1'b0);
      check ("err: rmask clear", wb_out.mem_rmask, 8'd0);
      check ("err: wmask clear", wb_out.mem_wmask, 8'd0);
    end else begin
      check1("wb.exc",        wb_out.exc,       e_exc);
      check ("wb.exccode",    wb_out.exccode,   e_exccode);
      check ("wb.exctval",    wb_out.exctval,   e_exctval);
      check1("wb.sb_alloc",   wb_out.sb_alloc,  e_sb_alloc);
      check ("wb.mem_rmask",  wb_out.mem_rmask, e_rmask);
      check ("wb.mem_wmask",  wb_out.mem_wmask, e_wmask);
      check ("wb.result",     wb_out.result,    e_result);
      check ("wb.mem_rdata",  wb_out.mem_rdata, e_rdata);
      check ("wb.mem_wdata",  wb_out.mem_wdata,
             (e_is_read && e_amox) ? e_amo_new : e_wdata);
    end

    // A faulting access must leave no store-buffer entry behind, whatever
    // else it reports: an entry nobody will ever commit wedges the buffer.
    if (wb_out.exc) check1("fault: no sb entry", wb_out.sb_alloc, 1'b0);
  endtask

  // ---------------------------------------------------------------------------
  // prog[] and phys[] must agree the instant the buffer says it is empty
  // ---------------------------------------------------------------------------
  task automatic check_drained();
    for (int unsigned pg = 0; pg < NPAGE; pg++)
      for (int unsigned o = 0; o < PGSZ; o++) begin
        // The write-error page is the one place the two are MEANT to diverge:
        // the bus refused a write that the program had already performed, and
        // store_err_o reports that imprecisely, after the fact.
        if (pg == PG_WRERR) continue;
        checks++;
        if (phys[pg][o] !== prog[pg][o]) begin
          errors++;
          if (errors < 25)
            $display("  FAIL drained p%0d[%0d] phys=0x%02h prog=0x%02h   [%s]",
                     pg, o, phys[pg][o], prog[pg][o], ctx);
        end
      end
  endtask
