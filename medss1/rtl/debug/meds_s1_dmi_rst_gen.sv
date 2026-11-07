// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// meds_s1_dmi_rst_gen : async-assert / sync-release reset generator    [COMPLETE]
//
// Shared reset generator: async assert, sync de-assert, active-low (R-C4).
// Asserts rst_n_o whenever the external reset is asserted OR a single-cycle
// hardreset_pulse_i fires, then releases it two clk_i cycles later so every
// downstream flop sees a clean, glitch-free de-assert edge.
//
// Exists specifically so consuming modules never generate reset logic
// locally (R-C4 explicitly forbids that) -- they simply instantiate this
// and use rst_n_o like any ordinary reset.
//
// Reference: RISC-V External Debug Support Specification (DTM/DMI);
// contract in docs/modules/meds_s1_dmi_rst_gen.md.
// =============================================================================

module meds_s1_dmi_rst_gen (
  input  logic clk_i,
  // external async active-low reset
  input  logic rst_ni,
  // single clk_i-wide pulse, already synchronized
  input  logic hardreset_pulse_i,
  output logic rst_n_o
);

  logic rst_assert_n;
  assign rst_assert_n = rst_ni & ~hardreset_pulse_i;

  logic sync1_q, sync2_q;

  always_ff @(posedge clk_i or negedge rst_assert_n) begin
    if (!rst_assert_n) begin
      sync1_q <= 1'b0;
      sync2_q <= 1'b0;
    end else begin
      sync1_q <= 1'b1;
      sync2_q <= sync1_q;
    end
  end

  assign rst_n_o = sync2_q;

endmodule : meds_s1_dmi_rst_gen
