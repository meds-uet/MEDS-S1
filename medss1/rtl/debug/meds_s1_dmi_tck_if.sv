// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// meds_s1_dmi_tck_if : TCK-domain half of the DMI clock crossing       [WIP -- R-06]
//
// TCK-domain half of the DMI clock-domain crossing. One clock/reset
// (R-N6): clk_i here is tck. Owns the 4-phase handshake initiator state
// (dmi_req_valid_q), the request snapshot register, and the hardreset
// toggle source. Pairs with meds_s1_dmi_core_if.sv across the boundary.
//
// Contract: RISC-V External Debug Support Specification, DMI chapter.
// req_pending_o = dmi_req_valid_q | ack_i covers the full round trip
// (not just the request half), closing the re-request hazard where a new
// request could be accepted while the previous ack is still unwinding.
//
// Reference: RISC-V External Debug Support Specification (DTM/DMI);
// contract in docs/modules/meds_s1_dmi_tck_if.md.
// =============================================================================

module meds_s1_dmi_tck_if
  import meds_s1_dtm_pkg::*;
(
  // tck
  input  logic                   clk_i,
  // trst_n_i
  input  logic                   rst_ni,

  // live DMI shift-reg contents
  input  logic [DMI_REQ_W-1:0]   dmi_req_i,
  // 1-cycle pulse, aligned with Update_DR
  input  logic                   req_trigger_i,
  // 1-cycle pulse, tck domain
  input  logic                   hardreset_pulse_i,

  // raw core-domain resp_valid (async)
  input  logic                   resp_valid_async_i,

  // gates req_trigger_i upstream (dtm_dr_regs)
  output logic                   req_pending_o,
  // synchronized ack, for dr_regs' edge detect
  output logic                   tck_ack_o,
  // stable snapshot, feeds core_if
  output logic [DMI_REQ_W-1:0]   req_latch_o,
  // == dmi_req_valid_q, async to core_if's synchronizer
  output logic                   req_valid_o,
  // to meds_s1_cdc_toggle_dst in core_if
  output logic                   hardreset_toggle_o
);

  // ---------------------------------------------------------------------
  // resp_valid synchronizer (core_clk -> tck): destination-domain
  // synchronizer lives here, per R-N6, reused via R-C9's shared module.
  // ---------------------------------------------------------------------
  logic tck_ack;

  meds_s1_cdc_2ff #(
    .WIDTH (1)
  ) u_ack_sync (
    .clk_i  (clk_i),
    .rst_ni (rst_ni),
    .async_i(resp_valid_async_i),
    .sync_o (tck_ack)
  );

  assign tck_ack_o = tck_ack;

  // ---------------------------------------------------------------------
  // 4-phase initiator flag
  // ---------------------------------------------------------------------
  logic dmi_req_valid_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)               dmi_req_valid_q <= 1'b0;
    else if (req_trigger_i)    dmi_req_valid_q <= 1'b1;
    else if (tck_ack)          dmi_req_valid_q <= 1'b0;
  end

  assign req_valid_o   = dmi_req_valid_q;
  assign req_pending_o = dmi_req_valid_q | tck_ack;

  // ---------------------------------------------------------------------
  // Request snapshot: immune to further shifting of the DMI register
  // while this transaction is in flight.
  // ---------------------------------------------------------------------
  logic [DMI_REQ_W-1:0] req_latch_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)              req_latch_q <= '0;
    else if (req_trigger_i)   req_latch_q <= dmi_req_i;
  end

  assign req_latch_o = req_latch_q;

  // ---------------------------------------------------------------------
  // Hardreset toggle source (R-C9: shared common module, not hand-rolled)
  // ---------------------------------------------------------------------
  meds_s1_cdc_toggle_src u_hardreset_toggle_src (
    .clk_i   (clk_i),
    .rst_ni  (rst_ni),
    .pulse_i (hardreset_pulse_i),
    .toggle_o(hardreset_toggle_o)
  );

endmodule : meds_s1_dmi_tck_if
