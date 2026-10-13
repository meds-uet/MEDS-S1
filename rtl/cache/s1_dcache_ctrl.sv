// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
// s1_dcache_ctrl : controller of the basic data cache R-03 [WIP -- R-03]

module s1_dcache_ctrl
  import s1_dcache_pkg::*;
(
  input  logic         clk_i,
  input  logic         rst_ni,
  input  logic         lsu_valid_i,     // The LSU has a request.
  input  logic         hit_i,           // The lookup found the line.
  input  logic         victim_dirty_i,  // The line to be replaced must be written back first.
  input  logic         mem_ready_i,     // Memory can take a request.
  input  logic         mem_valid_i,     // The fetched line has arrived.
  output dcache_ctrl_t ctrl_o           // These are the commands to the rest of the cache.
);

  // These are the steps the cache goes through.
  typedef enum logic [2:0] {
    S_IDLE,         // The cache waits for a request and reads both ways.
    S_LOOKUP,       // The cache compares the tags and serves a hit.
    S_WRITEBACK,    // The cache writes a dirty line back to memory.
    S_REFILL_REQ,   // The cache asks memory for the missing line.
    S_REFILL_WAIT,  // The cache waits for the line and stores it.
    S_REREAD        // The cache reads the set again so the lookup hits.
  } state_e;
  state_e state_q, state_d;

  // This block picks the next step and the commands for this step.
  always_comb begin
    state_d = state_q;
    ctrl_o  = '0;

    unique case (state_q)
      // The cache takes a request when the LSU has one.
      S_IDLE: begin
        ctrl_o.ready = 1'b1;
        if (lsu_valid_i) begin
          ctrl_o.accept = 1'b1;
          state_d       = S_LOOKUP;
        end
      end

      // A hit is answered at once, and a miss goes on to fetch the line.
      S_LOOKUP: begin
        if (hit_i) begin
          ctrl_o.hit_done = 1'b1;
          state_d         = S_IDLE;
        end else begin
          ctrl_o.miss = 1'b1;
          if (victim_dirty_i) state_d = S_WRITEBACK;
          else                state_d = S_REFILL_REQ;
        end
      end

      // The request to memory stays up until memory takes it.
      S_WRITEBACK: begin
        ctrl_o.writeback = 1'b1;
        if (mem_ready_i) state_d = S_REFILL_REQ;
      end

      S_REFILL_REQ: begin
        ctrl_o.refill_req = 1'b1;
        if (mem_ready_i) state_d = S_REFILL_WAIT;
      end

      S_REFILL_WAIT: begin
        if (mem_valid_i) begin
          ctrl_o.refill_done = 1'b1;
          state_d            = S_REREAD;
        end
      end

      // After the second read the lookup hits, so a store miss ends as a store hit.
      S_REREAD: begin
        ctrl_o.reread = 1'b1;
        state_d       = S_LOOKUP;
      end

      default: state_d = S_IDLE;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) state_q <= S_IDLE;
    else         state_q <= state_d;
  end

endmodule
