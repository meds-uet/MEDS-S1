// =============================================================================
// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// Author(s)    : Ammarah Wakeel (ammarahwakeel9@gmail.com) (Sep,2026)
// Modified By  :
//
// tb_s1_regfile : unit testbench for s1_regfile                     [WIP -- T-02]
// Description  :
// Directed checks for x0 semantics, write/read timing (including the
// same-cycle write-read bypass), and every forwarding-source priority
// combination (SPEC 8.1), followed by a randomised soak of writes/reads
// against a behavioural shadow register file.
//
// Run:  make test-unit TB=s1_regfile
// =============================================================================

module tb_s1_regfile
  import s1_pkg::*;
;

  logic                  clk, rst_n;
  logic [REG_ADDR_W-1:0] rs1_addr, rs2_addr;
  logic [XLEN-1:0]       rs1_val,  rs2_val;
  fwd_src_e              rs1_fwd,  rs2_fwd;
  logic                  rd_we;
  logic [REG_ADDR_W-1:0] rd_addr;
  logic [XLEN-1:0]       rd_wdata;
  logic                  ex_valid,  ex_rd_we;
  logic [REG_ADDR_W-1:0] ex_rd;
  logic                  mem_valid, mem_rd_we;
  logic [REG_ADDR_W-1:0] mem_rd;
  logic                  cb_rs1_hit, cb_rs2_hit;

  s1_regfile dut (
    .clk_i        (clk),
    .rst_ni       (rst_n),
    .rs1_addr_i   (rs1_addr),
    .rs2_addr_i   (rs2_addr),
    .rs1_val_o    (rs1_val),
    .rs2_val_o    (rs2_val),
    .rs1_fwd_o    (rs1_fwd),
    .rs2_fwd_o    (rs2_fwd),
    .rd_we_i      (rd_we),
    .rd_addr_i    (rd_addr),
    .rd_wdata_i   (rd_wdata),
    .ex_valid_i   (ex_valid),
    .ex_rd_i      (ex_rd),
    .ex_rd_we_i   (ex_rd_we),
    .mem_valid_i  (mem_valid),
    .mem_rd_i     (mem_rd),
    .mem_rd_we_i  (mem_rd_we),
    .cb_rs1_hit_i (cb_rs1_hit),
    .cb_rs2_hit_i (cb_rs2_hit)
  );

  int unsigned checks = 0;
  int unsigned errors = 0;
  string       cur_test;

  task automatic check_eq(string what, logic [63:0] got, logic [63:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL [%0s] %0s got=%0h exp=%0h", cur_test, what, got, exp);
    end
  endtask

  task automatic tick();
    clk = 1'b1; #1;
    clk = 1'b0; #1;
  endtask

  task automatic do_reset();
    rs1_addr = '0; rs2_addr = '0;
    rd_we = 1'b0; rd_addr = '0; rd_wdata = '0;
    ex_valid = 1'b0; ex_rd = '0; ex_rd_we = 1'b0;
    mem_valid = 1'b0; mem_rd = '0; mem_rd_we = 1'b0;
    cb_rs1_hit = 1'b0; cb_rs2_hit = 1'b0;
    clk = 1'b0;
    // Two-state sim: a reset low from time zero has no negedge; make one.
    rst_n = 1'b1; #1; rst_n = 1'b0; #1; clk = 1'b1; #1; clk = 1'b0; #1; rst_n = 1'b1; #1;
  endtask

  initial begin
    $display("=== tb_s1_regfile : XLEN=%0d REG_ADDR_W=%0d ===", XLEN, REG_ADDR_W);
    do_reset();

    // ==========================================================================
    // x0 semantics
    // ==========================================================================
    cur_test = "x0-read-is-zero";
    rs1_addr = 5'd0; rs2_addr = 5'd0; #1;
    check_eq("rs1_val", rs1_val, '0);
    check_eq("rs2_val", rs2_val, '0);
    check_eq("rs1_fwd", rs1_fwd, FWD_RF);
    check_eq("rs2_fwd", rs2_fwd, FWD_RF);

    cur_test = "x0-write-discarded";
    rd_we = 1'b1; rd_addr = 5'd0; rd_wdata = 64'hDEAD_BEEF_0000_0001; tick();
    rd_we = 1'b0;
    rs1_addr = 5'd0; #1;
    check_eq("x0 stays zero after write", rs1_val, '0);

    // ==========================================================================
    // Basic write / read across a cycle boundary, and reset
    // ==========================================================================
    cur_test = "write-then-read-next-cycle";
    rd_we = 1'b1; rd_addr = 5'd5; rd_wdata = 64'hCAFE_BABE_0000_0005; tick();
    rd_we = 1'b0;
    rs1_addr = 5'd5; #1;
    check_eq("rs1_val", rs1_val, 64'hCAFE_BABE_0000_0005);

    cur_test = "reset-clears";
    do_reset();
    rs1_addr = 5'd5; #1;
    check_eq("rs1_val after reset", rs1_val, '0);

    // ==========================================================================
    // Same-cycle write-read bypass
    // ==========================================================================
    cur_test = "same-cycle-write-read-bypass";
    rd_we = 1'b1; rd_addr = 5'd7; rd_wdata = 64'h1111_2222_3333_4444;
    rs1_addr = 5'd7; rs2_addr = 5'd7;
    #1;
    check_eq("rs1_val sees same-cycle write", rs1_val, 64'h1111_2222_3333_4444);
    check_eq("rs2_val sees same-cycle write", rs2_val, 64'h1111_2222_3333_4444);
    tick();
    rd_we = 1'b0;

    cur_test = "same-cycle-write-x0-still-zero";
    rd_we = 1'b1; rd_addr = 5'd0; rd_wdata = 64'hFFFF_FFFF_FFFF_FFFF;
    rs1_addr = 5'd0;
    #1;
    check_eq("x0 ignores same-cycle write bypass too", rs1_val, '0);
    tick();
    rd_we = 1'b0;

    // ==========================================================================
    // Forwarding-source selection: no hazard
    // ==========================================================================
    cur_test = "no-hazard-selects-rf";
    rs1_addr = 5'd10; rs2_addr = 5'd11;
    ex_valid = 1'b0; ex_rd = '0; ex_rd_we = 1'b0;
    mem_valid = 1'b0; mem_rd = '0; mem_rd_we = 1'b0;
    cb_rs1_hit = 1'b0; cb_rs2_hit = 1'b0;
    #1;
    check_eq("rs1_fwd", rs1_fwd, FWD_RF);
    check_eq("rs2_fwd", rs2_fwd, FWD_RF);

    // ==========================================================================
    // EX/MEM source
    // ==========================================================================
    cur_test = "ex-hazard-rs1";
    rs1_addr = 5'd12; rs2_addr = 5'd13;
    ex_valid = 1'b1; ex_rd = 5'd12; ex_rd_we = 1'b1;
    #1;
    check_eq("rs1_fwd==EXMEM", rs1_fwd, FWD_EXMEM);
    check_eq("rs2_fwd==RF (no match)", rs2_fwd, FWD_RF);

    cur_test = "ex-hazard-ignored-when-not-valid";
    ex_valid = 1'b0;
    #1;
    check_eq("falls through when ex not valid", rs1_fwd, FWD_RF);

    cur_test = "ex-hazard-ignored-when-not-rd_we";
    ex_valid = 1'b1; ex_rd_we = 1'b0;
    #1;
    check_eq("falls through when ex_rd_we=0", rs1_fwd, FWD_RF);

    cur_test = "ex-hazard-x0-is-not-a-hazard";
    // s1_decode.sv does not special-case x0: rd_we can be 1 for rd==x0. A
    // read of x0 must never forward regardless.
    ex_valid = 1'b1; ex_rd = 5'd0; ex_rd_we = 1'b1;
    rs1_addr = 5'd0;
    #1;
    check_eq("x0 read never forwards", rs1_fwd, FWD_RF);
    check_eq("x0 read value stays zero", rs1_val, '0);

    // ==========================================================================
    // MEM/WB source
    // ==========================================================================
    cur_test = "mem-hazard-rs2";
    ex_valid = 1'b0; ex_rd = '0; ex_rd_we = 1'b0;
    rs1_addr = 5'd14; rs2_addr = 5'd15;
    mem_valid = 1'b1; mem_rd = 5'd15; mem_rd_we = 1'b1;
    #1;
    check_eq("rs1_fwd==RF", rs1_fwd, FWD_RF);
    check_eq("rs2_fwd==MEMWB", rs2_fwd, FWD_MEMWB);

    cur_test = "mem-hazard-ignored-when-not-valid";
    mem_valid = 1'b0;
    #1;
    check_eq("falls through when mem not valid", rs2_fwd, FWD_RF);

    // ==========================================================================
    // CB source
    // ==========================================================================
    cur_test = "cb-hazard-rs1";
    mem_valid = 1'b0; mem_rd = '0; mem_rd_we = 1'b0;
    rs1_addr = 5'd16; rs2_addr = 5'd17;
    cb_rs1_hit = 1'b1; cb_rs2_hit = 1'b0;
    #1;
    check_eq("rs1_fwd==CB", rs1_fwd, FWD_CB);
    check_eq("rs2_fwd==RF", rs2_fwd, FWD_RF);

    // ==========================================================================
    // Priority ordering: EX/MEM > MEM/WB > CB > RF
    // ==========================================================================
    cur_test = "priority-ex-over-mem-and-cb";
    rs1_addr = 5'd18;
    ex_valid = 1'b1; ex_rd = 5'd18; ex_rd_we = 1'b1;
    mem_valid = 1'b1; mem_rd = 5'd18; mem_rd_we = 1'b1;
    cb_rs1_hit = 1'b1;
    #1;
    check_eq("EX wins over MEM and CB", rs1_fwd, FWD_EXMEM);

    cur_test = "priority-mem-over-cb";
    ex_valid = 1'b0; ex_rd = '0; ex_rd_we = 1'b0;
    #1;
    check_eq("MEM wins over CB", rs1_fwd, FWD_MEMWB);

    cur_test = "priority-cb-as-last-resort";
    mem_valid = 1'b0; mem_rd = '0; mem_rd_we = 1'b0;
    #1;
    check_eq("CB used when nothing closer hits", rs1_fwd, FWD_CB);

    // ==========================================================================
    // rs1 and rs2 resolve independently, from different sources at once
    // ==========================================================================
    cur_test = "independent-rs1-rs2-sources";
    rs1_addr = 5'd20; rs2_addr = 5'd21;
    ex_valid = 1'b1; ex_rd = 5'd20; ex_rd_we = 1'b1;
    mem_valid = 1'b1; mem_rd = 5'd21; mem_rd_we = 1'b1;
    cb_rs1_hit = 1'b0; cb_rs2_hit = 1'b0;
    #1;
    check_eq("rs1 forwards from EX",  rs1_fwd, FWD_EXMEM);
    check_eq("rs2 forwards from MEM", rs2_fwd, FWD_MEMWB);

    // ==========================================================================
    // Random soak: shadow register file vs DUT, random writes and reads.
    // fwd_src_e priority is already covered directly above; this soak targets
    // rs1_val/rs2_val (write timing and the write-read bypass) under
    // unpredictable address collisions.
    // ==========================================================================
    begin
      logic [XLEN-1:0]       shadow [32];
      logic [REG_ADDR_W-1:0] a1, a2, wa;
      logic [XLEN-1:0]       wd;
      int unsigned            i;

      do_reset();   // earlier directed tests left non-zero values (x5, x7, ...)
      for (i = 0; i < 32; i++) shadow[i] = '0;
      cur_test = "random-soak";

      for (i = 0; i < 5000; i++) begin
        a1 = REG_ADDR_W'($urandom_range(31, 0));
        a2 = REG_ADDR_W'($urandom_range(31, 0));
        wa = REG_ADDR_W'($urandom_range(31, 0));
        wd = {$urandom(), $urandom()};
        rd_we    = 1'($urandom_range(1, 0));
        rd_addr  = wa;
        rd_wdata = wd;
        rs1_addr = a1;
        rs2_addr = a2;
        #1;
        check_eq("shadow rs1", rs1_val,
                 (a1 == '0) ? 64'h0 : ((rd_we && wa == a1) ? wd : shadow[a1]));
        check_eq("shadow rs2", rs2_val,
                 (a2 == '0) ? 64'h0 : ((rd_we && wa == a2) ? wd : shadow[a2]));
        tick();
        if (rd_we && wa != '0) shadow[wa] = wd;
      end
    end

    $display("---------------------------------------------------------------");
    if (errors == 0) begin
      $display("=== PASS : %0d checks ===", checks);
      $finish;
    end else begin
      $display("=== FAIL : %0d errors of %0d checks ===", errors, checks);
      $fatal(1, "tb_s1_regfile failed");
    end
  end

endmodule
