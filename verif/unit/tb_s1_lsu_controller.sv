// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// tb_s1_lsu_controller : LSU controller and datapath testbench       [WIP -- R-02]
//
// The reference model treats a MEM-REQ response as eight little-endian bytes.
// It does not reproduce the DUT's shifts, masks, or controller states.
// =============================================================================

module tb_s1_lsu_controller
  import s1_pkg::*;
;

  localparam int unsigned W = 64;

  logic clk_i;
  logic rst_ni;
  logic lsu_valid_i;
  logic lsu_ready_o;
  logic [W-1:0] lsu_addr_i;
  logic [W-1:0] lsu_wdata_i;
  logic [2:0] lsu_size_i;
  logic lsu_write_i;
  logic lsu_unsigned_i;
  priv_lvl_e lsu_mode_i;
  logic [3:0] lsu_id_i;

  logic check_valid_o;
  logic [W-1:0] check_addr_o;
  logic [2:0] check_size_o;
  logic check_write_o;
  priv_lvl_e check_mode_o;
  logic pma_allow_i;
  logic [5:0] pma_fault_code_i;

  logic mem_req_valid_o;
  logic mem_req_ready_i;
  mem_req_t mem_req_o;
  logic mem_rsp_valid_i;
  logic mem_rsp_ready_o;
  mem_rsp_t mem_rsp_i;

  logic lsu_resp_valid_o;
  logic lsu_resp_ready_i;
  logic [W-1:0] lsu_rdata_o;
  logic lsu_fault_o;
  logic [5:0] lsu_fault_code_o;
  logic [W-1:0] lsu_fault_addr_o;

  int unsigned checks = 0;
  int unsigned errors = 0;

  s1_lsu_controller dut (
    .clk_i                 (clk_i),
    .rst_ni                (rst_ni),
    .lsu_valid_i           (lsu_valid_i),
    .lsu_ready_o           (lsu_ready_o),
    .lsu_addr_i            (lsu_addr_i),
    .lsu_wdata_i           (lsu_wdata_i),
    .lsu_size_i            (lsu_size_i),
    .lsu_write_i           (lsu_write_i),
    .lsu_unsigned_i        (lsu_unsigned_i),
    .lsu_mode_i            (lsu_mode_i),
    .lsu_id_i              (lsu_id_i),
    .check_valid_o         (check_valid_o),
    .check_addr_o          (check_addr_o),
    .check_size_o          (check_size_o),
    .check_write_o         (check_write_o),
    .check_mode_o          (check_mode_o),
    .pma_allow_i           (pma_allow_i),
    .pma_fault_code_i      (pma_fault_code_i),
    .mem_req_valid_o       (mem_req_valid_o),
    .mem_req_ready_i       (mem_req_ready_i),
    .mem_req_o             (mem_req_o),
    .mem_rsp_valid_i       (mem_rsp_valid_i),
    .mem_rsp_ready_o       (mem_rsp_ready_o),
    .mem_rsp_i             (mem_rsp_i),
    .lsu_resp_valid_o      (lsu_resp_valid_o),
    .lsu_resp_ready_i      (lsu_resp_ready_i),
    .lsu_rdata_o           (lsu_rdata_o),
    .lsu_fault_o           (lsu_fault_o),
    .lsu_fault_code_o      (lsu_fault_code_o),
    .lsu_fault_addr_o      (lsu_fault_addr_o)
  );

  always #5 clk_i <= ~clk_i;

  task automatic check(input string name, input logic [W-1:0] got,
                       input logic [W-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("  FAIL %-32s got=0x%016h exp=0x%016h", name, got, exp);
    end
  endtask

  task automatic check1(input string name, input logic got, input logic exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("  FAIL %-32s got=%0d exp=%0d", name, got, exp);
    end
  endtask

  task automatic reset_dut();
    rst_ni = 1'b0;
    lsu_valid_i = 1'b0;
    lsu_addr_i = '0;
    lsu_wdata_i = '0;
    lsu_size_i = '0;
    lsu_write_i = 1'b0;
    lsu_unsigned_i = 1'b0;
    lsu_mode_i = PRIV_M;
    lsu_id_i = '0;
    pma_allow_i = 1'b1;
    pma_fault_code_i = '0;
    mem_req_ready_i = 1'b0;
    mem_rsp_valid_i = 1'b0;
    mem_rsp_i = '0;
    lsu_resp_ready_i = 1'b0;
    repeat (2) @(posedge clk_i);
    rst_ni = 1'b1;
    @(posedge clk_i);
  endtask

  task automatic issue(input logic [W-1:0] addr,
                       input logic [W-1:0] data,
                       input logic [2:0] size,
                       input logic is_write,
                       input logic is_unsigned,
                       input logic [3:0] id);
    @(negedge clk_i);
    lsu_addr_i = addr;
    lsu_wdata_i = data;
    lsu_size_i = size;
    lsu_write_i = is_write;
    lsu_unsigned_i = is_unsigned;
    lsu_id_i = id;
    lsu_valid_i = 1'b1;
    while (!lsu_ready_o) @(negedge clk_i);
    @(negedge clk_i);
    lsu_valid_i = 1'b0;
  endtask

  task automatic complete_response(input logic [W-1:0] response_data,
                                   input logic response_error,
                                   input logic [1:0] response_error_code,
                                   input logic [3:0] response_id,
                                   input logic [W-1:0] expected_data,
                                   input logic expected_fault,
                                   input logic [5:0] expected_code);
    while (!mem_rsp_ready_o) @(negedge clk_i);
    @(negedge clk_i);
    mem_rsp_i.rdata = response_data;
    mem_rsp_i.err = response_error;
    mem_rsp_i.errcode = response_error_code;
    mem_rsp_i.id = response_id;
    mem_rsp_valid_i = 1'b1;
    while (!mem_rsp_ready_o) @(negedge clk_i);
    @(posedge clk_i);
    @(negedge clk_i);
    mem_rsp_valid_i = 1'b0;

    while (!lsu_resp_valid_o) @(negedge clk_i);
    check1("response fault", lsu_fault_o, expected_fault);
    check("response data", lsu_rdata_o, expected_data);
    check("response fault code", lsu_fault_code_o, expected_code);
    check("response fault address", lsu_fault_addr_o, lsu_addr_i);
    lsu_resp_ready_i = 1'b1;
    @(posedge clk_i);
    @(negedge clk_i);
    lsu_resp_ready_i = 1'b0;
  endtask

  task automatic complete_fault(input logic [W-1:0] expected_addr,
                                input logic [5:0] expected_code);
    while (!lsu_resp_valid_o) @(negedge clk_i);
    check1("fault response", lsu_fault_o, 1'b1);
    check("fault data", lsu_rdata_o, '0);
    check("fault code", lsu_fault_code_o, expected_code);
    check("fault address", lsu_fault_addr_o, expected_addr);
    lsu_resp_ready_i = 1'b1;
    @(posedge clk_i);
    @(negedge clk_i);
    lsu_resp_ready_i = 1'b0;
  endtask

  function automatic logic [7:0] cal_expected_be(input logic [2:0] size,
                                                 input logic [2:0] offset);
    cal_expected_be = '0;

    case (size)
        3'd0: cal_expected_be = 8'h01 << offset;
        3'd1: cal_expected_be = 8'h03 << offset;
        3'd2: cal_expected_be = 8'h0f << offset;
        3'd3: cal_expected_be = 8'hff;
        default: cal_expected_be = '0;
    endcase
endfunction

  task automatic expect_request(input logic [W-1:0] expected_addr,
                                input logic [W-1:0] expected_wdata,
                                input logic [7:0] expected_be,
                                input logic expected_write,
                                input logic [2:0] expected_size,
                                input logic [3:0] expected_id);
    while (!mem_req_valid_o) @(negedge clk_i);
    check("request address", mem_req_o.addr, expected_addr);
    check("request write data", mem_req_o.wdata, expected_wdata);
    check("request byte enable", mem_req_o.be, expected_be);
    check1("request write", mem_req_o.we, expected_write);
    check("request size", mem_req_o.size, expected_size);
    check("request id", mem_req_o.id, expected_id);
    mem_req_ready_i = 1'b1;
    @(posedge clk_i);
    @(negedge clk_i);
    mem_req_ready_i = 1'b0;
  endtask

  task automatic legal_load(input string name,
                            input logic [W-1:0] addr,
                            input logic [2:0] size,
                            input logic is_unsigned,
                            input logic [W-1:0] response_data,
                            input logic [W-1:0] expected_data);
    issue(addr, '0, size, 1'b0, is_unsigned, 4'h1);
    expect_request(addr, '0, cal_expected_be(size, addr[2:0]), 1'b0, size, 4'h1);
    complete_response(response_data, 1'b0, '0, 4'h1, expected_data, 1'b0, 6'd0);
    $display("  PASS %s", name);
  endtask

  initial begin
    clk_i = 1'b0;
    reset_dut();

    legal_load("LB", 64'd0, 3'd0, 1'b0, 64'h1122334455667788, 64'hffffffffffffff88);
    legal_load("LBU", 64'd1, 3'd0, 1'b1, 64'h1122334455667788, 64'h0000000000000077);
    legal_load("LH", 64'd2, 3'd1, 1'b0, 64'h1122334455667788, 64'h0000000000005566);
    legal_load("LHU", 64'd2, 3'd1, 1'b1, 64'h1122334455667788, 64'h0000000000005566);
    legal_load("LW", 64'd4, 3'd2, 1'b0, 64'h1122334455667788, 64'h0000000011223344);
    legal_load("LWU", 64'd4, 3'd2, 1'b1, 64'h1122334455667788, 64'h0000000011223344);
    legal_load("LD", 64'd0, 3'd3, 1'b0, 64'h1122334455667788, 64'h1122334455667788);

    legal_load("LH negative sign extension", 64'd0, 3'd1, 1'b0,
           64'h0000000000008001, 64'hffffffffffff8001);
    legal_load("LW negative sign extension", 64'd0, 3'd2, 1'b0,
           64'h0000000080000001, 64'hffffffff80000001);

    issue(64'd3, 64'hFFFF_FFFF_FF00_00AA, 3'd0, 1'b1, 1'b0, 4'h2);
    expect_request(64'd3, 64'h0000_0000_AA00_0000, 8'b00001000, 1'b1, 3'd0, 4'h2);
    complete_response('0, 1'b0, '0, 4'h2, '0, 1'b0, 6'd0);

    issue(64'd2, 64'hFFFF_0000_0000_BEEF, 3'd1, 1'b1, 1'b0, 4'h3);
    expect_request(64'd2, 64'h0000_0000_BEEF_0000, 8'b00001100, 1'b1, 3'd1, 4'h3);
    complete_response('0, 1'b0, '0, 4'h3, '0, 1'b0, 6'd0);

    issue(64'd0, 64'hFFFF_FFFF_DEAD_BEEF, 3'd2, 1'b1, 1'b0, 4'ha);
    expect_request(64'd0, 64'h0000_0000_DEAD_BEEF, 8'b00001111, 1'b1, 3'd2, 4'ha);
    complete_response('0, 1'b0, '0, 4'ha, '0, 1'b0, 6'd0);

    issue(64'd0, 64'hFFFF_FFFF_DEAD_BEEF, 3'd3, 1'b1, 1'b0, 4'hb);
    expect_request(64'd0, 64'hFFFF_FFFF_DEAD_BEEF, 8'b11111111, 1'b1, 3'd3, 4'hb);
    complete_response('0, 1'b0, '0, 4'hb, '0, 1'b0, 6'd0);

    issue(64'd1, 64'd0, 3'd1, 1'b0, 1'b0, 4'h4);
    complete_fault(64'd1, 6'd4);

    issue(64'd2, 64'd0, 3'd2, 1'b0, 1'b0, 4'h5);
    complete_fault(64'd2, 6'd4);

    issue(64'd4, 64'd0, 3'd3, 1'b0, 1'b0, 4'h6);
    complete_fault(64'd4, 6'd4);

    issue(64'd0, 64'd0, 3'd4, 1'b0, 1'b0, 4'h7);
    complete_fault(64'd0, 6'd2);

    pma_allow_i = 1'b0;
    pma_fault_code_i = 6'd7;
    issue(64'd0, 64'd0, 3'd0, 1'b1, 1'b0, 4'hd);
    repeat (2) begin
      @(posedge clk_i);
      check1("PMA deny emits no request", mem_req_valid_o, 1'b0);
    end
    complete_fault(64'd0, 6'd7);
    pma_allow_i = 1'b1;
    pma_fault_code_i = '0;

    issue(64'd0, 64'd0, 3'd0, 1'b0, 1'b0, 4'h8);
    while (!mem_req_valid_o) @(negedge clk_i);
    mem_req_ready_i = 1'b0;
    repeat (2) begin
      @(posedge clk_i);
      check1("request held under backpressure", mem_req_valid_o, 1'b1);
    end
    mem_req_ready_i = 1'b1;
    @(posedge clk_i);
    @(negedge clk_i);
    mem_req_ready_i = 1'b0;
    complete_response(64'h0000000000000042, 1'b0, '0, 4'h8,
                      64'h0000000000000042, 1'b0, 6'd0);

    issue(64'd0, 64'd0, 3'd0, 1'b0, 1'b0, 4'ha);
    expect_request(64'd0, '0, cal_expected_be(3'd0, 3'd0), 1'b0, 3'd0, 4'ha);
    mem_rsp_i.rdata = 64'hdead_beef;
    mem_rsp_i.err = 1'b0;
    mem_rsp_i.errcode = '0;
    mem_rsp_i.id = 4'hb;
    mem_rsp_valid_i = 1'b1;
    @(negedge clk_i);
    check1("mismatched response not ready", mem_rsp_ready_o, 1'b0);
    @(posedge clk_i);
    check1("mismatched response remains pending", lsu_resp_valid_o, 1'b0);
    mem_rsp_i.id = 4'ha;
    @(posedge clk_i);
    check1("matching response completes", lsu_resp_valid_o, 1'b1);
    @(negedge clk_i);
    mem_rsp_valid_i = 1'b0;
    while (!lsu_resp_valid_o) @(negedge clk_i);
    check1("matching response has no fault", lsu_fault_o, 1'b0);
    check("matching response data", lsu_rdata_o, 64'hffffffffffffffef);
    lsu_resp_ready_i = 1'b1;
    @(posedge clk_i);
    @(negedge clk_i);
    lsu_resp_ready_i = 1'b0;

    issue(64'd0, 64'd0, 3'd0, 1'b0, 1'b0, 4'h9);
    expect_request(64'd0, '0, cal_expected_be(3'd0, 3'd0), 1'b0, 3'd0, 4'h9);
    mem_rsp_i.rdata = 64'd0;
    mem_rsp_i.err = 1'b1;
    mem_rsp_i.errcode = 2'd2;
    mem_rsp_i.id = 4'h9;
    mem_rsp_valid_i = 1'b1;
    @(posedge clk_i);
    @(negedge clk_i);
    mem_rsp_valid_i = 1'b0;
    while (!lsu_resp_valid_o) @(negedge clk_i);
    check1("bus error fault", lsu_fault_o, 1'b1);
    check("bus error code", lsu_fault_code_o, 64'd5);
    lsu_resp_ready_i = 1'b1;
    @(posedge clk_i);

    if (errors == 0) begin
      $display("=== PASS : %0d checks ===", checks);
      $finish;
    end else begin
      $display("=== FAIL : %0d errors of %0d checks ===", errors, checks);
      $fatal(1, "tb_s1_lsu_controller failed");
    end
  end

endmodule
