// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// tb_s1_irq_prio : unit testbench for s1_irq_prio                       [WIP]
//
// Exhaustive over the six standard bits of mip, mie and mideleg, every mode,
// mstatus.MIE and mstatus.SIE, for S-mode absent and present.  Bits outside
// the standard set carry random values and must be ignored.  The reference
// decides each interrupt's destination from the privileged-spec conditions
// and then walks the priority list per destination.
//
// Run:  make test-unit TB=tb_s1_irq_prio
// =============================================================================

module tb_s1_irq_prio
  import s1_pkg::*;
;

  localparam int unsigned W     = XLEN;
  localparam int unsigned N_IRQ = 6;

  // Standard interrupts in priority order (privileged spec, mip/mie).
  localparam int unsigned PRIO [N_IRQ] = '{11, 3, 7, 9, 1, 5};

  localparam int unsigned DEST_NONE = 0;
  localparam int unsigned DEST_S    = 1;
  localparam int unsigned DEST_M    = 3;

  localparam priv_lvl_e MODES [3] = '{PRIV_U, PRIV_S, PRIV_M};

  logic [W-1:0] mip, mie, mideleg;
  logic         mstatus_mie, mstatus_sie;
  priv_lvl_e    priv;

  logic         valid [2];
  logic [5:0]   code  [2];

  int unsigned  checks = 0;
  int unsigned  errors = 0;
  int unsigned  hits [2][64];
  int unsigned  hits_to_s [2];

  s1_irq_prio #(.S_MODE_PRESENT(1'b0)) dut_no_s (
    .mip_i         (mip),
    .mie_i         (mie),
    .mideleg_i     (mideleg),
    .mstatus_mie_i (mstatus_mie),
    .mstatus_sie_i (mstatus_sie),
    .priv_i        (priv),
    .irq_valid_o   (valid[0]),
    .irq_code_o    (code[0])
  );

  s1_irq_prio #(.S_MODE_PRESENT(1'b1)) dut_s (
    .mip_i         (mip),
    .mie_i         (mie),
    .mideleg_i     (mideleg),
    .mstatus_mie_i (mstatus_mie),
    .mstatus_sie_i (mstatus_sie),
    .priv_i        (priv),
    .irq_valid_o   (valid[1]),
    .irq_code_o    (code[1])
  );

  // ---------------------------------------------------------------------------
  // Reference model
  // ---------------------------------------------------------------------------
  function automatic bit s_level(input int unsigned i);
    return (i == 1) || (i == 5) || (i == 9);
  endfunction

  // Where interrupt i traps to, from the conditions in the privileged spec.
  function automatic int unsigned destination(input bit s_present, input int unsigned i);
    bit delegated;
    if (!s_present && s_level(i)) return DEST_NONE;
    if (!(mip[i] && mie[i])) return DEST_NONE;
    delegated = s_present && s_level(i) && mideleg[i];
    if (!delegated) begin
      if ((priv == PRIV_M && mstatus_mie) || int'(priv) < int'(PRIV_M)) return DEST_M;
      return DEST_NONE;
    end
    if ((priv == PRIV_S && mstatus_sie) || int'(priv) < int'(PRIV_S)) return DEST_S;
    return DEST_NONE;
  endfunction

  // Decreasing destined privilege first, then the priority list.
  task automatic expected(input bit s_present, output bit exp_valid,
                          output int unsigned exp_code, output int unsigned exp_dest);
    int unsigned dests [2];
    dests     = '{DEST_M, DEST_S};
    exp_valid = 1'b0;
    exp_code  = 0;
    exp_dest  = DEST_NONE;
    foreach (dests[d]) begin
      foreach (PRIO[k]) begin
        if (!exp_valid && destination(s_present, PRIO[k]) == dests[d]) begin
          exp_valid = 1'b1;
          exp_code  = PRIO[k];
          exp_dest  = dests[d];
        end
      end
    end
  endtask

  // ---------------------------------------------------------------------------
  // Scoreboard
  // ---------------------------------------------------------------------------
  task automatic score(input int unsigned inst);
    bit          exp_valid;
    int unsigned exp_code;
    int unsigned exp_dest;
    expected(inst == 1, exp_valid, exp_code, exp_dest);
    checks += 2;
    if (valid[inst] !== exp_valid || code[inst] !== 6'(exp_code)) begin
      errors++;
      if (errors <= 10) begin
        $display("  FAIL S=%0d priv=%0d MIE=%0b SIE=%0b mip=%h mie=%h mideleg=%h : got %0b/%0d exp %0b/%0d",
                 inst, priv, mstatus_mie, mstatus_sie, mip[11:0], mie[11:0], mideleg[11:0],
                 valid[inst], code[inst], exp_valid, exp_code);
      end
    end
    if (exp_valid) hits[inst][exp_code]++;
    if (exp_dest == DEST_S) hits_to_s[inst]++;
  endtask

  task automatic check(input string name, input bit cond);
    checks++;
    if (!cond) begin
      errors++;
      $display("  FAIL %s", name);
    end
  endtask

  // Standard bits from the case index, everything else random.
  task automatic apply(input int unsigned v, input int unsigned p, input int unsigned g);
    mip     = {$urandom, $urandom};
    mie     = {$urandom, $urandom};
    mideleg = {$urandom, $urandom};
    foreach (PRIO[k]) begin
      mip[PRIO[k]]     = v[k];
      mie[PRIO[k]]     = v[N_IRQ + k];
      mideleg[PRIO[k]] = v[2 * N_IRQ + k];
    end
    priv        = MODES[p];
    mstatus_mie = g[0];
    mstatus_sie = g[1];
    #1;
  endtask

  initial begin
    $display("=== tb_s1_irq_prio : XLEN=%0d ===", W);

    for (int unsigned v = 0; v < (1 << (3 * N_IRQ)); v++) begin
      for (int unsigned p = 0; p < 3; p++) begin
        for (int unsigned g = 0; g < 4; g++) begin
          apply(v, p, g);
          if (MODES[p] != PRIV_S) score(0);
          score(1);
        end
      end
    end

    // Every outcome was reachable, and none that should not be.
    foreach (PRIO[k]) begin
      check($sformatf("S present: code %0d taken", PRIO[k]), hits[1][PRIO[k]] > 0);
      check($sformatf("S absent: code %0d taken iff M-level", PRIO[k]),
            (hits[0][PRIO[k]] > 0) == !s_level(PRIO[k]));
    end
    check("S present: some interrupt taken to S", hits_to_s[1] > 0);
    check("S absent: nothing taken to S", hits_to_s[0] == 0);

    if (errors == 0) begin
      $display("=== PASS : %0d checks ===", checks);
      $finish;
    end else begin
      $display("=== FAIL : %0d errors of %0d checks ===", errors, checks);
      $fatal(1, "tb_s1_irq_prio failed");
    end
  end

endmodule : tb_s1_irq_prio
