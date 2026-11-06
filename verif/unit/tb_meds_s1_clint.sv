
// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0

// tb_meds_s1_clint
// [WIP -- T-05]
//
// Directed tests for CLINT reset, register access, byte strobes, timer
// increments, interrupt outputs, and unmapped-address errors.

module tb_meds_s1_clint
  import meds_s1_lite_pkg::*;
();

  localparam int unsigned ADDR_W = 16;
  localparam int unsigned REG_DW = 64;
  localparam int unsigned REG_SW = REG_DW / 8;
  localparam int unsigned BYTE_W = 8;

  localparam int unsigned AXI_TIMEOUT_CYCLES = 50;
  localparam int unsigned WATCHDOG_CYCLES    = 1000;

  localparam logic [ADDR_W-1:0] MSIP_OFFSET     = 'h0000;
  localparam logic [ADDR_W-1:0] MTIME_OFFSET    = 'h4000;
  localparam logic [ADDR_W-1:0] MTIMECMP_OFFSET = 'hBFF8;
  localparam logic [ADDR_W-1:0] UNMAPPED_OFFSET = 'h1000;

  localparam logic [REG_DW-1:0] MTIME_PATTERN =
    64'h1122_3344_5566_7788;
  localparam logic [REG_DW-1:0] WRITE_PATTERN =
    64'hAABB_CCDD_EEFF_0012;
  localparam logic [REG_DW-1:0] MTIMECMP_PATTERN =
    64'h1234_5678_9ABC_DEF0;

  logic clk_i;
  logic rst_ni;
  logic rtc_tick_i;

  lite_req_t lite_req_i;
  lite_rsp_t lite_rsp_o;

  logic msip_o;
  logic mtip_o;

  logic [REG_DW-1:0] read_data;
  logic [1:0]        read_resp;
  logic [1:0]        write_resp;

  int unsigned checks;
  int unsigned errors;

  meds_s1_clint dut (
    .clk_i      (clk_i),
    .rst_ni     (rst_ni),
    .rtc_tick_i (rtc_tick_i),
    .lite_req_i (lite_req_i),
    .lite_rsp_o (lite_rsp_o),
    .msip_o     (msip_o),
    .mtip_o     (mtip_o)
  );

  initial begin
    clk_i = 1'b0;
    forever #5 clk_i = ~clk_i;
  end

  initial begin
    repeat (WATCHDOG_CYCLES) @(posedge clk_i);
    $fatal(1, "tb_meds_s1_clint: global watchdog expired");
  end

  task automatic check_data(
    input string             name,
    input logic [REG_DW-1:0] got,
    input logic [REG_DW-1:0] expected
  );
    checks++;

    if (got !== expected) begin
      errors++;
      $error("FAIL %-32s got=%h expected=%h",
             name, got, expected);
    end
  endtask

  task automatic check_bit(
    input string name,
    input logic  got,
    input logic  expected
  );
    checks++;

    if (got !== expected) begin
      errors++;
      $error("FAIL %-32s got=%b expected=%b",
             name, got, expected);
    end
  endtask

  task automatic check_resp(
    input string      name,
    input logic [1:0] got,
    input logic [1:0] expected
  );
    checks++;

    if (got !== expected) begin
      errors++;
      $error("FAIL %-32s got=%b expected=%b",
             name, got, expected);
    end
  endtask

  task automatic axi_write(
    input logic [ADDR_W-1:0] addr,
    input logic [REG_DW-1:0] data,
    input logic [REG_SW-1:0] strb
  );
    bit aw_done;
    bit w_done;
    int unsigned wait_cycles;

    aw_done = 1'b0;
    w_done  = 1'b0;
    wait_cycles = 0;

    @(negedge clk_i);
    lite_req_i.aw.addr  = addr;
    lite_req_i.aw_valid = 1'b1;
    lite_req_i.w.data   = data;
    lite_req_i.w.strb   = strb;
    lite_req_i.w_valid  = 1'b1;
    lite_req_i.b_ready  = 1'b0;

    while (!(aw_done && w_done)) begin
      @(posedge clk_i);

      if (!aw_done && lite_rsp_o.aw_ready)
        aw_done = 1'b1;

      if (!w_done && lite_rsp_o.w_ready)
        w_done = 1'b1;

      @(negedge clk_i);

      if (aw_done)
        lite_req_i.aw_valid = 1'b0;

      if (w_done)
        lite_req_i.w_valid = 1'b0;

      wait_cycles++;

      if (wait_cycles >= AXI_TIMEOUT_CYCLES)
        $fatal(1, "AXI write handshake timeout at %h", addr);
    end

    wait_cycles = 0;

    while (!lite_rsp_o.b_valid) begin
      @(posedge clk_i);
      @(negedge clk_i);

      wait_cycles++;

      if (wait_cycles >= AXI_TIMEOUT_CYCLES)
        $fatal(1, "AXI write response timeout at %h", addr);
    end

    write_resp = lite_rsp_o.b.resp;
    lite_req_i.b_ready = 1'b1;

    @(posedge clk_i);
    @(negedge clk_i);

    lite_req_i.b_ready = 1'b0;
  endtask

  task automatic axi_read(
    input  logic [ADDR_W-1:0] addr,
    output logic [REG_DW-1:0] data,
    output logic [1:0]        resp
  );
    int unsigned wait_cycles;

    wait_cycles = 0;

    @(negedge clk_i);
    lite_req_i.ar.addr  = addr;
    lite_req_i.ar_valid = 1'b1;
    lite_req_i.r_ready  = 1'b0;

    while (!lite_rsp_o.ar_ready) begin
      @(posedge clk_i);
      @(negedge clk_i);

      wait_cycles++;

      if (wait_cycles >= AXI_TIMEOUT_CYCLES)
        $fatal(1, "AXI read address timeout at %h", addr);
    end

    @(posedge clk_i);
    @(negedge clk_i);

    lite_req_i.ar_valid = 1'b0;
    wait_cycles = 0;

    while (!lite_rsp_o.r_valid) begin
      @(posedge clk_i);
      @(negedge clk_i);

      wait_cycles++;

      if (wait_cycles >= AXI_TIMEOUT_CYCLES)
        $fatal(1, "AXI read response timeout at %h", addr);
    end

    data = lite_rsp_o.r.data;
    resp = lite_rsp_o.r.resp;

    lite_req_i.r_ready = 1'b1;

    @(posedge clk_i);
    @(negedge clk_i);

    lite_req_i.r_ready = 1'b0;
  endtask

  initial begin
    checks     = 0;
    errors     = 0;
    lite_req_i = '0;
    rtc_tick_i = 1'b0;
    rst_ni     = 1'b0;

    repeat (4) @(negedge clk_i);

    check_bit("reset MSIP output", msip_o, 1'b0);
    check_bit("reset MTIP output", mtip_o, 1'b0);

    rst_ni = 1'b1;
    repeat (2) @(negedge clk_i);

    // Reset values and readable registers.
    axi_read(MSIP_OFFSET, read_data, read_resp);
    check_data("reset MSIP register", read_data, '0);
    check_resp("MSIP read response", read_resp, RESP_OKAY);

    axi_read(MTIME_OFFSET, read_data, read_resp);
    check_data("reset MTIME register", read_data, '0);
    check_resp("MTIME read response", read_resp, RESP_OKAY);

    axi_read(MTIMECMP_OFFSET, read_data, read_resp);
    check_data("reset MTIMECMP register", read_data, '1);
    check_resp("MTIMECMP read response", read_resp, RESP_OKAY);

    // Software interrupt set and clear.
    axi_write(MSIP_OFFSET, REG_DW'(1), '1);
    check_resp("MSIP set response", write_resp, RESP_OKAY);
    check_bit("MSIP asserts", msip_o, 1'b1);

    axi_read(MSIP_OFFSET, read_data, read_resp);
    check_data("MSIP reads set bit", read_data, REG_DW'(1));

    axi_write(MSIP_OFFSET, '0, '1);
    check_resp("MSIP clear response", write_resp, RESP_OKAY);
    check_bit("MSIP clears", msip_o, 1'b0);

    // Full-width MTIME and MTIMECMP accesses.
    axi_write(MTIME_OFFSET, MTIME_PATTERN, '1);
    check_resp("MTIME write response", write_resp, RESP_OKAY);

    axi_read(MTIME_OFFSET, read_data, read_resp);
    check_data("MTIME full-width write", read_data, MTIME_PATTERN);

    axi_write(MTIMECMP_OFFSET, MTIMECMP_PATTERN, '1);
    check_resp("MTIMECMP write response", write_resp, RESP_OKAY);

    axi_read(MTIMECMP_OFFSET, read_data, read_resp);
    check_data("MTIMECMP full-width write",
               read_data, MTIMECMP_PATTERN);

    // MTIME must not advance without rtc_tick_i.
    axi_write(MTIME_OFFSET, REG_DW'(100), '1);
    repeat (3) @(negedge clk_i);

    axi_read(MTIME_OFFSET, read_data, read_resp);
    check_data("MTIME holds without tick", read_data, REG_DW'(100));

    // A single RTC tick increments MTIME once.
    @(negedge clk_i);
    rtc_tick_i = 1'b1;
    @(posedge clk_i);
    @(negedge clk_i);
    rtc_tick_i = 1'b0;

    axi_read(MTIME_OFFSET, read_data, read_resp);
    check_data("MTIME increments on tick", read_data, REG_DW'(101));

    // MTIP asserts when MTIME reaches or exceeds MTIMECMP.
    axi_write(MTIMECMP_OFFSET, REG_DW'(200), '1);
    axi_write(MTIME_OFFSET, REG_DW'(199), '1);
    check_bit("MTIP below compare", mtip_o, 1'b0);

    axi_write(MTIME_OFFSET, REG_DW'(200), '1);
    check_bit("MTIP at compare", mtip_o, 1'b1);

    axi_write(MTIME_OFFSET, REG_DW'(201), '1);
    check_bit("MTIP above compare", mtip_o, 1'b1);

    axi_write(MTIMECMP_OFFSET, REG_DW'(500), '1);
    check_bit("MTIP clears above time", mtip_o, 1'b0);

    // A low-byte write changes only byte zero of MTIME.
    axi_write(MTIME_OFFSET, MTIME_PATTERN, '1);
    axi_write(MTIME_OFFSET, WRITE_PATTERN, REG_SW'(1));

    axi_read(MTIME_OFFSET, read_data, read_resp);
    check_data(
      "MTIME low-byte strobe",
      read_data,
      (MTIME_PATTERN & ~(REG_DW'(8'hFF))) |
      (WRITE_PATTERN & REG_DW'(8'hFF))
    );

    // A high-byte write changes only the most-significant byte of MTIMECMP.
    axi_write(MTIMECMP_OFFSET, MTIMECMP_PATTERN, '1);
    axi_write(
      MTIMECMP_OFFSET,
      WRITE_PATTERN,
      REG_SW'(1 << (REG_SW - 1))
    );

    axi_read(MTIMECMP_OFFSET, read_data, read_resp);
    check_data(
      "MTIMECMP high-byte strobe",
      read_data,
      (MTIMECMP_PATTERN & ~(REG_DW'(8'hFF) << ((REG_SW - 1) * BYTE_W))) |
      (WRITE_PATTERN & (REG_DW'(8'hFF) << ((REG_SW - 1) * BYTE_W)))
    );

    // Unmapped reads and writes should return slave errors.
    axi_read(UNMAPPED_OFFSET, read_data, read_resp);
    check_resp("unmapped read response", read_resp, RESP_SLVERR);
    check_data("unmapped read data", read_data, '0);

    axi_write(UNMAPPED_OFFSET, REG_DW'(1), '1);
    check_resp("unmapped write response", write_resp, RESP_SLVERR);

    if (errors == 0) begin
      $display("=== PASS : %0d checks ===", checks);
      $finish;
    end else begin
      $display("=== FAIL : %0d errors of %0d checks ===", errors, checks);
      $fatal(1, "tb_meds_s1_clint failed");
    end
  end

endmodule
