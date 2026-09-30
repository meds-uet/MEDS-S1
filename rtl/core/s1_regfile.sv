// =============================================================================
// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// Author(s)    : Ammarah Wakeel (ammarahwakeel9@gmail.com) (Sep,2026)
// Modified By  :
//
// s1_regfile   : ID-stage register file, reads and forwarding-source select  [WIP -- T-02]
// Description  :
// 32x64 integer register file (x0 hardwired to zero) with two combinational
// read ports and one retire-time write port, plus the forwarding-source half
// of SPEC 8.1's four-source network: for each of rs1/rs2 this module decides
// whether EX should use the plain register-file read, the instruction
// currently in EX (SPEC 8.1's EX/MEM source), the instruction currently in
// MEM (MEM/WB source), or a completed-but-not-retired completion buffer
// entry (CB source). The actual bypass mux that resolves the selected source
// into a value lives in s1_execute.sv -- this module supplies the raw
// register value and the selector, not the already-forwarded value.
//
// Reference: SPEC 6, 7.2, 8.1, 9.2. Contract: docs/modules/s1_regfile.md.
// =============================================================================

module s1_regfile
  import s1_pkg::*;
(
  input  logic                  clk_i,
  input  logic                  rst_ni,

  // ID: which registers this cycle's instruction reads (decoded_op_t.rs1/rs2)
  input  logic [REG_ADDR_W-1:0] rs1_addr_i,
  input  logic [REG_ADDR_W-1:0] rs2_addr_i,

  output logic [XLEN-1:0]       rs1_val_o,     // raw read, same-cycle write-bypassed
  output logic [XLEN-1:0]       rs2_val_o,
  output fwd_src_e              rs1_fwd_o,     // which source EX should actually use
  output fwd_src_e              rs2_fwd_o,

  // Retire-time architectural write (SPEC 9.2 step 1). Driven by the
  // completion buffer; a write to x0 is discarded.
  input  logic                  rd_we_i,
  input  logic [REG_ADDR_W-1:0] rd_addr_i,
  input  logic [XLEN-1:0]       rd_wdata_i,

  // Hazard snoop: the instruction currently in EX (SPEC 8.1 EX/MEM source).
  // "Currently in EX" is what this cycle's ID/EX register holds; by the time
  // this cycle's ID instruction itself reaches EX, that producer's result
  // will be sitting in the EX/MEM register, which s1_execute.sv reads
  // internally -- this module only needs to know whether that match exists.
  input  logic                  ex_valid_i,
  input  logic [REG_ADDR_W-1:0] ex_rd_i,
  input  logic                  ex_rd_we_i,

  // Hazard snoop: the instruction currently in MEM (SPEC 8.1 MEM/WB source).
  input  logic                  mem_valid_i,
  input  logic [REG_ADDR_W-1:0] mem_rd_i,
  input  logic                  mem_rd_we_i,

  // Hazard snoop: does a completed-but-not-retired completion buffer entry
  // exist for rs1 / rs2 (SPEC 8.1's fourth source, SPEC 9)? A query into
  // s1_completion_buffer.sv, which owns the CB array and is therefore the
  // only place that can correctly resolve ties between multiple in-flight
  // producers of the same register (SPEC 8.2's hazard/stall table).
  //
  // Provisional: s1_completion_buffer.sv does not exist yet (rtl/core/
  // README.md: TODO, R-01). This is this module's proposed half of that
  // interface, not a settled contract -- see docs/modules/s1_regfile.md.
  input  logic                  cb_rs1_hit_i,
  input  logic                  cb_rs2_hit_i
);

  // ---------------------------------------------------------------------------
  // Storage. x0 (index 0) is never written; reads of it are forced to zero
  // below regardless of what happens to be sitting in regs_q[0].
  // ---------------------------------------------------------------------------
  logic [XLEN-1:0] regs_q [32];

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      for (int i = 0; i < 32; i++) regs_q[i] <= '0;
    end else if (rd_we_i && rd_addr_i != '0) begin
      regs_q[rd_addr_i] <= rd_wdata_i;
    end
  end

  // ---------------------------------------------------------------------------
  // Read ports. A retire-time write and a decode read of the same address in
  // the same cycle must see the new value, not the value the flops hold
  // until the next edge -- without this, an instruction retiring the same
  // cycle its immediate successor is decoded would read a stale operand.
  // ---------------------------------------------------------------------------
  function automatic logic [XLEN-1:0] read_port(logic [REG_ADDR_W-1:0] addr);
    if (addr == '0) begin
      read_port = '0;
    end else if (rd_we_i && rd_addr_i == addr) begin
      read_port = rd_wdata_i;
    end else begin
      read_port = regs_q[addr];
    end
  endfunction

  assign rs1_val_o = read_port(rs1_addr_i);
  assign rs2_val_o = read_port(rs2_addr_i);

  // ---------------------------------------------------------------------------
  // Forwarding-source selection (SPEC 8.1). Priority is youngest-producer-
  // first: EX/MEM > MEM/WB > CB > plain register-file read, because a more
  // recently issued write to the same register always shadows an older one
  // that hasn't retired yet. x0 never forwards, even if some in-flight
  // entry's rd_we happens to be set for rd==x0 (s1_decode.sv does not
  // special-case x0 -- see its "Known limitations"): a hazard on x0 is not a
  // hazard, because a write to x0 is always architecturally discarded.
  //
  // This assumes the load-use stall (SPEC 8.2: "load-use -> stall 1"; here,
  // a load in EX while its consumer is in ID) has already been taken by the
  // time this is evaluated,
  // so the case never needs a special load check here -- if it stalls, ID
  // re-evaluates a cycle later once the load has moved from EX to MEM, and
  // the ordinary MEM/WB path below applies with no extra cycle from here.
  // ---------------------------------------------------------------------------
  function automatic fwd_src_e select_fwd(logic [REG_ADDR_W-1:0] addr, logic cb_hit);
    if (addr == '0) begin
      select_fwd = FWD_RF;
    end else if (ex_valid_i && ex_rd_we_i && ex_rd_i == addr) begin
      select_fwd = FWD_EXMEM;
    end else if (mem_valid_i && mem_rd_we_i && mem_rd_i == addr) begin
      select_fwd = FWD_MEMWB;
    end else if (cb_hit) begin
      select_fwd = FWD_CB;
    end else begin
      select_fwd = FWD_RF;
    end
  endfunction

  assign rs1_fwd_o = select_fwd(rs1_addr_i, cb_rs1_hit_i);
  assign rs2_fwd_o = select_fwd(rs2_addr_i, cb_rs2_hit_i);

endmodule
