// Copyright 2026 Maktab-e-Digital Systems Lahore.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// s1_icache : instruction cache (top-level)                      [COMPLETE]
//
// Top-level wrapper that instantiates the controller and datapath and
// exposes the CPU and memory interfaces to the rest of the SoC.
//
// Spec:      SPEC §15
// Testbench: tb_s1_icache.sv
// =============================================================================

module s1_icache #(
    parameter int unsigned CACHE_SIZE_KB   = 16,
    parameter int unsigned LINE_SIZE_BYTES = 64,
    parameter int unsigned ASSOCIATIVITY   = 2,
    parameter int unsigned ADDR_WIDTH      = 40,
    localparam int unsigned WAY_IDX_W      = (ASSOCIATIVITY > 1) ? $clog2(ASSOCIATIVITY) : 1
)(
    input  logic                         clk_i,
    input  logic                         rst_ni,

    // === CPU Interface ===
    input  logic                         req_valid_i,
    input  logic [ADDR_WIDTH-1:0]        req_addr_i,
    output logic                         rsp_valid_o,
    output logic [31:0]                  rsp_data_o,
    output logic                         rsp_error_o,

    // === Memory Interface ===
    output logic                         mem_req_o,
    output logic [ADDR_WIDTH-1:0]        mem_addr_o,
    input  logic                         mem_valid_i,
    input  logic [LINE_SIZE_BYTES*8-1:0] mem_data_i
);

    // -------------------------------------------------------------------------
    // Internal Wires — Controller ↔ Datapath
    // -------------------------------------------------------------------------
    // Datapath → Controller (status)
    logic                       dp_hit;
    logic [ASSOCIATIVITY-1:0]   dp_hit_way;
    logic [WAY_IDX_W-1:0]       dp_lru_way;
    logic [31:0]                dp_data;

    // Controller → Datapath (refill control)
    logic                       ctl_refill_sel;
    logic [ADDR_WIDTH-1:0]      ctl_refill_addr;
    logic                       ctl_refill_we;
    logic                       ctl_refill_valid;
    logic [WAY_IDX_W-1:0]       ctl_refill_way_sel;

    // -------------------------------------------------------------------------
    // Controller FSM
    // -------------------------------------------------------------------------
    s1_icache_controller #(
        .ADDR_WIDTH      (ADDR_WIDTH),
        .LINE_SIZE_BYTES (LINE_SIZE_BYTES),
        .ASSOCIATIVITY   (ASSOCIATIVITY)
    ) u_controller (
        .clk_i            (clk_i),
        .rst_ni           (rst_ni),

        // CPU
        .req_valid_i      (req_valid_i),
        .req_addr_i       (req_addr_i),
        .rsp_valid_o      (rsp_valid_o),
        .rsp_data_o       (rsp_data_o),
        .rsp_error_o      (rsp_error_o),

        // Datapath status
        .hit_i            (dp_hit),
        .hit_way_i        (dp_hit_way),
        .lru_way_i        (dp_lru_way),
        .dp_data_i        (dp_data),

        // Datapath control
        .refill_sel_o     (ctl_refill_sel),
        .refill_addr_o    (ctl_refill_addr),
        .refill_we_o      (ctl_refill_we),
        .refill_valid_o   (ctl_refill_valid),
        .refill_way_sel_o (ctl_refill_way_sel),

        // Memory
        .mem_req_o        (mem_req_o),
        .mem_addr_o       (mem_addr_o),
        .mem_valid_i      (mem_valid_i)
    );

    // -------------------------------------------------------------------------
    // Datapath
    // -------------------------------------------------------------------------
    s1_icache_datapath #(
        .CACHE_SIZE_KB   (CACHE_SIZE_KB),
        .LINE_SIZE_BYTES (LINE_SIZE_BYTES),
        .ASSOCIATIVITY   (ASSOCIATIVITY),
        .ADDR_WIDTH      (ADDR_WIDTH)
    ) u_datapath (
        .clk_i            (clk_i),
        .rst_ni           (rst_ni),

        // CPU address broadcast — the controller sees the same signal for
        // refill-address alignment.
        .req_addr_i       (req_addr_i),

        // Controller-driven refill
        .refill_sel_i     (ctl_refill_sel),
        .refill_addr_i    (ctl_refill_addr),
        .refill_we_i      (ctl_refill_we),
        .refill_valid_i   (ctl_refill_valid),
        .refill_way_sel_i (ctl_refill_way_sel),
        .refill_data_i    (mem_data_i),   // BYPASS: memory data → datapath

        // Status to controller
        .hit_o            (dp_hit),
        .hit_way_o        (dp_hit_way),
        .lru_way_o        (dp_lru_way),
        .rsp_data_o       (dp_data)
    );

endmodule
