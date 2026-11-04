// Copyright 2026 Maktab-e-Digital Systems Lahore.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// tb_s1_icache_datapath : unit testbench for s1_icache_datapath  [COMPLETE]
//
// Run:  make test-unit                          (all testbenches)
//       make test-unit TB=s1_icache_datapath    (just this one)
// =============================================================================
module tb_s1_icache_datapath();

    localparam int unsigned CACHE_SIZE_KB   = 16;
    localparam int unsigned LINE_SIZE_BYTES = 64;
    localparam int unsigned ASSOCIATIVITY   = 2;
    localparam int unsigned ADDR_WIDTH      = 40;

    localparam int unsigned LINE_SIZE_BITS = LINE_SIZE_BYTES * 8;
    localparam int unsigned OFFSET_BITS    = $clog2(LINE_SIZE_BYTES);
    localparam int unsigned NUM_SETS       = (CACHE_SIZE_KB * 1024)
                                              / (LINE_SIZE_BYTES * ASSOCIATIVITY);
    localparam int unsigned WORDS_PER_LINE = LINE_SIZE_BYTES / 4;
    localparam int unsigned WAY_IDX_W      = (ASSOCIATIVITY > 1) ? $clog2(ASSOCIATIVITY) : 1;

    logic                       clk_i, rst_ni;
    logic [ADDR_WIDTH-1:0]      req_addr_i;
    logic                       refill_sel_i;
    logic [ADDR_WIDTH-1:0]      refill_addr_i;
    logic                       refill_we_i;
    logic                       refill_valid_i;
    logic [WAY_IDX_W-1:0]       refill_way_sel_i;
    logic [LINE_SIZE_BITS-1:0]  refill_data_i;
    logic                       hit_o;
    logic [ASSOCIATIVITY-1:0]   hit_way_o;
    logic [WAY_IDX_W-1:0]       lru_way_o;
    logic [31:0]                rsp_data_o;

    int unsigned checks = 0;
    int unsigned errors = 0;

    // -------------------------------------------------------------------------
    // DUT
    // -------------------------------------------------------------------------
    s1_icache_datapath #(
        .CACHE_SIZE_KB   (CACHE_SIZE_KB),
        .LINE_SIZE_BYTES (LINE_SIZE_BYTES),
        .ASSOCIATIVITY   (ASSOCIATIVITY),
        .ADDR_WIDTH      (ADDR_WIDTH)
    ) DUT (
        .clk_i            (clk_i),
        .rst_ni           (rst_ni),
        .req_addr_i       (req_addr_i),
        .refill_sel_i     (refill_sel_i),
        .refill_addr_i    (refill_addr_i),
        .refill_we_i      (refill_we_i),
        .refill_valid_i   (refill_valid_i),
        .refill_way_sel_i (refill_way_sel_i),
        .refill_data_i    (refill_data_i),
        .hit_o            (hit_o),
        .hit_way_o        (hit_way_o),
        .lru_way_o        (lru_way_o),
        .rsp_data_o       (rsp_data_o)
    );

    initial clk_i = 0;
    always #5 clk_i = ~clk_i;

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------
    // Line pattern: word i = base + i.
    function automatic logic [LINE_SIZE_BITS-1:0] make_line(input logic [31:0] base);
        logic [LINE_SIZE_BITS-1:0] line;
        for (int i = 0; i < WORDS_PER_LINE; i++) line[i*32 +: 32] = base + i[31:0];
        return line;
    endfunction

    task automatic check1(input string name, input logic got, input logic exp);
        checks++;
        if (got !== exp) begin
            errors++;
            $display("  FAIL %s: got=%b exp=%b", name, got, exp);
        end
    endtask

    task automatic check32(input string name,
                           input logic [31:0] got,
                           input logic [31:0] exp);
        checks++;
        if (got !== exp) begin
            errors++;
            $display("  FAIL %s: got=0x%08h exp=0x%08h", name, got, exp);
        end
    endtask

    task automatic check_way(input string name,
                             input logic [ASSOCIATIVITY-1:0] got,
                             input logic [ASSOCIATIVITY-1:0] exp);
        checks++;
        if (got !== exp) begin
            errors++;
            $display("  FAIL %s: got=%b exp=%b", name, got, exp);
        end
    endtask

    // Refill a specific way at a specific address.
    // #1 after every posedge so TB drives/clears settle after the DUT latches.
    task automatic do_refill(
        input logic [ADDR_WIDTH-1:0]     addr,
        input logic [WAY_IDX_W-1:0]      way,
        input logic [LINE_SIZE_BITS-1:0] data
    );
        @(posedge clk_i);
        #1;
        refill_sel_i     = 1'b1;
        refill_we_i      = 1'b1;
        refill_valid_i   = 1'b1;
        refill_way_sel_i = way;
        refill_addr_i    = addr;
        refill_data_i    = data;

        @(posedge clk_i);
        #1;
        refill_sel_i     = 1'b0;
        refill_we_i      = 1'b0;
        refill_way_sel_i = '0;
        req_addr_i       = addr;    // park request so LRU read hits this set

        repeat (2) @(posedge clk_i);
        #1;
    endtask

    task automatic do_request(input logic [ADDR_WIDTH-1:0] addr);
        @(posedge clk_i);
        #1;
        req_addr_i = addr;
        repeat (2) @(posedge clk_i);
        #1;
    endtask

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    initial begin
        rst_ni           = 1'b0;
        req_addr_i       = '0;
        refill_sel_i     = 1'b0;
        refill_addr_i    = '0;
        refill_we_i      = 1'b0;
        refill_valid_i   = 1'b1;
        refill_way_sel_i = '0;
        refill_data_i    = '0;

        repeat (2) @(posedge clk_i);
        rst_ni = 1'b1;
        @(posedge clk_i);

        $display("=== tb_s1_icache_datapath ===");

        // -------------------------------------------------------------------
        // Post-reset invalidation sweep
        //   SRAM contents are x at reset; every set/way must be explicitly
        //   invalidated before any lookup so no garbage tag can match.
        // -------------------------------------------------------------------
        for (int s = 0; s < NUM_SETS; s++) begin
            for (int w = 0; w < ASSOCIATIVITY; w++) begin
                @(posedge clk_i);
                #1;
                refill_sel_i     = 1'b1;
                refill_we_i      = 1'b1;
                refill_valid_i   = 1'b0;                  // invalidate
                refill_addr_i    = 40'(s) << OFFSET_BITS;
                refill_way_sel_i = WAY_IDX_W'(w);
            end
        end
        @(posedge clk_i);
        #1;
        refill_sel_i   = 1'b0;
        refill_we_i    = 1'b0;
        refill_valid_i = 1'b1;
        repeat (2) @(posedge clk_i);
        #1;

        // -------------------------------------------------------------------
        // T1 — Refill way 0 at set 64, LRU should point at way 1
        // -------------------------------------------------------------------
        do_refill(40'h0000_1000, 1'b0, make_line(32'hA000_0000));
        check1("T1 LRU = way 1 after refill w0", lru_way_o, 1'b1);

        do_request(40'h0000_1000);
        check1 ("T1 hit",                          hit_o,      1'b1);
        check_way("T1 hit_way = way 0",            hit_way_o,  2'b01);
        check32("T1 word 0",                       rsp_data_o, 32'hA000_0000);
        check1 ("T1 LRU still way 1 after hit w0", lru_way_o,  1'b1);

        // -------------------------------------------------------------------
        // T2 — Word-select at several offsets in the same line
        // -------------------------------------------------------------------
        do_request(40'h0000_1004); check32("T2 word 1",  rsp_data_o, 32'hA000_0001);
        do_request(40'h0000_1008); check32("T2 word 2",  rsp_data_o, 32'hA000_0002);
        do_request(40'h0000_103C); check32("T2 word 15", rsp_data_o, 32'hA000_000F);

        // -------------------------------------------------------------------
        // T3 — Refill way 1 at the same set, LRU should flip back to way 0
        // -------------------------------------------------------------------
        do_refill(40'h0000_3000, 1'b1, make_line(32'hB000_0000));
        check1("T3 LRU = way 0 after refill w1", lru_way_o, 1'b0);

        do_request(40'h0000_3000);
        check1 ("T3 hit",               hit_o,      1'b1);
        check_way("T3 hit_way = way 1", hit_way_o,  2'b10);
        check32("T3 word 0 way 1",      rsp_data_o, 32'hB000_0000);

        // -------------------------------------------------------------------
        // T4 — Both ways populated, hit way 0 again
        // -------------------------------------------------------------------
        do_request(40'h0000_1000);
        check1 ("T4 hit way 0",                hit_way_o[0], 1'b1);
        check32("T4 word 0 way 0",             rsp_data_o,   32'hA000_0000);
        check1 ("T4 LRU = way 1 after hit w0", lru_way_o,    1'b1);

        // -------------------------------------------------------------------
        // T5 — Miss on an unknown tag in the same set
        // -------------------------------------------------------------------
        do_request(40'h0000_5000);
        check1 ("T5 miss",          hit_o,     1'b0);
        check_way("T5 hit_way = 0", hit_way_o, 2'b00);

        // -------------------------------------------------------------------
        // T6 — LRU isolation: activity on set 0 must not affect set 64
        // -------------------------------------------------------------------
        do_refill(40'h0000_0000, 1'b0, make_line(32'hC000_0000));
        check1("T6 LRU set 0 = way 1 after refill w0", lru_way_o, 1'b1);

        do_request(40'h0000_1000);
        check1("T6 LRU set 64 unchanged = way 1", lru_way_o, 1'b1);

        do_request(40'h0000_0000);
        check1 ("T6 hit set 0",             hit_o,      1'b1);
        check32("T6 word 0 set 0",          rsp_data_o, 32'hC000_0000);
        check1 ("T6 LRU set 0 still way 1", lru_way_o,  1'b1);

        // -------------------------------------------------------------------
        // T7 — Refill way 1 at set 0, LRU should flip back to way 0
        // -------------------------------------------------------------------
        do_refill(40'h0000_2000, 1'b1, make_line(32'hD000_0000));
        check1("T7 LRU set 0 = way 0 after refill w1", lru_way_o, 1'b0);

        do_request(40'h0000_2000);
        check1 ("T7 hit way 1",    hit_way_o[1], 1'b1);
        check32("T7 word 0 way 1", rsp_data_o,   32'hD000_0000);

        // -------------------------------------------------------------------
        // T8 — Both ways populated at set 0, hit way 0
        // -------------------------------------------------------------------
        do_request(40'h0000_0000);
        check1 ("T8 hit way 0",                      hit_way_o[0], 1'b1);
        check32("T8 word 0 way 0",                   rsp_data_o,   32'hC000_0000);
        check1 ("T8 LRU set 0 = way 1 after hit w0", lru_way_o,    1'b1);

        // -------------------------------------------------------------------
        // Summary
        // -------------------------------------------------------------------
        if (errors == 0) begin
            $display("=== PASS : %0d checks ===", checks);
            $finish;
        end else begin
            $display("=== FAIL : %0d errors of %0d checks ===", errors, checks);
            $fatal(1, "tb_s1_icache_datapath failed");
        end
    end

endmodule
