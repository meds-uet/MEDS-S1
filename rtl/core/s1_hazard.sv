// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// s1_hazard : RAW hazard and forwarding select for one ID-stage instruction
//                                                                   [WIP -- T-02]
// Description  :
// Purely combinational.  For each source operand, finds the youngest older
// writer of that register in EX, EX/MEM or a not-yet-completed MEM/WB entry:
//   - in EX, not a load/AMO : value arrives through EX's own EX/MEM register
//                             next cycle (from_ex_o -> FWD_EXMEM)
//   - in EX/MEM, not a load : value is already on exmem_i.result (from_mem_o)
//   - a load/AMO/LR/SC anywhere, or a pending MEM/WB entry : stall
// Anything older has completed in WB, and the register file bypasses it.
//
// Reference: SPEC 8.1; docs/modules/s1_id.md.  Testbench: verif/unit/tb_s1_hazard.sv.
// =============================================================================

module s1_hazard
  import s1_pkg::*;
(
  input  logic [REG_ADDR_W-1:0] rs1_i,
  input  logic [REG_ADDR_W-1:0] rs2_i,
  input  logic                  rs1_re_i,
  input  logic                  rs2_re_i,

  // Writer in EX (the ID/EX register)
  input  logic                  ex_wr_i,       // valid and writes rd
  input  logic [REG_ADDR_W-1:0] ex_rd_i,
  input  logic                  ex_load_i,     // value is not known until MEM

  // Writer in EX/MEM
  input  logic                  mem_wr_i,
  input  logic [REG_ADDR_W-1:0] mem_rd_i,
  input  logic                  mem_load_i,

  // MEM/WB entry still waiting on the D$
  input  logic                  wbp_wr_i,
  input  logic [REG_ADDR_W-1:0] wbp_rd_i,

  output logic                  from_ex_rs1_o,
  output logic                  from_ex_rs2_o,
  output logic                  from_mem_rs1_o,
  output logic                  from_mem_rs2_o,
  output logic                  stall_o        // a needed operand is not available yet
);

  logic [1:0] stall_rs, from_ex, from_mem;

  always_comb begin
    for (int unsigned k = 0; k < 2; k++) begin
      logic [REG_ADDR_W-1:0] r;
      logic                  re, hit_ex, hit_mem, hit_wbp;
      r       = (k == 0) ? rs1_i    : rs2_i;
      re      = ((k == 0) ? rs1_re_i : rs2_re_i) && (r != '0);
      hit_ex  = re && ex_wr_i  && (ex_rd_i  == r);
      hit_mem = re && mem_wr_i && (mem_rd_i == r);
      hit_wbp = re && wbp_wr_i && (wbp_rd_i == r);

      from_ex[k]  = hit_ex && !ex_load_i;
      from_mem[k] = !hit_ex && hit_mem && !mem_load_i;
      stall_rs[k] = hit_ex  ? ex_load_i
                  : hit_mem ? mem_load_i
                  :           hit_wbp;
    end
  end

  assign from_ex_rs1_o  = from_ex[0];
  assign from_ex_rs2_o  = from_ex[1];
  assign from_mem_rs1_o = from_mem[0];
  assign from_mem_rs2_o = from_mem[1];
  assign stall_o        = |stall_rs;

endmodule
