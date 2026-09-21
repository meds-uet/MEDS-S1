// SPDX-License-Identifier: Apache-2.0
// Copyright (c) Maktab-e-Digital Systems Lahore
//
// meds_s1_rr_arbiter -- round-robin arbiter for an AXI address channel.
//
// AXI rule (IHI0022 A3.2.1): once VALID is high, VALID and the payload must
// stay unchanged until READY. So when the granted request is not accepted
// in a cycle, the grant is LOCKED to that requester until it is accepted.
// After an accepted grant, priority rotates to the requester after it.

module meds_s1_rr_arbiter #(
  parameter int unsigned N  = 6,
  parameter int unsigned IW = (N > 1) ? $clog2(N) : 1
) (
  input  logic          clk_i,
  input  logic          rst_ni,
  input  logic [N-1:0]  req_i,
  input  logic          ready_i,   // downstream READY for the granted request
  output logic          valid_o,   // a request is granted this cycle
  output logic [IW-1:0] idx_o      // index of the granted requester
);

  logic [N-1:0]  mask_q;           // requesters allowed "first" this round
  logic          lock_q;
  logic [IW-1:0] lock_idx_q;

  logic          pick_valid;
  logic [IW-1:0] pick_idx;

  // First requester inside the mask, else first requester overall.
  always_comb begin
    pick_valid = 1'b0;
    pick_idx   = '0;
    for (int i = N - 1; i >= 0; i--) begin
      if (req_i[i]) begin pick_valid = 1'b1; pick_idx = IW'(i); end
    end
    for (int i = N - 1; i >= 0; i--) begin
      if (req_i[i] && mask_q[i]) pick_idx = IW'(i);
    end
  end

  assign idx_o   = lock_q ? lock_idx_q : pick_idx;
  assign valid_o = lock_q ? req_i[lock_idx_q] : pick_valid;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      mask_q     <= '1;
      lock_q     <= 1'b0;
      lock_idx_q <= '0;
    end else begin
      lock_q     <= valid_o && !ready_i;
      lock_idx_q <= idx_o;
      if (valid_o && ready_i) begin
        for (int i = 0; i < N; i++) mask_q[i] <= (i > int'(idx_o));
      end
    end
  end

endmodule : meds_s1_rr_arbiter
