// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
// s1_dcache_basic : basic data cache R-03 [WIP -- R-03]

module s1_dcache_basic
  import s1_dcache_pkg::*;
(
  input  logic            clk_i,
  input  logic            rst_ni,
  input  dcache_lsu_req_t lsu_req_i,   // The LSU asks for a load or a store.
  output dcache_lsu_rsp_t lsu_rsp_o,   // The cache answers the LSU.
  output dcache_mem_req_t mem_req_o,   // The cache asks memory for a line.
  input  dcache_mem_rsp_t mem_rsp_i    // Memory answers the cache.
);

  dcache_addr_t addr;
  assign addr = lsu_req_i.addr;

  // The cache keeps the request here until it is finished.
  dcache_req_t req_q, req_d;

  // Each line has a valid bit and a dirty bit, and each set has one LRU bit. They are flops because the SRAM is never reset.
  logic [WAYS-1:0][SETS-1:0] valid_q, valid_d;
  logic [WAYS-1:0][SETS-1:0] dirty_q, dirty_d;
  logic [SETS-1:0]           lru_q,   lru_d;

  // Each way has one tag SRAM and one data SRAM. Both ways are read at the same index in the same cycle.
  logic [WAYS-1:0]             tag_req,  tag_we;
  logic [WAYS-1:0]             data_req, data_we;
  logic [LINE_BYTES-1:0]       data_be;
  logic [LINE_W-1:0]           data_wdata;
  dcache_tag_t [WAYS-1:0]      tag_rdata;
  logic [WAYS-1:0][LINE_W-1:0] data_rdata;

  for (genvar w = 0; w < WAYS; w++) begin : g_way
    meds_s1_sram #(.DW(TAG_SRAM_W), .DEPTH(SETS)) u_tag (
      .clk_i   (clk_i),
      .rst_ni  (rst_ni),
      .req_i   (tag_req[w]),
      .we_i    (tag_we[w]),
      .addr_i  (req_d.index),
      .be_i    ('1),
      .wdata_i (dcache_tag_t'(req_q.tag)),
      .rdata_o (tag_rdata[w])
    );
    meds_s1_sram #(.DW(LINE_W), .DEPTH(SETS)) u_data (
      .clk_i   (clk_i),
      .rst_ni  (rst_ni),
      .req_i   (data_req[w]),
      .we_i    (data_we[w]),
      .addr_i  (req_d.index),
      .be_i    (data_be),
      .wdata_i (data_wdata),
      .rdata_o (data_rdata[w])
    );
  end

  // A way hits when its line is valid and its stored tag matches.
  logic [WAYS-1:0] way_hit;
  logic            hit, hit_way;
  for (genvar w = 0; w < WAYS; w++) begin : g_hit
    assign way_hit[w] = valid_q[w][req_q.index] && (tag_rdata[w] == dcache_tag_t'(req_q.tag));
  end
  assign hit     = |way_hit;
  assign hit_way = way_hit[1];

  // On a miss the cache picks an empty way first and the LRU way otherwise.
  logic victim, victim_q, victim_d;
  always_comb begin
    if      (!valid_q[0][req_q.index]) victim = 1'b0;
    else if (!valid_q[1][req_q.index]) victim = 1'b1;
    else                               victim = lru_q[req_q.index];
  end

  // The controller decides the step, and this module does what it commands.
  dcache_ctrl_t ctrl;
  s1_dcache_ctrl u_ctrl (
    .clk_i          (clk_i),
    .rst_ni         (rst_ni),
    .lsu_valid_i    (lsu_req_i.valid),
    .hit_i          (hit),
    .victim_dirty_i (valid_q[victim][req_q.index] && dirty_q[victim][req_q.index]),
    .mem_ready_i    (mem_rsp_i.ready),
    .mem_valid_i    (mem_rsp_i.valid),
    .ctrl_o         (ctrl)
  );

  // This block carries out the commands of the controller.
  always_comb begin
    // By default every flop keeps its value.
    req_d    = req_q;
    valid_d  = valid_q;
    dirty_d  = dirty_q;
    lru_d    = lru_q;
    victim_d = victim_q;

    // The answer to the LSU is the picked word of the line that hit.
    lsu_rsp_o       = '0;
    lsu_rsp_o.ready = ctrl.ready;
    lsu_rsp_o.valid = ctrl.hit_done;
    lsu_rsp_o.rdata = data_rdata[hit_way][req_q.word * DATA_W +: DATA_W];

    // A write-back goes to the address of the old line, and a fetch to the address of the request.
    mem_req_o       = '0;
    mem_req_o.valid = ctrl.writeback || ctrl.refill_req;
    mem_req_o.we    = ctrl.writeback;
    mem_req_o.wdata = data_rdata[victim_q];
    if (ctrl.writeback) mem_req_o.addr = {tag_rdata[victim_q][TAG_W-1:0], req_q.index, {OFFSET_W{1'b0}}};
    else                mem_req_o.addr = {req_q.tag,                      req_q.index, {OFFSET_W{1'b0}}};

    // By default the SRAMs are idle, and a write stores a whole line from memory.
    tag_req    = '0;
    tag_we     = '0;
    data_req   = '0;
    data_we    = '0;
    data_be    = '1;
    data_wdata = mem_rsp_i.rdata;

    // The request is saved when the controller accepts it.
    if (ctrl.accept) begin
      req_d.tag   = addr.tag;
      req_d.index = addr.index;
      req_d.word  = addr.word;
      req_d.we    = lsu_req_i.we;
      req_d.be    = lsu_req_i.be;
      req_d.wdata = lsu_req_i.wdata;
    end

    // Both ways are read for the first lookup and again after a refill.
    if (ctrl.accept || ctrl.reread) begin
      tag_req  = '1;
      data_req = '1;
    end

    // On a hit the other way becomes the older one.
    if (ctrl.hit_done) begin
      lru_d[req_q.index] = !hit_way;
      if (req_q.we) begin
        // A store writes only its bytes and makes the line dirty.
        data_req[hit_way]             = 1'b1;
        data_we[hit_way]              = 1'b1;
        data_wdata                    = {WORDS{req_q.wdata}};
        data_be                       = LINE_BYTES'(req_q.be) << (req_q.word * WORD_BYTES);
        dirty_d[hit_way][req_q.index] = 1'b1;
      end
    end

    // On a miss the way to replace is remembered until the refill is done.
    if (ctrl.miss) victim_d = victim;

    // When the line arrives it is stored and marked valid and clean.
    if (ctrl.refill_done) begin
      tag_req[victim_q]              = 1'b1;
      tag_we[victim_q]               = 1'b1;
      data_req[victim_q]             = 1'b1;
      data_we[victim_q]              = 1'b1;
      valid_d[victim_q][req_q.index] = 1'b1;
      dirty_d[victim_q][req_q.index] = 1'b0;
    end
  end

  // These flip flops take their new values on each clock edge, and reset empties the cache.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      req_q    <= '0;
      valid_q  <= '0;
      dirty_q  <= '0;
      lru_q    <= '0;
      victim_q <= 1'b0;
    end else begin
      req_q    <= req_d;
      valid_q  <= valid_d;
      dirty_q  <= dirty_d;
      lru_q    <= lru_d;
      victim_q <= victim_d;
    end
  end

  // The byte part of the address is not used because the byte enables pick the bytes.
  logic unused_ok;
  assign unused_ok = ^addr.byte_idx;

endmodule
