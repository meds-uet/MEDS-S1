// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// meds_s1_cdc_toggle_dst : destination half of a toggle pulse synchronizer  [COMPLETE]
//
// Destination-domain half of a rate-independent pulse synchronizer.
// Synchronizes the incoming toggle bit with meds_s1_cdc_2ff (R-C9: reuse
// the shared synchronizer rather than hand-rolled flops), then
// edge-detects it to produce a single clk_i-wide pulse_o per toggle event
// on the source side. One clock/reset per module (R-N6): this is the
// destination side only.
//
// Contract: pulse_o is asserted for exactly one clk_i cycle per toggle
// edge received; guaranteed not to be dropped regardless of the
// source:clk_i frequency ratio, unlike a plain level synchronizer on a
// narrow pulse.
//
// Reference: RISC-V External Debug Support Specification (DTM/DMI);
// contract in docs/modules/meds_s1_cdc_toggle_dst.md.
// =============================================================================

module meds_s1_cdc_toggle_dst (
  input  logic clk_i,
  input  logic rst_ni,
  input  logic toggle_i,
  output logic pulse_o
);

  logic sync_toggle;
  logic dly_q;

  meds_s1_cdc_2ff #(
    .WIDTH (1)
  ) u_toggle_sync (
    .clk_i  (clk_i),
    .rst_ni (rst_ni),
    .async_i(toggle_i),
    .sync_o (sync_toggle)
  );

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) dly_q <= 1'b0;
    else         dly_q <= sync_toggle;
  end

  assign pulse_o = sync_toggle ^ dly_q;

endmodule : meds_s1_cdc_toggle_dst
