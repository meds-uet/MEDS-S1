// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// tb_meds_s1_dtm_dr_regs : unit testbench for meds_s1_dtm_dr_regs      [WIP -- R-06]
//
// Unit testbench for meds_s1_dtm_dr_regs. The TAP strobes are driven
// directly, with the same Capture / Shift x N / Exit1 / Update cycle
// sequence the real TAP produces, so this block is verified on its own.
//
// Directed checks (each against the spec text, not against a model):
//   IDCODE   returns the parameterised value, read-only
//   BYPASS   captures 0, then is a one-bit delay
//   DTMCS    capture fields (version/abits/idle/dmistat), reserved and
//            write-1-to-trigger bits read back 0
//   DMI      request reaches the bridge, a blocked request does not
//   dmistat  sticky, first-error-wins, cleared only by dmireset
//   response hold register survives arbitrary delay and the response bus
//            changing underneath it
//   TDO mux  IR shift-out wins while shifting the IR
//   hold     an unselected / idle register retains its contents
// plus a randomized model of dmistat + the request gate (R-V5: the
// properties that wedge a debugger, not just wrong answers).
//
// Expectations derive from s1_pkg (R-V2). The DUT is instantiated with a
// non-default IDCODE so the parameter path is exercised.
//
// Run:  make test-unit TB=meds_s1_dtm_dr_regs
// =============================================================================

module tb_meds_s1_dtm_dr_regs;
  import meds_s1_dtm_pkg::*;

  localparam int unsigned HALF        = 5;
  localparam int unsigned N_RANDOM    = 400;
  localparam int unsigned N_REPEAT    = 8;
  localparam int unsigned MAX_PRINT   = 20;
  localparam longint unsigned TIMEOUT = 64'd20_000_000;
  localparam logic [DTM_IDCODE_W-1:0] TB_IDCODE = 32'h1BAD_B003;

  localparam int unsigned SEL_BYPASS = 0;
  localparam int unsigned SEL_DTMCS  = 1;
  localparam int unsigned SEL_DMI    = 2;
  localparam int unsigned SEL_IDCODE = 3;

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
      $fatal(1, "tb_meds_s1_dtm_dr_regs checked nothing");
    end else if (errors != 0) begin
      $display("=== FAIL : %0d errors of %0d checks ===", errors, checks);
      $fatal(1, "tb_meds_s1_dtm_dr_regs failed");
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

  // ---------------------------------------------------------------------
  // DUT
  // ---------------------------------------------------------------------
  logic                  clk;
  logic                  rst_n;
  logic                  tdi;
  logic                  capture_dr, shift_dr, update_dr;
  logic                  shift_ir, ir_shift_tdo;
  logic                  sel_bypass, sel_dtmcs, sel_dmi, sel_idcode;
  logic [DMI_RESP_W-1:0] stable_dmi_resp;
  logic                  tck_ack;
  logic                  req_pending;
  logic                  tdo;
  logic [DMI_REQ_W-1:0]  stable_dmi_req;
  logic                  dmi_req_trigger;
  logic                  dmihardreset_pulse;

  meds_s1_dtm_dr_regs #(
    .IDCODE_VALUE (TB_IDCODE)
  ) dut (
    .clk_i                (clk),
    .rst_ni               (rst_n),
    .tdi_i                (tdi),
    .capture_dr_i         (capture_dr),
    .shift_dr_i           (shift_dr),
    .update_dr_i          (update_dr),
    .shift_ir_i           (shift_ir),
    .ir_shift_tdo_i       (ir_shift_tdo),
    .sel_bypass_i         (sel_bypass),
    .sel_dtmcs_i          (sel_dtmcs),
    .sel_dmi_i            (sel_dmi),
    .sel_idcode_i         (sel_idcode),
    .stable_dmi_resp_i    (stable_dmi_resp),
    .tck_ack_i            (tck_ack),
    .req_pending_i        (req_pending),
    .tdo_o                (tdo),
    .stable_dmi_req_o     (stable_dmi_req),
    .dmi_req_trigger_o    (dmi_req_trigger),
    .dmihardreset_pulse_o (dmihardreset_pulse)
  );

  initial begin
    clk = 1'b0;
    forever #HALF clk = ~clk;
  end

  // ---------------------------------------------------------------------
  // Drivers. Inputs change just after a rising edge; the falling-edge
  // TDO register is sampled one time-unit after the falling edge.
  // ---------------------------------------------------------------------
  logic s_tdo, s_trig, s_hr;     // samples from the most recent dr_cycle
  logic last_trig, last_hr;      // samples from the most recent Update-DR

  task automatic dr_cycle(input logic cap, input logic sh,
                          input logic up,  input logic tdi_v);
    capture_dr = cap;
    shift_dr   = sh;
    update_dr  = up;
    tdi        = tdi_v;
    @(negedge clk); #1;
    s_tdo  = tdo;
    s_trig = dmi_req_trigger;
    s_hr   = dmihardreset_pulse;
    @(posedge clk); #1;
  endtask

  task automatic idle(input int unsigned n);
    repeat (n) dr_cycle(1'b0, 1'b0, 1'b0, 1'b0);
  endtask

  task automatic select_reg(input int unsigned which);
    sel_bypass = (which == SEL_BYPASS);
    sel_dtmcs  = (which == SEL_DTMCS);
    sel_dmi    = (which == SEL_DMI);
    sel_idcode = (which == SEL_IDCODE);
  endtask

  // A full DR scan: Capture, nbits x Shift, Exit1, Update, back to idle.
  task automatic dr_scan(input  int unsigned nbits,
                         input  logic [63:0] din,
                         output logic [63:0] dout);
    dout = '0;
    dr_cycle(1'b1, 1'b0, 1'b0, 1'b0);                 // Capture-DR
    for (int unsigned i = 0; i < nbits; i++) begin
      dr_cycle(1'b0, 1'b1, 1'b0, din[i]);             // Shift-DR
      dout[i] = s_tdo;
    end
    dr_cycle(1'b0, 1'b0, 1'b0, 1'b0);                 // Exit1-DR
    dr_cycle(1'b0, 1'b0, 1'b1, 1'b0);                 // Update-DR
    last_trig = s_trig;
    last_hr   = s_hr;
    dr_cycle(1'b0, 1'b0, 1'b0, 1'b0);                 // Run-Test/Idle
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

  // A response from the core domain: the bus is driven, then the
  // synchronized ack goes high for a few cycles and drops.
  task automatic ack_event(input logic [DMI_RESP_W-1:0] resp);
    stable_dmi_resp = resp;
    tck_ack         = 1'b1;
    idle(3);
    tck_ack         = 1'b0;
    idle(2);
  endtask

  logic [63:0] scan_out;

  task automatic read_dtmcs(output logic [DTM_DTMCS_W-1:0] val);
    select_reg(SEL_DTMCS);
    dr_scan(DTM_DTMCS_W, 64'd0, scan_out);
    val = scan_out[DTM_DTMCS_W-1:0];
  endtask

  task automatic read_dmistat(output logic [DMI_OP_W-1:0] stat);
    select_reg(SEL_DTMCS);
    dr_scan(DTM_DTMCS_W, 64'd0, scan_out);
    stat = scan_out[DTMCS_DMISTAT_LSB +: DMI_OP_W];
  endtask

  task automatic clear_dmistat();
    select_reg(SEL_DTMCS);
    dr_scan(DTM_DTMCS_W, 64'd1 << DTMCS_DMIRESET_BIT, scan_out);
  endtask

  task automatic apply_reset();
    @(negedge clk); #1;
    rst_n = 1'b0;
    #1;
  endtask

  task automatic release_reset();
    @(negedge clk); #1;
    rst_n = 1'b1;
    @(posedge clk); #1;
  endtask

  // ---------------------------------------------------------------------
  // Directed tests
  // ---------------------------------------------------------------------
  task automatic test_idcode();
    logic [63:0] din;
    for (int unsigned k = 0; k < N_REPEAT; k++) begin
      select_reg(SEL_IDCODE);
      din = {$urandom(), $urandom()};
      dr_scan(DTM_IDCODE_W, din, scan_out);
      check(scan_out[DTM_IDCODE_W-1:0] == TB_IDCODE,
            "IDCODE scans out the configured value");
    end
    // Read-only: shifting data in must not alter what the next read sees.
    din = '1;
    dr_scan(DTM_IDCODE_W, din, scan_out);
    dr_scan(DTM_IDCODE_W, 64'd0, scan_out);
    check(scan_out[DTM_IDCODE_W-1:0] == TB_IDCODE,
          "IDCODE is unaffected by data shifted in");
  endtask

  task automatic test_bypass();
    localparam int unsigned NB = 12;
    logic [63:0] din;
    for (int unsigned k = 0; k < N_REPEAT; k++) begin
      select_reg(SEL_BYPASS);
      din = {$urandom(), $urandom()};
      dr_scan(NB, din, scan_out);
      check(scan_out[0] == 1'b0, "BYPASS captures 0");
      for (int unsigned i = 1; i < NB; i++)
        check(scan_out[i] == din[i-1], "BYPASS is a one-bit delay");
    end
  endtask

  task automatic test_dtmcs_capture();
    logic [DTM_DTMCS_W-1:0] v;
    clear_dmistat();
    read_dtmcs(v);
    check(v[DTMCS_VERSION_LSB +: 4] == DTMCS_VERSION_VAL, "DTMCS version field");
    check(v[DTMCS_ABITS_LSB +: 6] == 6'(DMI_ABITS),        "DTMCS abits equals the dm_addr width");
    check(v[DTMCS_IDLE_LSB +: 3] == DTMCS_IDLE_VAL,        "DTMCS idle field");
    check(v[DTMCS_DMISTAT_LSB +: DMI_OP_W] == DMI_STATUS_SUCCESS, "DTMCS dmistat reads 0 after clear");
    check(v[DTMCS_DMIRESET_BIT]     == 1'b0, "dmireset reads back 0");
    check(v[DTMCS_DMIHARDRESET_BIT] == 1'b0, "dmihardreset reads back 0");
    check(v[DTMCS_IDLE_LSB + 3] == 1'b0, "DTMCS bit 15 (reserved) reads 0");
    check(v[DTM_DTMCS_W-1 : DTMCS_DMIHARDRESET_BIT+1] == '0, "DTMCS upper reserved bits read 0");
  endtask

  task automatic test_reset_pulses();
    select_reg(SEL_DTMCS);
    dr_scan(DTM_DTMCS_W, 64'd0, scan_out);
    check(!last_hr, "no dmihardreset pulse when the bit is 0");
    dr_scan(DTM_DTMCS_W, 64'd1 << DTMCS_DMIRESET_BIT, scan_out);
    check(!last_hr, "dmireset alone does not raise dmihardreset");
    dr_scan(DTM_DTMCS_W, 64'd1 << DTMCS_DMIHARDRESET_BIT, scan_out);
    check(last_hr, "dmihardreset pulse on Update-DR when the bit is set");
    // The pulse is exactly the Update-DR cycle: not before, not after.
    dr_cycle(1'b1, 1'b0, 1'b0, 1'b0);
    check(!s_hr, "no pulse during Capture-DR");
    for (int unsigned i = 0; i < DTM_DTMCS_W; i++)
      dr_cycle(1'b0, 1'b1, 1'b0, (i == DTMCS_DMIHARDRESET_BIT));
    check(!s_hr, "no pulse while shifting");
    dr_cycle(1'b0, 1'b0, 1'b0, 1'b0);
    check(!s_hr, "no pulse in Exit1-DR");
    dr_cycle(1'b0, 1'b0, 1'b1, 1'b0);
    check(s_hr, "pulse during Update-DR");
    dr_cycle(1'b0, 1'b0, 1'b0, 1'b0);
    check(!s_hr, "pulse is gone the cycle after Update-DR");
    // Gated by the selected register: a DMI scan with the same bit set
    // in its data must not fire it.
    select_reg(SEL_DMI);
    dr_scan(DMI_REQ_W, '1, scan_out);
    check(!last_hr, "dmihardreset is gated by sel_dtmcs");
    clear_dmistat();
  endtask

  task automatic test_dmi_request();
    logic [DMI_REQ_W-1:0] r;
    for (int unsigned k = 0; k < N_REPEAT; k++) begin
      r = DMI_REQ_W'({$urandom(), $urandom()});
      select_reg(SEL_DMI);
      req_pending = 1'b0;
      dr_scan(DMI_REQ_W, 64'(r), scan_out);
      check(last_trig, "clean Update-DR raises dmi_req_trigger");
      check(stable_dmi_req == r, "request shifted in is what reaches the bridge");
    end
  endtask

  task automatic test_busy_sticky();
    logic [DMI_REQ_W-1:0] r2, r3;
    logic [DMI_OP_W-1:0]  stat;
    clear_dmistat();

    r2 = mk_req(DMI_OP_WRITE, DMI_ABITS'($urandom()), $urandom());
    select_reg(SEL_DMI);
    req_pending = 1'b1;
    dr_scan(DMI_REQ_W, 64'(r2), scan_out);
    check(!last_trig, "no trigger while a request is already pending (overrun)");
    req_pending = 1'b0;

    read_dmistat(stat);
    check(stat == DMI_STATUS_BUSY, "overrun latches dmistat = BUSY");

    // Sticky: still BUSY long after the pending request is gone.
    idle(8);
    read_dmistat(stat);
    check(stat == DMI_STATUS_BUSY, "dmistat stays sticky after the overrun clears");

    // While sticky, new requests are silently dropped...
    r3 = mk_req(DMI_OP_READ, DMI_ABITS'($urandom()), $urandom());
    select_reg(SEL_DMI);
    dr_scan(DMI_REQ_W, 64'(r3), scan_out);
    check(!last_trig, "request dropped while dmistat is non-zero");
    // ...and Capture-DR reports the sticky status with zeroed data and
    // the held (last shifted-in) address.
    check(scan_out[DMI_RESP_STATUS_LSB +: DMI_OP_W] == DMI_STATUS_BUSY,
          "DMI capture reports the sticky status");
    check(scan_out[DMI_RESP_DATA_LSB +: DMI_DATA_W] == '0,
          "DMI capture data is zero while an error is latched");
    check(scan_out[DMI_REQ_ADDR_LSB +: DMI_ABITS] == r2[DMI_REQ_ADDR_LSB +: DMI_ABITS],
          "DMI capture holds the previous address field");

    // dmireset releases it; the very next request goes through.
    clear_dmistat();
    read_dmistat(stat);
    check(stat == DMI_STATUS_SUCCESS, "dmireset clears dmistat");
    select_reg(SEL_DMI);
    dr_scan(DMI_REQ_W, 64'(r3), scan_out);
    check(last_trig, "requests flow again after dmireset");
  endtask

  task automatic test_overrun_gating();
    logic [DMI_OP_W-1:0] stat;
    clear_dmistat();
    // An Update-DR on any register OTHER than DMI, with a request pending,
    // is not a DMI overrun and must never latch BUSY.
    req_pending = 1'b1;
    select_reg(SEL_IDCODE);
    dr_scan(DTM_IDCODE_W, 64'd0, scan_out);
    select_reg(SEL_BYPASS);
    dr_scan(4, 64'd0, scan_out);
    select_reg(SEL_DTMCS);
    dr_scan(DTM_DTMCS_W, 64'd0, scan_out);
    req_pending = 1'b0;
    read_dmistat(stat);
    check(stat == DMI_STATUS_SUCCESS,
          "Update-DR on a non-DMI register while pending is not an overrun");
  endtask

  task automatic test_resp_hold();
    logic [DMI_DATA_W-1:0] rd;
    logic [DMI_RESP_W-1:0] resp, junk;
    logic [DMI_REQ_W-1:0]  last_req;

    clear_dmistat();
    select_reg(SEL_DMI);
    last_req = mk_req(DMI_OP_READ, DMI_ABITS'($urandom()), $urandom());
    dr_scan(DMI_REQ_W, 64'(last_req), scan_out);

    rd   = $urandom();
    resp = mk_resp(rd, DMI_STATUS_SUCCESS);
    junk = DMI_RESP_W'({$urandom(), $urandom()}) | mk_resp('0, 2'b01);
    junk[DMI_RESP_STATUS_LSB +: DMI_OP_W] = DMI_STATUS_SUCCESS;

    // The bus is only meaningful at the ack edge. Change it while the ack
    // is still high, then again after it drops: neither may be latched.
    stable_dmi_resp = resp;
    tck_ack         = 1'b1;
    idle(2);
    stable_dmi_resp = junk;
    idle(2);
    tck_ack         = 1'b0;
    stable_dmi_resp = ~junk;
    idle(12);      // arbitrarily long before the debugger gets round to it

    dr_scan(DMI_REQ_W, 64'd0, scan_out);
    check(scan_out[DMI_RESP_W-1:0] == resp,
          "held response survives delay and the bus changing underneath it");
    check(scan_out[DMI_REQ_ADDR_LSB +: DMI_ABITS] == last_req[DMI_REQ_ADDR_LSB +: DMI_ABITS],
          "address field holds its last shifted-in value on capture");
    check(scan_out[DMI_RESP_STATUS_LSB +: DMI_OP_W] == DMI_STATUS_SUCCESS, "captured status is SUCCESS");

    // A fresh ack edge replaces the held value.
    rd   = $urandom();
    resp = mk_resp(rd, DMI_STATUS_SUCCESS);
    ack_event(resp);
    dr_scan(DMI_REQ_W, 64'd0, scan_out);
    check(scan_out[DMI_RESP_W-1:0] == resp, "a new ack edge updates the held response");
  endtask

  task automatic test_failed_sticky();
    logic [DMI_OP_W-1:0] stat;
    logic [DMI_DATA_W-1:0] rd;
    clear_dmistat();
    select_reg(SEL_DMI);

    // A success response never touches dmistat.
    ack_event(mk_resp($urandom(), DMI_STATUS_SUCCESS));
    read_dmistat(stat);
    check(stat == DMI_STATUS_SUCCESS, "a SUCCESS response leaves dmistat at 0");

    // A failed response latches FAILED.
    rd = $urandom();
    ack_event(mk_resp(rd, DMI_STATUS_FAILED));
    read_dmistat(stat);
    check(stat == DMI_STATUS_FAILED, "a FAILED response latches dmistat = FAILED");

    // Sticky across later successes; first error wins over a later overrun.
    ack_event(mk_resp($urandom(), DMI_STATUS_SUCCESS));
    read_dmistat(stat);
    check(stat == DMI_STATUS_FAILED, "dmistat is not cleared by a later SUCCESS");
    select_reg(SEL_DMI);
    req_pending = 1'b1;
    dr_cycle(1'b0, 1'b0, 1'b1, 1'b0);
    req_pending = 1'b0;
    read_dmistat(stat);
    check(stat == DMI_STATUS_FAILED, "first error wins: a later overrun does not replace FAILED");

    // Capture shows the sticky status with zero data.
    select_reg(SEL_DMI);
    dr_scan(DMI_REQ_W, 64'd0, scan_out);
    check(scan_out[DMI_RESP_STATUS_LSB +: DMI_OP_W] == DMI_STATUS_FAILED,
          "DMI capture shows the sticky FAILED status");
    check(scan_out[DMI_RESP_DATA_LSB +: DMI_DATA_W] == '0, "DMI capture data is zero under FAILED");

    clear_dmistat();
    read_dmistat(stat);
    check(stat == DMI_STATUS_SUCCESS, "dmireset clears FAILED");

    // The reverse order: BUSY first, then a FAILED response, stays BUSY.
    select_reg(SEL_DMI);
    req_pending = 1'b1;
    dr_cycle(1'b0, 1'b0, 1'b1, 1'b0);
    req_pending = 1'b0;
    ack_event(mk_resp($urandom(), DMI_STATUS_FAILED));
    read_dmistat(stat);
    check(stat == DMI_STATUS_BUSY, "first error wins: FAILED does not replace BUSY");
    clear_dmistat();
  endtask

  task automatic test_tdo_mux();
    // Capture IDCODE so the selected register's LSB is known (TB_IDCODE[0]=1).
    select_reg(SEL_IDCODE);
    dr_cycle(1'b1, 1'b0, 1'b0, 1'b0);
    shift_ir = 1'b0;
    dr_cycle(1'b0, 1'b0, 1'b0, 1'b0);
    check(s_tdo == TB_IDCODE[0], "TDO follows the selected data register");

    // Shifting the IR takes priority over the DR select lines.
    shift_ir     = 1'b1;
    ir_shift_tdo = 1'b0;
    dr_cycle(1'b0, 1'b0, 1'b0, 1'b0);
    check(s_tdo == 1'b0, "IR shift-out (0) wins over a DR whose LSB is 1");
    ir_shift_tdo = 1'b1;
    select_reg(SEL_BYPASS);                      // bypass_q holds 0
    dr_cycle(1'b0, 1'b0, 1'b0, 1'b0);
    check(s_tdo == 1'b1, "IR shift-out (1) wins over a DR whose LSB is 0");
    shift_ir     = 1'b0;
    ir_shift_tdo = 1'b0;
  endtask

  task automatic test_hold_rules();
    logic [DMI_REQ_W-1:0] r;
    r = DMI_REQ_W'({$urandom(), $urandom()});
    select_reg(SEL_DMI);
    req_pending = 1'b0;
    dr_scan(DMI_REQ_W, 64'(r), scan_out);
    check(stable_dmi_req == r, "precondition: DMI register holds the request");

    // Another register being scanned must not disturb it.
    select_reg(SEL_DTMCS);
    dr_scan(DTM_DTMCS_W, {$urandom(), $urandom()} & ~(64'd3 << DTMCS_DMIRESET_BIT), scan_out);
    select_reg(SEL_IDCODE);
    dr_scan(DTM_IDCODE_W, {$urandom(), $urandom()}, scan_out);
    check(stable_dmi_req == r, "an unselected register holds while others are scanned");

    // Selected but neither capturing nor shifting (Pause / Exit / idle).
    select_reg(SEL_DMI);
    idle(6);
    check(stable_dmi_req == r, "a selected register holds outside Capture/Shift");
  endtask

  task automatic test_async_reset();
    logic [DMI_OP_W-1:0] stat;
    logic [DMI_REQ_W-1:0] r;
    // Latch an error and load the DMI register, then reset mid-cycle.
    select_reg(SEL_DMI);
    r = mk_req(DMI_OP_WRITE, DMI_ABITS'($urandom()), $urandom());
    dr_scan(DMI_REQ_W, 64'(r), scan_out);
    req_pending = 1'b1;
    dr_cycle(1'b0, 1'b0, 1'b1, 1'b0);
    req_pending = 1'b0;
    read_dmistat(stat);
    check(stat == DMI_STATUS_BUSY, "precondition: an error is latched before reset");

    apply_reset();
    check(stable_dmi_req == '0, "async reset clears the DMI register immediately");
    check(!dmihardreset_pulse && !dmi_req_trigger, "no pulses while in reset");
    release_reset();
    read_dmistat(stat);
    check(stat == DMI_STATUS_SUCCESS, "async reset clears dmistat");
    select_reg(SEL_IDCODE);
    dr_scan(DTM_IDCODE_W, 64'd0, scan_out);
    check(scan_out[DTM_IDCODE_W-1:0] == TB_IDCODE, "IDCODE intact after reset");
  endtask

  // ---------------------------------------------------------------------
  // Randomized model of dmistat and the request gate
  // ---------------------------------------------------------------------
  task automatic test_random_model();
    logic [DMI_OP_W-1:0] m_stat, stat, st;
    logic                pend;
    clear_dmistat();
    m_stat = DMI_STATUS_SUCCESS;
    for (int unsigned i = 0; i < N_RANDOM; i++) begin
      case ($urandom_range(0, 4))
        0, 1: begin   // an Update-DR on the DMI register, pending or not
          pend = 1'($urandom_range(0, 1));
          select_reg(SEL_DMI);
          req_pending = pend;
          dr_cycle(1'b0, 1'b0, 1'b1, 1'b0);
          check(s_trig == (m_stat == DMI_STATUS_SUCCESS && !pend),
                "model: trigger iff no error latched and nothing pending");
          if (m_stat == DMI_STATUS_SUCCESS && pend) m_stat = DMI_STATUS_BUSY;
          req_pending = 1'b0;
          idle(1);
        end
        2: begin      // a response arrives from the core domain
          st = 1'($urandom_range(0, 1)) ? DMI_STATUS_FAILED : DMI_STATUS_SUCCESS;
          ack_event(mk_resp($urandom(), st));
          if (m_stat == DMI_STATUS_SUCCESS && st == DMI_STATUS_FAILED)
            m_stat = DMI_STATUS_FAILED;
        end
        3: begin      // the debugger clears it
          clear_dmistat();
          m_stat = DMI_STATUS_SUCCESS;
        end
        default: begin // the debugger reads it back
          read_dmistat(stat);
          check(stat == m_stat, "model: dmistat read back matches");
        end
      endcase
    end
    read_dmistat(stat);
    check(stat == m_stat, "model: final dmistat matches");
    clear_dmistat();
  endtask

  // ---------------------------------------------------------------------
  // Main
  // ---------------------------------------------------------------------
  initial begin
    rst_n           = 1'b0;
    tdi             = 1'b0;
    capture_dr      = 1'b0;
    shift_dr        = 1'b0;
    update_dr       = 1'b0;
    shift_ir        = 1'b0;
    ir_shift_tdo    = 1'b0;
    stable_dmi_resp = '0;
    tck_ack         = 1'b0;
    req_pending     = 1'b0;
    select_reg(SEL_IDCODE);

    repeat (3) @(posedge clk);
    #1;
    check(stable_dmi_req == '0 && tdo == 1'b0, "outputs are 0 while in reset");
    @(negedge clk); #1;
    rst_n = 1'b1;
    @(posedge clk); #1;

    test_idcode();
    test_bypass();
    test_dtmcs_capture();
    test_reset_pulses();
    test_dmi_request();
    test_busy_sticky();
    test_overrun_gating();
    test_resp_hold();
    test_failed_sticky();
    test_tdo_mux();
    test_hold_rules();
    test_random_model();
    test_async_reset();

    finish_tb();
  end

endmodule : tb_meds_s1_dtm_dr_regs
