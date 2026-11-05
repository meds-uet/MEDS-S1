// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// tb_meds_s1_sba_ctrl : unit testbench for meds_s1_sba_ctrl          [COMPLETE]
//
// Verifies SBA read/write transactions, independent AW/W handshaking,
// direction-qualified R/B responses, safe SBCS polling while busy, and
// non-destructive completion of in-flight AXI transactions on sbbusyerror.
//
// Run:  make test-unit                     (all testbenches)
//       make test-unit TB=meds_s1_sba_ctrl (just this one)
// =============================================================================

module tb_meds_s1_sba_ctrl;

  logic       clk_i;
  logic       rst_ni;

  logic       dmi_en_i;
  logic       dmi_wr_en_i;
  logic       dmi_rd_en_i;
  logic [7:0] dmi_addr_i;

  logic       sbreadonaddr_i;
  logic       sbreadondata_i;
  logic       sbautoincrement_i;
  logic       clear_errors_i;

  logic       sbbusy_o;
  logic       set_sberror_o;
  logic       set_sbbusyerror_o;
  logic       inc_sbaddress_o;

  logic       axi_arready_i;
  logic       axi_awready_i;
  logic       axi_wready_i;
  logic       axi_rvalid_i;
  logic [1:0] axi_rresp_i;
  logic       axi_bvalid_i;
  logic [1:0] axi_bresp_i;
  logic       axi_req_valid_o;
  logic       axi_is_read_o;
  logic       axi_arvalid_o;
  logic       axi_awvalid_o;
  logic       axi_wvalid_o;
  logic       axi_rready_o;
  logic       axi_bready_o;

  int unsigned checks = 0;
  int unsigned errors = 0;

  meds_s1_sba_ctrl dut (
    .clk_i             (clk_i),
    .rst_ni            (rst_ni),
    .dmi_en_i          (dmi_en_i),
    .dmi_wr_en_i       (dmi_wr_en_i),
    .dmi_rd_en_i       (dmi_rd_en_i),
    .dmi_addr_i        (dmi_addr_i),
    .sbreadonaddr_i    (sbreadonaddr_i),
    .sbreadondata_i    (sbreadondata_i),
    .sbautoincrement_i (sbautoincrement_i),
    .clear_errors_i    (clear_errors_i),
    .sbbusy_o          (sbbusy_o),
    .set_sberror_o     (set_sberror_o),
    .set_sbbusyerror_o (set_sbbusyerror_o),
    .inc_sbaddress_o   (inc_sbaddress_o),
    .axi_arready_i     (axi_arready_i),
    .axi_awready_i     (axi_awready_i),
    .axi_wready_i      (axi_wready_i),
    .axi_rvalid_i      (axi_rvalid_i),
    .axi_rresp_i       (axi_rresp_i),
    .axi_bvalid_i      (axi_bvalid_i),
    .axi_bresp_i       (axi_bresp_i),
    .axi_req_valid_o   (axi_req_valid_o),
    .axi_is_read_o     (axi_is_read_o),
    .axi_arvalid_o     (axi_arvalid_o),
    .axi_awvalid_o     (axi_awvalid_o),
    .axi_wvalid_o      (axi_wvalid_o),
    .axi_rready_o      (axi_rready_o),
    .axi_bready_o      (axi_bready_o)
  );

  task automatic check1(input string name, input logic got, input logic exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("  FAIL %-32s got=%0d exp=%0d", name, got, exp);
    end
  endtask

  initial clk_i = 1'b0;
  always #5 clk_i <= ~clk_i;

  task automatic step_clk(input int cycles = 1);
    repeat (cycles) @(posedge clk_i);
    #1;
  endtask

  initial begin
    $display("=== tb_meds_s1_sba_ctrl ===");

    rst_ni            = 1'b0;
    dmi_en_i          = 1'b0;
    dmi_wr_en_i       = 1'b0;
    dmi_rd_en_i       = 1'b0;
    dmi_addr_i        = 8'h0;
    sbreadonaddr_i    = 1'b0;
    sbreadondata_i    = 1'b0;
    sbautoincrement_i = 1'b0;
    clear_errors_i    = 1'b0;

    axi_arready_i     = 1'b0;
    axi_awready_i     = 1'b0;
    axi_wready_i      = 1'b0;
    axi_rvalid_i      = 1'b0;
    axi_rresp_i       = 2'b00;
    axi_bvalid_i      = 1'b0;
    axi_bresp_i       = 2'b00;

    step_clk(2);
    rst_ni = 1'b1;
    step_clk(2);

    // -------------------------------------------------------------------------
    // Test 1: Valid Write Transaction with Staggered AW/W Handshakes
    // -------------------------------------------------------------------------
    dmi_en_i    = 1'b1;
    dmi_wr_en_i = 1'b1;
    dmi_addr_i  = 8'h3C; // SBDATA0
    step_clk(1);
    dmi_en_i    = 1'b0;
    dmi_wr_en_i = 1'b0;

    check1("T1: Entered AXI_ADDR_DATA_E", (dut.state_q == dut.AXI_ADDR_DATA_E), 1'b1);
    check1("T1: sbbusy_o asserted", sbbusy_o, 1'b1);
    check1("T1: axi_awvalid_o asserted", axi_awvalid_o, 1'b1);
    check1("T1: axi_wvalid_o asserted", axi_wvalid_o, 1'b1);
    check1("T1: axi_is_read_o deasserted", axi_is_read_o, 1'b0);

    // Staggered handshake: AW accepted first, W accepted next cycle
    axi_awready_i = 1'b1;
    axi_wready_i  = 1'b0;
    step_clk(1);
    axi_awready_i = 1'b0;
    check1("T1: Stay in ADDR_DATA for W", (dut.state_q == dut.AXI_ADDR_DATA_E), 1'b1);
    check1("T1: axi_awvalid_o deasserted", axi_awvalid_o, 1'b0);
    check1("T1: axi_wvalid_o stays high", axi_wvalid_o, 1'b1);

    axi_wready_i = 1'b1;
    step_clk(1);
    axi_wready_i = 1'b0;

    check1("T1: Entered AXI_RESP_E", (dut.state_q == dut.AXI_RESP_E), 1'b1);
    check1("T1: axi_bready_o asserted", axi_bready_o, 1'b1);
    check1("T1: axi_rready_o deasserted", axi_rready_o, 1'b0);

    // Stray rvalid during write must be ignored
    axi_rvalid_i = 1'b1;
    step_clk(1);
    axi_rvalid_i = 1'b0;
    check1("T1: Ignore stray rvalid on wr", (dut.state_q == dut.AXI_RESP_E), 1'b1);

    sbautoincrement_i = 1'b1;
    axi_bvalid_i      = 1'b1;
    axi_bresp_i       = 2'b00; // OKAY
    #1;
    check1("T1: inc_sbaddress_o asserted", inc_sbaddress_o, 1'b1);

    step_clk(1);
    axi_bvalid_i      = 1'b0;
    check1("T1: Returned to IDLE_E", (dut.state_q == dut.IDLE_E), 1'b1);

    // -------------------------------------------------------------------------
    // Test 2: Valid Read Transaction & Safe SBCS Polling During Busy
    // -------------------------------------------------------------------------
    dmi_en_i       = 1'b1;
    dmi_wr_en_i    = 1'b1;
    dmi_addr_i     = 8'h39; // SBADDRESS0
    sbreadonaddr_i = 1'b1;
    step_clk(1);
    dmi_en_i       = 1'b0;
    dmi_wr_en_i    = 1'b0;

    check1("T2: Entered AXI_ADDR_DATA_E", (dut.state_q == dut.AXI_ADDR_DATA_E), 1'b1);
    check1("T2: axi_arvalid_o asserted", axi_arvalid_o, 1'b1);

    // Poll SBCS (read 0x38) while busy -> must NOT set sbbusyerror
    dmi_en_i    = 1'b1;
    dmi_rd_en_i = 1'b1;
    dmi_addr_i  = 8'h38; // SBCS
    #1;
    check1("T2: No busyerr on SBCS poll", set_sbbusyerror_o, 1'b0);
    step_clk(1);
    dmi_en_i    = 1'b0;
    dmi_rd_en_i = 1'b0;

    axi_arready_i = 1'b1;
    step_clk(1);
    axi_arready_i = 1'b0;

    check1("T2: Entered AXI_RESP_E", (dut.state_q == dut.AXI_RESP_E), 1'b1);
    check1("T2: axi_rready_o asserted", axi_rready_o, 1'b1);
    check1("T2: axi_bready_o deasserted", axi_bready_o, 1'b0);

    // Stray bvalid during read must be ignored
    axi_bvalid_i = 1'b1;
    step_clk(1);
    axi_bvalid_i = 1'b0;
    check1("T2: Ignore stray bvalid on rd", (dut.state_q == dut.AXI_RESP_E), 1'b1);

    axi_rvalid_i = 1'b1;
    axi_rresp_i  = 2'b00; // OKAY
    step_clk(1);
    axi_rvalid_i = 1'b0;

    check1("T2: Returned to IDLE_E", (dut.state_q == dut.IDLE_E), 1'b1);

    // -------------------------------------------------------------------------
    // Test 3: Busy Error Completes In-Flight AXI Transaction Before Halting
    // -------------------------------------------------------------------------
    dmi_en_i    = 1'b1;
    dmi_wr_en_i = 1'b1;
    dmi_addr_i  = 8'h3C; // SBDATA0
    step_clk(1);

    // In AXI_ADDR_DATA_E: issue illegal write to SBDATA0 while busy
    dmi_en_i    = 1'b1;
    dmi_wr_en_i = 1'b1;
    dmi_addr_i  = 8'h3C;
    #1;
    check1("T3: set_sbbusyerror_o asserted", set_sbbusyerror_o, 1'b1);
    step_clk(1);
    dmi_en_i    = 1'b0;
    dmi_wr_en_i = 1'b0;

    // Must NOT drop axi_req_valid_o or abandon transaction before handshake
    check1("T3: Stay in AXI_ADDR_DATA_E", (dut.state_q == dut.AXI_ADDR_DATA_E), 1'b1);
    check1("T3: axi_req_valid_o held high", axi_req_valid_o, 1'b1);

    // Finish AW/W handshake and B response
    axi_awready_i = 1'b1;
    axi_wready_i  = 1'b1;
    step_clk(1);
    axi_awready_i = 1'b0;
    axi_wready_i  = 1'b0;
    check1("T3: Advance to AXI_RESP_E", (dut.state_q == dut.AXI_RESP_E), 1'b1);

    axi_bvalid_i = 1'b1;
    axi_bresp_i  = 2'b00;
    step_clk(1);
    axi_bvalid_i = 1'b0;

    check1("T3: Entered ERROR_HALT_E", (dut.state_q == dut.ERROR_HALT_E), 1'b1);
    check1("T3: sbbusy_o deasserted", sbbusy_o, 1'b0);

    // Clear errors via SBCS
    dmi_en_i       = 1'b1;
    dmi_wr_en_i    = 1'b1;
    dmi_addr_i     = 8'h38; // SBCS
    clear_errors_i = 1'b1;
    step_clk(1);
    dmi_en_i       = 1'b0;
    dmi_wr_en_i    = 1'b0;
    clear_errors_i = 1'b0;

    check1("T3: Returned to IDLE_E", (dut.state_q == dut.IDLE_E), 1'b1);

    // -------------------------------------------------------------------------
    // Test 4: Bus Error (SLVERR)
    // -------------------------------------------------------------------------
    dmi_en_i    = 1'b1;
    dmi_wr_en_i = 1'b1;
    dmi_addr_i  = 8'h3C; // SBDATA0
    step_clk(1);
    dmi_en_i    = 1'b0;
    dmi_wr_en_i = 1'b0;

    axi_awready_i = 1'b1;
    axi_wready_i  = 1'b1;
    step_clk(1);
    axi_awready_i = 1'b0;
    axi_wready_i  = 1'b0;

    axi_bvalid_i = 1'b1;
    axi_bresp_i  = 2'b10; // SLVERR
    #1;
    check1("T4: set_sberror_o asserted", set_sberror_o, 1'b1);
    step_clk(1);
    axi_bvalid_i = 1'b0;
    axi_bresp_i  = 2'b00;

    check1("T4: Entered ERROR_HALT_E", (dut.state_q == dut.ERROR_HALT_E), 1'b1);

    // Clear errors
    dmi_en_i       = 1'b1;
    dmi_wr_en_i    = 1'b1;
    dmi_addr_i     = 8'h38; // SBCS
    clear_errors_i = 1'b1;
    step_clk(1);
    dmi_en_i       = 1'b0;
    dmi_wr_en_i    = 1'b0;
    clear_errors_i = 1'b0;

    check1("T4: Returned to IDLE_E", (dut.state_q == dut.IDLE_E), 1'b1);

    if (errors == 0) begin
      $display("=== PASS : %0d checks ===", checks);
      $finish;
    end else begin
      $display("=== FAIL : %0d errors of %0d checks ===", errors, checks);
      $fatal(1, "tb_meds_s1_sba_ctrl failed");
    end
  end

endmodule
