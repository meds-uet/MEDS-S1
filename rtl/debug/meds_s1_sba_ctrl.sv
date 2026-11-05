// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// meds_s1_sba_ctrl : System Bus Access Controller                    [COMPLETE]
//
// FSM to manage System Bus Access (SBA) transactions for the Debug Module,
// bridging DMI SBA register operations to the AXI4 backbone with independent
// AW/W handshaking and direction-qualified R/B response handling.
//
// Reference: SPEC section 13, INTERFACES.md section 7.
// Testbench: verif/unit/tb_meds_s1_sba_ctrl.sv.
// =============================================================================

module meds_s1_sba_ctrl (
  input  logic       clk_i,
  input  logic       rst_ni,

  // DMI Interface
  input  logic       dmi_en_i,
  input  logic       dmi_wr_en_i,
  input  logic       dmi_rd_en_i,
  input  logic [7:0] dmi_addr_i,

  // SBA Configuration & Control (from DMI registers)
  input  logic       sbreadonaddr_i,
  input  logic       sbreadondata_i,
  input  logic       sbautoincrement_i,
  input  logic       clear_errors_i,

  // SBA Status (to DMI registers)
  output logic       sbbusy_o,
  output logic       set_sberror_o,
  output logic       set_sbbusyerror_o,
  output logic       inc_sbaddress_o,

  // AXI4 Handshake Interface
  input  logic       axi_arready_i,
  input  logic       axi_awready_i,
  input  logic       axi_wready_i,
  input  logic       axi_rvalid_i,
  input  logic [1:0] axi_rresp_i,
  input  logic       axi_bvalid_i,
  input  logic [1:0] axi_bresp_i,
  output logic       axi_req_valid_o,
  output logic       axi_is_read_o,
  output logic       axi_arvalid_o,
  output logic       axi_awvalid_o,
  output logic       axi_wvalid_o,
  output logic       axi_rready_o,
  output logic       axi_bready_o
);

  // RISC-V Debug Specification v1.0 (DMI SBA register offsets)
  localparam logic [7:0] SBADDRESS3 = 8'h37;
  localparam logic [7:0] SBCS       = 8'h38;
  localparam logic [7:0] SBADDRESS0 = 8'h39;
  localparam logic [7:0] SBADDRESS1 = 8'h3A;
  localparam logic [7:0] SBADDRESS2 = 8'h3B;
  localparam logic [7:0] SBDATA0    = 8'h3C;
  localparam logic [7:0] SBDATA1    = 8'h3D;
  localparam logic [7:0] SBDATA2    = 8'h3E;
  localparam logic [7:0] SBDATA3    = 8'h3F;
  localparam logic [1:0] AXI_OKAY   = 2'b00;

  typedef enum logic [1:0] {
    IDLE_E,
    AXI_ADDR_DATA_E,
    AXI_RESP_E,
    ERROR_HALT_E
  } sba_state_e;

  sba_state_e state_q, next_state_d;
  logic       is_read_q, is_read_d;
  logic       aw_done_q, aw_done_d;
  logic       w_done_q, w_done_d;
  logic       busy_err_q, busy_err_d;

  logic       sba_addr_wr;
  logic       sba_data_acc;
  logic       sba_illegal_dmi_access;

  // Per RISC-V Debug Spec
  // Only writes to sbaddress* or reads/writes to sbdata* while sbbusy is high
  // set sbbusyerror. Polling sbcs or accessing unrelated DMI registers is legal.
  assign sba_addr_wr = dmi_en_i && dmi_wr_en_i &&
                       ((dmi_addr_i == SBADDRESS0) || (dmi_addr_i == SBADDRESS1) ||
                        (dmi_addr_i == SBADDRESS2) || (dmi_addr_i == SBADDRESS3));

  assign sba_data_acc = dmi_en_i && (dmi_rd_en_i || dmi_wr_en_i) &&
                        ((dmi_addr_i == SBDATA0) || (dmi_addr_i == SBDATA1) ||
                         (dmi_addr_i == SBDATA2) || (dmi_addr_i == SBDATA3));

  assign sba_illegal_dmi_access = sba_addr_wr || sba_data_acc;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q    <= IDLE_E;
      is_read_q  <= 1'b0;
      aw_done_q  <= 1'b0;
      w_done_q   <= 1'b0;
      busy_err_q <= 1'b0;
    end else begin
      state_q    <= next_state_d;
      is_read_q  <= is_read_d;
      aw_done_q  <= aw_done_d;
      w_done_q   <= w_done_d;
      busy_err_q <= busy_err_d;
    end
  end

  assign axi_is_read_o = is_read_q;

  always_comb begin
    // Default assignments to prevent latches
    next_state_d      = state_q;
    is_read_d         = is_read_q;
    aw_done_d         = aw_done_q;
    w_done_d          = w_done_q;
    busy_err_d        = busy_err_q;

    sbbusy_o          = 1'b0;
    set_sberror_o     = 1'b0;
    set_sbbusyerror_o = 1'b0;
    inc_sbaddress_o   = 1'b0;

    axi_req_valid_o   = 1'b0;
    axi_arvalid_o     = 1'b0;
    axi_awvalid_o     = 1'b0;
    axi_wvalid_o      = 1'b0;
    axi_rready_o      = 1'b0;
    axi_bready_o      = 1'b0;

    unique case (state_q)
      IDLE_E: begin
        aw_done_d  = 1'b0;
        w_done_d   = 1'b0;
        busy_err_d = 1'b0;

        if (dmi_en_i && dmi_wr_en_i && (dmi_addr_i == SBADDRESS0) && sbreadonaddr_i) begin
          is_read_d    = 1'b1;
          next_state_d = AXI_ADDR_DATA_E;
        end else if (dmi_en_i && dmi_rd_en_i && (dmi_addr_i == SBDATA0) && sbreadondata_i) begin
          is_read_d    = 1'b1;
          next_state_d = AXI_ADDR_DATA_E;
        end else if (dmi_en_i && dmi_wr_en_i && (dmi_addr_i == SBDATA0)) begin
          is_read_d    = 1'b0;
          next_state_d = AXI_ADDR_DATA_E;
        end
      end

      AXI_ADDR_DATA_E: begin
        sbbusy_o        = 1'b1;
        axi_req_valid_o = 1'b1;
        axi_arvalid_o   = is_read_q;
        axi_awvalid_o   = !is_read_q && !aw_done_q;
        axi_wvalid_o    = !is_read_q && !w_done_q;

        if (sba_illegal_dmi_access) begin
          set_sbbusyerror_o = 1'b1;
          busy_err_d        = 1'b1;
        end

        if (is_read_q) begin
          if (axi_arready_i) begin
            next_state_d = AXI_RESP_E;
          end
        end else begin
          if (axi_awready_i) begin
            aw_done_d = 1'b1;
          end
          if (axi_wready_i) begin
            w_done_d = 1'b1;
          end
          if (aw_done_d && w_done_d) begin
            aw_done_d    = 1'b0;
            w_done_d     = 1'b0;
            next_state_d = AXI_RESP_E;
          end
        end
      end

      AXI_RESP_E: begin
        sbbusy_o     = 1'b1;
        axi_rready_o = is_read_q;
        axi_bready_o = !is_read_q;

        if (sba_illegal_dmi_access) begin
          set_sbbusyerror_o = 1'b1;
          busy_err_d        = 1'b1;
        end

        if (is_read_q && axi_rvalid_i) begin
          if (axi_rresp_i != AXI_OKAY) begin
            set_sberror_o = 1'b1;
            next_state_d  = ERROR_HALT_E;
          end else if (busy_err_d) begin
            next_state_d  = ERROR_HALT_E;
          end else begin
            inc_sbaddress_o = sbautoincrement_i;
            next_state_d    = IDLE_E;
          end
        end else if (!is_read_q && axi_bvalid_i) begin
          if (axi_bresp_i != AXI_OKAY) begin
            set_sberror_o = 1'b1;
            next_state_d  = ERROR_HALT_E;
          end else if (busy_err_d) begin
            next_state_d  = ERROR_HALT_E;
          end else begin
            inc_sbaddress_o = sbautoincrement_i;
            next_state_d    = IDLE_E;
          end
        end
      end

      ERROR_HALT_E: begin
        sbbusy_o = 1'b0;

        if (dmi_en_i && dmi_wr_en_i && (dmi_addr_i == SBCS) && clear_errors_i) begin
          busy_err_d   = 1'b0;
          next_state_d = IDLE_E;
        end
      end

      default: begin
        next_state_d = IDLE_E;
      end
    endcase
  end

endmodule
