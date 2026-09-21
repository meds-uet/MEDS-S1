// SPDX-License-Identifier: Apache-2.0
// Copyright (c) Maktab-e-Digital Systems Lahore
//
// meds_s1_axil_reg_protocol — generic AXI4-Lite register-shell top level.
// Instantiates the five channel modules and wires them together
// internally (aw/w feeding into b, ar feeding into r). Exposes standard
// AXI4-Lite ports on one side and a plain register-style boundary
// (wr_addr_o/wr_data_o/wr_strb_o/wr_en_o/wr_addr_valid_i, rd_addr_o/
// rd_data_i/rd_addr_valid_i) on the other. Reusable for any AXI4-Lite
// slave in the platform: an accelerator's cfg window (SPEC sec20, the
// meds_s1_accel_socket's cfg_axil port) or a plain peripheral on the
// AXI4-Lite subtree (SPEC sec24 — CLINT, PLIC, UART, SPI, GPIO, Timer).
// This module does not know or care what sits behind the register
// boundary.
//
// CONTRACT for the register block behind this shell:
//   * honour wr_strb_o byte by byte (SPEC P3: never write bytes that were
//     not strobed);
//   * drive wr_addr_valid_i / rd_addr_valid_i low for an offset it does not
//     implement -- the shell then answers SLVERR (-> access fault);
//   * rd_data_i must be combinational from rd_addr_o (one-cycle lookup).
// ADDR_WIDTH is the LOCAL offset width (default 16 = one 64 KB window);
// connect the low ADDR_WIDTH bits of the 40-bit Lite address.

module meds_s1_axil_reg_protocol
  import meds_s1_axi4_pkg::*;
#(
  parameter int unsigned ADDR_WIDTH = AXIL_LOCAL_ADDR_W,
  parameter int unsigned DATA_WIDTH = AXIL_DATA_W,
  parameter int unsigned STRB_WIDTH = DATA_WIDTH / 8
) (
  input  logic                  clk_i,
  input  logic                  rst_ni,

  // Write address channel
  input  logic [ADDR_WIDTH-1:0] awaddr_i,
  input  logic                  awvalid_i,
  output logic                  awready_o,

  // Write data channel
  input  logic [DATA_WIDTH-1:0] wdata_i,
  input  logic [STRB_WIDTH-1:0] wstrb_i,
  input  logic                  wvalid_i,
  output logic                  wready_o,

  // Write response channel
  output logic [1:0]            bresp_o,
  output logic                  bvalid_o,
  input  logic                  bready_i,

  // Read address channel
  input  logic [ADDR_WIDTH-1:0] araddr_i,
  input  logic                  arvalid_i,
  output logic                  arready_o,

  // Read data channel
  output logic [DATA_WIDTH-1:0] rdata_o,
  output logic [1:0]            rresp_o,
  output logic                  rvalid_o,
  input  logic                  rready_i,

  // ---------------- Generic register-content boundary ----------------
  // Whatever sits behind this shell drives rd_data_i/rd_addr_valid_i
  // combinationally off rd_addr_o, and consumes wr_addr_o/wr_data_o/
  // wr_strb_o/wr_en_o, driving wr_addr_valid_i back.
  output logic [ADDR_WIDTH-1:0] wr_addr_o,
  output logic [DATA_WIDTH-1:0] wr_data_o,
  output logic [STRB_WIDTH-1:0] wr_strb_o,
  output logic                  wr_en_o,
  input  logic                  wr_addr_valid_i,

  output logic [ADDR_WIDTH-1:0] rd_addr_o,
  input  logic [DATA_WIDTH-1:0] rd_data_i,
  input  logic                  rd_addr_valid_i
);

  logic [ADDR_WIDTH-1:0] aw_captured_addr;
  logic                   aw_captured;
  logic                   aw_consume;

  logic [DATA_WIDTH-1:0] w_captured_data;
  logic [STRB_WIDTH-1:0] w_captured_strb;
  logic                   w_captured;
  logic                   w_consume;

  logic [ADDR_WIDTH-1:0] ar_captured_addr;
  logic                   ar_captured;
  logic                   ar_consume;

  meds_s1_axil_aw_ch #(
    .ADDR_WIDTH (ADDR_WIDTH)
  ) u_aw_ch (
    .clk_i              (clk_i),
    .rst_ni             (rst_ni),

    .awaddr_i           (awaddr_i),
    .awvalid_i          (awvalid_i),
    .awready_o          (awready_o),

    .aw_captured_addr_o (aw_captured_addr),
    .aw_captured_o      (aw_captured),
    .aw_consume_i       (aw_consume)
  );

  meds_s1_axil_w_ch #(
    .DATA_WIDTH (DATA_WIDTH),
    .STRB_WIDTH (STRB_WIDTH)
  ) u_w_ch (
    .clk_i             (clk_i),
    .rst_ni            (rst_ni),

    .wdata_i           (wdata_i),
    .wstrb_i           (wstrb_i),
    .wvalid_i          (wvalid_i),
    .wready_o          (wready_o),

    .w_captured_data_o (w_captured_data),
    .w_captured_strb_o (w_captured_strb),
    .w_captured_o      (w_captured),
    .w_consume_i       (w_consume)
  );

  meds_s1_axil_b_ch #(
    .ADDR_WIDTH (ADDR_WIDTH),
    .DATA_WIDTH (DATA_WIDTH),
    .STRB_WIDTH (STRB_WIDTH)
  ) u_b_ch (
    .clk_i              (clk_i),
    .rst_ni             (rst_ni),

    .aw_captured_addr_i (aw_captured_addr),
    .aw_captured_i      (aw_captured),
    .aw_consume_o       (aw_consume),

    .w_captured_data_i  (w_captured_data),
    .w_captured_strb_i  (w_captured_strb),
    .w_captured_i       (w_captured),
    .w_consume_o        (w_consume),

    .bresp_o            (bresp_o),
    .bvalid_o           (bvalid_o),
    .bready_i           (bready_i),

    .wr_addr_o          (wr_addr_o),
    .wr_data_o          (wr_data_o),
    .wr_strb_o          (wr_strb_o),
    .wr_en_o            (wr_en_o),
    .wr_addr_valid_i    (wr_addr_valid_i)
  );

  meds_s1_axil_ar_ch #(
    .ADDR_WIDTH (ADDR_WIDTH)
  ) u_ar_ch (
    .clk_i              (clk_i),
    .rst_ni             (rst_ni),

    .araddr_i           (araddr_i),
    .arvalid_i          (arvalid_i),
    .arready_o          (arready_o),

    .ar_captured_addr_o (ar_captured_addr),
    .ar_captured_o      (ar_captured),
    .ar_consume_i       (ar_consume)
  );

  meds_s1_axil_r_ch #(
    .ADDR_WIDTH (ADDR_WIDTH),
    .DATA_WIDTH (DATA_WIDTH)
  ) u_r_ch (
    .clk_i              (clk_i),
    .rst_ni             (rst_ni),

    .ar_captured_addr_i (ar_captured_addr),
    .ar_captured_i      (ar_captured),
    .ar_consume_o       (ar_consume),

    .rdata_o            (rdata_o),
    .rresp_o            (rresp_o),
    .rvalid_o           (rvalid_o),
    .rready_i           (rready_i),

    .rd_addr_o          (rd_addr_o),
    .rd_data_i          (rd_data_i),
    .rd_addr_valid_i    (rd_addr_valid_i)
  );

endmodule : meds_s1_axil_reg_protocol
