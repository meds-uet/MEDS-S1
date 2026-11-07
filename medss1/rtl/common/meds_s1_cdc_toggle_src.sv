// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// meds_s1_cdc_toggle_src : source half of a toggle pulse synchronizer  [COMPLETE]
//
// Source-domain half of a rate-independent pulse synchronizer. Flips an
// internal toggle bit on every pulse_i. Pair with meds_s1_cdc_toggle_dst
// in the destination domain to recover a single destination-clock-wide
// pulse per source event, regardless of the clk_i:dst_clk frequency
// ratio (R-C9). One clock/reset per module (R-N6): this is the source
// side only.
//
// Contract: toggle_o must be treated as an async (quasi-static between
// edges) signal by the receiving synchronizer; never sampled directly
// without a destination-domain 2FF stage.
//
// Reference: RISC-V External Debug Support Specification (DTM/DMI);
// contract in docs/modules/meds_s1_cdc_toggle_src.md.
// =============================================================================

module meds_s1_cdc_toggle_src (
  input  logic clk_i,
  input  logic rst_ni,
  input  logic pulse_i,
  output logic toggle_o
);

  logic toggle_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)        toggle_q <= 1'b0;
    else if (pulse_i)   toggle_q <= ~toggle_q;
  end

  assign toggle_o = toggle_q;

endmodule : meds_s1_cdc_toggle_src
