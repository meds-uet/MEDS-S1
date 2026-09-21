// SPDX-License-Identifier: Apache-2.0
// Copyright (c) Maktab-e-Digital Systems Lahore
//
// meds_s1_axi4_r_ch -- read burst sequencer + read data channel.
// For each beat: present rd_addr_o, register rd_data_i and its response
// (OKAY, or SLVERR if rd_addr_valid_i is low -- per beat, as AXI4 requires),
// raise rvalid_o, and step the address with axi_next_addr on RREADY.
// RLAST is set on beat ARLEN. The beat counter is 8 bits (1..256 beats).

module meds_s1_axi4_r_ch
  import meds_s1_axi4_pkg::*;
#(
  parameter int unsigned ID_W = AXI_ID_W
) (
  input  logic                  clk_i,
  input  logic                  rst_ni,

  // From meds_s1_axi4_ar_ch
  input  logic [ID_W-1:0]       ar_captured_id_i,
  input  logic [AXI_ADDR_W-1:0] ar_captured_addr_i,
  input  logic [7:0]            ar_captured_len_i,
  input  logic [2:0]            ar_captured_size_i,
  input  logic [1:0]            ar_captured_burst_i,
  input  logic                  ar_captured_i,
  output logic                  ar_consume_o,

  // R channel
  output logic [ID_W-1:0]       rid_o,
  output logic [AXI_DATA_W-1:0] rdata_o,
  output logic [1:0]            rresp_o,
  output logic                  rlast_o,
  output logic                  rvalid_o,
  input  logic                  rready_i,

  // Register boundary
  output logic [AXI_ADDR_W-1:0] rd_addr_o,
  input  logic [AXI_DATA_W-1:0] rd_data_i,        // combinational from rd_addr_o
  input  logic                  rd_addr_valid_i   // 0 -> SLVERR
);

  typedef enum logic [1:0] {R_IDLE_E, R_LOOKUP_E, R_RESP_E} r_state_e;

  r_state_e              state_q;
  logic [AXI_ADDR_W-1:0] addr_q;
  logic [7:0]            beat_q, len_q;
  logic [2:0]            size_q;
  logic [1:0]            burst_q;
  logic [ID_W-1:0]       id_q;
  logic [AXI_DATA_W-1:0] data_q;
  logic [1:0]            resp_q;

  assign rd_addr_o    = addr_q;
  assign rvalid_o     = (state_q == R_RESP_E);
  assign rid_o        = id_q;
  assign rdata_o      = data_q;
  assign rresp_o      = resp_q;
  assign rlast_o      = (beat_q == len_q);
  assign ar_consume_o = (state_q == R_IDLE_E) && ar_captured_i;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= R_IDLE_E;
      addr_q  <= '0; beat_q <= '0; len_q <= '0; size_q <= '0; burst_q <= '0;
      id_q    <= '0; data_q <= '0; resp_q <= RESP_OKAY;
    end else begin
      unique case (state_q)
        R_IDLE_E: if (ar_captured_i) begin
          addr_q  <= ar_captured_addr_i;
          len_q   <= ar_captured_len_i;
          size_q  <= ar_captured_size_i;
          burst_q <= ar_captured_burst_i;
          id_q    <= ar_captured_id_i;
          beat_q  <= '0;
          state_q <= R_LOOKUP_E;
        end
        R_LOOKUP_E: begin
          data_q  <= rd_data_i;
          resp_q  <= rd_addr_valid_i ? RESP_OKAY : RESP_SLVERR;
          state_q <= R_RESP_E;
        end
        R_RESP_E: if (rready_i) begin
          if (rlast_o) state_q <= R_IDLE_E;
          else begin
            beat_q  <= beat_q + 8'd1;
            addr_q  <= axi_next_addr(addr_q, size_q, len_q, burst_q);
            state_q <= R_LOOKUP_E;
          end
        end
        default: state_q <= R_IDLE_E;
      endcase
    end
  end

endmodule : meds_s1_axi4_r_ch
