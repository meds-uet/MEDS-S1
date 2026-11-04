// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// s1_lsu_datapath : scalar load/store byte-lane datapath              [WIP -- R-02]
//
// Purely combinational logic for transfer sizing, natural-alignment checking,
// store byte enables, store lane placement, and load extension.
// Reference: MEDS-S1 specification sections 7.3, 11 and 14.
// =============================================================================

module s1_lsu_datapath
  import s1_pkg::*;
(
  // Only the low address bits select byte lanes.
  input  logic [2:0]      addr_i,
  input  logic [XLEN-1:0] store_data_i,
  input  logic [2:0]      size_i,
  input  logic             load_unsigned_i,
  input  logic [XLEN-1:0] response_data_i,

  output logic             size_valid_o,
  output logic             alignment_ok_o,
  output logic [XLEN/8-1:0] mem_be_o,
  output logic [XLEN-1:0]   mem_wdata_o,
  output logic [XLEN-1:0]   load_data_o
);

  localparam int unsigned BYTE_LANES = XLEN / 8;

  logic [BYTE_LANES-1:0] transfer_mask;
  logic [XLEN-1:0]       shifted_response;
  logic [XLEN-1:0]       shifted_store;

  always_comb begin
    size_valid_o = 1'b1;
    alignment_ok_o = 1'b1;
    transfer_mask = '0;

    case (size_i)
      3'd0: begin
        transfer_mask = {{(BYTE_LANES-1){1'b0}}, 1'b1};
        alignment_ok_o = 1'b1;
      end
      3'd1: begin
        transfer_mask = {{(BYTE_LANES-2){1'b0}}, 2'b11};
        alignment_ok_o = (addr_i[0] == 1'b0);
      end
      3'd2: begin
        transfer_mask = {{(BYTE_LANES-4){1'b0}}, 4'b1111};
        alignment_ok_o = (addr_i[1:0] == 2'b00);
      end
      3'd3: begin
        transfer_mask = {BYTE_LANES{1'b1}};
        alignment_ok_o = (addr_i[2:0] == 3'b000);
      end
      default: begin
        size_valid_o = 1'b0;
        alignment_ok_o = 1'b0;
        transfer_mask = '0;
      end
    endcase

    mem_be_o = transfer_mask << addr_i[2:0];
    shifted_store = '0;
    case (size_i)
      3'd0: shifted_store[7:0]   = store_data_i[7:0];
      3'd1: shifted_store[15:0]  = store_data_i[15:0];
      3'd2: shifted_store[31:0]  = store_data_i[31:0];
      3'd3: shifted_store        = store_data_i;
      default: shifted_store     = '0;
    endcase
    shifted_store = shifted_store << (addr_i[2:0] * 8);
    mem_wdata_o = shifted_store;

    shifted_response = response_data_i >> (addr_i[2:0] * 8);
    load_data_o = '0;
    case (size_i)
      3'd0: begin
        if (load_unsigned_i) load_data_o = {{(XLEN-8){1'b0}}, shifted_response[7:0]};
        else                 load_data_o = {{(XLEN-8){shifted_response[7]}}, shifted_response[7:0]};
      end
      3'd1: begin
        if (load_unsigned_i) load_data_o = {{(XLEN-16){1'b0}}, shifted_response[15:0]};
        else                 load_data_o = {{(XLEN-16){shifted_response[15]}}, shifted_response[15:0]};
      end
      3'd2: begin
        if (load_unsigned_i) load_data_o = {{(XLEN-32){1'b0}}, shifted_response[31:0]};
        else                 load_data_o = {{(XLEN-32){shifted_response[31]}}, shifted_response[31:0]};
      end
      3'd3: load_data_o = shifted_response;
      default: load_data_o = '0;
    endcase
  end

endmodule
