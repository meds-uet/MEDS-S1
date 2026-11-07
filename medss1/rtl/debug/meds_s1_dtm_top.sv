// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// meds_s1_dtm_top : JTAG debug transport module top level              [WIP -- R-06]
//
// Pure structural wrapper: instantiates meds_s1_dtm_tap, meds_s1_dtm_dr_regs,
// meds_s1_dmi_tck_if and meds_s1_dmi_core_if, and wires them together. No
// logic of its own beyond the interconnect. Two clock domains meet here
// only as port-level wiring between single-domain leaf modules (R-N6).
//
// External interface:
//   JTAG side (tck domain):              tck_i, trst_n_i, tms_i, tdi_i, tdo_o
//   Debug Module side (core_clk domain): core_clk_i, dmi_rst_n_i,
//                                         dm_addr_o, dm_wdata_o, dm_write_o,
//                                         dm_read_o, dm_rdata_i, dm_ready_i
//
// Reference: RISC-V External Debug Support Specification (DTM/DMI);
// contract in docs/modules/meds_s1_dtm_top.md.
// =============================================================================

module meds_s1_dtm_top
  import meds_s1_dtm_pkg::*;
#(
  parameter logic [DTM_IDCODE_W-1:0] IDCODE_VALUE = DTM_IDCODE_DEFAULT
) (
  // ---------------- JTAG pins (tck domain) ----------------
  input  logic                  tck_i,
  input  logic                  trst_n_i,
  input  logic                  tms_i,
  input  logic                  tdi_i,
  output logic                  tdo_o,

  // ---------------- Debug Module interface (core_clk domain) ----------------
  input  logic                  core_clk_i,
  input  logic                  dmi_rst_n_i,

  output logic [DMI_ABITS-1:0]  dm_addr_o,
  output logic [DMI_DATA_W-1:0] dm_wdata_o,
  output logic                  dm_write_o,
  output logic                  dm_read_o,
  input  logic [DMI_DATA_W-1:0] dm_rdata_i,
  input  logic                  dm_ready_i
);

  // -------------------------------------------------------------------
  // tap <-> dr_regs
  // -------------------------------------------------------------------
  logic capture_dr, shift_dr, update_dr;
  logic shift_ir, ir_shift_tdo;
  logic sel_bypass, sel_dtmcs, sel_dmi, sel_idcode;

  // -------------------------------------------------------------------
  // dr_regs <-> tck_if
  // -------------------------------------------------------------------
  logic [DMI_REQ_W-1:0] dmi_req;
  logic                 dmi_req_trigger;
  logic                 dmihardreset_pulse;
  logic                 req_pending;
  logic                 tck_ack;

  // -------------------------------------------------------------------
  // tck_if <-> core_if (crosses the clock boundary)
  // -------------------------------------------------------------------
  logic [DMI_REQ_W-1:0]  req_latch;
  logic                  req_valid_async;
  logic                  hardreset_toggle;
  logic                  resp_valid_async;
  logic [DMI_RESP_W-1:0] resp_data;

  meds_s1_dtm_tap u_tap (
    .clk_i         (tck_i),
    .rst_ni        (trst_n_i),
    .tms_i         (tms_i),
    .tdi_i         (tdi_i),

    .capture_dr_o  (capture_dr),
    .shift_dr_o    (shift_dr),
    .update_dr_o   (update_dr),

    .shift_ir_o    (shift_ir),
    .ir_shift_tdo_o(ir_shift_tdo),

    .sel_bypass_o  (sel_bypass),
    .sel_dtmcs_o   (sel_dtmcs),
    .sel_dmi_o     (sel_dmi),
    .sel_idcode_o  (sel_idcode)
  );

  meds_s1_dtm_dr_regs #(
    .IDCODE_VALUE (IDCODE_VALUE)
  ) u_dr_regs (
    .clk_i                (tck_i),
    .rst_ni               (trst_n_i),
    .tdi_i                (tdi_i),

    .capture_dr_i         (capture_dr),
    .shift_dr_i           (shift_dr),
    .update_dr_i          (update_dr),
    .shift_ir_i           (shift_ir),
    .ir_shift_tdo_i       (ir_shift_tdo),
    .sel_bypass_i         (sel_bypass),
    .sel_dtmcs_i          (sel_dtmcs),
    .sel_dmi_i            (sel_dmi),
    .sel_idcode_i         (sel_idcode),

    .stable_dmi_resp_i    (resp_data),
    .tck_ack_i            (tck_ack),
    .req_pending_i        (req_pending),

    .tdo_o                (tdo_o),

    .stable_dmi_req_o     (dmi_req),
    .dmi_req_trigger_o    (dmi_req_trigger),
    .dmihardreset_pulse_o (dmihardreset_pulse)
  );

  meds_s1_dmi_tck_if u_tck_if (
    .clk_i              (tck_i),
    .rst_ni             (trst_n_i),

    .dmi_req_i          (dmi_req),
    .req_trigger_i      (dmi_req_trigger),
    .hardreset_pulse_i  (dmihardreset_pulse),

    .resp_valid_async_i (resp_valid_async),

    .req_pending_o      (req_pending),
    .tck_ack_o          (tck_ack),
    .req_latch_o        (req_latch),
    .req_valid_o        (req_valid_async),
    .hardreset_toggle_o (hardreset_toggle)
  );

  meds_s1_dmi_core_if u_core_if (
    .clk_i               (core_clk_i),
    .rst_ni              (dmi_rst_n_i),

    .req_latch_i         (req_latch),
    .req_valid_async_i   (req_valid_async),
    .hardreset_toggle_i  (hardreset_toggle),

    .resp_valid_async_o  (resp_valid_async),
    .resp_data_o         (resp_data),

    .dm_addr_o           (dm_addr_o),
    .dm_wdata_o          (dm_wdata_o),
    .dm_write_o          (dm_write_o),
    .dm_read_o           (dm_read_o),
    .dm_rdata_i          (dm_rdata_i),
    .dm_ready_i          (dm_ready_i)
  );

endmodule : meds_s1_dtm_top
