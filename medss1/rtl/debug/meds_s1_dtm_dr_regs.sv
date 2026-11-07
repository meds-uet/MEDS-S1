// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// meds_s1_dtm_dr_regs : DTM data registers, dmistat and TDO mux        [WIP -- R-06]
//
// TCK-domain data path: BYPASS (1b), DTMCS (32b), IDCODE (32b), DMI (41b)
// shift registers, the sticky dmistat error tracker, the TCK-domain
// response hold register, and the central TDO mux + output flop. One
// clock/reset (R-N6): clk_i/rst_ni here are tck/trst_n_i.
//
// All four DR shift registers share one hold-mux rule: update only on
// (sel_x & capture_dr_i) [parallel load] or (sel_x & shift_dr_i) [serial
// shift]; otherwise retain value.
//
// DMI bit layout (s1_pkg, LSB shifts out to TDO first):
//   [40:34] address | [33:2] data | [1:0] op/status
//
// Contract: RISC-V External Debug Support Specification (DTMCS/DMI/IDCODE
// register definitions).
//
// Reference: RISC-V External Debug Support Specification (DTM/DMI);
// contract in docs/modules/meds_s1_dtm_dr_regs.md.
// =============================================================================

module meds_s1_dtm_dr_regs
  import meds_s1_dtm_pkg::*;
#(
  parameter logic [DTM_IDCODE_W-1:0] IDCODE_VALUE = DTM_IDCODE_DEFAULT
) (
  input  logic                  clk_i,
  input  logic                  rst_ni,
  input  logic                  tdi_i,

  input  logic                  capture_dr_i,
  input  logic                  shift_dr_i,
  input  logic                  update_dr_i,
  input  logic                  shift_ir_i,
  input  logic                  ir_shift_tdo_i,
  input  logic                  sel_bypass_i,
  input  logic                  sel_dtmcs_i,
  input  logic                  sel_dmi_i,
  input  logic                  sel_idcode_i,

  // {rdata, status}
  input  logic [DMI_RESP_W-1:0] stable_dmi_resp_i,
  // level
  input  logic                  tck_ack_i,
  input  logic                  req_pending_i,

  output logic                  tdo_o,

  output logic [DMI_REQ_W-1:0]  stable_dmi_req_o,
  output logic                  dmi_req_trigger_o,
  output logic                  dmihardreset_pulse_o
);

  // ---------------------------------------------------------------------
  // tck_ack rising-edge detector
  // ---------------------------------------------------------------------
  logic tck_ack_q, tck_ack_rise;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) tck_ack_q <= 1'b0;
    else         tck_ack_q <= tck_ack_i;
  end

  assign tck_ack_rise = tck_ack_i & ~tck_ack_q;

  // ---------------------------------------------------------------------
  // dmi_resp_hold: latches the response bus on tck_ack's rising edge and
  // holds it stable for Capture_DR, however many clk_i cycles later.
  // ---------------------------------------------------------------------
  logic [DMI_RESP_W-1:0] dmi_resp_hold_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)            dmi_resp_hold_q <= '0;
    else if (tck_ack_rise)  dmi_resp_hold_q <= stable_dmi_resp_i;
  end

  // ---------------------------------------------------------------------
  // BYPASS register (1 bit)
  // ---------------------------------------------------------------------
  logic bypass_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)                            bypass_q <= 1'b0;
    else if (sel_bypass_i && capture_dr_i)  bypass_q <= 1'b0;
    else if (sel_bypass_i && shift_dr_i)    bypass_q <= tdi_i;
  end

  // ---------------------------------------------------------------------
  // DTMCS register (32 bits)
  // ---------------------------------------------------------------------
  logic [1:0]              dmistat_q;
  logic [DTM_DTMCS_W-1:0]  dtmcs_q;
  logic [DTM_DTMCS_W-1:0]  dtmcs_capture_val;

  assign dtmcs_capture_val = {
    {(DTM_DTMCS_W - DTMCS_DMIHARDRESET_BIT - 1){1'b0}}, // reserved, [31:18]
    1'b0,                                               // [17] dmihardreset reads 0
    1'b0,                                               // [16] dmireset reads 0
    1'b0,                                               // [15] reserved
    DTMCS_IDLE_VAL,                                     // [14:12] idle
    dmistat_q,                                          // [11:10] dmistat
    DTMCS_ABITS_VAL,                                    // [9:4] abits
    DTMCS_VERSION_VAL                                   // [3:0] version
  };

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)                           dtmcs_q <= '0;
    else if (sel_dtmcs_i && capture_dr_i)  dtmcs_q <= dtmcs_capture_val;
    else if (sel_dtmcs_i && shift_dr_i)    dtmcs_q <= {tdi_i, dtmcs_q[DTM_DTMCS_W-1:1]};
  end

  // dmireset/dmihardreset: derived combinationally from the stable shift
  // register contents, gated to the exact Update_DR cycle -- no literal
  // 32-bit Update FF needed for a pure write-1-to-trigger field.
  logic dmireset_pulse;

  assign dmireset_pulse       = update_dr_i && sel_dtmcs_i && dtmcs_q[DTMCS_DMIRESET_BIT];
  assign dmihardreset_pulse_o = update_dr_i && sel_dtmcs_i && dtmcs_q[DTMCS_DMIHARDRESET_BIT];

  // ---------------------------------------------------------------------
  // dmistat sticky error tracker: cleared by dmireset/dmihardreset
  // (always wins); otherwise sets once (first error wins, sticky) on
  // overrun or a failed response; never touched by a success response.
  // ---------------------------------------------------------------------
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      dmistat_q <= DMI_STATUS_SUCCESS;
    end else if (dmireset_pulse || dmihardreset_pulse_o) begin
      dmistat_q <= DMI_STATUS_SUCCESS;
    end else if (dmistat_q == DMI_STATUS_SUCCESS) begin
      if (update_dr_i && sel_dmi_i && req_pending_i)
        dmistat_q <= DMI_STATUS_BUSY;                                  // overrun
      else if (tck_ack_rise &&
               (stable_dmi_resp_i[DMI_RESP_STATUS_LSB +: DMI_OP_W] == DMI_STATUS_FAILED))
        dmistat_q <= DMI_STATUS_FAILED;
    end
  end

  // ---------------------------------------------------------------------
  // IDCODE register (32 bits, read-only content)
  // ---------------------------------------------------------------------
  logic [DTM_IDCODE_W-1:0] idcode_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)                            idcode_q <= IDCODE_VALUE;
    else if (sel_idcode_i && capture_dr_i)  idcode_q <= IDCODE_VALUE;
    else if (sel_idcode_i && shift_dr_i)    idcode_q <= {tdi_i, idcode_q[DTM_IDCODE_W-1:1]};
  end

  // ---------------------------------------------------------------------
  // DMI register (41 bits)
  // ---------------------------------------------------------------------
  logic [DMI_REQ_W-1:0] dmi_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      dmi_q <= '0;
    end else if (sel_dmi_i && capture_dr_i) begin
      if (dmistat_q == DMI_STATUS_SUCCESS)
        dmi_q[DMI_RESP_W-1:0] <= dmi_resp_hold_q;             // addr bits held
      else
        dmi_q[DMI_RESP_W-1:0] <= {{DMI_DATA_W{1'b0}}, dmistat_q}; // addr bits held
    end else if (sel_dmi_i && shift_dr_i) begin
      dmi_q <= {tdi_i, dmi_q[DMI_REQ_W-1:1]};
    end
  end

  assign stable_dmi_req_o = dmi_q;

  assign dmi_req_trigger_o = update_dr_i && sel_dmi_i &&
                              (dmistat_q == DMI_STATUS_SUCCESS) && !req_pending_i;

  // ---------------------------------------------------------------------
  // Central TDO mux + output register
  // ---------------------------------------------------------------------
  logic mux_out;

  always_comb begin
    mux_out = bypass_q; // R-C3: safe default before the if/else chain
    if (shift_ir_i)          mux_out = ir_shift_tdo_i;
    else if (sel_bypass_i)   mux_out = bypass_q;
    else if (sel_dtmcs_i)    mux_out = dtmcs_q[0];
    else if (sel_dmi_i)      mux_out = dmi_q[0];
    else if (sel_idcode_i)   mux_out = idcode_q[0];
  end

  logic tdo_q;

  always_ff @(negedge clk_i or negedge rst_ni) begin
    if (!rst_ni) tdo_q <= 1'b0;
    else         tdo_q <= mux_out;
  end

  assign tdo_o = tdo_q;

endmodule : meds_s1_dtm_dr_regs
