// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// tb_hs_chk : AXI handshake checker (VALID/payload stable until READY)
//
// Shared verification IP, pulled into a unit testbench with
//   `include "verif/common/tb_hs_chk.sv"
// (path is relative to the repo root: run_unit_tests.py runs from there and
// compiles only rtl/ plus the testbench file).
//
// Timing discipline: every signal this model drives changes at the NEGEDGE of
// clk, and every handshake is decided by sampling at the negedge (+#1).
// =============================================================================
`ifndef TB_HS_CHK_SV
`define TB_HS_CHK_SV

module tb_hs_chk #(parameter int W = 1, parameter string NAME = "ch") (
  input logic clk, rst_n, valid, ready,
  input logic [W-1:0] payload
);
  int errors = 0;
  logic pend = 0; logic [W-1:0] held;

  // Registers: pure non-blocking, as always_ff requires. Async reset to match
  // the DUT style this checker is normally wired against (avoids Verilator's
  // SYNCASYNCNET warning on a shared reset net).
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pend <= 0;
    end else begin
      pend <= valid && !ready;
      held <= payload;
    end
  end

  // Check + simulation-only counter: reads pend/held before this edge's
  // update lands (NBA semantics), exactly as it would inside the always_ff
  // above -- split out only because `errors` is a plain int, not a register,
  // and Verilator's always_ff requires non-blocking assignments only.
  initial forever @(posedge clk) begin
    if (rst_n && pend && (!valid || payload !== held)) begin
      errors++;
      $display("  [CHK] %s: VALID dropped or payload changed before READY (t=%0t)", NAME, $time);
    end
  end
endmodule : tb_hs_chk

// =============================================================================

`endif
