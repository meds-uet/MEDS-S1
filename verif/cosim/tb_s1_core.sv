// =============================================================================
// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// Author(s)    : integration (Oct 2026)
// Modified By  :
//
// tb_s1_core   : integration testbench -- programs vs spike         [COMPLETE]
// Description  :
// Runs a program through the assembled core, IF to WB, and checks every
// retirement on RVFI against spike's commit log.  The program is chosen at
// build time: -DPROG_SVH='"prog_<name>.svh"' (default rv64i_full, every RV64I
// instruction; `sort` is the C sorting workload).
//
// Nothing here models the ISA.  gen.py builds prog_<name>.svh and its two
// $readmemh files from the toolchain -- the image with objcopy, the
// expectations from spike -- so a bug in this testbench cannot agree with a
// matching bug in the core.
//
// Per retirement it checks, against spike:
//   order, pc, instruction, privilege mode, trap, rd and the value written,
//   the next pc (a trap's is the handler), and the memory access -- address,
//   byte mask, and for a store the data.
// and, against a shadow register file built from spike's own writes:
//   rs1/rs2 -- the address is the instruction's field or 0, and the value is
//   the architectural one.  That checks the operand EX actually used, which a
//   result check alone cannot: forwarding the wrong value can still produce
//   the right answer.
//
// Memory is one byte array behind both I2 ports, as DRAM is.  With +stall the
// two ports drop `ready` and delay responses at random ($urandom, seeded by
// +verilator+seed+N), which is what exposes hazards that a one-cycle memory
// hides.  Both ports are protocol-checked every cycle: a presented request
// stays presented with a stable payload until accepted (R-C10), and the core
// never has a second request outstanding (INTERFACES.md 2, v1).
//
// Tied off, and asserted unused at the end:
//   md_*           no RV64M instruction is executed
// PMA and PMP answer permissively: the checkers are outside the core.  The CSR
// file is outside it too; tb_csr_model stands in for the few CSRs the
// program's trap handler uses, and never raises an interrupt.
//
// Run:  see verif/cosim/README.md
// =============================================================================

module tb_s1_core
  import s1_pkg::*;
;

  logic clk = 1'b0, rst_n = 1'b0;
  initial forever #5 clk = ~clk;

  // ---------------------------------------------------------------------------
  // Core
  // ---------------------------------------------------------------------------
  logic     imem_req_valid, imem_req_ready, imem_rsp_valid, imem_rsp_ready;
  mem_req_t imem_req;
  mem_rsp_t imem_rsp;
  logic     dmem_req_valid, dmem_req_ready, dmem_rsp_valid, dmem_rsp_ready;
  mem_req_t dmem_req;
  mem_rsp_t dmem_rsp;
  logic     fence_i, store_err;
  logic [XLEN-1:0] store_err_addr;
  logic [XLEN-1:0] chk_addr;
  logic [2:0]      chk_size;
  logic            chk_rd, chk_wr, chk_ex;
  priv_lvl_e       chk_priv;
  pma_t            pma;
  logic            pma_fault, pmp_allow;
  logic            md_start, md_flush, md_done;
  muldiv_op_e      md_op;
  logic [XLEN-1:0] md_a, md_b, md_result;
  rvfi_t           rvfi;
  // CSR file port
  logic [11:0]     csr_addr;
  logic            csr_re, csr_we, csr_illegal, mret, irq_valid, instret;
  logic [XLEN-1:0] csr_rdata, trap_vec, mepc;
  csr_upd_t        csr_commit;
  trap_req_t       trap_req;
  priv_lvl_e       priv, priv_data;
  logic [5:0]      irq_code;
  logic [7:0]      perf;

`ifndef PROG_SVH
`define PROG_SVH "prog_rv64i_full.svh"
`endif
  `include `PROG_SVH

  s1_core #(.RESET_PC(PROG_ENTRY)) dut (
    .clk_i(clk), .rst_ni(rst_n),
    .imem_req_valid_o(imem_req_valid), .imem_req_ready_i(imem_req_ready),
    .imem_req_o(imem_req), .imem_rsp_valid_i(imem_rsp_valid),
    .imem_rsp_ready_o(imem_rsp_ready), .imem_rsp_i(imem_rsp),
    .dmem_req_valid_o(dmem_req_valid), .dmem_req_ready_i(dmem_req_ready),
    .dmem_req_o(dmem_req), .dmem_rsp_valid_i(dmem_rsp_valid),
    .dmem_rsp_ready_o(dmem_rsp_ready), .dmem_rsp_i(dmem_rsp),
    .fence_i_o(fence_i),
    .store_err_o(store_err), .store_err_addr_o(store_err_addr),
    .chk_addr_o(chk_addr), .chk_size_o(chk_size), .chk_rd_o(chk_rd),
    .chk_wr_o(chk_wr), .chk_ex_o(chk_ex), .chk_priv_o(chk_priv),
    .pma_i(pma), .pma_fault_i(pma_fault), .pmp_allow_i(pmp_allow),
    .md_start_o(md_start), .md_op_o(md_op), .md_a_o(md_a), .md_b_o(md_b),
    .md_flush_o(md_flush), .md_done_i(md_done), .md_result_i(md_result),
    .csr_addr_o(csr_addr), .csr_re_o(csr_re), .csr_we_o(csr_we),
    .csr_rdata_i(csr_rdata), .csr_illegal_i(csr_illegal),
    .csr_commit_o(csr_commit), .trap_req_o(trap_req), .mret_o(mret),
    .trap_vec_i(trap_vec), .mepc_i(mepc), .priv_i(priv), .priv_data_i(priv_data),
    .irq_valid_i(irq_valid), .irq_code_i(irq_code), .instret_o(instret),
    .perf_br_taken_o(perf[0]), .perf_br_mispredict_o(perf[1]),
    .perf_load_retired_o(perf[2]), .perf_store_retired_o(perf[3]),
    .perf_sb_full_o(perf[4]), .perf_muldiv_stall_o(perf[5]),
    .perf_load_use_o(perf[6]), .perf_hazard_stall_o(perf[7]),
    .rvfi_o(rvfi)
  );

  // The CSR file is another project's; this is a minimal stand-in that covers
  // only what the program's trap handler uses (see tb_csr_model.sv).
  tb_csr_model u_csr (
    .clk_i(clk), .rst_ni(rst_n),
    .csr_addr_i(csr_addr), .csr_re_i(csr_re), .csr_we_i(csr_we),
    .csr_rdata_o(csr_rdata), .csr_illegal_o(csr_illegal),
    .csr_commit_i(csr_commit), .trap_req_i(trap_req), .mret_i(mret),
    .trap_vec_o(trap_vec), .mepc_o(mepc), .priv_o(priv), .priv_data_o(priv_data),
    .irq_valid_o(irq_valid), .irq_code_o(irq_code), .instret_i(instret)
  );

  // ---------------------------------------------------------------------------
  // Tie-offs
  // ---------------------------------------------------------------------------
  always_comb begin
    pma            = '0;              // DRAM: cacheable, idempotent, any alignment
    pma.cacheable  = 1'b1;
    pma.idempotent = 1'b1;
    pma.atomic_lrsc= 1'b1;
    pma.atomic_amo = 1'b1;
    pma_fault      = 1'b0;
    pmp_allow      = 1'b1;
    md_done        = 1'b0;
    md_result      = '0;
  end

  // ---------------------------------------------------------------------------
  // Checking helpers
  // ---------------------------------------------------------------------------
  int unsigned checks = 0, errors = 0;
  bit          verbose;               // +v: print every failure, not the first 30
  initial verbose = $test$plusargs("v") != 0;

  task automatic check(input string name, input logic [XLEN-1:0] got,
                       input logic [XLEN-1:0] want);
    checks++;
    if (got !== want) begin
      errors++;
      if (verbose || errors <= 30)
        $display("  FAIL @%0t %-22s got=0x%016h want=0x%016h", $time, name, got, want);
    end
  endtask

  // ---------------------------------------------------------------------------
  // Memory: one byte array behind both ports
  // ---------------------------------------------------------------------------
  localparam int unsigned BEAT_BYTES = XLEN / 8;

  byte unsigned mem [longint unsigned];

  task automatic mem_w32(input logic [XLEN-1:0] a, input logic [31:0] w);
    for (int unsigned i = 0; i < 4; i++) mem[a + i] = w[i*8 +: 8];
  endtask

  function automatic logic [XLEN-1:0] mem_beat(input logic [XLEN-1:0] a);
    logic [XLEN-1:0] base, d;
    base = {a[XLEN-1:3], 3'b000};
    d    = '0;
    for (int unsigned i = 0; i < BEAT_BYTES; i++)
      if (mem.exists(base + i) != 0) d[i*8 +: 8] = mem[base + i];
    return d;
  endfunction

  // +stall: random ready and response latency on both ports
  bit stall_en;
  initial stall_en = $test$plusargs("stall") != 0;

  function automatic int unsigned rsp_lat();
    return stall_en ? $urandom_range(0, 4) : 0;
  endfunction

  logic        i_rdy_q, d_rdy_q;
  int unsigned i_stall = 0, d_stall = 0;
  always_ff @(posedge clk) begin
    i_rdy_q <= !stall_en || ($urandom_range(0, 3) != 0);
    d_rdy_q <= !stall_en || ($urandom_range(0, 3) != 0);
    if (imem_req_valid && !imem_req_ready) i_stall++;
    if (dmem_req_valid && !dmem_req_ready) d_stall++;
  end
  assign imem_req_ready = i_rdy_q;
  assign dmem_req_ready = d_rdy_q;

  // ---- I-side --------------------------------------------------------------
  logic        i_pend;
  int unsigned i_cnt;
  mem_rsp_t    i_rsp_q;

  assign imem_rsp_valid = i_pend && (i_cnt == 0);
  assign imem_rsp       = i_rsp_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      i_pend  <= 1'b0;
      i_cnt   <= 0;
      i_rsp_q <= '0;
    end else begin
      if (imem_rsp_valid && imem_rsp_ready) i_pend <= 1'b0;
      else if (i_pend && i_cnt != 0)        i_cnt  <= i_cnt - 1;
      if (imem_req_valid && imem_req_ready) begin
        if (i_pend && !(imem_rsp_valid && imem_rsp_ready))
          check("imem: one outstanding", 1, 0);
        check("imem: never writes", XLEN'(imem_req.we), 0);
        i_pend        <= 1'b1;
        i_cnt         <= rsp_lat();
        i_rsp_q.rdata <= mem_beat(imem_req.addr);
        i_rsp_q.err   <= 1'b0;
        i_rsp_q.id    <= imem_req.id;
      end
    end
  end

  // ---- D-side --------------------------------------------------------------
  logic        d_pend;
  int unsigned d_cnt;
  mem_rsp_t    d_rsp_q;
  int unsigned n_ld = 0, n_st = 0;
  bit          tohost_seen = 0;

  assign dmem_rsp_valid = d_pend && (d_cnt == 0);
  assign dmem_rsp       = d_rsp_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      d_pend  <= 1'b0;
      d_cnt   <= 0;
      d_rsp_q <= '0;
    end else begin
      if (dmem_rsp_valid && dmem_rsp_ready) d_pend <= 1'b0;
      else if (d_pend && d_cnt != 0)        d_cnt  <= d_cnt - 1;
      if (dmem_req_valid && dmem_req_ready) begin
        logic [XLEN-1:0] base;
        if (d_pend && !(dmem_rsp_valid && dmem_rsp_ready))
          check("dmem: one outstanding", 1, 0);
        base = {dmem_req.addr[XLEN-1:3], 3'b000};
        if (dmem_req.we) begin
          for (int unsigned i = 0; i < BEAT_BYTES; i++)
            if (dmem_req.be[i]) mem[base + i] = dmem_req.wdata[i*8 +: 8];
          if (base == TOHOST) tohost_seen = 1;
          n_st++;
        end else begin
          n_ld++;
        end
        d_pend        <= 1'b1;
        d_cnt         <= rsp_lat();
        d_rsp_q.rdata <= mem_beat(dmem_req.addr);
        d_rsp_q.err   <= 1'b0;
        d_rsp_q.id    <= dmem_req.id;
      end
    end
  end

  // ---- I2 protocol: a presented request is held, unchanged, until accepted ---
  logic     i_held_q, d_held_q;
  mem_req_t i_req_q, d_req_q;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      i_held_q <= 1'b0;
      d_held_q <= 1'b0;
      i_req_q  <= '0;
      d_req_q  <= '0;
    end else begin
      if (i_held_q) begin
        check("imem: valid held (R-C10)",   XLEN'(imem_req_valid), 1);
        check("imem: payload held (R-C10)", XLEN'(imem_req == i_req_q), 1);
      end
      if (d_held_q) begin
        check("dmem: valid held (R-C10)",   XLEN'(dmem_req_valid), 1);
        check("dmem: payload held (R-C10)", XLEN'(dmem_req == d_req_q), 1);
      end
      i_held_q <= imem_req_valid && !imem_req_ready;
      d_held_q <= dmem_req_valid && !dmem_req_ready;
      i_req_q  <= imem_req;
      d_req_q  <= dmem_req;
    end
  end

  // ---------------------------------------------------------------------------
  // Expected retirement stream
  // ---------------------------------------------------------------------------
  logic [XLEN-1:0] e_pc    [N_EXP];
  logic [ILEN-1:0] e_insn  [N_EXP];
  logic [1:0]      e_mode  [N_EXP];
  logic            e_trap  [N_EXP];
  logic [4:0]      e_rd    [N_EXP];
  logic [XLEN-1:0] e_wdata [N_EXP];
  logic [XLEN-1:0] e_npc   [N_EXP];
  logic [1:0]      e_mkind [N_EXP];
  logic [XLEN-1:0] e_maddr [N_EXP];
  logic [7:0]      e_mmask [N_EXP];
  logic [XLEN-1:0] e_mdata [N_EXP];

  // One line of EXP_HEX, laid out as gen.py packs it (FIELDS, MSB first).
  typedef struct packed {
    logic [XLEN-1:0] pc;
    logic [ILEN-1:0] insn;
    logic [1:0]      mode;
    logic            trap;
    logic [4:0]      rd;
    logic [XLEN-1:0] wdata;
    logic [XLEN-1:0] npc;
    logic [1:0]      mkind;
    logic [XLEN-1:0] maddr;
    logic [7:0]      mmask;
    logic [XLEN-1:0] mdata;
  } exp_t;

  task automatic load_expected();
    logic [EXP_W-1:0] raw [N_EXP];
    exp_t             r;
    $readmemh(EXP_HEX, raw);
    for (int unsigned o = 0; o < N_EXP; o++) begin
      r = exp_t'(raw[o]);
      e_pc[o] = r.pc;  e_insn[o] = r.insn;  e_mode[o] = r.mode;  e_trap[o] = r.trap;
      e_rd[o] = r.rd;  e_wdata[o] = r.wdata;  e_npc[o] = r.npc;  e_mkind[o] = r.mkind;
      e_maddr[o] = r.maddr;  e_mmask[o] = r.mmask;  e_mdata[o] = r.mdata;
    end
  endtask

  task automatic load_program();
    logic [31:0] img [N_WORDS];
    $readmemh(IMG_HEX, img);
    for (int unsigned i = 0; i < N_WORDS; i++) mem_w32(PROG_BASE + XLEN'(4 * i), img[i]);
  endtask

  // ---------------------------------------------------------------------------
  // Check every retirement
  // ---------------------------------------------------------------------------
  int unsigned retired = 0, cyc = 0, spun = 0, n_trap = 0, n_umode = 0;
  logic [XLEN-1:0] shadow [32];       // architectural registers, from spike's writes

  initial for (int i = 0; i < 32; i++) shadow[i] = '0;

  always_ff @(posedge clk) if (rst_n) cyc <= cyc + 1;

  task automatic check_operand(input string name, input logic [4:0] addr,
                               input logic [XLEN-1:0] data, input logic [4:0] field);
    checks++;
    if (addr != 5'd0 && addr != field) begin
      errors++;
      if (verbose || errors <= 30)
        $display("  FAIL @%0t %s_addr=%0d is neither 0 nor the field %0d",
                 $time, name, addr, field);
    end
    check({name, "_rdata"}, data, (addr == 5'd0) ? '0 : shadow[addr]);
  endtask

  always_ff @(posedge clk) begin
    if (rst_n && rvfi.valid) begin
      if (retired >= N_EXP) begin
        // Past the program: every further retirement is the final self-branch.
        check("spin pc",             rvfi.pc_rdata, SPIN_PC);
        check("spin pc_wdata",       rvfi.pc_wdata, SPIN_PC);
        check("spin writes nothing", XLEN'(rvfi.rd_addr), 0);
        spun++;
      end else begin
        check("order",     rvfi.order,             XLEN'(retired));
        check("pc_rdata",  rvfi.pc_rdata,          e_pc[retired]);
        check("insn",      XLEN'(rvfi.insn),       XLEN'(e_insn[retired]));
        check("mode",      XLEN'(rvfi.mode),       XLEN'(e_mode[retired]));
        check("trap",      XLEN'(rvfi.trap),       XLEN'(e_trap[retired]));
        check("rd_addr",   XLEN'(rvfi.rd_addr),    XLEN'(e_rd[retired]));
        check("rd_wdata",  rvfi.rd_wdata,          e_wdata[retired]);
        check("pc_wdata",  rvfi.pc_wdata,          e_npc[retired]);
        check("ixl",       XLEN'(rvfi.ixl),        2);
        check_operand("rs1", rvfi.rs1_addr, rvfi.rs1_rdata, e_insn[retired][19:15]);
        check_operand("rs2", rvfi.rs2_addr, rvfi.rs2_rdata, e_insn[retired][24:20]);
        unique case (e_mkind[retired])
          2'd1: begin
            check("mem_addr (load)",  rvfi.mem.addr,         e_maddr[retired]);
            check("mem_rmask",        XLEN'(rvfi.mem.rmask), XLEN'(e_mmask[retired]));
            check("mem_wmask (load)", XLEN'(rvfi.mem.wmask), 0);
          end
          2'd2: begin
            check("mem_addr (store)", rvfi.mem.addr,         e_maddr[retired]);
            check("mem_wmask",        XLEN'(rvfi.mem.wmask), XLEN'(e_mmask[retired]));
            check("mem_wdata",        rvfi.mem.wdata,        e_mdata[retired]);
            check("mem_rmask (store)",XLEN'(rvfi.mem.rmask), 0);
          end
          default: begin
            check("no mem access",    XLEN'({rvfi.mem.rmask, rvfi.mem.wmask}), 0);
          end
        endcase
        if (e_rd[retired] != 5'd0) shadow[e_rd[retired]] = e_wdata[retired];
        if (e_trap[retired])          n_trap++;
        if (e_mode[retired] == 2'd0)  n_umode++;
      end
      retired++;
    end
  end

  // ---------------------------------------------------------------------------
  // Program and run
  // ---------------------------------------------------------------------------
  // Generous: the worst random-stall run takes about 4 cycles per retirement.
  localparam int unsigned WATCHDOG = 20 * N_EXP + 10000;

  initial begin
    load_program();
    load_expected();

    repeat (4) @(posedge clk);
    #1 rst_n = 1'b1;

    // A cycle counter rather than a forked watchdog: 5.020 rejects `repeat`
    // inside fork with %Error-LIFETIME.
    wait (retired >= N_EXP || cyc > WATCHDOG);
    repeat (40) @(posedge clk);         // let the spin retire a few times
    if (retired < N_EXP) begin
      $display("  FAIL watchdog: only %0d of %0d retired after %0d cycles",
               retired, N_EXP, cyc);
      errors++;
    end

    check("every instruction retired", XLEN'(retired >= N_EXP), 1);
    check("the spin was reached",      XLEN'(spun > 0), 1);
    check("tohost written",            XLEN'(tohost_seen), 1);
    // 1 is pass: the program's own self-check (crt0.s: (code << 1) | 1).
    check("tohost == 1 (self-check)",  mem_beat(TOHOST), 1);
    check("no store error",            XLEN'(store_err), 0);
    check("no multiply dispatched",    XLEN'(md_start), 0);
    check("no fence.i",                XLEN'(fence_i), 0);

    $display("%s, %s: %0d-word image, retired %0d (%0d traps, %0d in U-mode) in %0d cycles, then spun %0d times",
             `PROG_SVH, stall_en ? "random stalls" : "no stalls", N_WORDS, N_EXP, n_trap, n_umode,
             cyc, spun);
    $display("bus: %0d loads, %0d stores; ready withheld %0d (I) / %0d (D) cycles",
             n_ld, n_st, i_stall, d_stall);
    if (errors != 0) $fatal(1, "=== FAIL : %0d of %0d checks ===", errors, checks);
    $display("=== PASS : %0d checks ===", checks);
    $finish;
  end
endmodule
