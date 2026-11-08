// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// tb_s1_id : unit testbench for s1_id                               [WIP -- T-02]
// Description  :
// Directed cases for operand resolve, forwarding select, load-use stall,
// CSR/SYSTEM serialisation, flush, mispredict block and ID/EX back-pressure.
// Decode itself is covered by tb_s1_decode.
//
// Run:  make test-unit TB=s1_id
// =============================================================================

module tb_s1_id
  import s1_pkg::*;
;
  logic            clk = 1'b0, rst_n = 1'b0;
  logic            flush, redirect;
  logic            f_valid, f_ready;
  fetch_rsp_t      f_rsp;
  logic [XLEN-1:0] rs1_data, rs2_data;
  logic            em_valid;
  ex_mem_t         em;
  logic            wp_pend, wp_we;
  logic [REG_ADDR_W-1:0] wp_rd;
  logic            busy;
  logic            ex_valid, ex_ready;
  id_ex_t          ex;
  logic            p_lu, p_hz;

  s1_id dut (
    .clk_i (clk), .rst_ni (rst_n), .flush_i (flush), .ex_redirect_valid_i (redirect),
    .fetch_rsp_valid_i (f_valid), .fetch_rsp_ready_o (f_ready), .fetch_rsp_i (f_rsp),
    .rs1_data_i (rs1_data), .rs2_data_i (rs2_data),
    .exmem_valid_i (em_valid), .exmem_i (em),
    .memwb_pend_i (wp_pend), .memwb_rd_i (wp_rd), .memwb_rd_we_i (wp_we),
    .downstream_busy_i (busy),
    .ex_valid_o (ex_valid), .ex_ready_i (ex_ready), .ex_o (ex),
    .perf_load_use_o (p_lu), .perf_hazard_stall_o (p_hz)
  );

  int unsigned checks = 0, errors = 0, cycle = 0;

  task automatic check(input bit ok, input string what);
    checks++;
    if (!ok) begin
      errors++;
      if (errors <= 30) $display("  FAIL @%0d %s", cycle, what);
    end
  endtask

  function automatic logic [31:0] addi(input int rd, input int rs1, input int imm);
    return {imm[11:0], 5'(rs1), 3'b000, 5'(rd), 7'h13};
  endfunction
  function automatic logic [31:0] add(input int rd, input int rs1, input int rs2);
    return {7'b0, 5'(rs2), 5'(rs1), 3'b000, 5'(rd), 7'h33};
  endfunction
  function automatic logic [31:0] ld(input int rd, input int rs1);
    return {12'b0, 5'(rs1), 3'b011, 5'(rd), 7'h03};
  endfunction
  function automatic logic [31:0] csrrw(input int rd, input int rs1);
    return {12'h340, 5'(rs1), 3'b001, 5'(rd), 7'h73};
  endfunction

  task automatic tick();
    clk = 1'b1; #1; clk = 1'b0; #1; cycle++;
  endtask

  task automatic idle_inputs();
    flush = 0; redirect = 0; f_valid = 0; f_rsp = '0; rs1_data = '0; rs2_data = '0;
    em_valid = 0; em = '0; em.amo_op = AMO_NONE; wp_pend = 0; wp_we = 0; wp_rd = '0;
    busy = 0; ex_ready = 1;
  endtask

  task automatic present(input logic [31:0] w, input logic [XLEN-1:0] pc = 64'h1000);
    f_valid = 1; f_rsp = '0; f_rsp.pc = pc; f_rsp.instr = w; f_rsp.instr_raw = w;
    #1;
  endtask

  // Issue one instruction and clear the inputs; ID/EX then holds it.
  task automatic issue(input logic [31:0] w);
    present(w);
    check(f_ready, "issue: ready");
    tick();
    f_valid = 0; #1;
  endtask

  initial begin
    idle_inputs();
    #1; rst_n = 1'b0; tick(); rst_n = 1'b1; #1;
    $display("=== tb_s1_id ===");

    // Plain flow: addi x1, x2, 3 with x2 from the register file.
    rs1_data = 64'h22; rs2_data = 64'h33;
    issue(addi(1, 2, 3));
    check(ex_valid, "addi: ex_valid");
    check(ex.op.rd == 1 && ex.op.rs1 == 2 && ex.op.rd_we, "addi: decoded");
    check(ex.rs1_val == 64'h22 && ex.rs1_fwd == FWD_RF, "addi: operand from regfile");

    // add x4, x1, x1 right behind it: producer in EX, so FWD_EXMEM on both.
    present(add(4, 1, 1));
    check(f_ready, "dependent add: not stalled");
    check(!p_hz, "dependent add: no hazard event");
    tick();
    f_valid = 0; #1;
    check(ex.rs1_fwd == FWD_EXMEM && ex.rs2_fwd == FWD_EXMEM, "dependent add: EX forward select");

    // Producer in EX/MEM, an ALU op: value taken from exmem.result.
    idle_inputs(); tick();
    em_valid = 1; em.rd = 5; em.rd_we = 1; em.result = 64'hABCD; #1;
    issue(addi(6, 5, 1));
    check(ex.rs1_val == 64'hABCD && ex.rs1_fwd == FWD_RF, "EX/MEM bypass");

    // Load in EX: consumer stalls, and the event fires.
    idle_inputs(); tick();
    issue(ld(7, 2));
    present(addi(8, 7, 0));
    check(!f_ready && p_lu && p_hz, "load in EX: stall");
    ex_ready = 0; tick(); #1;
    check(!f_ready && p_lu, "load in EX: still stalled while load sits in EX");
    // Load moves on to EX/MEM, still a load.
    ex_ready = 1; tick(); #1;       // the load leaves EX for EX/MEM
    em_valid = 1; em.rd = 7; em.rd_we = 1; em.is_load = 1; #1;
    check(!f_ready, "load in EX/MEM: stall");
    // Load pending in MEM/WB.
    em_valid = 0; em.is_load = 0; wp_pend = 1; wp_we = 1; wp_rd = 7; #1;
    check(!f_ready, "load pending in MEM/WB: stall");
    // Load completed: the register file has it.
    wp_pend = 0; #1;
    check(f_ready, "load done: released");
    tick(); f_valid = 0; #1;
    check(ex_valid && ex.op.rd == 8, "consumer issued after load");

    // AMO in EX/MEM is also a load-type producer.
    idle_inputs(); tick();
    em_valid = 1; em.rd = 9; em.rd_we = 1; em.amo_op = AMO_ADD; #1;
    present(addi(10, 9, 0));
    check(!f_ready, "AMO in EX/MEM: stall");
    idle_inputs(); tick();

    // x0 never creates a hazard.
    em_valid = 1; em.rd = 0; em.rd_we = 1; em.is_load = 1; #1;
    present(addi(1, 0, 0));
    check(f_ready, "x0 reader not stalled by x0 writer");
    idle_inputs(); tick();

    // CSR serialisation: waits for downstream, and for ID/EX to empty.
    busy = 1; present(csrrw(0, 1));
    check(!f_ready && p_hz && !p_lu, "csr: waits for downstream");
    busy = 0; #1;
    check(f_ready, "csr: issues on an empty pipeline");
    tick(); f_valid = 0; #1;
    check(ex_valid && ex.op.csr_op == CSR_RW, "csr: issued");
    present(csrrw(0, 1));
    check(!f_ready, "csr behind csr: waits for ID/EX");
    tick(); f_valid = 0; #1;     // first one leaves EX
    present(csrrw(0, 1));
    check(f_ready, "csr behind csr: issues once EX is empty");
    idle_inputs(); tick(); tick();

    // A fetch exception reads nothing, even with a matching writer.
    em_valid = 1; em.rd = 3; em.rd_we = 1; em.is_load = 1; #1;
    present(add(1, 3, 3)); f_rsp.exc = 1; f_rsp.exccode = EXC_INSTR_ACCESS_FAULT; #1;
    check(f_ready, "fetch exception: no hazard");
    tick(); f_valid = 0; #1;
    check(ex.exc && ex.exccode == EXC_INSTR_ACCESS_FAULT, "fetch exception carried");
    idle_inputs(); tick();

    // Flush and mispredict block the issue.
    present(addi(1, 2, 3)); flush = 1; #1;
    tick(); flush = 0; f_valid = 0; #1;
    check(!ex_valid, "flush: nothing issued");
    present(addi(1, 2, 3)); redirect = 1; #1;
    tick(); redirect = 0; f_valid = 0; #1;
    check(!ex_valid, "mispredict: wrong-path not issued");

    // Flush clears an instruction already in ID/EX.
    issue(addi(1, 2, 3));
    check(ex_valid, "setup: in ID/EX");
    flush = 1; #1; tick(); flush = 0; #1;
    check(!ex_valid, "flush clears ID/EX");

    // ID/EX back-pressure: EX not ready holds both stages.
    issue(addi(1, 2, 3));
    ex_ready = 0;
    present(addi(2, 3, 4));
    check(!f_ready, "ID/EX full: IF/ID held");
    tick(); #1;
    check(ex.op.rd == 1 && ex_valid, "ID/EX full: contents held");
    ex_ready = 1; #1;
    check(f_ready, "EX ready: IF/ID accepted");
    tick(); f_valid = 0; #1;
    check(ex.op.rd == 2, "second instruction issued");

    // Pass-through fields.
    idle_inputs(); tick();
    present(addi(1, 2, 3)); f_rsp.compressed = 1; f_rsp.pred_taken = 1; f_rsp.instr_raw = 32'h4501;
    tick(); f_valid = 0; #1;
    check(ex.compressed && ex.pred_taken && ex.instr_raw == 32'h4501, "fetch fields carried");

    if (errors == 0) $display("=== PASS : %0d checks ===", checks);
    else             $display("=== FAIL : %0d errors of %0d checks ===", errors, checks);
    if (errors != 0) $fatal(1, "tb_s1_id failed");
    $finish;
  end
endmodule
