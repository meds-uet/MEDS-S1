// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// meds_s1_cdc_2ff : double-flop level synchronizer                     [COMPLETE]
//
// Generic double-flop level synchronizer. Destination-domain clock/reset
// only (R-N6): the source side is purely combinational/async input.
// Use for level (held) signals, not single-cycle pulses -- a pulse
// narrower than one destination clock period can be missed here; use
// meds_s1_cdc_toggle_src/_dst for pulses instead (R-C9).
//
// Contract: standard 2-flop metastability synchronizer, one bit of
// destination-clock latency added on top of the inherent 2-cycle delay.
//
// Reference: RISC-V External Debug Support Specification (DTM/DMI);
// contract in docs/modules/meds_s1_cdc_2ff.md.
// =============================================================================

module meds_s1_cdc_2ff #(
  parameter int unsigned WIDTH = 1
) (
  input  logic             clk_i,
  input  logic             rst_ni,
  input  logic [WIDTH-1:0] async_i,
  output logic [WIDTH-1:0] sync_o
);

  logic [WIDTH-1:0] meta_q, sync_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      meta_q <= '0;
      sync_q <= '0;
    end else begin
      meta_q <= async_i;
      sync_q <= meta_q;
    end
  end

  assign sync_o = sync_q;

endmodule : meds_s1_cdc_2ff
