// Copyright 2026 Maktab-e-Digital Systems Lahore.
 // Licensed under the Apache License, Version 2.0, see LICENSE file for details.
 // SPDX-License-Identifier: Apache-2.0
 //
 // =============================================================================
 // meds_s1_lite_regif : AXI4-Lite slave -> register-file adapter [COMPLETE]
 //
 // Shared AXI4-Lite adapter for peripheral register files. Independent AW, W,
 // and AR buffers accept requests in either order. A round-robin arbiter serves
 // one register access per cycle; registered B and R responses hold their
 // payloads until accepted. Supports 32-bit and 64-bit registers on the I4 bus.
 //
 // Register-file contract (`lite_reg_req_t` / `lite_reg_rsp_t`):
 //
 //   reg_req_o.we/re       one-cycle strobes, never both in the same cycle
 //   reg_req_o.addr        byte offset, aligned down to REG_DW/8
 //   reg_req_o.wdata/strb  write data shifted to the register lane and byte enables
 //   reg_rsp_i.rdata       combinational read data, valid in the same cycle as re
 //   reg_rsp_i.err         combinational from addr: "nothing is mapped here"
 //
 // Reference: INTERFACES.md section 3 (I4).
 // Full contract: docs/modules/meds_s1_lite_regif.md.
 // Testbench: verif/unit/tb_meds_s1_lite_regif.sv
 // =============================================================================

module meds_s1_lite_regif
  import meds_s1_lite_pkg::*;
#(
  // Window address bits, derived from the region size in configs/*.yaml.
  parameter int unsigned ADDR_W = 16,
  // Register-file width.  Must be LITE_DW (64) or LITE_DW/2 (32).
  parameter int unsigned REG_DW = 32
) (
  input  logic                clk_i,
  input  logic                rst_ni,

  // I4 bus port (frozen).
  input  lite_req_t           lite_req_i,
  output lite_rsp_t           lite_rsp_o,

  // Register-file port, with parameter-sized values in the low bits.
  output lite_reg_req_t       reg_req_o,
  input  lite_reg_rsp_t       reg_rsp_i
);

  localparam int unsigned REG_SW         = REG_DW / 8;
  localparam int unsigned REG_ALIGN_BITS = $clog2(REG_SW);

  logic [ADDR_W-1:0]   addr_o;
  logic                we_o, re_o;
  logic [REG_DW-1:0]   wdata_o, rdata_i;
  logic [REG_SW-1:0]   wstrb_o;
  logic                err_i;

  assign reg_req_o.addr  = {{(LITE_AW-ADDR_W){1'b0}}, addr_o};
  assign reg_req_o.we    = we_o;
  assign reg_req_o.re    = re_o;
  assign reg_req_o.wdata = {{(LITE_DW-REG_DW){1'b0}}, wdata_o};
  assign reg_req_o.wstrb = {{(LITE_SW-REG_SW){1'b0}}, wstrb_o};
  assign rdata_i         = reg_rsp_i.rdata[REG_DW-1:0];
  assign err_i           = reg_rsp_i.err;

  // Separate AW and W holders allow either channel to arrive first.
  logic          aw_full_q, w_full_q, ar_full_q;
  // READY remains low until the first clock edge after reset release.
  logic          active_q;
  lite_addr_t    aw_addr_q, ar_addr_q;
  lite_data_t    wdata_q;
  lite_strb_t    wstrb_q;

  logic          b_full_q, r_full_q;
  lite_resp_t    bresp_q, rresp_q;
  lite_data_t    rdata_q;

  // The next tie favours the direction opposite the previous grant.
  logic          last_grant_write_q;

  logic          write_candidate, read_candidate;
  logic          execute_write, execute_read;
  logic          write_spans_lanes, write_error;
  lite_data_t    read_bus_data;

  // Generate-scope tasks reject invalid parameters during elaboration.
  if ((ADDR_W < 3) || (ADDR_W > LITE_AW)) begin : gen_bad_addr_width
    $fatal(1, "meds_s1_lite_regif: ADDR_W (%0d) must be in [3, %0d]",
           ADDR_W, LITE_AW);
  end
  if ((REG_DW != LITE_DW) && (REG_DW != (LITE_DW / 2))) begin : gen_bad_reg_width
    $fatal(1, "meds_s1_lite_regif: REG_DW (%0d) must be %0d or %0d",
           REG_DW, LITE_DW / 2, LITE_DW);
  end

  // R-C10: channel outputs depend on registered state, never response READY.
  always_comb begin
    lite_rsp_o = LITE_RSP_IDLE;
    if (active_q) begin
      lite_rsp_o.aw_ready = !aw_full_q;
      lite_rsp_o.w_ready  = !w_full_q;
      lite_rsp_o.ar_ready = !ar_full_q;
    end
    lite_rsp_o.b_valid = b_full_q;
    lite_rsp_o.b.resp  = bresp_q;
    lite_rsp_o.r_valid = r_full_q;
    lite_rsp_o.r.resp  = rresp_q;
    lite_rsp_o.r.data  = rdata_q;
  end

  // Keep arbitration independent of the peripheral decode to avoid feedback
  // from err_i or rdata_i into addr_o.
  always_comb begin
    write_candidate = aw_full_q && w_full_q && !b_full_q;
    read_candidate  = ar_full_q && !r_full_q;
    execute_write   = 1'b0;
    execute_read    = 1'b0;

    if (write_candidate && read_candidate) begin
      if (last_grant_write_q) begin
        execute_read = 1'b1;
      end else begin
        execute_write = 1'b1;
      end
    end else if (write_candidate) begin
      execute_write = 1'b1;
    end else if (read_candidate) begin
      execute_read = 1'b1;
    end
  end

  always_comb begin
    addr_o = '0;
    if (execute_write) begin
      addr_o = aw_addr_q[ADDR_W-1:0];
    end else if (execute_read) begin
      addr_o = ar_addr_q[ADDR_W-1:0];
    end
    addr_o[REG_ALIGN_BITS-1:0] = '0;
    wdata_o = '0;
    wstrb_o = '0;
    if (execute_write) begin
      if (REG_DW == LITE_DW) begin
        wdata_o = wdata_q[REG_DW-1:0];
        wstrb_o = wstrb_q[REG_SW-1:0];
      end else if (aw_addr_q[REG_ALIGN_BITS]) begin
        wdata_o = wdata_q[LITE_DW-1 -: REG_DW];
        wstrb_o = wstrb_q[LITE_SW-1 -: REG_SW];
      end else begin
        wdata_o = wdata_q[REG_DW-1:0];
        wstrb_o = wstrb_q[REG_SW-1:0];
      end
    end
  end

  // Cross-lane writes must fail without modifying a 32-bit register file.
  always_comb begin
    write_spans_lanes = 1'b0;
    if (REG_DW == (LITE_DW / 2)) begin
      write_spans_lanes = (|wstrb_q[(LITE_SW / 2)-1:0]) &&
                          (|wstrb_q[LITE_SW-1:LITE_SW / 2]);
    end
  end

  // Keep the register write strobe independent of peripheral error decode.
  assign we_o = execute_write && !write_spans_lanes;
  assign re_o = execute_read;

  // Peripheral decode errors still determine the write response.
  always_comb begin
    write_error = err_i || write_spans_lanes;
  end

  // Separate read data from address selection to keep decode feedback one-way.
  always_comb begin
    read_bus_data = '0;
    if (execute_read) begin
      if (REG_DW == LITE_DW) begin
        read_bus_data[REG_DW-1:0] = rdata_i;
      end else if (ar_addr_q[REG_ALIGN_BITS]) begin
        read_bus_data[LITE_DW-1 -: REG_DW] = rdata_i;
      end else begin
        read_bus_data[REG_DW-1:0] = rdata_i;
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      active_q            <= 1'b0;
      aw_full_q           <= 1'b0;
      w_full_q            <= 1'b0;
      ar_full_q           <= 1'b0;
      aw_addr_q           <= '0;
      ar_addr_q           <= '0;
      wdata_q             <= '0;
      wstrb_q             <= '0;
      b_full_q            <= 1'b0;
      r_full_q            <= 1'b0;
      bresp_q             <= RESP_OKAY;
      rresp_q             <= RESP_OKAY;
      rdata_q             <= '0;
      last_grant_write_q  <= 1'b0;
    end else begin
      active_q <= 1'b1;
      if (lite_rsp_o.aw_ready && lite_req_i.aw_valid) begin
        aw_full_q <= 1'b1;
        aw_addr_q <= lite_req_i.aw.addr;
      end
      if (lite_rsp_o.w_ready && lite_req_i.w_valid) begin
        w_full_q <= 1'b1;
        wdata_q  <= lite_req_i.w.data;
        wstrb_q  <= lite_req_i.w.strb;
      end
      if (lite_rsp_o.ar_ready && lite_req_i.ar_valid) begin
        ar_full_q <= 1'b1;
        ar_addr_q <= lite_req_i.ar.addr;
      end

      if (b_full_q && lite_req_i.b_ready) begin
        b_full_q <= 1'b0;
      end
      if (r_full_q && lite_req_i.r_ready) begin
        r_full_q <= 1'b0;
      end

      if (execute_write) begin
        aw_full_q          <= 1'b0;
        w_full_q           <= 1'b0;
        b_full_q           <= 1'b1;
        bresp_q            <= write_error ? RESP_SLVERR : RESP_OKAY;
        last_grant_write_q <= 1'b1;
      end else if (execute_read) begin
        ar_full_q          <= 1'b0;
        r_full_q           <= 1'b1;
        rresp_q            <= err_i ? RESP_SLVERR : RESP_OKAY;
        rdata_q            <= read_bus_data;
        last_grant_write_q <= 1'b0;
      end
    end
  end

endmodule
