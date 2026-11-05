// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// s1_regfile : integer register file                              [COMPLETE]
//
// 2**REG_ADDR_W registers of XLEN bits; x0 reads as zero.  N_READ read ports
// with a one-cycle registered read, and one write port.  All storage is
// meds_s1_sram (R-C5) and is not reset.
//
// Reference: SPEC sections 7.2, 9.2, 17.  Testbench: verif/unit/tb_s1_regfile.sv.
// Contract and design rationale: docs/modules/s1_regfile.md.
// =============================================================================

module s1_regfile
  import s1_pkg::*;
#(
  parameter int unsigned N_READ = 2
) (
  input  logic                  clk_i,
  input  logic                  rst_ni,

  // Read: address in one cycle, data in the next.  Packed, not unpacked
  // arrays: Verilator 5.020 silently miscompiles a write to one element of an
  // unpacked-array input port (it reads as zero in the module).
  input  logic [N_READ-1:0][REG_ADDR_W-1:0] raddr_i,
  output logic [N_READ-1:0][XLEN-1:0]       rdata_o,

  // Write, at retire (SPEC 9.2 step 1).  A write to x0 is discarded.
  input  logic                  we_i,
  input  logic [REG_ADDR_W-1:0] waddr_i,
  input  logic [XLEN-1:0]       wdata_i
);

  localparam int unsigned N_REG = 2**REG_ADDR_W;

  logic wr;
  assign wr = we_i && (waddr_i != '0);

  // Last cycle's write.  meds_s1_sram returns the OLD word when an address is
  // read and written in the same cycle, so that write is bypassed from here.
  // Only wr_q is reset; waddr_q/wdata_q load on a write and are ignored while
  // wr_q is low.
  logic                  wr_q;
  logic [REG_ADDR_W-1:0] waddr_q;
  logic [XLEN-1:0]       wdata_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) wr_q <= 1'b0;
    else         wr_q <= wr;
  end

  always_ff @(posedge clk_i) begin
    if (wr) begin
      waddr_q <= waddr_i;
      wdata_q <= wdata_i;
    end
  end

  for (genvar p = 0; p < N_READ; p++) begin : g_port

    // meds_s1_sram has one port, and a read port is busy every cycle, so each
    // read port owns two banks.  cur_q[r] names the bank holding register r.
    // A read uses that bank; a write in the same cycle goes to the other bank
    // and repoints cur_q, so neither bank ever sees two accesses at once.
    // cur_q[0] belongs to x0: it is never written, so it stays 0 and synthesis
    // removes it.
    logic [N_REG-1:0]      cur_q;
    logic                  rsel, rsel_q;
    logic [REG_ADDR_W-1:0] raddr_q;

    assign rsel = cur_q[raddr_i[p]];

    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        cur_q   <= '0;
        rsel_q  <= 1'b0;
        raddr_q <= '0;
      end else begin
        rsel_q  <= rsel;
        raddr_q <= raddr_i[p];
        for (int unsigned r = 1; r < N_REG; r++) begin
          if (wr && (waddr_i == REG_ADDR_W'(r))) cur_q[r] <= ~rsel;
        end
      end
    end

    logic [1:0]           bank_wr;
    logic [1:0][XLEN-1:0] bank_rdata;

    for (genvar b = 0; b < 2; b++) begin : g_bank
      assign bank_wr[b] = wr && (rsel != b[0]);

      meds_s1_sram #(
        .DW    (XLEN),
        .DEPTH (N_REG)
      ) u_sram (
        .clk_i,
        .rst_ni,
        .req_i   (bank_wr[b] || (rsel == b[0])),
        .we_i    (bank_wr[b]),
        .addr_i  (bank_wr[b] ? waddr_i : raddr_i[p]),
        .be_i    ('1),
        .wdata_i (wdata_i),
        .rdata_o (bank_rdata[b])
      );
    end

    // Newest value first: a write retiring this cycle, then last cycle's
    // write, then the bank that was read.
    always_comb begin
      if (raddr_q == '0) begin
        rdata_o[p] = '0;
      end else if (wr && (waddr_i == raddr_q)) begin
        rdata_o[p] = wdata_i;
      end else if (wr_q && (waddr_q == raddr_q)) begin
        rdata_o[p] = wdata_q;
      end else begin
        rdata_o[p] = bank_rdata[rsel_q];
      end
    end

  end

endmodule
