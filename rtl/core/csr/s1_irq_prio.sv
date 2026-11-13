// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// s1_irq_prio : pending, enabled interrupt selection                     [WIP]
//
// Picks the interrupt to take this cycle from mip, mie, mideleg, mstatus.MIE,
// mstatus.SIE and the current mode, following the privileged spec: an
// interrupt destined for M beats any destined for S, and within a destination
// the order is MEI > MSI > MTI > SEI > SSI > STI.  Purely combinational.
//
// Reference: SPEC section 10.3.  Testbench: verif/unit/tb_s1_irq_prio.sv.
// =============================================================================

module s1_irq_prio
  import s1_pkg::*;
#(
  parameter bit S_MODE_PRESENT = 1'b0
) (
  input  logic [XLEN-1:0] mip_i,
  input  logic [XLEN-1:0] mie_i,
  input  logic [XLEN-1:0] mideleg_i,
  input  logic            mstatus_mie_i,
  input  logic            mstatus_sie_i,
  input  priv_lvl_e       priv_i,

  output logic            irq_valid_o,
  output logic [5:0]      irq_code_o
);

  // Interrupt codes, equal to their mip/mie bit positions.
  localparam int unsigned IRQ_SSI = 1;
  localparam int unsigned IRQ_MSI = 3;
  localparam int unsigned IRQ_STI = 5;
  localparam int unsigned IRQ_MTI = 7;
  localparam int unsigned IRQ_SEI = 9;
  localparam int unsigned IRQ_MEI = 11;

  localparam logic [XLEN-1:0] M_IRQS = (XLEN'(1) << IRQ_MEI) | (XLEN'(1) << IRQ_MSI)
                                     | (XLEN'(1) << IRQ_MTI);
  localparam logic [XLEN-1:0] S_IRQS = S_MODE_PRESENT
                                     ? (XLEN'(1) << IRQ_SEI) | (XLEN'(1) << IRQ_SSI)
                                     | (XLEN'(1) << IRQ_STI)
                                     : '0;

  // ---------------------------------------------------------------------------
  // Destination.
  // Only S-level bits can be delegated; without S-mode nothing is.
  // ---------------------------------------------------------------------------
  logic [XLEN-1:0] pending, deleg, to_m, to_s;
  logic            m_enabled, s_enabled;

  assign pending   = mip_i & mie_i & (M_IRQS | S_IRQS);
  assign deleg     = mideleg_i & S_IRQS;
  assign m_enabled = (priv_i != PRIV_M) || mstatus_mie_i;
  assign s_enabled = S_MODE_PRESENT
                  && ((priv_i == PRIV_U) || ((priv_i == PRIV_S) && mstatus_sie_i));
  assign to_m      = m_enabled ? (pending & ~deleg) : '0;
  assign to_s      = s_enabled ? (pending & deleg) : '0;

  // ---------------------------------------------------------------------------
  // Priority.
  // ---------------------------------------------------------------------------
  always_comb begin
    irq_valid_o = (|to_m) || (|to_s);
    irq_code_o  = '0;
    if      (to_m[IRQ_MEI]) irq_code_o = 6'(IRQ_MEI);
    else if (to_m[IRQ_MSI]) irq_code_o = 6'(IRQ_MSI);
    else if (to_m[IRQ_MTI]) irq_code_o = 6'(IRQ_MTI);
    else if (to_m[IRQ_SEI]) irq_code_o = 6'(IRQ_SEI);
    else if (to_m[IRQ_SSI]) irq_code_o = 6'(IRQ_SSI);
    else if (to_m[IRQ_STI]) irq_code_o = 6'(IRQ_STI);
    else if (to_s[IRQ_SEI]) irq_code_o = 6'(IRQ_SEI);
    else if (to_s[IRQ_SSI]) irq_code_o = 6'(IRQ_SSI);
    else if (to_s[IRQ_STI]) irq_code_o = 6'(IRQ_STI);
  end

endmodule : s1_irq_prio
