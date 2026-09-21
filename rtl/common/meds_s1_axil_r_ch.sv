// SPDX-License-Identifier: Apache-2.0
// Copyright (c) Maktab-e-Digital Systems Lahore
//
// meds_s1_axil_r_ch — AXI4-Lite read-data channel. Once an address has been
// captured, presents it on rd_addr_o, looks at the combinational
// rd_data_i/rd_addr_valid_i response, decides OKAY vs SLVERR, then raises
// rvalid_o with the data and waits for rready_i.

module meds_s1_axil_r_ch
  import meds_s1_axi4_pkg::*;
#(
  parameter int unsigned ADDR_WIDTH = AXIL_LOCAL_ADDR_W,
  parameter int unsigned DATA_WIDTH = AXIL_DATA_W
) (
  input  logic                  clk_i,
  input  logic                  rst_ni,

  // From meds_s1_axil_ar_ch
  input  logic [ADDR_WIDTH-1:0] ar_captured_addr_i,
  input  logic                  ar_captured_i,
  output logic                  ar_consume_o,

  // Read data channel
  output logic [DATA_WIDTH-1:0] rdata_o,
  output logic [1:0]            rresp_o,
  output logic                  rvalid_o,
  input  logic                  rready_i,

  // Internal read-lookup interface (to register storage)
  output logic [ADDR_WIDTH-1:0] rd_addr_o,       // address presented to storage
  input  logic [DATA_WIDTH-1:0] rd_data_i,       // data for rd_addr_o, combinational in rd_addr_o
  input  logic                  rd_addr_valid_i  // 1 = in range -> OKAY, else SLVERR
);

  typedef enum logic [1:0] {R_IDLE_E, R_LOOKUP_E, R_RESP_E} r_state_e;

  r_state_e              state_q, state_d;
  logic [ADDR_WIDTH-1:0] addr_q, addr_d;
  logic [DATA_WIDTH-1:0] data_q, data_d;
  logic [1:0]            resp_q, resp_d;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= R_IDLE_E;
      addr_q  <= '0;
      data_q  <= '0;
      resp_q  <= RESP_OKAY;
    end else begin
      state_q <= state_d;
      addr_q  <= addr_d;
      data_q  <= data_d;
      resp_q  <= resp_d;
    end
  end

  always_comb begin
    state_d = state_q;
    addr_d  = addr_q;
    data_d  = data_q;
    resp_d  = resp_q;

    ar_consume_o = 1'b0;
    rvalid_o     = 1'b0;

    unique case (state_q)

      R_IDLE_E: begin
        if (ar_captured_i) begin
          addr_d       = ar_captured_addr_i;
          ar_consume_o = 1'b1;
          state_d      = R_LOOKUP_E;
        end
      end

      R_LOOKUP_E: begin
        data_d  = rd_data_i;
        resp_d  = rd_addr_valid_i ? RESP_OKAY : RESP_SLVERR;
        state_d = R_RESP_E;
      end

      R_RESP_E: begin
        rvalid_o = 1'b1;
        if (rready_i) state_d = R_IDLE_E;
      end

      default: state_d = R_IDLE_E;
    endcase
  end

  assign rd_addr_o = addr_q;
  assign rdata_o   = data_q;
  assign rresp_o   = resp_q;

endmodule : meds_s1_axil_r_ch
