// SPDX-License-Identifier: Apache-2.0
// Copyright (c) Maktab-e-Digital Systems Lahore
//
// meds_s1_axil_demux -- one AXI4-Lite master to N AXI4-Lite slave ports.
// The parent supplies the decode (aw_hit_i/aw_sel_i from the current
// AWADDR, ar_hit_i/ar_sel_i from ARADDR), so this module holds no address
// map of its own.
//
// Write: the AW decode is latched, then AW and W are driven to that port
//        together (handshaken independently), then its B is returned.
// Read : AR forwarded, selection latched, R returned from that port.
// An address with no port is answered locally with DECERR.
// One transaction per direction at a time (SPEC: subtree is "no bursts").

module meds_s1_axil_demux
  import meds_s1_axi4_pkg::*;
#(
  parameter int unsigned N  = NUM_PERIPH,
  parameter int unsigned SW = PIDX_W
) (
  input  logic                          clk_i,
  input  logic                          rst_ni,

  // decode for the current AW / AR address
  input  logic                          aw_hit_i,
  input  logic [SW-1:0]                 aw_sel_i,
  input  logic                          ar_hit_i,
  input  logic [SW-1:0]                 ar_sel_i,

  // ---------------- upstream (from one Lite master) ----------------
  input  logic [AXIL_ADDR_W-1:0]        awaddr_i,
  input  logic                          awvalid_i,
  output logic                          awready_o,
  input  logic [AXIL_DATA_W-1:0]        wdata_i,
  input  logic [AXIL_STRB_W-1:0]        wstrb_i,
  input  logic                          wvalid_i,
  output logic                          wready_o,
  output logic [1:0]                    bresp_o,
  output logic                          bvalid_o,
  input  logic                          bready_i,
  input  logic [AXIL_ADDR_W-1:0]        araddr_i,
  input  logic                          arvalid_i,
  output logic                          arready_o,
  output logic [AXIL_DATA_W-1:0]        rdata_o,
  output logic [1:0]                    rresp_o,
  output logic                          rvalid_o,
  input  logic                          rready_i,

  // ---------------- downstream ports ----------------
  output logic [N-1:0][AXIL_ADDR_W-1:0] p_awaddr_o,
  output logic [N-1:0]                  p_awvalid_o,
  input  logic [N-1:0]                  p_awready_i,
  output logic [N-1:0][AXIL_DATA_W-1:0] p_wdata_o,
  output logic [N-1:0][AXIL_STRB_W-1:0] p_wstrb_o,
  output logic [N-1:0]                  p_wvalid_o,
  input  logic [N-1:0]                  p_wready_i,
  input  logic [N-1:0][1:0]             p_bresp_i,
  input  logic [N-1:0]                  p_bvalid_i,
  output logic [N-1:0]                  p_bready_o,
  output logic [N-1:0][AXIL_ADDR_W-1:0] p_araddr_o,
  output logic [N-1:0]                  p_arvalid_o,
  input  logic [N-1:0]                  p_arready_i,
  input  logic [N-1:0][AXIL_DATA_W-1:0] p_rdata_i,
  input  logic [N-1:0][1:0]             p_rresp_i,
  input  logic [N-1:0]                  p_rvalid_i,
  output logic [N-1:0]                  p_rready_o
);

  // ---------------- write ----------------
  // W_IDLE: wait for AWVALID and latch its decode (holding AWREADY low
  //         until then is legal slave behaviour).
  // W_FWD : drive AW and W to the selected port at the same time and track
  //         each handshake separately. As a master toward the peripheral we
  //         must never wait for AWREADY before driving WVALID (AXI A3.3.1),
  //         because the peripheral may wait for W before taking AW.
  // W_RESP: return that port's B.  Unmapped: accept AW+W, answer DECERR.
  typedef enum logic [1:0] {W_IDLE_E, W_FWD_E, W_RESP_E} w_state_e;
  w_state_e      w_state_q;
  logic [SW-1:0] w_sel_q;
  logic          w_hit_q, aw_done_q, w_done_q;
  logic          aw_hs, w_hs;

  always_comb begin
    for (int i = 0; i < N; i++) begin
      p_awaddr_o[i]  = awaddr_i;
      p_awvalid_o[i] = 1'b0;
      p_wdata_o[i]   = wdata_i;
      p_wstrb_o[i]   = wstrb_i;
      p_wvalid_o[i]  = 1'b0;
      p_bready_o[i]  = 1'b0;
    end
    awready_o = 1'b0;
    wready_o  = 1'b0;
    bvalid_o  = 1'b0;
    bresp_o   = RESP_OKAY;

    unique case (w_state_q)
      W_IDLE_E: ;
      W_FWD_E: begin
        if (w_hit_q) begin
          p_awvalid_o[w_sel_q] = awvalid_i && !aw_done_q;
          awready_o            = p_awready_i[w_sel_q] && !aw_done_q;
          p_wvalid_o[w_sel_q]  = wvalid_i && !w_done_q;
          wready_o             = p_wready_i[w_sel_q] && !w_done_q;
        end else begin
          awready_o = !aw_done_q;
          wready_o  = !w_done_q;
        end
      end
      W_RESP_E: begin
        if (w_hit_q) begin
          bvalid_o            = p_bvalid_i[w_sel_q];
          bresp_o             = p_bresp_i[w_sel_q];
          p_bready_o[w_sel_q] = bready_i;
        end else begin
          bvalid_o = 1'b1;
          bresp_o  = RESP_DECERR;
        end
      end
      default: ;
    endcase
  end

  assign aw_hs = awvalid_i && awready_o;
  assign w_hs  = wvalid_i  && wready_o;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      w_state_q <= W_IDLE_E;
      w_sel_q   <= '0;
      w_hit_q   <= 1'b0;
      aw_done_q <= 1'b0;
      w_done_q  <= 1'b0;
    end else begin
      unique case (w_state_q)
        W_IDLE_E: if (awvalid_i) begin
          w_sel_q   <= aw_sel_i;
          w_hit_q   <= aw_hit_i;
          w_state_q <= W_FWD_E;
        end
        W_FWD_E: begin
          if ((aw_done_q || aw_hs) && (w_done_q || w_hs)) begin
            aw_done_q <= 1'b0;
            w_done_q  <= 1'b0;
            w_state_q <= W_RESP_E;
          end else begin
            if (aw_hs) aw_done_q <= 1'b1;
            if (w_hs)  w_done_q  <= 1'b1;
          end
        end
        W_RESP_E: if (bvalid_o && bready_i) w_state_q <= W_IDLE_E;
        default:  w_state_q <= W_IDLE_E;
      endcase
    end
  end

  // ---------------- read ----------------
  typedef enum logic [1:0] {R_IDLE_E, R_DATA_E, R_ERR_E} r_state_e;
  r_state_e      r_state_q;
  logic [SW-1:0] r_sel_q;

  always_comb begin
    for (int i = 0; i < N; i++) begin
      p_araddr_o[i]  = araddr_i;
      p_arvalid_o[i] = 1'b0;
      p_rready_o[i]  = 1'b0;
    end
    arready_o = 1'b0;
    rvalid_o  = 1'b0;
    rdata_o   = '0;
    rresp_o   = RESP_OKAY;

    unique case (r_state_q)
      R_IDLE_E: if (arvalid_i) begin
        if (ar_hit_i) begin
          p_arvalid_o[ar_sel_i] = 1'b1;
          arready_o             = p_arready_i[ar_sel_i];
        end else begin
          arready_o = 1'b1;
        end
      end
      R_DATA_E: begin
        rvalid_o            = p_rvalid_i[r_sel_q];
        rdata_o             = p_rdata_i[r_sel_q];
        rresp_o             = p_rresp_i[r_sel_q];
        p_rready_o[r_sel_q] = rready_i;
      end
      R_ERR_E: begin
        rvalid_o = 1'b1;
        rresp_o  = RESP_DECERR;
      end
      default: ;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      r_state_q <= R_IDLE_E;
      r_sel_q   <= '0;
    end else begin
      unique case (r_state_q)
        R_IDLE_E: if (arvalid_i && arready_o) begin
          r_sel_q   <= ar_sel_i;
          r_state_q <= ar_hit_i ? R_DATA_E : R_ERR_E;
        end
        R_DATA_E: if (rvalid_o && rready_i) r_state_q <= R_IDLE_E;
        R_ERR_E:  if (rready_i)             r_state_q <= R_IDLE_E;
        default:  r_state_q <= R_IDLE_E;
      endcase
    end
  end

endmodule : meds_s1_axil_demux
