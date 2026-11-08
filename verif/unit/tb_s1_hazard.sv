// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// tb_s1_hazard : unit testbench for s1_hazard                       [WIP -- T-02]
// Description  :
// Random operand/writer combinations against a model that walks the writers
// youngest first (EX, EX/MEM, pending MEM/WB).
//
// Run:  make test-unit TB=s1_hazard
// =============================================================================

module tb_s1_hazard
  import s1_pkg::*;
;
  logic [REG_ADDR_W-1:0] rs1, rs2, ex_rd, mem_rd, wbp_rd;
  logic                  rs1_re, rs2_re, ex_wr, ex_load, mem_wr, mem_load, wbp_wr;
  logic                  fx1, fx2, fm1, fm2, stall;

  s1_hazard dut (
    .rs1_i (rs1), .rs2_i (rs2), .rs1_re_i (rs1_re), .rs2_re_i (rs2_re),
    .ex_wr_i (ex_wr), .ex_rd_i (ex_rd), .ex_load_i (ex_load),
    .mem_wr_i (mem_wr), .mem_rd_i (mem_rd), .mem_load_i (mem_load),
    .wbp_wr_i (wbp_wr), .wbp_rd_i (wbp_rd),
    .from_ex_rs1_o (fx1), .from_ex_rs2_o (fx2),
    .from_mem_rs1_o (fm1), .from_mem_rs2_o (fm2),
    .stall_o (stall)
  );

  int unsigned checks = 0, errors = 0;
  int unsigned n_ex, n_mem, n_stall;

  // 0 = register file, 1 = EX forward, 2 = EX/MEM value, 3 = stall
  function automatic int unsigned model(input logic [REG_ADDR_W-1:0] r, input logic re);
    if (!re || r == '0) return 0;
    if (ex_wr  && ex_rd  == r) return ex_load  ? 3 : 1;
    if (mem_wr && mem_rd == r) return mem_load ? 3 : 2;
    if (wbp_wr && wbp_rd == r) return 3;
    return 0;
  endfunction

  task automatic check(input bit ok, input string what);
    checks++;
    if (!ok) begin
      errors++;
      if (errors <= 20) $display("  FAIL %s", what);
    end
  endtask

  initial begin
    int unsigned m1, m2;
    $display("=== tb_s1_hazard ===");
    for (int unsigned n = 0; n < 200000; n++) begin
      // few registers so that collisions are common
      rs1 = 5'($urandom_range(5)); rs2 = 5'($urandom_range(5));
      ex_rd = 5'($urandom_range(5)); mem_rd = 5'($urandom_range(5)); wbp_rd = 5'($urandom_range(5));
      {rs1_re, rs2_re, ex_wr, ex_load, mem_wr, mem_load, wbp_wr} = 7'($urandom);
      #1;
      m1 = model(rs1, rs1_re);
      m2 = model(rs2, rs2_re);
      check(fx1 == (m1 == 1) && fm1 == (m1 == 2), $sformatf("rs1 select, model %0d", m1));
      check(fx2 == (m2 == 1) && fm2 == (m2 == 2), $sformatf("rs2 select, model %0d", m2));
      check(stall == (m1 == 3 || m2 == 3), $sformatf("stall, model %0d/%0d", m1, m2));
      if (m1 == 1 || m2 == 1) n_ex++;
      if (m1 == 2 || m2 == 2) n_mem++;
      if (m1 == 3 || m2 == 3) n_stall++;
    end
    $display("  coverage: %0d EX forwards, %0d EX/MEM forwards, %0d stalls", n_ex, n_mem, n_stall);
    if (errors == 0) $display("=== PASS : %0d checks ===", checks);
    else             $display("=== FAIL : %0d errors of %0d checks ===", errors, checks);
    if (errors != 0) $fatal(1, "tb_s1_hazard failed");
    $finish;
  end
endmodule
