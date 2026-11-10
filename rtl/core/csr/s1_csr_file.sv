// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// s1_csr_file : address-decoded CSR storage, WPRI/WARL handling, external routing [WIP -- T-03]
//
// The address decoder is generated, not hand-written (SPEC 10.2).
// gen/s1_csr_gen.py merges core and extension YAMLs into s1_csr_pkg::CSR_TABLE.
// Adding a CSR is a YAML edit + regenerate; this RTL remains untouched.
//
// * WPRI: A write changes only the write_mask bits; the others keep their value.
// * WARL: Routed through s1_csr_legalize.sv when has_warl=1.
// * WLRL: No dedicated handling; write_mask provides the only protection.
// * Access: csr_illegal_o follows rtl/core/csr/csr_access_matrix.md.
//
// Reference: SPEC section 10.2, section 19 (external CSR port).
// Interface contract: docs/modules/s1_csr_file.md. Testbench: verif/unit/tb_s1_csr_file.sv.
// =============================================================================

module s1_csr_file
  import s1_pkg::*;
  import s1_csr_pkg::*;
#(
  parameter bit          U_MODE_PRESENT = 1'b1,
  parameter bit          S_MODE_PRESENT = 1'b0,
  parameter int unsigned PMP_REGIONS    = s1_pkg::PMP_N
) (
  input  logic             clk_i,
  input  logic             rst_ni,

  input  logic [11:0]      csr_addr_i,
  input  logic [XLEN-1:0]  csr_wdata_i,
  input  logic             csr_we_i,
  input  priv_lvl_e        priv_i,

  // Hardware writes take priority over the retiring instruction's software
  // write. Four slots let trap entry update its state in one clock edge.
  input  logic             hw_we_i    [4],
  input  logic [11:0]      hw_addr_i  [4],
  input  logic [XLEN-1:0]  hw_wdata_i [4],

  output logic [XLEN-1:0]  csr_rdata_o,
  output logic             csr_illegal_o,

  // Direct state taps for the trap unit. These avoid serialising a trap across
  // the software CSR read port, which has registered one-address latency.
  output logic [XLEN-1:0]  trap_mstatus_o,
  output logic [XLEN-1:0]  trap_medeleg_o,
  output logic [XLEN-1:0]  trap_mideleg_o,
  output logic [XLEN-1:0]  trap_mepc_o,
  output logic [XLEN-1:0]  trap_mtvec_o,
  output logic [XLEN-1:0]  trap_sepc_o,
  output logic [XLEN-1:0]  trap_stvec_o,
  output logic [XLEN-1:0]  trap_dcsr_o,
  output logic [XLEN-1:0]  trap_dpc_o,

  // External CSR port: routed to the coprocessor owning this address.
  output logic [11:0]      ext_csr_addr_o,
  output logic [XLEN-1:0]  ext_csr_wdata_o,
  output logic             ext_csr_we_o,
  input  logic [XLEN-1:0]  ext_csr_rdata_i
);

  // ---------------------------------------------------------------------------
  // Address match.
  // Static, fully-unrolled comparator over CSR_TABLE (SPEC 10.2). Replaces 
  // hand-written case chains. idx defaults to 0 on a miss; the read-mux 
  // MUST check hit first to prevent silent aliasing to CSR_TABLE[0].
  // ---------------------------------------------------------------------------
  logic                        hit;
  logic [$clog2(NUM_CSRS)-1:0] idx;

  always_comb begin
    hit = 1'b0;
    idx = '0;
    for (int unsigned i = 0; i < NUM_CSRS; i++) begin
      if (CSR_TABLE[i].addr == csr_addr_i) begin
        hit = 1'b1;
        idx = i[$clog2(NUM_CSRS)-1:0];
      end
    end
  end

  logic is_ext;
  assign is_ext = hit & (CSR_TABLE[idx].cls == CSR_CLASS_EXTERNAL);

  // ---------------------------------------------------------------------------
  // Access check (rtl/core/csr/csr_access_matrix.md).
  // Debug Mode is not implemented, so a debug-only CSR is always illegal.
  // ---------------------------------------------------------------------------
  logic gated_off, legal;

  assign gated_off = (CSR_TABLE[idx].gate_u   && !U_MODE_PRESENT)
                  || (CSR_TABLE[idx].gate_s   && !S_MODE_PRESENT)
                  || (CSR_TABLE[idx].gate_pmp && PMP_REGIONS == 0);

  assign legal = hit && !gated_off
              && (priv_i >= CSR_TABLE[idx].min_priv)
              && !(csr_we_i && CSR_TABLE[idx].read_only)
              && !CSR_TABLE[idx].debug_only;

  assign csr_illegal_o = ~legal;

  // ---------------------------------------------------------------------------
  // External routing.
  // Core forwards external CSR requests directly to the coprocessor.
  // The core does not store external CSR state (SPEC 19).
  // ---------------------------------------------------------------------------
  assign ext_csr_addr_o  = csr_addr_i;
  assign ext_csr_wdata_o = csr_wdata_i;
  assign ext_csr_we_o    = is_ext & legal & csr_we_i;

  // ---------------------------------------------------------------------------
  // Per-config masks.
  // S-mode adds writable bits; U-mode and S-mode add read-only constants
  // (UXL/SXL). An alias shows only its view_mask bits of the CSR it views.
  // ---------------------------------------------------------------------------
  function automatic logic [XLEN-1:0] wmask_of(input logic [$clog2(NUM_CSRS)-1:0] i);
    wmask_of = XLEN'(CSR_TABLE[i].write_mask
                    | (S_MODE_PRESENT ? CSR_TABLE[i].wmask_if_s : 64'h0));
  endfunction

  function automatic logic [XLEN-1:0] ro_const_of(input logic [$clog2(NUM_CSRS)-1:0] i);
    ro_const_of = XLEN'(CSR_TABLE[i].ro_const
                       | (U_MODE_PRESENT ? CSR_TABLE[i].ro_const_if_u : 64'h0)
                       | (S_MODE_PRESENT ? CSR_TABLE[i].ro_const_if_s : 64'h0));
  endfunction

  function automatic logic [XLEN-1:0] view_mask_of(input logic [$clog2(NUM_CSRS)-1:0] i);
    view_mask_of = (CSR_TABLE[i].presence == CSR_PRESENT_ALIAS) ? XLEN'(CSR_TABLE[i].view_mask)
                                                                : '1;
  endfunction

  // ---------------------------------------------------------------------------
  // WPRI (structural) then WARL (semantic).
  // Mask WPRI bits *before* WARL legalization so reserved bits are cleared
  // before reaching logic that doesn't expect them.
  // ---------------------------------------------------------------------------
  logic [XLEN-1:0] wmask_cur;
  logic [XLEN-1:0] wdata_masked, wdata_legal, wdata_final;

  assign wmask_cur    = wmask_of(idx);
  assign wdata_masked = csr_wdata_i & wmask_cur;

  s1_csr_legalize u_legalize (
    .csr_addr_i    ( csr_addr_i ),
    .wdata_i       ( wdata_masked ),
    .legal_wdata_o ( wdata_legal )
  );

  assign wdata_final = CSR_TABLE[idx].has_warl ? wdata_legal : wdata_masked;

  // ---------------------------------------------------------------------------
  // Storage.
  // State storage for CORE and COUNTER classes only. External CSRs are
  // stateless in the core. CSRs are architectural registers, not a bulk memory,
  // so this deliberately uses flops rather than the platform SRAM wrapper.
  // The read response remains registered to preserve the CSR-file contract.
  // ---------------------------------------------------------------------------
  logic [XLEN-1:0] storage [NUM_CSRS];
  logic [XLEN-1:0] storage_rdata;

  function automatic logic [$clog2(NUM_CSRS)-1:0] index_of(input logic [11:0] addr);
    index_of = '0;
    for (int unsigned i = 0; i < NUM_CSRS; i++) begin
      if (CSR_TABLE[i].addr == addr) index_of = i[$clog2(NUM_CSRS)-1:0];
    end
  endfunction

  // An alias (presence alias_of) reads and writes the CSR it is a view of.
  logic [$clog2(NUM_CSRS)-1:0] store_idx;

  assign store_idx = (CSR_TABLE[idx].presence == CSR_PRESENT_ALIAS)
                   ? index_of(CSR_TABLE[idx].view_addr) : idx;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      storage_rdata <= '0;
      for (int unsigned i = 0; i < NUM_CSRS; i++) begin
        storage[i] <= XLEN'(CSR_TABLE[i].reset_val);
      end
    end else begin
      storage_rdata <= storage[store_idx];

      if (legal && !is_ext && csr_we_i) begin
        storage[store_idx] <= (storage[store_idx] & ~wmask_cur) | wdata_final;
      end

      // Hardware writes follow the software write so they win an address
      // collision and all four trap-state CSRs update on this same edge.
      for (int unsigned p = 0; p < 4; p++) begin
        for (int unsigned i = 0; i < NUM_CSRS; i++) begin
          if (hw_we_i[p] && hw_addr_i[p] == CSR_TABLE[i].addr) begin
            storage[i] <= hw_wdata_i[p];
          end
        end
      end
    end
  end

  // Pipeline control signals to match the registered CSR read response.
  logic        hit_q;
  logic        is_ext_q;
  logic [$clog2(NUM_CSRS)-1:0] idx_q;
  logic [$clog2(NUM_CSRS)-1:0] store_idx_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      hit_q       <= 1'b0;
      is_ext_q    <= 1'b0;
      idx_q       <= '0;
      store_idx_q <= '0;
    end else begin
      hit_q       <= hit;
      is_ext_q    <= is_ext;
      idx_q       <= idx;
      store_idx_q <= store_idx;
    end
  end

  // ---------------------------------------------------------------------------
  // Read mux.
  // A miss MUST return '0, not storage[0]. Checking ~hit_q first prevents
  // silent aliasing bugs if the ternary chain is ever reordered carelessly.
  // Bits outside write_mask hold their reset or hardware-written value, so the
  // read is not masked by it; read-only constants are ORed in.
  // ---------------------------------------------------------------------------
  assign csr_rdata_o   = ~hit_q  ? '0
                        : is_ext_q ? ext_csr_rdata_i
                        : (storage_rdata | ro_const_of(store_idx_q)) & view_mask_of(idx_q);

  assign trap_mstatus_o = storage[index_of(CSR_MSTATUS)];
  assign trap_medeleg_o = storage[index_of(CSR_MEDELEG)];
  assign trap_mideleg_o = storage[index_of(CSR_MIDELEG)];
  assign trap_mepc_o    = storage[index_of(CSR_MEPC)];
  assign trap_mtvec_o   = storage[index_of(CSR_MTVEC)];
  assign trap_sepc_o    = storage[index_of(CSR_SEPC)];
  assign trap_stvec_o   = storage[index_of(CSR_STVEC)];
  assign trap_dcsr_o    = storage[index_of(CSR_DCSR)];
  assign trap_dpc_o     = storage[index_of(CSR_DPC)];

endmodule : s1_csr_file
