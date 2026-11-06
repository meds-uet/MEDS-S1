
// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0

// meds_s1_clint
// Contract: docs/modules/meds_s1_clint.md
//
// Single-hart CLINT providing machine software and timer interrupts.
// MTIME advances only when rtc_tick_i is asserted.

module meds_s1_clint
  import meds_s1_lite_pkg::*;
(
  input  logic      clk_i,
  input  logic      rst_ni,
  input  logic      rtc_tick_i,
  input  lite_req_t lite_req_i,
  output lite_rsp_t lite_rsp_o,
  output logic      msip_o,
  output logic      mtip_o
);

  localparam int unsigned ADDR_W = 16;
  localparam int unsigned REG_DW = 64;

  localparam logic [ADDR_W-1:0] MSIP_OFFSET     = 'h0000;
  localparam logic [ADDR_W-1:0] MTIME_OFFSET    = 'h4000;
  localparam logic [ADDR_W-1:0] MTIMECMP_OFFSET = 'hBFF8;

  localparam int unsigned MSIP_BIT = 0;

  logic [REG_DW-1:0] mtime;
  logic [REG_DW-1:0] mtimecmp;
  logic              msip;

  lite_reg_req_t reg_req;
  lite_reg_rsp_t reg_rsp;

  meds_s1_lite_regif #(
    .ADDR_W (ADDR_W),
    .REG_DW (REG_DW)
  ) i_lite_regif (
    .clk_i      (clk_i),
    .rst_ni     (rst_ni),
    .lite_req_i (lite_req_i),
    .lite_rsp_o (lite_rsp_o),
    .reg_req_o  (reg_req),
    .reg_rsp_i  (reg_rsp)
  );

  // Register read data and address decode.
  // err must be cleared for mapped addresses on BOTH reads and writes.
  always_comb begin
    reg_rsp = '0;
    reg_rsp.err = 1'b1;

    case (reg_req.addr)
      LITE_AW'(MSIP_OFFSET): begin
        if (reg_req.re)
          reg_rsp.rdata[MSIP_BIT] = msip;
        reg_rsp.err = 1'b0;
      end

      LITE_AW'(MTIME_OFFSET): begin
        if (reg_req.re)
          reg_rsp.rdata = LITE_DW'(mtime);
        reg_rsp.err = 1'b0;
      end

      LITE_AW'(MTIMECMP_OFFSET): begin
        if (reg_req.re)
          reg_rsp.rdata = LITE_DW'(mtimecmp);
        reg_rsp.err = 1'b0;
      end

      default: begin
        // Unmapped address: return slave error.
      end
    endcase
  end

  // Register writes and timer counter update.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      mtime    <= '0;
      mtimecmp <= '1;
      msip     <= 1'b0;
    end else begin

      if (reg_req.we) begin
        case (reg_req.addr[ADDR_W-1:0])

          MSIP_OFFSET: begin
            msip <= reg_req.wdata[MSIP_BIT];
          end

          MTIME_OFFSET: begin
            mtime <= {
              reg_req.wstrb[7] ? reg_req.wdata[63:56] : mtime[63:56],
              reg_req.wstrb[6] ? reg_req.wdata[55:48] : mtime[55:48],
              reg_req.wstrb[5] ? reg_req.wdata[47:40] : mtime[47:40],
              reg_req.wstrb[4] ? reg_req.wdata[39:32] : mtime[39:32],
              reg_req.wstrb[3] ? reg_req.wdata[31:24] : mtime[31:24],
              reg_req.wstrb[2] ? reg_req.wdata[23:16] : mtime[23:16],
              reg_req.wstrb[1] ? reg_req.wdata[15:8]  : mtime[15:8],
              reg_req.wstrb[0] ? reg_req.wdata[7:0]   : mtime[7:0]
            };
          end

          MTIMECMP_OFFSET: begin
            mtimecmp <= {
              reg_req.wstrb[7] ? reg_req.wdata[63:56] : mtimecmp[63:56],
              reg_req.wstrb[6] ? reg_req.wdata[55:48] : mtimecmp[55:48],
              reg_req.wstrb[5] ? reg_req.wdata[47:40] : mtimecmp[47:40],
              reg_req.wstrb[4] ? reg_req.wdata[39:32] : mtimecmp[39:32],
              reg_req.wstrb[3] ? reg_req.wdata[31:24] : mtimecmp[31:24],
              reg_req.wstrb[2] ? reg_req.wdata[23:16] : mtimecmp[23:16],
              reg_req.wstrb[1] ? reg_req.wdata[15:8]  : mtimecmp[15:8],
              reg_req.wstrb[0] ? reg_req.wdata[7:0]   : mtimecmp[7:0]
            };
          end

          default: begin
            // No write for unmapped addresses.
          end

        endcase
      end

      // An MTIME write takes priority over an RTC tick in the same cycle.
      if (rtc_tick_i &&
          !(reg_req.we &&
            reg_req.addr[ADDR_W-1:0] == MTIME_OFFSET)) begin
        mtime <= mtime + REG_DW'(1);
      end
    end
  end

  // Interrupt outputs.
  always_comb begin
    msip_o = msip;
    mtip_o = (mtime >= mtimecmp);
  end

endmodule
