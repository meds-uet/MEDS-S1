// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// tb_s1_trap_unit : unit testbench for s1_trap_unit                     [WIP]
//
// The trap unit runs against s1_csr_file, so traps, xRETs and software CSR
// writes all go through the storage the core will use.  A reference model
// keeps the architectural state (mode, mstatus fields, mepc, mcause, mtval,
// mtvec) from the privileged-spec rules.  Every cycle the scoreboard checks the
// redirect before the edge and the CSR state after it.  Directed cases cover
// the PR #19 review items; a random phase mixes them.  M and U only.
//
// Run:  make test-unit TB=tb_s1_trap_unit
// =============================================================================

module tb_s1_trap_unit
  import s1_pkg::*;
  import s1_csr_pkg::*;
;

  // mstatus field positions (privileged spec).
  localparam int unsigned F_MIE  = 3;
  localparam int unsigned F_MPIE = 7;
  localparam int unsigned F_MPP  = 11;
  localparam int unsigned F_MPRV = 17;

  localparam logic [1:0] MODE_DIRECT   = 2'd0;
  localparam logic [1:0] MODE_VECTORED = 2'd1;

  localparam logic [5:0] EXCEPTIONS [14] = '{
    EXC_INSTR_ADDR_MISALIGNED, EXC_INSTR_ACCESS_FAULT,  EXC_ILLEGAL_INSTR,
    EXC_BREAKPOINT,            EXC_LOAD_ADDR_MISALIGNED, EXC_LOAD_ACCESS_FAULT,
    EXC_STORE_ADDR_MISALIGNED, EXC_STORE_ACCESS_FAULT,  EXC_ECALL_U,
    EXC_ECALL_S,               EXC_ECALL_M,             EXC_INSTR_PAGE_FAULT,
    EXC_LOAD_PAGE_FAULT,       EXC_STORE_PAGE_FAULT
  };

  // SSI, MSI, STI, MTI, SEI, MEI.
  localparam logic [5:0] INTERRUPTS [6] = '{6'd1, 6'd3, 6'd5, 6'd7, 6'd9, 6'd11};

  logic             clk;
  logic             rst_n;

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  // Requests for the coming edge; cycle() clears them.
  logic             trap_valid;
  logic             trap_irq;
  logic [5:0]       trap_cause;
  logic [XLEN-1:0]  trap_tval;
  logic [XLEN-1:0]  trap_pc;
  logic             mret_valid;
  logic             sret_valid;
  logic             csr_we;
  logic [11:0]      csr_addr;
  logic [XLEN-1:0]  csr_wdata;

  logic             hw_we    [4];
  logic [11:0]      hw_addr  [4];
  logic [XLEN-1:0]  hw_wdata [4];
  logic [XLEN-1:0]  tap_mstatus, tap_medeleg, tap_mideleg, tap_mepc, tap_mtvec;
  logic [XLEN-1:0]  tap_sepc, tap_stvec, tap_dcsr, tap_dpc;
  logic             redirect_valid;
  logic [XLEN-1:0]  redirect_pc;
  priv_lvl_e        priv;
  logic [XLEN-1:0]  csr_rdata;
  logic             csr_illegal;
  logic [11:0]      ext_addr;
  logic [XLEN-1:0]  ext_wdata;
  logic             ext_we;

  s1_trap_unit #(
    .U_MODE_PRESENT (1'b1),
    .S_MODE_PRESENT (1'b0)
  ) dut (
    .clk_i               (clk),
    .rst_ni              (rst_n),
    .trap_valid_i        (trap_valid),
    .trap_is_interrupt_i (trap_irq),
    .trap_cause_i        (trap_cause),
    .trap_tval_i         (trap_tval),
    .trap_pc_i           (trap_pc),
    .mret_valid_i        (mret_valid),
    .sret_valid_i        (sret_valid),
    .mstatus_rdata_i     (tap_mstatus),
    .medeleg_rdata_i     (tap_medeleg),
    .mideleg_rdata_i     (tap_mideleg),
    .mepc_rdata_i        (tap_mepc),
    .mtvec_rdata_i       (tap_mtvec),
    .sepc_rdata_i        (tap_sepc),
    .stvec_rdata_i       (tap_stvec),
    .hw_we_o             (hw_we),
    .hw_addr_o           (hw_addr),
    .hw_wdata_o          (hw_wdata),
    .redirect_valid_o    (redirect_valid),
    .redirect_pc_o       (redirect_pc),
    .priv_mode_o         (priv)
  );

  s1_csr_file #(
    .U_MODE_PRESENT (1'b1),
    .S_MODE_PRESENT (1'b0)
  ) u_csr (
    .clk_i           (clk),
    .rst_ni          (rst_n),
    .csr_addr_i      (csr_addr),
    .csr_wdata_i     (csr_wdata),
    .csr_we_i        (csr_we),
    .priv_i          (priv),
    .hw_we_i         (hw_we),
    .hw_addr_i       (hw_addr),
    .hw_wdata_i      (hw_wdata),
    .csr_rdata_o     (csr_rdata),
    .csr_illegal_o   (csr_illegal),
    .trap_mstatus_o  (tap_mstatus),
    .trap_medeleg_o  (tap_medeleg),
    .trap_mideleg_o  (tap_mideleg),
    .trap_mepc_o     (tap_mepc),
    .trap_mtvec_o    (tap_mtvec),
    .trap_sepc_o     (tap_sepc),
    .trap_stvec_o    (tap_stvec),
    .trap_dcsr_o     (tap_dcsr),
    .trap_dpc_o      (tap_dpc),
    .ext_csr_addr_o  (ext_addr),
    .ext_csr_wdata_o (ext_wdata),
    .ext_csr_we_o    (ext_we),
    .ext_csr_rdata_i ('0)
  );

  // ---------------------------------------------------------------------------
  // Reference model: architectural state, one variable per field.
  // ---------------------------------------------------------------------------
  priv_lvl_e        ref_priv;
  logic             ref_mie;
  logic             ref_mpie;
  priv_lvl_e        ref_mpp;
  logic             ref_mprv;
  logic [XLEN-1:0]  ref_mepc;
  logic [XLEN-1:0]  ref_mcause;
  logic [XLEN-1:0]  ref_mtval;
  logic [XLEN-1:0]  ref_mtvec;

  logic             last_redirect_valid;
  logic [XLEN-1:0]  last_redirect_pc;
  logic [XLEN-1:0]  cur_mcause;
  logic [XLEN-1:0]  cur_mtval;

  int unsigned      checks = 0;
  int unsigned      errors = 0;
  int unsigned      n_trap_from_u, n_mret_from_u, n_trap_and_write, n_illegal_write;

  function automatic logic [XLEN-1:0] rand_word();
    logic [XLEN-1:0] w;
    for (int unsigned i = 0; i < XLEN; i += 32) w[i +: 32] = $urandom;
    return w;
  endfunction

  function automatic logic [XLEN-1:0] ref_mstatus();
    return (XLEN'(ref_mie) << F_MIE) | (XLEN'(ref_mpie) << F_MPIE)
         | (XLEN'(ref_mpp) << F_MPP) | (XLEN'(ref_mprv) << F_MPRV);
  endfunction

  function automatic logic [XLEN-1:0] mstatus_value(input logic mie, input logic mpie,
                                                    input priv_lvl_e mpp, input logic mprv);
    return (XLEN'(mie) << F_MIE) | (XLEN'(mpie) << F_MPIE)
         | (XLEN'(mpp) << F_MPP) | (XLEN'(mprv) << F_MPRV);
  endfunction

  // Interrupt flag in the top bit, code in the bottom.
  function automatic logic [XLEN-1:0] ref_cause(input logic irq, input logic [5:0] cause);
    return (irq ? (XLEN'(1) << (XLEN - 1)) : XLEN'(0)) + XLEN'(cause);
  endfunction

  // BASE is mtvec without its two mode bits; Vectored adds 4 bytes per cause,
  // for interrupts only.
  function automatic logic [XLEN-1:0] ref_target(input logic irq, input logic [5:0] cause);
    logic [XLEN-1:0] base;
    base = ref_mtvec - XLEN'(ref_mtvec[1:0]);
    if (irq && ref_mtvec[1:0] == MODE_VECTORED) return base + XLEN'(4) * XLEN'(cause);
    return base;
  endfunction

  task automatic check(input string name, input logic cond);
    checks++;
    if (!cond) begin
      errors++;
      if (errors <= 20) $display("  FAIL %-50s at %0t", name, $time);
    end
  endtask

  // ---------------------------------------------------------------------------
  // One clock cycle.  Requests are set at a falling edge; the redirect is
  // checked before the rising edge and the state at the next falling edge.
  // ---------------------------------------------------------------------------
  task automatic cycle();
    logic             exp_redirect;
    logic [XLEN-1:0]  exp_pc;
    priv_lvl_e        n_priv;
    logic             n_mie, n_mpie, n_mprv;
    priv_lvl_e        n_mpp;
    logic [XLEN-1:0]  n_mepc, n_mcause, n_mtval, n_mtvec;

    #1;
    exp_redirect = trap_valid || (mret_valid && ref_priv == PRIV_M);
    exp_pc       = trap_valid ? ref_target(trap_irq, trap_cause) : ref_mepc;
    check("redirect valid", redirect_valid == exp_redirect);
    if (exp_redirect) check("redirect pc", redirect_pc == exp_pc);
    if (trap_valid) check("trap target has no mode bits", redirect_pc[1:0] == 2'b00);
    if (!exp_redirect) check("no CSR write without an action",
                             !(hw_we[0] || hw_we[1] || hw_we[2] || hw_we[3]));
    last_redirect_valid = redirect_valid;
    last_redirect_pc    = redirect_pc;

    // The software write lands first; the trap unit's write replaces it for
    // every CSR the trap unit writes.  Both read the state before the edge.
    n_priv   = ref_priv;
    n_mie    = ref_mie;
    n_mpie   = ref_mpie;
    n_mpp    = ref_mpp;
    n_mprv   = ref_mprv;
    n_mepc   = ref_mepc;
    n_mcause = ref_mcause;
    n_mtval  = ref_mtval;
    n_mtvec  = ref_mtvec;

    if (csr_we && ref_priv != PRIV_M) n_illegal_write++;
    if (csr_we && ref_priv == PRIV_M) begin
      if (csr_addr == CSR_MEPC)   n_mepc   = csr_wdata & ~XLEN'(1);
      if (csr_addr == CSR_MCAUSE) n_mcause = csr_wdata;
      if (csr_addr == CSR_MTVAL)  n_mtval  = csr_wdata;
      if (csr_addr == CSR_MTVEC)  n_mtvec  = csr_wdata;
      if (csr_addr == CSR_MSTATUS) begin
        n_mie  = csr_wdata[F_MIE];
        n_mpie = csr_wdata[F_MPIE];
        n_mpp  = priv_lvl_e'(csr_wdata[F_MPP +: 2]);
        n_mprv = csr_wdata[F_MPRV];
      end
    end

    if (trap_valid) begin
      if (ref_priv == PRIV_U) n_trap_from_u++;
      if (csr_we) n_trap_and_write++;
      n_mepc   = trap_pc;
      n_mcause = ref_cause(trap_irq, trap_cause);
      n_mtval  = trap_tval;
      n_mie    = 1'b0;
      n_mpie   = ref_mie;
      n_mpp    = ref_priv;
      n_mprv   = ref_mprv;
      n_priv   = PRIV_M;
    end else if (mret_valid && ref_priv == PRIV_M) begin
      n_mie    = ref_mpie;
      n_mpie   = 1'b1;
      n_mpp    = PRIV_U;
      n_mprv   = (ref_mpp == PRIV_M) ? ref_mprv : 1'b0;
      n_priv   = ref_mpp;
    end else if (mret_valid) begin
      n_mret_from_u++;
    end

    @(posedge clk);
    @(negedge clk);

    ref_priv   = n_priv;
    ref_mie    = n_mie;
    ref_mpie   = n_mpie;
    ref_mpp    = n_mpp;
    ref_mprv   = n_mprv;
    ref_mepc   = n_mepc;
    ref_mcause = n_mcause;
    ref_mtval  = n_mtval;
    ref_mtvec  = n_mtvec;

    cur_mcause = stored(CSR_MCAUSE);
    cur_mtval  = stored(CSR_MTVAL);

    check("privilege", priv == ref_priv);
    check("mstatus",   tap_mstatus == ref_mstatus());
    check("mepc",      tap_mepc == ref_mepc);
    check("mcause",    cur_mcause == ref_mcause);
    check("mtval",     cur_mtval == ref_mtval);
    check("mtvec",     tap_mtvec == ref_mtvec);

    trap_valid = 1'b0;
    mret_valid = 1'b0;
    sret_valid = 1'b0;
    csr_we     = 1'b0;
  endtask

  // mcause and mtval have no trap tap; read them from storage by address.
  function automatic logic [XLEN-1:0] stored(input logic [11:0] addr);
    for (int unsigned i = 0; i < NUM_CSRS; i++) begin
      if (CSR_TABLE[i].addr == addr) return u_csr.storage[i];
    end
    return '0;
  endfunction

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------
  task automatic sw_write(input logic [11:0] addr, input logic [XLEN-1:0] data);
    csr_we    = 1'b1;
    csr_addr  = addr;
    csr_wdata = data;
    cycle();
  endtask

  task automatic set_trap(input logic irq, input logic [5:0] cause);
    trap_valid = 1'b1;
    trap_irq   = irq;
    trap_cause = cause;
    trap_pc    = rand_word() & ~XLEN'(1);
    trap_tval  = rand_word();
  endtask

  task automatic take_trap(input logic irq, input logic [5:0] cause);
    set_trap(irq, cause);
    cycle();
  endtask

  task automatic do_mret();
    mret_valid = 1'b1;
    cycle();
  endtask

  task automatic enter_m();
    if (ref_priv != PRIV_M) take_trap(1'b0, EXC_ECALL_U);
  endtask

  task automatic enter_u();
    enter_m();
    sw_write(CSR_MSTATUS, mstatus_value(ref_mie, ref_mpie, PRIV_U, ref_mprv));
    sw_write(CSR_MEPC, rand_word());
    do_mret();
  endtask

  task automatic set_mtvec(input logic [1:0] mode);
    enter_m();
    sw_write(CSR_MTVEC, (rand_word() & ~XLEN'(3)) | XLEN'(mode));
  endtask

  task automatic random_write();
    int unsigned r;
    logic [31:0] rnd;
    r   = $urandom_range(4, 0);
    rnd = $urandom;
    csr_we = 1'b1;
    if (r == 0) begin
      csr_addr  = CSR_MEPC;
      csr_wdata = rand_word();
    end else if (r == 1) begin
      csr_addr  = CSR_MCAUSE;
      csr_wdata = rand_word();
    end else if (r == 2) begin
      csr_addr  = CSR_MTVAL;
      csr_wdata = rand_word();
    end else if (r == 3) begin
      csr_addr  = CSR_MTVEC;
      csr_wdata = (rand_word() & ~XLEN'(3)) | XLEN'(rnd[0]);
    end else begin
      csr_addr  = CSR_MSTATUS;
      csr_wdata = mstatus_value(rnd[0], rnd[1], rnd[2] ? PRIV_M : PRIV_U, rnd[3]);
    end
  endtask

  task automatic random_trap();
    int unsigned k;
    k = $urandom_range(2, 0);
    if (k == 0) begin
      k = $urandom_range(5, 0);
      set_trap(1'b1, INTERRUPTS[k]);
    end else begin
      k = $urandom_range(13, 0);
      set_trap(1'b0, EXCEPTIONS[k]);
    end
  endtask

  // ---------------------------------------------------------------------------
  // Stimulus
  // ---------------------------------------------------------------------------
  logic [1:0]       modes [2];
  priv_lvl_e        from_mode;
  priv_lvl_e        pre_priv;
  logic             pre_mie;
  logic             pre_mprv;
  logic [XLEN-1:0]  snap_mstatus, snap_mepc, saved_mtvec;
  logic [XLEN-1:0]  sw_value;
  int unsigned      r;

  initial begin
    $display("=== tb_s1_trap_unit : XLEN=%0d ===", XLEN);
    modes = '{MODE_DIRECT, MODE_VECTORED};

    trap_valid = 1'b0;
    trap_irq   = 1'b0;
    trap_cause = '0;
    trap_tval  = '0;
    trap_pc    = '0;
    mret_valid = 1'b0;
    sret_valid = 1'b0;
    csr_we     = 1'b0;
    csr_addr   = CSR_MSTATUS;
    csr_wdata  = '0;

    ref_priv   = PRIV_M;
    ref_mie    = 1'b0;
    ref_mpie   = 1'b0;
    ref_mpp    = PRIV_U;
    ref_mprv   = 1'b0;
    ref_mepc   = '0;
    ref_mcause = '0;
    ref_mtval  = '0;
    ref_mtvec  = '0;

    n_trap_from_u    = 0;
    n_mret_from_u    = 0;
    n_trap_and_write = 0;
    n_illegal_write  = 0;

    rst_n = 1'b0;
    repeat (2) @(negedge clk);
    rst_n = 1'b1;
    cycle();
    check("reset enters M-mode", priv == PRIV_M);

    // --- mret with no preceding trap: the boot sequence -----------------------
    sw_write(CSR_MSTATUS, mstatus_value(1'b0, 1'b1, PRIV_U, 1'b1));
    sw_write(CSR_MEPC, rand_word());
    snap_mepc = ref_mepc;
    do_mret();
    check("boot mret redirects to mepc", last_redirect_valid && last_redirect_pc == snap_mepc);
    check("boot mret enters U-mode", priv == PRIV_U);
    check("boot mret sets MPP to U", tap_mstatus[F_MPP +: 2] == PRIV_U);
    check("boot mret clears MPRV", !tap_mstatus[F_MPRV]);
    check("boot mret sets MIE from MPIE", tap_mstatus[F_MIE]);
    check("boot mret sets MPIE", tap_mstatus[F_MPIE]);

    // --- mret and sret outside M change nothing --------------------------------
    snap_mstatus = tap_mstatus;
    snap_mepc    = tap_mepc;
    do_mret();
    check("mret in U: no redirect", !last_redirect_valid);
    check("mret in U: stays in U", priv == PRIV_U);
    check("mret in U: mstatus unchanged", tap_mstatus == snap_mstatus);
    check("mret in U: mepc unchanged", tap_mepc == snap_mepc);
    sret_valid = 1'b1;
    cycle();
    check("sret without S-mode: no redirect", !last_redirect_valid);
    check("sret without S-mode: mstatus unchanged", tap_mstatus == snap_mstatus);

    // --- mret to M keeps MPRV ---------------------------------------------------
    enter_m();
    sw_write(CSR_MSTATUS, mstatus_value(1'b0, 1'b0, PRIV_M, 1'b1));
    do_mret();
    check("mret to M stays in M", priv == PRIV_M);
    check("mret to M keeps MPRV", tap_mstatus[F_MPRV]);
    check("mret to M sets MPP to U", tap_mstatus[F_MPP +: 2] == PRIV_U);

    // --- every exception, from U and M, Direct and Vectored ---------------------
    foreach (EXCEPTIONS[e]) begin
      foreach (modes[m]) begin
        for (int unsigned f = 0; f < 2; f++) begin
          set_mtvec(modes[m]);
          if (f == 0) enter_u();
          pre_priv = ref_priv;
          take_trap(1'b0, EXCEPTIONS[e]);
          check($sformatf("exception %0d: mcause, no interrupt bit", EXCEPTIONS[e]),
                cur_mcause == XLEN'(EXCEPTIONS[e]));
          check($sformatf("exception %0d: mepc", EXCEPTIONS[e]), tap_mepc == trap_pc);
          check($sformatf("exception %0d: target is BASE", EXCEPTIONS[e]),
                last_redirect_pc == (tap_mtvec & ~XLEN'(3)));
          check($sformatf("exception %0d: MPP is the previous mode", EXCEPTIONS[e]),
                tap_mstatus[F_MPP +: 2] == pre_priv);
          check($sformatf("exception %0d: enters M", EXCEPTIONS[e]), priv == PRIV_M);
        end
      end
    end

    // --- every interrupt, Direct and Vectored -----------------------------------
    foreach (INTERRUPTS[i]) begin
      foreach (modes[m]) begin
        for (int unsigned f = 0; f < 2; f++) begin
          set_mtvec(modes[m]);
          if (f == 0) enter_u();
          take_trap(1'b1, INTERRUPTS[i]);
          check($sformatf("interrupt %0d: mcause interrupt bit", INTERRUPTS[i]),
                cur_mcause[XLEN-1]);
          check($sformatf("interrupt %0d: mcause code", INTERRUPTS[i]),
                cur_mcause[XLEN-2:0] == (XLEN-1)'(INTERRUPTS[i]));
          if (modes[m] == MODE_VECTORED) begin
            check($sformatf("interrupt %0d: vectored target", INTERRUPTS[i]),
                  last_redirect_pc == (tap_mtvec & ~XLEN'(3)) + XLEN'(4) * XLEN'(INTERRUPTS[i]));
          end else begin
            check($sformatf("interrupt %0d: direct target", INTERRUPTS[i]),
                  last_redirect_pc == (tap_mtvec & ~XLEN'(3)));
          end
        end
      end
    end

    // --- nested trap: a trap inside the handler is not lost ---------------------
    enter_u();
    take_trap(1'b0, EXC_ECALL_U);
    check("first trap recorded", cur_mcause == XLEN'(EXC_ECALL_U));
    take_trap(1'b0, EXC_LOAD_ACCESS_FAULT);
    check("nested trap redirects", last_redirect_valid);
    check("nested trap: mcause is the second cause",
          cur_mcause == XLEN'(EXC_LOAD_ACCESS_FAULT));
    check("nested trap: mepc is the second pc", tap_mepc == trap_pc);
    check("nested trap: mtval is the second tval", cur_mtval == trap_tval);
    check("nested trap: MPP is M", tap_mstatus[F_MPP +: 2] == PRIV_M);
    take_trap(1'b1, INTERRUPTS[3]);
    check("nested interrupt: mcause", cur_mcause == ref_cause(1'b1, INTERRUPTS[3]));

    // --- trap entry beats a software write in the same cycle --------------------
    enter_m();
    sw_write(CSR_MSTATUS, mstatus_value(1'b1, 1'b0, PRIV_U, 1'b0));

    sw_value = rand_word();
    csr_we = 1'b1; csr_addr = CSR_MEPC; csr_wdata = sw_value;
    take_trap(1'b0, EXC_ILLEGAL_INSTR);
    check("trap beats write: mepc", tap_mepc == trap_pc);

    csr_we = 1'b1; csr_addr = CSR_MCAUSE; csr_wdata = rand_word();
    take_trap(1'b0, EXC_BREAKPOINT);
    check("trap beats write: mcause", cur_mcause == XLEN'(EXC_BREAKPOINT));

    csr_we = 1'b1; csr_addr = CSR_MTVAL; csr_wdata = rand_word();
    take_trap(1'b0, EXC_LOAD_PAGE_FAULT);
    check("trap beats write: mtval", cur_mtval == trap_tval);

    pre_mie  = ref_mie;
    pre_mprv = ref_mprv;
    csr_we = 1'b1; csr_addr = CSR_MSTATUS;
    csr_wdata = mstatus_value(~pre_mie, 1'b1, PRIV_U, ~pre_mprv);
    take_trap(1'b0, EXC_ECALL_M);
    check("trap beats write: mstatus MPIE from old MIE", tap_mstatus[F_MPIE] == pre_mie);
    check("trap beats write: mstatus MPRV unchanged", tap_mstatus[F_MPRV] == pre_mprv);
    check("trap beats write: mstatus MPP is M", tap_mstatus[F_MPP +: 2] == PRIV_M);

    saved_mtvec = ref_mtvec;
    sw_value    = (rand_word() & ~XLEN'(3)) | XLEN'(MODE_VECTORED);
    csr_we = 1'b1; csr_addr = CSR_MTVEC; csr_wdata = sw_value;
    take_trap(1'b0, EXC_ECALL_M);
    check("write to a CSR the trap does not touch lands", tap_mtvec == sw_value);
    check("same-cycle trap uses the old mtvec", last_redirect_pc == (saved_mtvec & ~XLEN'(3)));

    // --- random mix ---------------------------------------------------------------
    for (int unsigned n = 0; n < 4000; n++) begin
      r = $urandom_range(9, 0);
      if (r <= 2) begin
        random_trap();
      end else if (r == 3) begin
        mret_valid = 1'b1;
      end else if (r == 4) begin
        sret_valid = 1'b1;
      end else if (r <= 6) begin
        random_write();
      end else if (r == 7) begin
        random_write();
        random_trap();
      end
      cycle();
    end
    check("random: traps taken from U", n_trap_from_u > 0);
    check("random: mret attempted from U", n_mret_from_u > 0);
    check("random: trap and write in one cycle", n_trap_and_write > 0);
    check("random: write refused outside M", n_illegal_write > 0);

    if (errors == 0) begin
      $display("=== PASS : %0d checks ===", checks);
      $finish;
    end else begin
      $display("=== FAIL : %0d errors of %0d checks ===", errors, checks);
      $fatal(1, "tb_s1_trap_unit failed");
    end
  end

endmodule : tb_s1_trap_unit
