// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// s1_csr_legalize : WARL field legalization, by CSR address [WIP -- T-03]
//
// WPRI is handled structurally in s1_csr_file.sv via write_mask.
// WARL is per-field semantic (what is "legal" differs per field),
// making this the only hand-written WARL routing file.
// Only CSRs with has_warl=1 in s1_csr_pkg::CSR_TABLE are routed here.
// =============================================================================

module s1_csr_legalize
  import s1_pkg::*;
(
  input  logic [11:0]     csr_addr_i,
  input  logic [XLEN-1:0] wdata_i,      // Pre-masked for WPRI by s1_csr_file

  output logic [XLEN-1:0] legal_wdata_o
);

  // ---------------------------------------------------------------------------
  // WARL Legalization.
  // ---------------------------------------------------------------------------
  always_comb begin
    legal_wdata_o = wdata_i;

    unique case (csr_addr_i)
      12'h105,
      12'h305: begin // stvec/mtvec: MODE must be Direct or Vectored.
        legal_wdata_o = wdata_i[1:0] inside {2'b00, 2'b01} ? wdata_i : {wdata_i[XLEN-1:2], 2'b00};
      end
      12'h300: begin // M/U-only v1.0: MPP may encode U or M, never S/reserved.
        if (!(wdata_i[12:11] inside {2'b00, 2'b11})) begin
          legal_wdata_o[12:11] = 2'b00;
        end
      end
      default: legal_wdata_o = wdata_i;
    endcase
  end

endmodule : s1_csr_legalize
