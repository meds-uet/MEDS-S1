// Copyright 2026 Maktab-e-Digital Systems Lahore.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// s1_icache_datapath : instruction-cache datapath (read-only)    [COMPLETE]
//
// N-way set-associative, blocking, read-only fetch datapath. All arrays
// (tag, data, replacement state) go through meds_s1_sram per NFR-5.
//
// Spec:      SPEC §15, §17, INTERFACES.md §8
// Testbench: tb_s1_icache_datapath.sv
// =============================================================================

module s1_icache_datapath #(
    parameter int unsigned CACHE_SIZE_KB   = 16,
    parameter int unsigned LINE_SIZE_BYTES = 64,
    parameter int unsigned ASSOCIATIVITY   = 2,
    parameter int unsigned ADDR_WIDTH      = 40,
    localparam int unsigned WAY_IDX_W      = (ASSOCIATIVITY > 1) ? $clog2(ASSOCIATIVITY) : 1
)(
    input  logic                         clk_i,
    input  logic                         rst_ni,

    // From CPU (broadcast — same signal the controller sees)
    input  logic [ADDR_WIDTH-1:0]        req_addr_i,

    // From Controller
    input  logic                         refill_sel_i,
    input  logic [ADDR_WIDTH-1:0]        refill_addr_i,
    input  logic                         refill_we_i,
    input  logic                         refill_valid_i,   // 0 = write INVALID
    input  logic [WAY_IDX_W-1:0]         refill_way_sel_i,
    input  logic [LINE_SIZE_BYTES*8-1:0] refill_data_i,

    // To Controller
    output logic                         hit_o,
    output logic [ASSOCIATIVITY-1:0]     hit_way_o,        // one-hot
    output logic [WAY_IDX_W-1:0]         lru_way_o,        // victim way
    output logic [31:0]                  rsp_data_o
);

    // -------------------------------------------------------------------------
    // Derived Parameters
    // -------------------------------------------------------------------------
    localparam int unsigned LINE_SIZE_BITS   = LINE_SIZE_BYTES * 8;
    localparam int unsigned OFFSET_BITS      = $clog2(LINE_SIZE_BYTES);
    localparam int unsigned NUM_SETS         = (CACHE_SIZE_KB * 1024)
                                                / (LINE_SIZE_BYTES * ASSOCIATIVITY);
    localparam int unsigned INDEX_BITS       = $clog2(NUM_SETS);
    localparam int unsigned TAG_BITS         = ADDR_WIDTH - INDEX_BITS - OFFSET_BITS;
    localparam int unsigned TAG_ENTRY_WIDTH  = TAG_BITS + 1;   // {valid, tag}
    localparam int unsigned TAG_ENTRY_PADDED = ((TAG_ENTRY_WIDTH + 7) / 8) * 8;

    localparam int unsigned WORD_SEL_BITS    = $clog2(LINE_SIZE_BYTES / 4);

    // meds_s1_sram's be_i is (DW>>3) wide, so any array narrower than a
    // byte (the per-set LRU bit) must be padded up — same trick as the tag
    // entry above.
    localparam int unsigned LRU_ENTRY_PADDED = 8;

`ifndef SYNTHESIS
    initial begin
        assert (ASSOCIATIVITY inside {1, 2, 4, 8, 16})
            else $error("s1_icache_datapath: ASSOCIATIVITY=%0d must be a power of two",
                        ASSOCIATIVITY);
    end
`endif

    // -------------------------------------------------------------------------
    // Address Mux — refill takes priority over the CPU fetch
    // -------------------------------------------------------------------------
    logic [ADDR_WIDTH-1:0]  dp_addr;
    logic [TAG_BITS-1:0]    dp_tag;
    logic [INDEX_BITS-1:0]  dp_index;
    logic [OFFSET_BITS-1:0] dp_offset;

    assign dp_addr   = refill_sel_i ? refill_addr_i : req_addr_i;
    assign dp_tag    = dp_addr[ADDR_WIDTH-1 : INDEX_BITS+OFFSET_BITS];
    assign dp_index  = dp_addr[INDEX_BITS+OFFSET_BITS-1 : OFFSET_BITS];
    assign dp_offset = dp_addr[OFFSET_BITS-1 : 0];

    // -------------------------------------------------------------------------
    // Shared SRAM Control
    //   All tag/data/LRU arrays are indexed by the same set index. sram_req
    //   is always asserted; writes are gated by the per-way write enables.
    // -------------------------------------------------------------------------
    logic [INDEX_BITS-1:0] sram_addr;
    logic                  sram_req;

    assign sram_addr = dp_index;
    assign sram_req  = 1'b1;

    // =========================================================================
    // Tag Arrays (one per way)
    // =========================================================================
    logic [TAG_ENTRY_PADDED-1:0] tag_rdata_padded [ASSOCIATIVITY];
    logic [TAG_ENTRY_PADDED-1:0] tag_wdata_padded [ASSOCIATIVITY];
    logic [TAG_ENTRY_WIDTH-1:0]  tag_rdata        [ASSOCIATIVITY];
    logic [TAG_ENTRY_WIDTH-1:0]  tag_wdata        [ASSOCIATIVITY];
    logic                        tag_we           [ASSOCIATIVITY];

    logic                        tag_valid        [ASSOCIATIVITY];
    logic [TAG_BITS-1:0]         tag_field        [ASSOCIATIVITY];
    logic [ASSOCIATIVITY-1:0]    tag_match;

    for (genvar w = 0; w < ASSOCIATIVITY; w++) begin : g_tag_way

        assign tag_we[w]    = refill_we_i && (refill_way_sel_i == WAY_IDX_W'(w));
        assign tag_wdata[w] = {refill_valid_i, dp_tag};

        // Pad tag entry to a byte boundary for meds_s1_sram's byte-enable port.
        assign tag_wdata_padded[w] = {{(TAG_ENTRY_PADDED-TAG_ENTRY_WIDTH){1'b0}},
                                      tag_wdata[w]};

        meds_s1_sram #(
            .DW    (TAG_ENTRY_PADDED),
            .DEPTH (NUM_SETS),
            .IMPL  (0)
        ) u_tag_array (
            .clk_i   (clk_i),
            .rst_ni  (rst_ni),
            .req_i   (sram_req),
            .we_i    (tag_we[w]),
            .addr_i  (sram_addr),
            .be_i    ({TAG_ENTRY_PADDED/8{1'b1}}),
            .wdata_i (tag_wdata_padded[w]),
            .rdata_o (tag_rdata_padded[w])
        );

        assign tag_rdata[w] = tag_rdata_padded[w][TAG_ENTRY_WIDTH-1:0];
        assign tag_valid[w] = tag_rdata[w][TAG_BITS];
        assign tag_field[w] = tag_rdata[w][TAG_BITS-1:0];
        assign tag_match[w] = tag_valid[w] && (tag_field[w] == dp_tag);
    end

    // -------------------------------------------------------------------------
    // Hit Detection
    //   hit_way_o is one-hot by construction: at most one way can match a
    //   given tag, because the controller never writes the same tag into
    //   both ways at the same set.
    // -------------------------------------------------------------------------
    assign hit_o     = |tag_match;
    assign hit_way_o = tag_match;

    // =========================================================================
    // Data Arrays (one per way)
    // =========================================================================
    logic [LINE_SIZE_BITS-1:0] data_rdata [ASSOCIATIVITY];
    logic [LINE_SIZE_BITS-1:0] data_wdata [ASSOCIATIVITY];
    logic                      data_we    [ASSOCIATIVITY];

    for (genvar w = 0; w < ASSOCIATIVITY; w++) begin : g_data_way

        assign data_we[w]    = refill_we_i && (refill_way_sel_i == WAY_IDX_W'(w));
        assign data_wdata[w] = refill_data_i;

        meds_s1_sram #(
            .DW    (LINE_SIZE_BITS),
            .DEPTH (NUM_SETS),
            .IMPL  (0)
        ) u_data_array (
            .clk_i   (clk_i),
            .rst_ni  (rst_ni),
            .req_i   (sram_req),
            .we_i    (data_we[w]),
            .addr_i  (sram_addr),
            .be_i    ({LINE_SIZE_BITS/8{1'b1}}),
            .wdata_i (data_wdata[w]),
            .rdata_o (data_rdata[w])
        );
    end

    // -------------------------------------------------------------------------
    // Word-Select Mux
    //   hit_way_o is one-hot, so OR-ing every way's data with its hit bit
    //   selects exactly the hit line. Generic over ASSOCIATIVITY.
    // -------------------------------------------------------------------------
    logic [LINE_SIZE_BITS-1:0] data_selected;
    logic [WORD_SEL_BITS-1:0]  word_sel;

    always_comb begin
        data_selected = '0;
        for (int unsigned w = 0; w < ASSOCIATIVITY; w++) begin
            if (hit_way_o[w]) data_selected |= data_rdata[w];
        end
    end

    assign word_sel   = dp_offset[OFFSET_BITS-1:2];
    assign rsp_data_o = data_selected[word_sel*32 +: 32];

    // =========================================================================
    // LRU State (per set, stored through meds_s1_sram like every other array)
    // =========================================================================
    if (ASSOCIATIVITY == 1) begin : g_lru_direct_mapped

        // Direct-mapped: no replacement choice to make.
        assign lru_way_o = '0;

    end else if (ASSOCIATIVITY == 2) begin : g_lru_2way

        logic [LRU_ENTRY_PADDED-1:0] lru_rdata_padded, lru_wdata_padded;
        logic                        lru_we;

        // x-safe: treat hit_o=x as "not a definite hit" so the LRU array
        // takes its read path (stable stored value) instead of forwarding
        // an x-poisoned write value during continuous or indeterminate hits.
        assign lru_we           = (hit_o === 1'b1) | refill_we_i;

        // Update rule: on hit, the other way becomes the victim; on refill,
        // the other way (still) becomes the victim because the just-refilled
        // way is now MRU.
        assign lru_wdata_padded = {{(LRU_ENTRY_PADDED-1){1'b0}},
                                   refill_we_i ? ~refill_way_sel_i : hit_way_o[0]};

        meds_s1_sram #(
            .DW    (LRU_ENTRY_PADDED),
            .DEPTH (NUM_SETS),
            .IMPL  (0)
        ) u_lru_array (
            .clk_i   (clk_i),
            .rst_ni  (rst_ni),
            .req_i   (sram_req),
            .we_i    (lru_we),
            .addr_i  (sram_addr),
            .be_i    ({LRU_ENTRY_PADDED/8{1'b1}}),
            .wdata_i (lru_wdata_padded),
            .rdata_o (lru_rdata_padded)
        );

        // Write-forwarding: meds_s1_sram's read-during-write returns OLD
        // contents, so the read path does not update during a write cycle.
        // Forward the write value when writing to keep lru_way_o current.
        assign lru_way_o = lru_we ? lru_wdata_padded[0] : lru_rdata_padded[0];

    end else begin : g_lru_unsupported

        // Wider associativity needs a tree-PLRU or LRU-counter scheme that
        // is not implemented in v1.0. Fail loudly at elaboration rather
        // than silently returning a meaningless victim way.
        assign lru_way_o = '0;

`ifndef SYNTHESIS
        initial $error({"s1_icache_datapath: replacement policy only implemented ",
                        "for ASSOCIATIVITY==2 (got %0d)"}, ASSOCIATIVITY);
`endif
    end

endmodule
