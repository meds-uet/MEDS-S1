// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// meds_s1_dtm_pkg : JTAG DTM / DMI constants and encodings             [WIP -- R-06]
//
// Everything the DTM modules, and the Debug Module that sits behind them, must
// agree on lives here: DMI widths and bit layout, op/status encodings, the
// 5-bit JTAG instruction opcodes and the DTMCS field positions.  Kept apart
// from s1_pkg, which holds the core's own types, following the precedent of
// meds_s1_lite_pkg: a subsystem's interface contract in one file.
//
// Reference: RISC-V External Debug Support Specification (DTM/DMI).
// =============================================================================

package meds_s1_dtm_pkg;

  // ===================================================================
  // DTM / DMI -- widths
  // ===================================================================
  parameter int unsigned DTM_IR_W        = 5;
  parameter int unsigned DTM_DTMCS_W     = 32;
  parameter int unsigned DTM_IDCODE_W    = 32;
  parameter int unsigned DMI_ABITS       = 7;                 // dm_addr width
  parameter int unsigned DMI_DATA_W      = 32;                // dm_wdata/dm_rdata width
  parameter int unsigned DMI_OP_W        = 2;                 // req op / resp status width
  parameter int unsigned DMI_REQ_W       = DMI_ABITS + DMI_DATA_W + DMI_OP_W;  // 41
  parameter int unsigned DMI_RESP_W      = DMI_DATA_W + DMI_OP_W;              // 34

  // ===================================================================
  // DTM -- IR opcodes (5-bit)
  // ===================================================================
  parameter logic [DTM_IR_W-1:0] DTM_IR_IDCODE = 5'b00001;
  parameter logic [DTM_IR_W-1:0] DTM_IR_DTMCS  = 5'b10000;
  parameter logic [DTM_IR_W-1:0] DTM_IR_DMI    = 5'b10001;
  parameter logic [DTM_IR_W-1:0] DTM_IR_BYPASS = 5'b11111;

  // IR reset / Capture-IR fixed value. Both equal 5'b00001: reset defaults
  // to IDCODE (so a debugger can identify the chip without first loading an
  // instruction), and the capture pattern's mandatory [1:0]==2'b01 happens
  // to coincide with it.
  parameter logic [DTM_IR_W-1:0] DTM_IR_RESET_VAL   = DTM_IR_IDCODE;
  parameter logic [DTM_IR_W-1:0] DTM_IR_CAPTURE_VAL = 5'b00001;

  // ===================================================================
  // DTMCS -- field bit positions (spec-standard layout)
  // ===================================================================
  parameter int unsigned DTMCS_VERSION_LSB     = 0;
  parameter int unsigned DTMCS_ABITS_LSB       = 4;
  parameter int unsigned DTMCS_DMISTAT_LSB     = 10;
  parameter int unsigned DTMCS_IDLE_LSB        = 12;
  parameter int unsigned DTMCS_DMIRESET_BIT    = 16;
  parameter int unsigned DTMCS_DMIHARDRESET_BIT = 17;

  parameter logic [3:0] DTMCS_VERSION_VAL = 4'd1;   // spec 0.13/1.0
  parameter logic [5:0] DTMCS_ABITS_VAL   = DMI_ABITS[5:0];
  parameter logic [2:0] DTMCS_IDLE_VAL    = 3'b000;

  // ===================================================================
  // DMI -- request op / response status encodings
  // ===================================================================
  typedef enum logic [DMI_OP_W-1:0] {
    DMI_OP_NOP   = 2'b00,
    DMI_OP_READ  = 2'b01,
    DMI_OP_WRITE = 2'b10
    // 2'b11 reserved
  } dmi_op_e;

  typedef enum logic [DMI_OP_W-1:0] {
    DMI_STATUS_SUCCESS  = 2'b00,
    // 2'b01 reserved
    DMI_STATUS_FAILED   = 2'b10,
    DMI_STATUS_BUSY     = 2'b11
  } dmi_status_e;

  // ===================================================================
  // DMI -- 41-bit request / 34-bit response bit layout
  //   req : [40:34]=addr  [33:2]=wdata  [1:0]=op
  //   resp: [33:2]=rdata  [1:0]=status
  // ===================================================================
  parameter int unsigned DMI_REQ_ADDR_LSB  = DMI_OP_W + DMI_DATA_W;  // 34
  parameter int unsigned DMI_REQ_DATA_LSB  = DMI_OP_W;               // 2
  parameter int unsigned DMI_REQ_OP_LSB    = 0;

  parameter int unsigned DMI_RESP_DATA_LSB   = DMI_OP_W;             // 2
  parameter int unsigned DMI_RESP_STATUS_LSB = 0;

  // ===================================================================
  // IDCODE -- default placeholder (override via module parameter)
  // ===================================================================
  parameter logic [DTM_IDCODE_W-1:0] DTM_IDCODE_DEFAULT =
      {4'h1, 16'h1000, 11'h000, 1'b1};

endpackage : meds_s1_dtm_pkg
