// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// tb_meds_s1_dmi_core_if : unit testbench for meds_s1_dmi_core_if      [WIP -- R-06]
//
// Unit testbench for meds_s1_dmi_core_if (core_clk half of the DMI bridge
// plus the Bridge FSM). The TCK domain and the Debug Module are played by
// the testbench; the DM is driven directly so every dm_ready timing,
// including "never", is under control.
//
// Properties checked (the ones that wedge a debugger, R-V5):
//   - the request crosses the synchronizer in exactly REQ_SYNC_STAGES
//     edges before any DM strobe appears;
//   - read / write strobes match the op, and strobe + address + data hold
//     steady until dm_ready (R-C10: payload stable until acknowledged);
//   - the response is captured ONCE on the completing edge and held, even
//     though the DM's data bus changes afterwards;
//   - resp_valid is a level held until the request deassert has crossed;
//   - a NOP completes with NO dm_ready ever arriving, touches no DM
//     strobe and returns an all-zero response;
//   - a hardreset landing in any FSM state does not wedge the bridge: the
//     access is aborted and, since the request is still asserted, restarted;
//   - a reserved opcode must not wedge the bridge either;
//   - asynchronous reset clears everything.
//
// Expectations derive from s1_pkg (R-V2).
//
// Run:  make test-unit TB=meds_s1_dmi_core_if
// =============================================================================

module tb_meds_s1_dmi_core_if;
  import meds_s1_dtm_pkg::*;

  localparam int unsigned HALF            = 5;
  localparam int unsigned REQ_SYNC_STAGES = 2;     // two-flop request synchronizer
  localparam int unsigned N_ACCESS        = 80;
  localparam int unsigned MAX_DM_LAT      = 5;
  localparam int unsigned BOUND           = 24;    // ticks allowed for any recovery
  localparam int unsigned MAX_PRINT       = 20;
  localparam longint unsigned TIMEOUT     = 64'd5_000_000;

  int unsigned checks = 0;
  int unsigned errors   = 0;

  task automatic check(input bit cond, input string what);
    checks++;
    if (!cond) begin
      errors++;
      if (errors <= MAX_PRINT) $display("FAIL @%0t: %s", $time, what);
    end
  endtask

  task automatic finish_tb();
    if (checks == 0) begin
      $display("=== FAIL : no checks executed ===");
      $fatal(1, "tb_meds_s1_dmi_core_if checked nothing");
    end else if (errors != 0) begin
      $display("=== FAIL : %0d errors of %0d checks ===", errors, checks);
      $fatal(1, "tb_meds_s1_dmi_core_if failed");
    end else begin
      $display("=== PASS : %0d checks ===", checks);
      $finish;
    end
  endtask

  initial begin
    #TIMEOUT;
    $display("=== FAIL : watchdog timeout ===");
    $fatal(1, "watchdog timeout");
  end

  logic                  clk;
  logic                  rst_n;
  logic [DMI_REQ_W-1:0]  req_latch;
  logic                  req_valid_async;
  logic                  hardreset_toggle;
  logic                  resp_valid;
  logic [DMI_RESP_W-1:0] resp_data;
  logic [DMI_ABITS-1:0]  dm_addr;
  logic [DMI_DATA_W-1:0] dm_wdata;
  logic                  dm_write;
  logic                  dm_read;
  logic [DMI_DATA_W-1:0] dm_rdata;
  logic                  dm_ready;

  meds_s1_dmi_core_if dut (
    .clk_i              (clk),
    .rst_ni             (rst_n),
    .req_latch_i        (req_latch),
    .req_valid_async_i  (req_valid_async),
    .hardreset_toggle_i (hardreset_toggle),
    .resp_valid_async_o (resp_valid),
    .resp_data_o        (resp_data),
    .dm_addr_o          (dm_addr),
    .dm_wdata_o         (dm_wdata),
    .dm_write_o         (dm_write),
    .dm_read_o          (dm_read),
    .dm_rdata_i         (dm_rdata),
    .dm_ready_i         (dm_ready)
  );

  initial begin
    clk = 1'b0;
    forever #HALF clk = ~clk;
  end

  task automatic tick();
    @(posedge clk); #1;
  endtask

  function automatic logic [DMI_REQ_W-1:0] mk_req(
      input logic [DMI_OP_W-1:0]   op,
      input logic [DMI_ABITS-1:0]  addr,
      input logic [DMI_DATA_W-1:0] data);
    logic [DMI_REQ_W-1:0] r;
    r = '0;
    r[DMI_REQ_OP_LSB   +: DMI_OP_W]   = op;
    r[DMI_REQ_DATA_LSB +: DMI_DATA_W] = data;
    r[DMI_REQ_ADDR_LSB +: DMI_ABITS]  = addr;
    return r;
  endfunction

  function automatic logic [DMI_RESP_W-1:0] mk_resp(
      input logic [DMI_DATA_W-1:0] data,
      input logic [DMI_OP_W-1:0]   status);
    logic [DMI_RESP_W-1:0] r;
    r = '0;
    r[DMI_RESP_DATA_LSB   +: DMI_DATA_W] = data;
    r[DMI_RESP_STATUS_LSB +: DMI_OP_W]   = status;
    return r;
  endfunction

  // Deassert the request and check the response drops only after the
  // deassert has crossed the synchronizer.
  task automatic drop_request();
    req_valid_async = 1'b0;
    repeat (REQ_SYNC_STAGES) begin
      tick();
      check(resp_valid, "resp_valid holds until the request deassert has crossed");
    end
    tick();
    check(!resp_valid, "resp_valid drops once the request deassert has crossed");
    check(!dm_read && !dm_write, "no DM strobe once back in idle");
  endtask

  // A complete read or write access with the DM completing after `lat`
  // extra cycles.
  task automatic run_access(input logic [DMI_OP_W-1:0]   op,
                            input logic [DMI_ABITS-1:0]  addr,
                            input logic [DMI_DATA_W-1:0] wdata,
                            input int unsigned           lat,
                            input logic [DMI_DATA_W-1:0] rd);
    logic exp_rd, exp_wr;
    exp_rd = (op == DMI_OP_READ);
    exp_wr = (op == DMI_OP_WRITE);

    req_latch       = mk_req(op, addr, wdata);
    req_valid_async = 1'b1;
    for (int unsigned i = 0; i < REQ_SYNC_STAGES; i++) begin
      tick();
      check(!dm_read && !dm_write, "no DM strobe before the request has crossed");
      check(!resp_valid, "no response before the request has crossed");
    end
    tick();   // idle -> access
    check(dm_read == exp_rd && dm_write == exp_wr, "strobes match the op");
    check(dm_addr == addr && dm_wdata == wdata, "address and data presented to the DM");
    check(!resp_valid, "no response while the access is pending");

    repeat (lat) begin
      tick();
      check(dm_read == exp_rd && dm_write == exp_wr, "strobe held until dm_ready");
      check(dm_addr == addr && dm_wdata == wdata, "payload stable until dm_ready");
      check(!resp_valid, "no response before dm_ready");
    end

    dm_rdata = rd;
    dm_ready = 1'b1;
    tick();
    dm_ready = 1'b0;
    dm_rdata = ~rd;          // the DM drops its data bus straight afterwards
    check(resp_valid, "dm_ready completes the access");
    check(resp_data == mk_resp(rd, DMI_STATUS_SUCCESS),
          "response is {rdata, SUCCESS} captured on the completing edge");
    check(!dm_read && !dm_write, "strobes drop once the access completes");

    repeat (4) begin
      tick();
      check(resp_valid, "resp_valid is a level, held while the request stays up");
      check(resp_data == mk_resp(rd, DMI_STATUS_SUCCESS),
            "response held static although the DM data bus changed");
    end
    drop_request();
  endtask

  // A NOP: the DM is never asked and dm_ready never arrives.
  task automatic run_nop(input logic [DMI_ABITS-1:0]  addr,
                         input logic [DMI_DATA_W-1:0] wdata);
    req_latch       = mk_req(DMI_OP_NOP, addr, wdata);
    req_valid_async = 1'b1;
    for (int unsigned i = 0; i < REQ_SYNC_STAGES; i++) begin
      tick();
      check(!resp_valid, "NOP: no response before the request has crossed");
      check(!dm_read && !dm_write, "NOP: no DM strobe");
    end
    tick();
    check(resp_valid, "NOP completes with no dm_ready (cannot hang waiting for the DM)");
    check(!dm_read && !dm_write, "NOP never drives a DM strobe");
    check(resp_data == mk_resp('0, DMI_STATUS_SUCCESS),
          "NOP response is all zero (no stale data leaks out)");
    repeat (3) begin
      tick();
      check(resp_valid && !dm_read && !dm_write, "NOP response held, DM untouched");
    end
    drop_request();
  endtask

  // ---------------------------------------------------------------------
  // Tests
  // ---------------------------------------------------------------------
  // An encoding that is neither NOP, READ nor WRITE, found rather than assumed.
  function automatic logic [DMI_OP_W-1:0] reserved_op();
    for (int unsigned v = 2 ** DMI_OP_W - 1; v > 0; v--)
      if (DMI_OP_W'(v) != DMI_OP_NOP && DMI_OP_W'(v) != DMI_OP_READ &&
          DMI_OP_W'(v) != DMI_OP_WRITE)
        return DMI_OP_W'(v);
    return '0;
  endfunction

  task automatic test_idle();
    repeat (20) begin
      tick();
      check(!resp_valid && !dm_read && !dm_write,
            "idle: never responds or strobes without a request");
    end
  endtask

  task automatic test_directed();
    run_access(DMI_OP_WRITE, DMI_ABITS'($urandom()), $urandom(), 0, $urandom());
    run_access(DMI_OP_READ,  DMI_ABITS'($urandom()), $urandom(), 0, $urandom());
    run_access(DMI_OP_WRITE, DMI_ABITS'($urandom()), $urandom(), MAX_DM_LAT, $urandom());
    run_access(DMI_OP_READ,  DMI_ABITS'($urandom()), $urandom(), MAX_DM_LAT, $urandom());
    run_nop(DMI_ABITS'($urandom()), $urandom());
  endtask

  task automatic test_random_accesses();
    logic [DMI_OP_W-1:0] op;
    for (int unsigned i = 0; i < N_ACCESS; i++) begin
      case ($urandom_range(0, 2))
        0:       op = DMI_OP_READ;
        1:       op = DMI_OP_WRITE;
        default: op = DMI_OP_NOP;
      endcase
      if (op == DMI_OP_NOP)
        run_nop(DMI_ABITS'($urandom()), $urandom());
      else
        run_access(op, DMI_ABITS'($urandom()), $urandom(),
                   $urandom_range(0, MAX_DM_LAT), $urandom());
      repeat ($urandom_range(0, 3)) tick();
    end
  endtask

  // Toggle the hardreset source bit (a source-domain event arriving).
  task automatic pulse_hardreset();
    hardreset_toggle = ~hardreset_toggle;
  endtask

  // Finish an access that is currently in the access state.
  task automatic complete_pending(input logic [DMI_DATA_W-1:0] rd);
    dm_rdata = rd;
    dm_ready = 1'b1;
    tick();
    dm_ready = 1'b0;
    dm_rdata = ~rd;
    check(resp_valid, "pending access completes normally after the disturbance");
    drop_request();
  endtask

  task automatic test_hardreset();
    logic [DMI_DATA_W-1:0] rd;
    int unsigned w;

    // --- hardreset with the FSM idle: harmless
    pulse_hardreset();
    repeat (BOUND) tick();
    check(!resp_valid && !dm_read && !dm_write, "hardreset while idle changes nothing");
    run_access(DMI_OP_WRITE, DMI_ABITS'($urandom()), $urandom(), 1, $urandom());

    // --- hardreset during ACCESS: aborted, then restarted (request still up)
    req_latch       = mk_req(DMI_OP_READ, DMI_ABITS'($urandom()), $urandom());
    req_valid_async = 1'b1;
    repeat (REQ_SYNC_STAGES + 1) tick();
    check(dm_read, "precondition: access in flight");
    pulse_hardreset();
    w = 0;
    while (w < BOUND && dm_read) begin tick(); w++; end
    check(!dm_read, "hardreset aborts the in-flight access");
    w = 0;
    while (w < BOUND && !dm_read) begin tick(); w++; end
    check(dm_read, "request still asserted: the bridge restarts it (not wedged)");
    rd = $urandom();
    complete_pending(rd);

    // --- hardreset during COMPLETED: response dropped, then redone
    req_latch       = mk_req(DMI_OP_WRITE, DMI_ABITS'($urandom()), $urandom());
    req_valid_async = 1'b1;
    repeat (REQ_SYNC_STAGES + 1) tick();
    dm_rdata = $urandom();
    dm_ready = 1'b1;
    tick();
    dm_ready = 1'b0;
    check(resp_valid, "precondition: access completed");
    pulse_hardreset();
    w = 0;
    while (w < BOUND && resp_valid) begin tick(); w++; end
    check(!resp_valid, "hardreset in COMPLETED clears the response");
    w = 0;
    while (w < BOUND && !dm_write) begin tick(); w++; end
    check(dm_write, "bridge picks the still-asserted request up again");
    complete_pending($urandom());

    // --- two hardresets, spaced: both honoured, bridge still usable
    pulse_hardreset();
    repeat (BOUND) tick();
    pulse_hardreset();
    repeat (BOUND) tick();
    run_access(DMI_OP_READ, DMI_ABITS'($urandom()), $urandom(), 0, $urandom());
  endtask

  task automatic test_reserved_op();
    int unsigned w;
    // dm_ready never arrives: a reserved opcode must still terminate.
    check(reserved_op() != DMI_OP_NOP, "a reserved opcode encoding exists");
    req_latch       = mk_req(reserved_op(), DMI_ABITS'($urandom()), $urandom());
    req_valid_async = 1'b1;
    w = 0;
    while (w < BOUND && !resp_valid) begin tick(); w++; end
    check(resp_valid, "a reserved opcode must terminate without the DM (must not wedge the bridge)");
    check(!dm_read && !dm_write, "a reserved opcode never drives a DM strobe");
  endtask

  task automatic test_async_reset();
    req_valid_async = 1'b0;
    repeat (BOUND) tick();           // settle whatever came before
    req_latch       = mk_req(DMI_OP_READ, DMI_ABITS'($urandom()), $urandom());
    req_valid_async = 1'b1;
    repeat (REQ_SYNC_STAGES + 1) tick();
    check(dm_read, "precondition: access in flight before reset");
    @(negedge clk); #1;
    rst_n = 1'b0;
    #1;
    check(!dm_read && !dm_write && !resp_valid, "async reset aborts the access at once");
    check(resp_data == '0, "async reset clears the response register");
    req_valid_async = 1'b0;
    @(negedge clk); #1;
    rst_n = 1'b1;
    repeat (BOUND) tick();
    check(!resp_valid && !dm_read && !dm_write, "idle after reset");
    run_access(DMI_OP_WRITE, DMI_ABITS'($urandom()), $urandom(), 0, $urandom());
  endtask

  initial begin
    rst_n            = 1'b0;
    req_latch        = '0;
    req_valid_async  = 1'b0;
    hardreset_toggle = 1'b0;
    dm_rdata         = '0;
    dm_ready         = 1'b0;

    repeat (3) tick();
    check(!resp_valid && !dm_read && !dm_write && resp_data == '0, "all outputs idle in reset");
    @(negedge clk); #1;
    rst_n = 1'b1;
    repeat (BOUND) tick();

    test_idle();
    test_directed();
    test_random_accesses();
    test_hardreset();
    test_async_reset();
    test_reserved_op();      // last: may leave the FSM stuck if it wedges

    finish_tb();
  end

endmodule : tb_meds_s1_dmi_core_if
