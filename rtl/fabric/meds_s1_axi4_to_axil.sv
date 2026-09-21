// SPDX-License-Identifier: Apache-2.0
// Copyright (c) Maktab-e-Digital Systems Lahore
//
// meds_s1_axi4_to_axil -- AXI4 (256-bit, bursts) slave to AXI4-Lite
// (32-bit, single beat) master. Used for:
//   * the peripheral subtree bridge (SPEC sec18.1, "AXI4-Lite bridge"), and
//   * each accelerator socket's cfg_axil port (SPEC sec20, LITE_DW=32).
//
// Every AXI4 beat is split into 32-bit AXI4-Lite transactions:
//   write: one Lite write per 32-bit word whose WSTRB nibble is non-zero,
//          with that nibble as the Lite WSTRB. So a 64-bit `sd` to CLINT
//          mtimecmp becomes two 32-bit writes -- no bytes are ever dropped.
//   read : one Lite read per 32-bit word covered by the beat's
//          [addr, aligned(addr,size)+2^size) byte range, so a 64-bit `ld`
//          of mtime returns both halves. Words outside that range are not
//          read (important for read-sensitive registers such as UART RX).
// Bursts are walked beat by beat with axi_next_addr(). The B response and
// each R beat carry the worst Lite response seen (DECERR > SLVERR > OKAY).
//
// Lite AW and W are driven together but handshaken independently, so a
// Lite slave may accept them in any order or cycle.
// One AXI4 transaction per direction at a time; the Lite address is the
// full 40-bit address (SPEC sec18.2).

module meds_s1_axi4_to_axil
  import meds_s1_axi4_pkg::*;
#(
  parameter int unsigned ID_W = AXI_SID_W
) (
  input  logic                   clk_i,
  input  logic                   rst_ni,

  // ---------------- AXI4 slave side ----------------
  input  logic [ID_W-1:0]        awid_i,
  input  logic [AXI_ADDR_W-1:0]  awaddr_i,
  input  logic [7:0]             awlen_i,
  input  logic [2:0]             awsize_i,
  input  logic [1:0]             awburst_i,
  input  logic                   awvalid_i,
  output logic                   awready_o,
  input  logic [AXI_DATA_W-1:0]  wdata_i,
  input  logic [AXI_STRB_W-1:0]  wstrb_i,
  input  logic                   wlast_i,
  input  logic                   wvalid_i,
  output logic                   wready_o,
  output logic [ID_W-1:0]        bid_o,
  output logic [1:0]             bresp_o,
  output logic                   bvalid_o,
  input  logic                   bready_i,
  input  logic [ID_W-1:0]        arid_i,
  input  logic [AXI_ADDR_W-1:0]  araddr_i,
  input  logic [7:0]             arlen_i,
  input  logic [2:0]             arsize_i,
  input  logic [1:0]             arburst_i,
  input  logic                   arvalid_i,
  output logic                   arready_o,
  output logic [ID_W-1:0]        rid_o,
  output logic [AXI_DATA_W-1:0]  rdata_o,
  output logic [1:0]             rresp_o,
  output logic                   rlast_o,
  output logic                   rvalid_o,
  input  logic                   rready_i,

  // ---------------- AXI4-Lite master side ----------------
  output logic [AXIL_ADDR_W-1:0] l_awaddr_o,
  output logic                   l_awvalid_o,
  input  logic                   l_awready_i,
  output logic [AXIL_DATA_W-1:0] l_wdata_o,
  output logic [AXIL_STRB_W-1:0] l_wstrb_o,
  output logic                   l_wvalid_o,
  input  logic                   l_wready_i,
  input  logic [1:0]             l_bresp_i,
  input  logic                   l_bvalid_i,
  output logic                   l_bready_o,
  output logic [AXIL_ADDR_W-1:0] l_araddr_o,
  output logic                   l_arvalid_o,
  input  logic                   l_arready_i,
  input  logic [AXIL_DATA_W-1:0] l_rdata_i,
  input  logic [1:0]             l_rresp_i,
  input  logic                   l_rvalid_i,
  output logic                   l_rready_o
);

  // ===========================================================================
  // Write path
  // ===========================================================================
  typedef enum logic [2:0] {W_IDLE_E, W_BEAT_E, W_WORD_E, W_LBRESP_E, W_BRESP_E} w_state_e;

  w_state_e              w_state_q;
  logic [ID_W-1:0]       w_id_q;
  logic [AXI_ADDR_W-1:0] w_addr_q;           // address of the current beat
  logic [7:0]            w_len_q, w_beat_q;
  logic [2:0]            w_size_q;
  logic [1:0]            w_burst_q;
  logic [AXI_DATA_W-1:0] w_data_q;
  logic [AXI_STRB_W-1:0] w_strb_q;
  logic [2:0]            w_word_q;           // 32-bit word within the beat
  logic [1:0]            w_resp_q;
  logic                  l_aw_done_q, l_w_done_q;

  logic [3:0] w_nibble;
  logic       w_word_last, w_beat_last;
  assign w_nibble    = w_strb_q[w_word_q*4 +: 4];
  assign w_word_last = (w_word_q == 3'd7);
  assign w_beat_last = (w_beat_q == w_len_q);

  assign awready_o   = (w_state_q == W_IDLE_E);
  assign wready_o    = (w_state_q == W_BEAT_E);
  assign bvalid_o    = (w_state_q == W_BRESP_E);
  assign bid_o       = w_id_q;
  assign bresp_o     = w_resp_q;

  assign l_awaddr_o  = {w_addr_q[AXI_ADDR_W-1:5], w_word_q, 2'b00};
  assign l_wdata_o   = w_data_q[w_word_q*32 +: 32];
  assign l_wstrb_o   = w_nibble;
  assign l_awvalid_o = (w_state_q == W_WORD_E) && (w_nibble != 4'h0) && !l_aw_done_q;
  assign l_wvalid_o  = (w_state_q == W_WORD_E) && (w_nibble != 4'h0) && !l_w_done_q;
  assign l_bready_o  = (w_state_q == W_LBRESP_E);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      w_state_q   <= W_IDLE_E;
      w_id_q      <= '0;  w_addr_q  <= '0;  w_len_q  <= '0; w_beat_q <= '0;
      w_size_q    <= '0;  w_burst_q <= '0;  w_data_q <= '0; w_strb_q <= '0;
      w_word_q    <= '0;  w_resp_q  <= RESP_OKAY;
      l_aw_done_q <= 1'b0; l_w_done_q <= 1'b0;
    end else begin
      unique case (w_state_q)

        W_IDLE_E: if (awvalid_i) begin
          w_id_q    <= awid_i;
          w_addr_q  <= awaddr_i;
          w_len_q   <= awlen_i;
          w_size_q  <= awsize_i;
          w_burst_q <= awburst_i;
          w_beat_q  <= '0;
          w_resp_q  <= RESP_OKAY;
          w_state_q <= W_BEAT_E;
        end

        W_BEAT_E: if (wvalid_i) begin
          w_data_q  <= wdata_i;
          w_strb_q  <= wstrb_i;
          w_word_q  <= '0;
          w_state_q <= W_WORD_E;
        end

        W_WORD_E: begin
          if (w_nibble == 4'h0) begin
            // nothing to write in this word: move on
            if (!w_word_last) w_word_q <= w_word_q + 3'd1;
            else if (w_beat_last) w_state_q <= W_BRESP_E;
            else begin
              w_beat_q  <= w_beat_q + 8'd1;
              w_addr_q  <= axi_next_addr(w_addr_q, w_size_q, w_len_q, w_burst_q);
              w_state_q <= W_BEAT_E;
            end
          end else begin
            // AW and W handshake independently
            if ((l_aw_done_q || l_awready_i) && (l_w_done_q || l_wready_i)) begin
              l_aw_done_q <= 1'b0;
              l_w_done_q  <= 1'b0;
              w_state_q   <= W_LBRESP_E;
            end else begin
              if (l_awvalid_o && l_awready_i) l_aw_done_q <= 1'b1;
              if (l_wvalid_o  && l_wready_i)  l_w_done_q  <= 1'b1;
            end
          end
        end

        W_LBRESP_E: if (l_bvalid_i) begin
          w_resp_q <= resp_merge(w_resp_q, l_bresp_i);
          if (!w_word_last) begin
            w_word_q  <= w_word_q + 3'd1;
            w_state_q <= W_WORD_E;
          end else if (w_beat_last) begin
            w_state_q <= W_BRESP_E;
          end else begin
            w_beat_q  <= w_beat_q + 8'd1;
            w_addr_q  <= axi_next_addr(w_addr_q, w_size_q, w_len_q, w_burst_q);
            w_state_q <= W_BEAT_E;
          end
        end

        W_BRESP_E: if (bready_i) w_state_q <= W_IDLE_E;

        default: w_state_q <= W_IDLE_E;
      endcase
    end
  end

  // ===========================================================================
  // Read path
  // ===========================================================================
  typedef enum logic [1:0] {R_IDLE_E, R_WORD_E, R_LRDATA_E, R_SEND_E} r_state_e;

  r_state_e              r_state_q;
  logic [ID_W-1:0]       r_id_q;
  logic [AXI_ADDR_W-1:0] r_addr_q;
  logic [7:0]            r_len_q, r_beat_q;
  logic [2:0]            r_size_q;
  logic [1:0]            r_burst_q;
  logic [2:0]            r_word_q;
  logic [AXI_DATA_W-1:0] r_data_q;
  logic [1:0]            r_resp_q;

  // Last 32-bit word touched by this beat: bytes [addr, aligned+2^size).
  logic [AXI_ADDR_W-1:0] r_bytes, r_end;
  logic [2:0]            r_last_word;
  assign r_bytes     = AXI_ADDR_W'(1) << r_size_q;
  assign r_end       = (r_addr_q & ~(r_bytes - 1)) + r_bytes - 1;
  assign r_last_word = (r_size_q >= 3'd5) ? 3'd7 : r_end[4:2];

  assign arready_o   = (r_state_q == R_IDLE_E);
  assign rvalid_o    = (r_state_q == R_SEND_E);
  assign rid_o       = r_id_q;
  assign rdata_o     = r_data_q;
  assign rresp_o     = r_resp_q;
  assign rlast_o     = (r_beat_q == r_len_q);

  assign l_araddr_o  = {r_addr_q[AXI_ADDR_W-1:5], r_word_q, 2'b00};
  assign l_arvalid_o = (r_state_q == R_WORD_E);
  assign l_rready_o  = (r_state_q == R_LRDATA_E);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      r_state_q <= R_IDLE_E;
      r_id_q    <= '0; r_addr_q  <= '0; r_len_q  <= '0; r_beat_q <= '0;
      r_size_q  <= '0; r_burst_q <= '0; r_word_q <= '0; r_data_q <= '0;
      r_resp_q  <= RESP_OKAY;
    end else begin
      unique case (r_state_q)

        R_IDLE_E: if (arvalid_i) begin
          r_id_q    <= arid_i;
          r_addr_q  <= araddr_i;
          r_len_q   <= arlen_i;
          r_size_q  <= arsize_i;
          r_burst_q <= arburst_i;
          r_beat_q  <= '0;
          r_word_q  <= araddr_i[4:2];
          r_data_q  <= '0;
          r_resp_q  <= RESP_OKAY;
          r_state_q <= R_WORD_E;
        end

        R_WORD_E: if (l_arready_i) r_state_q <= R_LRDATA_E;

        R_LRDATA_E: if (l_rvalid_i) begin
          r_data_q[r_word_q*32 +: 32] <= l_rdata_i;
          r_resp_q <= resp_merge(r_resp_q, l_rresp_i);
          if (r_word_q == r_last_word) r_state_q <= R_SEND_E;
          else begin
            r_word_q  <= r_word_q + 3'd1;
            r_state_q <= R_WORD_E;
          end
        end

        R_SEND_E: if (rready_i) begin
          if (rlast_o) r_state_q <= R_IDLE_E;
          else begin : next_beat
            logic [AXI_ADDR_W-1:0] nxt;
            nxt       = axi_next_addr(r_addr_q, r_size_q, r_len_q, r_burst_q);
            r_addr_q  <= nxt;
            r_beat_q  <= r_beat_q + 8'd1;
            r_word_q  <= nxt[4:2];
            r_data_q  <= '0;
            r_resp_q  <= RESP_OKAY;
            r_state_q <= R_WORD_E;
          end
        end

        default: r_state_q <= R_IDLE_E;
      endcase
    end
  end

endmodule : meds_s1_axi4_to_axil
