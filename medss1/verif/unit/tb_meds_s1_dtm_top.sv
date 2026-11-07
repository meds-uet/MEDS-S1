// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// tb_meds_s1_dtm_top : integration testbench for meds_s1_dtm_top       [WIP -- R-06]
//
// Integration testbench for meds_s1_dtm_top. The testbench is a JTAG probe on
// the real pins (driven exactly as a debugger would: select an instruction,
// scan a data register) and a behavioural Debug Module on the core-clock side
// with a memory, random latency and a stall control.  The DM is deliberately
// unforgiving: it samples address and data live, checks the payload stays
// stable while an access is outstanding (R-C10), and drives junk on rdata
// whenever it is not acknowledging.
//
// The same scenarios run at THREE TCK:core clock ratios in one simulation
// (R-V2): the default, a core 20x slower than TCK, and a core 8x faster.  The
// ratio is not decoration: the request/ack collision hazard only appears as a
// silently lost write when the core is slower than TCK, so a single ratio
// cannot guard it.  All pacing is derived from the clock periods.
//
// Scenarios: IDCODE; Capture-IR pattern through the TDO mux; DTMCS fields;
// BYPASS and an unimplemented opcode; write / read-back / NOP-collect with
// exact DM access counts; overrun while the DM is stalled (the second request
// must never reach the DM; dmistat latches BUSY; sticky; dmireset recovers);
// dmireset must not touch the bridge while dmihardreset must, exactly once per
// event; a sweep of a second request across every phase of the first.
//
// Run:  make test-unit TB=meds_s1_dtm_top
// =============================================================================

module tb_meds_s1_dtm_top_case
  import meds_s1_dtm_pkg::*;
#(
  parameter int unsigned TCK_HALF   = 25,
  parameter int unsigned CORE_HALF  = 7,
  parameter int unsigned DM_MAX_LAT = 3
) (
  output int unsigned checks_o,
  output int unsigned errors_o,
  output logic        done_o
);

  localparam int unsigned N_XFERS   = 24;
  localparam int unsigned N_WORDS   = 2 ** DMI_ABITS;
  localparam int unsigned MAX_PRINT = 20;
  localparam logic [DTM_IDCODE_W-1:0] TB_IDCODE = 32'h1BAD_B003;
  localparam logic [DMI_DATA_W-1:0]   PATTERN   = {(DMI_DATA_W/8){8'h5A}};

  // The collision sweep forces the DM latency so that a whole transaction
  // lasts about as long as one DMI scan; otherwise, with a fast core, the
  // second request could never arrive while the first is still in flight.
  localparam int unsigned SCAN_TCK_CYCLES = DMI_REQ_W + 8;
  localparam int unsigned SWEEP_LAT       = (SCAN_TCK_CYCLES * TCK_HALF) / CORE_HALF + 1;

  // Generous time for one transaction to complete the whole 4-phase
  // handshake, expressed in TCK cycles of idle.
  localparam int unsigned SETTLE_CYCLES =
      (2 * (20 + DM_MAX_LAT) * CORE_HALF) / TCK_HALF + 16;
  localparam int unsigned SWEEP_SETTLE =
      SETTLE_CYCLES + (2 * SWEEP_LAT * CORE_HALF) / TCK_HALF + 16;

  int unsigned checks = 0;
  int unsigned errors   = 0;

  task automatic check(input bit cond, input string what);
    checks++;
    if (!cond) begin
      errors++;
      if (errors <= MAX_PRINT) $display("FAIL @%0t [TCK_HALF=%0d CORE_HALF=%0d]: %s", $time, TCK_HALF, CORE_HALF, what);
    end
  endtask

  // ---------------------------------------------------------------------
  // DUT
  // ---------------------------------------------------------------------
  logic                  tck, trst_n, tms, tdi, tdo;
  logic                  core_clk, dmi_rst_n;
  logic [DMI_ABITS-1:0]  dm_addr;
  logic [DMI_DATA_W-1:0] dm_wdata;
  logic                  dm_write, dm_read;
  logic [DMI_DATA_W-1:0] dm_rdata;
  logic                  dm_ready;

  meds_s1_dtm_top #(
    .IDCODE_VALUE (TB_IDCODE)
  ) dut (
    .tck_i      (tck),
    .trst_n_i    (trst_n),
    .tms_i      (tms),
    .tdi_i      (tdi),
    .tdo_o      (tdo),
    .core_clk_i (core_clk),
    .dmi_rst_n_i (dmi_rst_n),
    .dm_addr_o  (dm_addr),
    .dm_wdata_o (dm_wdata),
    .dm_write_o (dm_write),
    .dm_read_o  (dm_read),
    .dm_rdata_i (dm_rdata),
    .dm_ready_i (dm_ready)
  );

  initial begin
    tck = 1'b0;
    forever #TCK_HALF tck = ~tck;
  end

  // Offset so the two clocks have an arbitrary phase relationship.
  initial begin
    core_clk = 1'b0;
    #3;
    forever #CORE_HALF core_clk = ~core_clk;
  end

  // ---------------------------------------------------------------------
  // Behavioural Debug Module
  //
  // Deliberately unforgiving: address and data are sampled LIVE when the
  // access completes (as a real DM writing its register would), the
  // payload must stay stable while an access is outstanding (R-C10), and
  // rdata is junk on every cycle that dm_ready is not asserted.
  // ---------------------------------------------------------------------
  logic [DMI_DATA_W-1:0] dm_mem  [N_WORDS];
  logic [DMI_DATA_W-1:0] exp_mem [N_WORDS];
  int unsigned           dm_n_reads;
  int unsigned           dm_n_writes;
  int unsigned           dm_n_aborts;   // strobe dropped while access outstanding
  logic                  dm_stall;
  int                    dm_lat_force;   // < 0: random latency

  logic                  dm_active;
  logic                  dm_is_write;
  logic                  dm_was_strobing;
  logic                  dm_strobe;
  logic [DMI_ABITS-1:0]  dm_a;
  logic [DMI_DATA_W-1:0] dm_w;
  int unsigned           dm_wait;

  initial begin
    dm_ready        = 1'b0;
    dm_rdata        = '0;
    dm_active       = 1'b0;
    dm_is_write     = 1'b0;
    dm_was_strobing = 1'b0;
    dm_a            = '0;
    dm_w            = '0;
    dm_wait         = 0;
    forever begin
      @(posedge core_clk); #1;
      dm_ready  = 1'b0;
      dm_rdata  = $urandom();
      dm_strobe = dm_read || dm_write;

      if (dm_active) begin
        if (dm_strobe)
          check(dm_addr == dm_a && dm_wdata == dm_w && dm_write == dm_is_write,
                "DM: request payload stays stable while the access is outstanding");
        if (dm_was_strobing && !dm_strobe)
          dm_n_aborts++;
      end

      if (!dm_active) begin
        if (dm_strobe) begin
          dm_active   = 1'b1;
          dm_is_write = dm_write;
          dm_a        = dm_addr;
          dm_w        = dm_wdata;
          dm_wait     = (dm_lat_force >= 0) ? unsigned'(dm_lat_force)
                                            : $urandom_range(0, DM_MAX_LAT);
        end
      end else if (!dm_stall) begin
        if (dm_wait > 0) begin
          dm_wait--;
        end else begin
          if (dm_is_write) begin
            dm_mem[dm_addr] = dm_wdata;               // live sample
            dm_n_writes++;
          end else begin
            dm_n_reads++;
            dm_rdata = dm_mem[dm_addr];
          end
          dm_ready  = 1'b1;
          dm_active = 1'b0;
        end
      end
      dm_was_strobing = dm_active && dm_strobe;
    end
  end

  // ---------------------------------------------------------------------
  // JTAG probe
  // ---------------------------------------------------------------------
  logic s_tdo;

  // One TCK cycle. Entered just after a rising edge: TMS/TDI are driven
  // for the coming edge, TDO (launched on the falling edge) is sampled.
  task automatic tck_cycle(input logic tms_v, input logic tdi_v);
    tms = tms_v;
    tdi = tdi_v;
    @(negedge tck); #1;
    s_tdo = tdo;
    @(posedge tck); #1;
  endtask

  task automatic idle_tck(input int unsigned n);
    repeat (n) tck_cycle(1'b0, 1'b0);
  endtask

  // From Run-Test/Idle.
  task automatic scan_ir(input  logic [DTM_IR_W-1:0] val,
                         output logic [DTM_IR_W-1:0] out_bits);
    out_bits = '0;
    tck_cycle(1'b1, 1'b0);
    tck_cycle(1'b1, 1'b0);
    tck_cycle(1'b0, 1'b0);
    tck_cycle(1'b0, 1'b0);
    for (int unsigned i = 0; i < DTM_IR_W; i++) begin
      tck_cycle(i == DTM_IR_W - 1, val[i]);
      out_bits[i] = s_tdo;
    end
    tck_cycle(1'b1, 1'b0);
    tck_cycle(1'b0, 1'b0);
  endtask

  task automatic scan_dr(input  int unsigned nbits,
                         input  logic [63:0] din,
                         output logic [63:0] dout);
    dout = '0;
    tck_cycle(1'b1, 1'b0);
    tck_cycle(1'b0, 1'b0);
    tck_cycle(1'b0, 1'b0);
    for (int unsigned i = 0; i < nbits; i++) begin
      tck_cycle(i == nbits - 1, din[i]);
      dout[i] = s_tdo;
    end
    tck_cycle(1'b1, 1'b0);
    tck_cycle(1'b0, 1'b0);
  endtask

  task automatic settle();
    idle_tck(SETTLE_CYCLES);
  endtask

  logic [DTM_IR_W-1:0]   ir_seen;
  logic [63:0]           dr_out;
  logic [DMI_RESP_W-1:0] last_resp;
  logic [DMI_ABITS-1:0]  last_aout;

  task automatic select_ir(input logic [DTM_IR_W-1:0] val);
    scan_ir(val, ir_seen);
    check(ir_seen == DTM_IR_CAPTURE_VAL,
          "Capture-IR pattern reaches TDO through the central mux");
  endtask

  // One DMI scan: shifts in a request, collects the previous response.
  task automatic dmi_scan(input logic [DMI_OP_W-1:0]   op,
                          input logic [DMI_ABITS-1:0]  a,
                          input logic [DMI_DATA_W-1:0] d);
    logic [63:0] din;
    din = '0;
    din[DMI_REQ_OP_LSB   +: DMI_OP_W]   = op;
    din[DMI_REQ_DATA_LSB +: DMI_DATA_W] = d;
    din[DMI_REQ_ADDR_LSB +: DMI_ABITS]  = a;
    scan_dr(DMI_REQ_W, din, dr_out);
    last_resp = dr_out[DMI_RESP_W-1:0];
    last_aout = dr_out[DMI_REQ_ADDR_LSB +: DMI_ABITS];
  endtask

  task automatic read_dmistat(output logic [DMI_OP_W-1:0] stat);
    select_ir(DTM_IR_DTMCS);
    scan_dr(DTM_DTMCS_W, 64'd0, dr_out);
    stat = dr_out[DTMCS_DMISTAT_LSB +: DMI_OP_W];
  endtask

  task automatic write_dtmcs(input logic [63:0] val);
    select_ir(DTM_IR_DTMCS);
    scan_dr(DTM_DTMCS_W, val, dr_out);
  endtask

  // ---------------------------------------------------------------------
  // Scenarios
  // ---------------------------------------------------------------------
  // An opcode nothing implements, found rather than assumed.
  function automatic logic [DTM_IR_W-1:0] unused_opcode();
    for (int unsigned v = 2 ** DTM_IR_W - 1; v > 0; v--)
      if (DTM_IR_W'(v) != DTM_IR_IDCODE && DTM_IR_W'(v) != DTM_IR_DTMCS &&
          DTM_IR_W'(v) != DTM_IR_DMI    && DTM_IR_W'(v) != DTM_IR_BYPASS)
        return DTM_IR_W'(v);
    return '0;
  endfunction

  task automatic test_idcode();
    scan_dr(DTM_IDCODE_W, 64'd0, dr_out);
    check(dr_out[DTM_IDCODE_W-1:0] == TB_IDCODE,
          "IDCODE is selected after reset and reads back the configured value");
  endtask

  task automatic test_dtmcs();
    select_ir(DTM_IR_DTMCS);
    scan_dr(DTM_DTMCS_W, 64'd0, dr_out);
    check(dr_out[DTMCS_VERSION_LSB +: 4] == DTMCS_VERSION_VAL, "DTMCS version");
    check(dr_out[DTMCS_ABITS_LSB +: 6] == 6'(DMI_ABITS), "DTMCS abits equals the DM address width");
    check(dr_out[DTMCS_IDLE_LSB +: 3] == DTMCS_IDLE_VAL, "DTMCS idle");
    check(dr_out[DTMCS_DMISTAT_LSB +: DMI_OP_W] == DMI_STATUS_SUCCESS, "DTMCS dmistat is 0 after reset");
  endtask

  task automatic test_bypass();
    logic [63:0] din;
    logic [DTM_IR_W-1:0] unknown_op;
    localparam int unsigned NB = 10;

    din = {$urandom(), $urandom()};
    select_ir(DTM_IR_BYPASS);
    scan_dr(NB, din, dr_out);
    check(dr_out[0] == 1'b0, "BYPASS captures 0");
    for (int unsigned i = 1; i < NB; i++)
      check(dr_out[i] == din[i-1], "BYPASS is a one-bit delay");

    // An opcode nobody implements must behave as BYPASS too.
    unknown_op = unused_opcode();
    check(unknown_op != DTM_IR_IDCODE && unknown_op != DTM_IR_DTMCS &&
          unknown_op != DTM_IR_DMI, "test opcode really is unimplemented");
    select_ir(unknown_op);
    din = {$urandom(), $urandom()};
    scan_dr(NB, din, dr_out);
    check(dr_out[0] == 1'b0, "unknown opcode captures 0 (BYPASS)");
    for (int unsigned i = 1; i < NB; i++)
      check(dr_out[i] == din[i-1], "unknown opcode is a one-bit delay (BYPASS)");
  endtask

  task automatic test_readback();
    logic [DMI_ABITS-1:0]  a;
    logic [DMI_DATA_W-1:0] d;
    int unsigned           w0, r0;

    select_ir(DTM_IR_DMI);
    for (int unsigned k = 0; k < N_XFERS; k++) begin
      a  = DMI_ABITS'($urandom());
      d  = $urandom();
      w0 = dm_n_writes;
      r0 = dm_n_reads;

      dmi_scan(DMI_OP_WRITE, a, d);
      settle();
      check(dm_n_writes == w0 + 1, "a write reaches the DM exactly once");
      check(dm_mem[a] == d, "the DM holds the written data");
      exp_mem[a] = d;

      dmi_scan(DMI_OP_READ, a, '0);
      settle();
      check(dm_n_reads == r0 + 1, "a read reaches the DM exactly once");

      // A NOP both starts no DM access and collects the read's response.
      dmi_scan(DMI_OP_NOP, '0, '0);
      settle();
      check(last_resp[DMI_RESP_STATUS_LSB +: DMI_OP_W] == DMI_STATUS_SUCCESS,
            "response status is SUCCESS");
      check(last_resp[DMI_RESP_DATA_LSB +: DMI_DATA_W] == exp_mem[a],
            "read-back returns exactly what was written");
      check(last_aout == a, "address field holds the previous request's address");
      check(dm_n_writes == w0 + 1 && dm_n_reads == r0 + 1,
            "a NOP never reaches the DM");
    end
  endtask

  task automatic test_overrun();
    logic [DMI_ABITS-1:0]  a1, a2, a3, a4;
    logic [DMI_DATA_W-1:0] d1, d2, d3, d4, a2_before;
    logic [DMI_OP_W-1:0]   stat;
    int unsigned           w0, w1;

    a1 = DMI_ABITS'($urandom());
    a2 = a1 ^ DMI_ABITS'(1);
    a3 = a1 ^ DMI_ABITS'(2);
    a4 = a1 ^ DMI_ABITS'(4);
    d1 = $urandom();
    d2 = $urandom();
    d3 = $urandom();
    d4 = $urandom();
    a2_before = dm_mem[a2];

    select_ir(DTM_IR_DMI);
    dm_stall = 1'b1;                       // the DM holds the first access
    w0 = dm_n_writes;
    dmi_scan(DMI_OP_WRITE, a1, d1);        // accepted
    dmi_scan(DMI_OP_WRITE, a2, d2);        // arrives while #1 is in flight
    dm_stall = 1'b0;
    settle();
    check(dm_n_writes == w0 + 1, "overrun: only the first request reached the DM");
    check(dm_mem[a1] == d1, "overrun: the first request still completed");
    check(dm_mem[a2] == a2_before, "overrun: the overrunning request never reached the DM");
    exp_mem[a1] = d1;

    read_dmistat(stat);
    check(stat == DMI_STATUS_BUSY, "overrun latches dmistat = BUSY");

    // The debugger sees it in the DMI response too, with zeroed data.
    select_ir(DTM_IR_DMI);
    dmi_scan(DMI_OP_NOP, '0, '0);
    settle();
    check(last_resp[DMI_RESP_STATUS_LSB +: DMI_OP_W] == DMI_STATUS_BUSY,
          "DMI response reports BUSY");
    check(last_resp[DMI_RESP_DATA_LSB +: DMI_DATA_W] == '0, "BUSY response carries no stale data");

    // Sticky: requests are silently dropped, however long we wait.
    w1 = dm_n_writes;
    dmi_scan(DMI_OP_WRITE, a3, d3);
    settle();
    check(dm_n_writes == w1, "requests are dropped while dmistat is non-zero");

    // dmireset releases it and the next request goes through.
    write_dtmcs(64'd1 << DTMCS_DMIRESET_BIT);
    read_dmistat(stat);
    check(stat == DMI_STATUS_SUCCESS, "dmireset clears dmistat");
    select_ir(DTM_IR_DMI);
    dmi_scan(DMI_OP_WRITE, a4, d4);
    settle();
    check(dm_n_writes == w1 + 1 && dm_mem[a4] == d4, "requests flow again after dmireset");
    exp_mem[a4] = d4;
  endtask

  task automatic test_hardreset_midflight();
    logic [DMI_ABITS-1:0]  a5, a6;
    logic [DMI_DATA_W-1:0] d5, d6;
    logic [DMI_OP_W-1:0]   stat;
    int unsigned           ab0;

    // Twice: the second one distinguishes "toggle" from "set" in the
    // hardreset crossing, which a single event cannot.
    for (int unsigned h = 0; h < 2; h++) begin
      a5 = DMI_ABITS'($urandom());
      a6 = a5 ^ DMI_ABITS'(8);
      d5 = $urandom();
      d6 = $urandom();

      select_ir(DTM_IR_DMI);
      dm_stall = 1'b1;
      dmi_scan(DMI_OP_WRITE, a5, d5);        // stuck at the DM
      settle();
      ab0 = dm_n_aborts;

      // dmireset must NOT touch the bridge...
      write_dtmcs(64'd1 << DTMCS_DMIRESET_BIT);
      settle();
      check(dm_n_aborts == ab0, "dmireset does not disturb an in-flight transaction");

      // ...dmihardreset must, and exactly once per event.
      write_dtmcs(64'd1 << DTMCS_DMIHARDRESET_BIT);
      settle();
      check(dm_n_aborts == ab0 + 1,
            "dmihardreset reaches the core domain and aborts the stuck access, once");

      select_ir(DTM_IR_DMI);
      dm_stall = 1'b0;
      settle();
      check(dm_mem[a5] == d5, "a request pending across a hardreset still completes");

      // The bridge is not wedged: a fresh transaction works end to end.
      dmi_scan(DMI_OP_WRITE, a6, d6);
      settle();
      check(dm_mem[a6] == d6, "bridge still works after a hardreset mid-flight");
      dmi_scan(DMI_OP_NOP, '0, '0);
      settle();
      check(last_resp[DMI_RESP_STATUS_LSB +: DMI_OP_W] == DMI_STATUS_SUCCESS,
            "status is SUCCESS after the hardreset recovery");
      read_dmistat(stat);
      check(stat == DMI_STATUS_SUCCESS, "dmistat is clear after a hardreset");
    end
  endtask

  // Two writes separated by every phase relationship between the second
  // Update-DR and the first transaction's handshake, including the window
  // where the request flag has cleared but the ack is still unwinding.
  // Whatever the timing, a request may be accepted or rejected with BUSY,
  // but it must never be silently lost, corrupted or wedge the bridge.
  task automatic test_gap_sweep();
    logic [DMI_ABITS-1:0]  ax, ay;
    logic [DMI_DATA_W-1:0] dx, dy;
    logic [DMI_OP_W-1:0]   stat;
    int unsigned           n0, step, n_ok, n_busy;

    dm_lat_force = int'(SWEEP_LAT);
    step   = (SETTLE_CYCLES / 16) + 1;
    n_ok   = 0;
    n_busy = 0;
    for (int unsigned gap = 0; gap <= SETTLE_CYCLES; gap += step) begin
      ax = DMI_ABITS'($urandom());
      ay = ax ^ DMI_ABITS'(16);
      dx = $urandom();
      dy = $urandom();
      n0 = dm_n_writes;

      select_ir(DTM_IR_DMI);
      dmi_scan(DMI_OP_WRITE, ax, dx);
      idle_tck(gap);
      dmi_scan(DMI_OP_WRITE, ay, dy);
      idle_tck(SWEEP_SETTLE);
      read_dmistat(stat);

      if (stat == DMI_STATUS_SUCCESS) begin
        n_ok++;
        check(dm_n_writes == n0 + 2 && dm_mem[ax] == dx && dm_mem[ay] == dy,
              "no silent loss: with no error latched both writes reached the DM intact");
      end else begin
        n_busy++;
        check(stat == DMI_STATUS_BUSY, "a collision can only ever report BUSY");
        check(dm_n_writes == n0 + 1 && dm_mem[ax] == dx,
              "collision: the first write completed and the second was dropped cleanly");
      end
      write_dtmcs(64'd1 << DTMCS_DMIRESET_BIT);

      // Liveness after every gap value: the bridge is never left wedged.
      select_ir(DTM_IR_DMI);
      dmi_scan(DMI_OP_WRITE, ax, dx ^ PATTERN);
      idle_tck(SWEEP_SETTLE);
      check(dm_mem[ax] == (dx ^ PATTERN), "bridge still works after this gap");
    end
    dm_lat_force = -1;
    check(n_ok > 0 && n_busy > 0,
          "sweep covered both outcomes (accepted and BUSY-rejected)");
  endtask

  // ---------------------------------------------------------------------
  // Main
  // ---------------------------------------------------------------------
  initial begin
    done_o = 1'b0;
    $display("=== tb_meds_s1_dtm_top_case : TCK_HALF=%0d CORE_HALF=%0d ===", TCK_HALF, CORE_HALF);
    for (int unsigned i = 0; i < N_WORDS; i++) begin
      dm_mem[i]  = $urandom();
      exp_mem[i] = dm_mem[i];
    end
    dm_n_reads  = 0;
    dm_n_writes = 0;
    dm_n_aborts = 0;
    dm_stall    = 1'b0;
    dm_lat_force = -1;

    trst_n    = 1'b0;
    dmi_rst_n = 1'b0;
    tms       = 1'b1;
    tdi       = 1'b0;
    repeat (4) @(posedge tck);
    #1;
    trst_n    = 1'b1;
    dmi_rst_n = 1'b1;

    // Standard debugger start-up: five TMS=1 clocks, then to Run-Test/Idle.
    repeat (5) tck_cycle(1'b1, 1'b0);
    tck_cycle(1'b0, 1'b0);

    check(DMI_ABITS >= 5, "testbench geometry: the distinct-address stimulus needs DMI_ABITS >= 5");
    test_idcode();
    test_dtmcs();
    test_bypass();
    test_readback();
    test_overrun();
    test_hardreset_midflight();
    test_gap_sweep();

    done_o = 1'b1;
  end

  assign checks_o = checks;
  assign errors_o = errors;

endmodule : tb_meds_s1_dtm_top_case

// =============================================================================
// Wrapper: the same scenarios at three TCK:core clock ratios, one simulation.
// =============================================================================
module tb_meds_s1_dtm_top;

  localparam int unsigned N_CFG = 3;
  // default / core 20x slower than TCK / core 8x faster than TCK
  localparam int unsigned TCK_H  [N_CFG] = '{25,   5, 40};
  localparam int unsigned CORE_H [N_CFG] = '{ 7, 100,  5};
  localparam longint unsigned TIMEOUT = 64'd400_000_000;

  int unsigned checks = 0;
  int unsigned errors = 0;
  int unsigned n_done = 0;

  task automatic finish_tb();
    if (checks == 0) begin
      $display("=== FAIL : no checks executed ===");
      $fatal(1, "tb_meds_s1_dtm_top checked nothing");
    end else if (errors != 0) begin
      $display("=== FAIL : %0d errors of %0d checks ===", errors, checks);
      $fatal(1, "tb_meds_s1_dtm_top failed");
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

  for (genvar g = 0; g < N_CFG; g++) begin : gen_cfg
    int unsigned c;
    int unsigned e;
    logic        d;

    tb_meds_s1_dtm_top_case #(
      .TCK_HALF  (TCK_H[g]),
      .CORE_HALF (CORE_H[g])
    ) u_case (
      .checks_o (c),
      .errors_o (e),
      .done_o   (d)
    );

    initial begin
      wait (d);
      checks += c;
      errors += e;
      n_done++;
    end
  end

  initial begin
    wait (n_done == N_CFG);
    finish_tb();
  end

endmodule : tb_meds_s1_dtm_top
