// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0

module s1_lsu_controller
  import s1_pkg::*;
(
  input  logic                  clk_i,
  input  logic                  rst_ni,
  input  logic                  lsu_valid_i,
  output logic                  lsu_ready_o,
  input  logic [XLEN-1:0]      lsu_addr_i,
  input  logic [XLEN-1:0]      lsu_wdata_i,
  input  logic [2:0]            lsu_size_i,
  input  logic                  lsu_write_i,
  input  logic                  lsu_unsigned_i,
  input  priv_lvl_e             lsu_mode_i,
  input  logic [MXIF_ID_W-1:0] lsu_id_i,

  output logic                  check_valid_o,
  output logic [XLEN-1:0]      check_addr_o,
  output logic [2:0]            check_size_o,
  output logic                  check_write_o,
  output priv_lvl_e             check_mode_o,
  input  logic                  pma_allow_i,
  input  logic [5:0]            pma_fault_code_i,

  output logic                  mem_req_valid_o,
  input  logic                  mem_req_ready_i,
  output mem_req_t              mem_req_o,
  input  logic                  mem_rsp_valid_i,
  output logic                  mem_rsp_ready_o,
  /* verilator lint_off UNUSEDSIGNAL */
  input  mem_rsp_t              mem_rsp_i,
  /* verilator lint_on UNUSEDSIGNAL */

  output logic                  lsu_resp_valid_o,
  input  logic                  lsu_resp_ready_i,
  output logic [XLEN-1:0]      lsu_rdata_o,
  output logic                  lsu_fault_o,
  output logic [5:0]            lsu_fault_code_o,
  output logic [XLEN-1:0]      lsu_fault_addr_o
);

  typedef enum logic [2:0] {
    ST_IDLE, ST_CHECK, ST_ISSUE, ST_WAIT_RSP, ST_RESP
  } state_e;

  state_e state_q, state_d;
  logic [XLEN-1:0] addr_q, wdata_q;
  logic [2:0] size_q;
  logic write_q, unsigned_q;
  priv_lvl_e mode_q;
  logic [MXIF_ID_W-1:0] id_q;
  logic [XLEN-1:0] response_data_q;
  logic response_fault_q;
  logic [5:0] response_fault_code_q;
  logic [XLEN-1:0] response_fault_addr_q;
  logic size_valid, alignment_ok;
  logic [XLEN/8-1:0] mem_be;
  logic [XLEN-1:0] mem_wdata, load_data;

  s1_lsu_datapath datapath (
    .addr_i          (addr_q[2:0]),
    .store_data_i    (wdata_q),
    .size_i          (size_q),
    .load_unsigned_i (unsigned_q),
    .response_data_i (mem_rsp_i.rdata),
    .size_valid_o    (size_valid),
    .alignment_ok_o  (alignment_ok),
    .mem_be_o        (mem_be),
    .mem_wdata_o     (mem_wdata),
    .load_data_o     (load_data)
  );

  always_comb begin
    state_d = state_q;
    case (state_q)
      ST_IDLE: if (lsu_valid_i) state_d = ST_CHECK;
      ST_CHECK: begin
        if (!size_valid || !alignment_ok || !pma_allow_i) state_d = ST_RESP;
        else state_d = ST_ISSUE;
      end
      ST_ISSUE: if (mem_req_ready_i) state_d = ST_WAIT_RSP;
      ST_WAIT_RSP: if (mem_rsp_valid_i && mem_rsp_i.id == id_q) state_d = ST_RESP;
      ST_RESP: if (lsu_resp_ready_i) state_d = ST_IDLE;
      default: state_d = ST_IDLE;
    endcase
  end

  always_comb begin
    lsu_ready_o = (state_q == ST_IDLE);
    check_valid_o = (state_q == ST_CHECK);
    check_addr_o = addr_q;
    check_size_o = size_q;
    check_write_o = write_q;
    check_mode_o = mode_q;

    mem_req_valid_o = (state_q == ST_ISSUE);
    mem_req_o = '0;
    mem_req_o.addr = addr_q;
    mem_req_o.we = write_q;
    mem_req_o.be = mem_be;
    mem_req_o.wdata = mem_wdata;
    mem_req_o.size = size_q;
    mem_req_o.mode = mode_q;
    mem_req_o.id = id_q;

    // Keep an unmatched response pending instead of accepting and dropping it.
    mem_rsp_ready_o = (state_q == ST_WAIT_RSP) &&
                      (!mem_rsp_valid_i || mem_rsp_i.id == id_q);
    lsu_resp_valid_o = (state_q == ST_RESP);
    lsu_rdata_o = response_data_q;
    lsu_fault_o = response_fault_q;
    lsu_fault_code_o = response_fault_code_q;
    lsu_fault_addr_o = response_fault_addr_q;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= ST_IDLE;
      addr_q <= '0;
      wdata_q <= '0;
      size_q <= '0;
      write_q <= 1'b0;
      unsigned_q <= 1'b0;
      mode_q <= PRIV_M;
      id_q <= '0;
      response_data_q <= '0;
      response_fault_q <= 1'b0;
      response_fault_code_q <= '0;
      response_fault_addr_q <= '0;
    end else begin
      state_q <= state_d;

      if (state_q == ST_IDLE && lsu_valid_i) begin
        addr_q <= lsu_addr_i;
        wdata_q <= lsu_wdata_i;
        size_q <= lsu_size_i;
        write_q <= lsu_write_i;
        unsigned_q <= lsu_unsigned_i;
        mode_q <= lsu_mode_i;
        id_q <= lsu_id_i;
      end

      if (state_q == ST_CHECK && state_d == ST_RESP) begin
        response_data_q <= '0;
        response_fault_q <= 1'b1;
        response_fault_addr_q <= addr_q;
        if (!size_valid) begin
          response_fault_code_q <= EXC_ILLEGAL_INSTR;
        end else if (!alignment_ok) begin
          response_fault_code_q <= write_q ? EXC_STORE_ADDR_MISALIGNED :
                                              EXC_LOAD_ADDR_MISALIGNED;
        end else begin
          response_fault_code_q <= (pma_fault_code_i != 0) ?
                                   pma_fault_code_i :
                                   (write_q ? EXC_STORE_ACCESS_FAULT :
                                              EXC_LOAD_ACCESS_FAULT);
        end
      end

      if (state_q == ST_WAIT_RSP && mem_rsp_valid_i && mem_rsp_i.id == id_q) begin
        response_data_q <= write_q ? '0 : load_data;
        response_fault_q <= mem_rsp_i.err;
        response_fault_code_q <= mem_rsp_i.err ?
                                 (write_q ? EXC_STORE_ACCESS_FAULT :
                                            EXC_LOAD_ACCESS_FAULT) : '0;
        response_fault_addr_q <= addr_q;
      end

      if (state_q == ST_RESP && lsu_resp_ready_i) begin
        response_fault_q <= 1'b0;
        response_fault_code_q <= '0;
      end
    end
  end
endmodule
