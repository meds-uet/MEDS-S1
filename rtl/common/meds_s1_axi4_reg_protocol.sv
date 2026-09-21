// SPDX-License-Identifier: Apache-2.0
// Copyright (c) Maktab-e-Digital Systems Lahore
//
// meds_s1_axi4_reg_protocol — full-AXI4, burst-capable register-shell top
// level. Instantiates the five channel modules and wires them together
// (aw/w feeding into b, ar feeding into r), the same way
// meds_s1_axil_reg_protocol does for the single-beat AXI4-Lite case, but
// with awlen/awsize/awburst, wlast, arlen/arsize/arburst and rlast on the
// AXI-facing side, and one wr_en_o pulse / rd_addr_o lookup PER BEAT
// (rather than per transaction) on the register-content boundary.
// Whatever sits behind that boundary does not need to know a burst is
// happening at all.
//
// Reusable for any simple burst-capable slave on the backbone (SPEC sec18),
// e.g. the Boot ROM or on-chip SRAM front end. Set ID_W = AXI_SID_W when it
// sits directly behind a crossbar slave port, so the master tag in the ID is
// echoed back unchanged.
//
// CONTRACT for the storage behind this shell:
//   * wr_data_o / wr_strb_o are the full 256-bit beat and its byte strobes,
//     on the byte lanes AXI defines for wr_addr_o. Honour wr_strb_o per byte.
//   * rd_data_i must be combinational from rd_addr_o and placed on the byte
//     lanes AXI defines for that address (a memory simply returns the whole
//     32-byte line containing rd_addr_o).
//   * drive wr_addr_valid_i / rd_addr_valid_i low for an unimplemented
//     address; the shell answers SLVERR.

module meds_s1_axi4_reg_protocol
  import meds_s1_axi4_pkg::*;
#(
  parameter int unsigned ID_W = AXI_ID_W
) (
  input  logic                  clk_i,
  input  logic                  rst_ni,

  // Write address channel
  input  logic [ID_W-1:0]       awid_i,
  input  logic [AXI_ADDR_W-1:0] awaddr_i,
  input  logic [7:0]            awlen_i,
  input  logic [2:0]            awsize_i,
  input  logic [1:0]            awburst_i,
  input  logic                  awvalid_i,
  output logic                  awready_o,

  // Write data channel
  input  logic [AXI_DATA_W-1:0] wdata_i,
  input  logic [AXI_STRB_W-1:0] wstrb_i,
  input  logic                  wlast_i,
  input  logic                  wvalid_i,
  output logic                  wready_o,

  // Write response channel
  output logic [ID_W-1:0]       bid_o,
  output logic [1:0]            bresp_o,
  output logic                  bvalid_o,
  input  logic                  bready_i,

  // Read address channel
  input  logic [ID_W-1:0]       arid_i,
  input  logic [AXI_ADDR_W-1:0] araddr_i,
  input  logic [7:0]            arlen_i,
  input  logic [2:0]            arsize_i,
  input  logic [1:0]            arburst_i,
  input  logic                  arvalid_i,
  output logic                  arready_o,

  // Read data channel
  output logic [ID_W-1:0]       rid_o,
  output logic [AXI_DATA_W-1:0] rdata_o,
  output logic [1:0]            rresp_o,
  output logic                  rlast_o,
  output logic                  rvalid_o,
  input  logic                  rready_i,

  // ---------------- Generic register-content boundary ----------------
  // One wr_en_o pulse per write beat, one rd_addr_o lookup per read beat.
  output logic [AXI_ADDR_W-1:0] wr_addr_o,
  output logic [AXI_DATA_W-1:0] wr_data_o,
  output logic [AXI_STRB_W-1:0] wr_strb_o,
  output logic                  wr_en_o,
  input  logic                  wr_addr_valid_i,

  output logic [AXI_ADDR_W-1:0] rd_addr_o,
  input  logic [AXI_DATA_W-1:0] rd_data_i,
  input  logic                  rd_addr_valid_i
);

  // ---- aw / w buffers <-> b commit logic ----
  logic [ID_W-1:0]       aw_captured_id;
  logic [AXI_ADDR_W-1:0] aw_captured_addr;
  logic [7:0]            aw_captured_len;
  logic [2:0]            aw_captured_size;
  logic [1:0]            aw_captured_burst;
  logic                  aw_captured;
  logic                  aw_consume;

  logic [AXI_DATA_W-1:0] w_captured_data;
  logic [AXI_STRB_W-1:0] w_captured_strb;
  logic                  w_captured_last;
  logic                  w_captured;
  logic                  w_consume;

  // ---- ar buffer <-> r response logic ----
  logic [ID_W-1:0]       ar_captured_id;
  logic [AXI_ADDR_W-1:0] ar_captured_addr;
  logic [7:0]            ar_captured_len;
  logic [2:0]            ar_captured_size;
  logic [1:0]            ar_captured_burst;
  logic                  ar_captured;
  logic                  ar_consume;

  meds_s1_axi4_aw_ch #(
    .ID_W (ID_W)
  ) u_aw_ch (
    .clk_i  (clk_i),
    .rst_ni (rst_ni),

    .awid_i    (awid_i),
    .awaddr_i  (awaddr_i),
    .awlen_i   (awlen_i),
    .awsize_i  (awsize_i),
    .awburst_i (awburst_i),
    .awvalid_i (awvalid_i),
    .awready_o (awready_o),

    .aw_captured_id_o    (aw_captured_id),
    .aw_captured_addr_o  (aw_captured_addr),
    .aw_captured_len_o   (aw_captured_len),
    .aw_captured_size_o  (aw_captured_size),
    .aw_captured_burst_o (aw_captured_burst),
    .aw_captured_o       (aw_captured),
    .aw_consume_i        (aw_consume)
  );

  meds_s1_axi4_w_ch u_w_ch (
    .clk_i  (clk_i),
    .rst_ni (rst_ni),

    .wdata_i  (wdata_i),
    .wstrb_i  (wstrb_i),
    .wlast_i  (wlast_i),
    .wvalid_i (wvalid_i),
    .wready_o (wready_o),

    .w_captured_data_o (w_captured_data),
    .w_captured_strb_o (w_captured_strb),
    .w_captured_last_o (w_captured_last),
    .w_captured_o      (w_captured),
    .w_consume_i       (w_consume)
  );

  meds_s1_axi4_b_ch #(
    .ID_W (ID_W)
  ) u_b_ch (
    .clk_i  (clk_i),
    .rst_ni (rst_ni),

    .aw_captured_id_i    (aw_captured_id),
    .aw_captured_addr_i  (aw_captured_addr),
    .aw_captured_len_i   (aw_captured_len),
    .aw_captured_size_i  (aw_captured_size),
    .aw_captured_burst_i (aw_captured_burst),
    .aw_captured_i       (aw_captured),
    .aw_consume_o        (aw_consume),

    .w_captured_data_i (w_captured_data),
    .w_captured_strb_i (w_captured_strb),
    .w_captured_last_i (w_captured_last),
    .w_captured_i      (w_captured),
    .w_consume_o       (w_consume),

    .bid_o    (bid_o),
    .bresp_o  (bresp_o),
    .bvalid_o (bvalid_o),
    .bready_i (bready_i),

    .wr_addr_o       (wr_addr_o),
    .wr_data_o       (wr_data_o),
    .wr_strb_o       (wr_strb_o),
    .wr_en_o         (wr_en_o),
    .wr_addr_valid_i (wr_addr_valid_i)
  );

  meds_s1_axi4_ar_ch #(
    .ID_W (ID_W)
  ) u_ar_ch (
    .clk_i  (clk_i),
    .rst_ni (rst_ni),

    .arid_i    (arid_i),
    .araddr_i  (araddr_i),
    .arlen_i   (arlen_i),
    .arsize_i  (arsize_i),
    .arburst_i (arburst_i),
    .arvalid_i (arvalid_i),
    .arready_o (arready_o),

    .ar_captured_id_o    (ar_captured_id),
    .ar_captured_addr_o  (ar_captured_addr),
    .ar_captured_len_o   (ar_captured_len),
    .ar_captured_size_o  (ar_captured_size),
    .ar_captured_burst_o (ar_captured_burst),
    .ar_captured_o       (ar_captured),
    .ar_consume_i        (ar_consume)
  );

  meds_s1_axi4_r_ch #(
    .ID_W (ID_W)
  ) u_r_ch (
    .clk_i  (clk_i),
    .rst_ni (rst_ni),

    .ar_captured_id_i    (ar_captured_id),
    .ar_captured_addr_i  (ar_captured_addr),
    .ar_captured_len_i   (ar_captured_len),
    .ar_captured_size_i  (ar_captured_size),
    .ar_captured_burst_i (ar_captured_burst),
    .ar_captured_i       (ar_captured),
    .ar_consume_o        (ar_consume),

    .rid_o    (rid_o),
    .rdata_o  (rdata_o),
    .rresp_o  (rresp_o),
    .rlast_o  (rlast_o),
    .rvalid_o (rvalid_o),
    .rready_i (rready_i),

    .rd_addr_o       (rd_addr_o),
    .rd_data_i       (rd_data_i),
    .rd_addr_valid_i (rd_addr_valid_i)
  );

endmodule : meds_s1_axi4_reg_protocol
