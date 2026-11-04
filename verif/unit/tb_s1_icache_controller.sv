// Copyright 2026 Maktab-e-Digital Systems Lahore.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// tb_s1_icache_controller : unit testbench for s1_icache_controller [COMPLETE]
//
// Run:  make test-unit                            (all testbenches)
//       make test-unit TB=s1_icache_controller    (just this one)
// =============================================================================

module tb_s1_icache_controller();

    localparam int unsigned ADDR_WIDTH      = 40;
    localparam int unsigned LINE_SIZE_BYTES = 64;
    localparam int unsigned ASSOCIATIVITY   = 2;
    localparam int unsigned OFFSET_BITS     = $clog2(LINE_SIZE_BYTES);
    localparam int unsigned WAY_IDX_W       = (ASSOCIATIVITY > 1) ? $clog2(ASSOCIATIVITY) : 1;

    localparam logic [31:0] DP_DATA_VALUE   = 32'hCAFE_1234;
    localparam int unsigned MEM_LATENCY     = 4;

    // DUT signals
    logic                       clk_i, rst_ni;
    logic                       req_valid_i;
    logic [ADDR_WIDTH-1:0]      req_addr_i;
    logic                       rsp_valid_o;
    logic [31:0]                rsp_data_o;
    logic                       rsp_error_o;
    logic                       hit_i;
    logic [ASSOCIATIVITY-1:0]   hit_way_i;
    logic [WAY_IDX_W-1:0]       lru_way_i;
    logic [31:0]                dp_data_i;
    logic                       refill_sel_o;
    logic [ADDR_WIDTH-1:0]      refill_addr_o;
    logic                       refill_we_o;
    logic                       refill_valid_o;
    logic [WAY_IDX_W-1:0]       refill_way_sel_o;
    logic                       mem_req_o;
    logic [ADDR_WIDTH-1:0]      mem_addr_o;
    logic                       mem_valid_i;

    int unsigned checks = 0;
    int unsigned errors = 0;

    // -------------------------------------------------------------------------
    // DUT
    // -------------------------------------------------------------------------
    s1_icache_controller #(
        .ADDR_WIDTH      (ADDR_WIDTH),
        .LINE_SIZE_BYTES (LINE_SIZE_BYTES),
        .ASSOCIATIVITY   (ASSOCIATIVITY)
    ) DUT (
        .clk_i            (clk_i),
        .rst_ni           (rst_ni),
        .req_valid_i      (req_valid_i),
        .req_addr_i       (req_addr_i),
        .rsp_valid_o      (rsp_valid_o),
        .rsp_data_o       (rsp_data_o),
        .rsp_error_o      (rsp_error_o),
        .hit_i            (hit_i),
        .hit_way_i        (hit_way_i),
        .lru_way_i        (lru_way_i),
        .dp_data_i        (dp_data_i),
        .refill_sel_o     (refill_sel_o),
        .refill_addr_o    (refill_addr_o),
        .refill_we_o      (refill_we_o),
        .refill_valid_o   (refill_valid_o),
        .refill_way_sel_o (refill_way_sel_o),
        .mem_req_o        (mem_req_o),
        .mem_addr_o       (mem_addr_o),
        .mem_valid_i      (mem_valid_i)
    );

    initial clk_i = 0;
    always #5 clk_i = ~clk_i;

    // -------------------------------------------------------------------------
    // Stimulus stubs — fixed values to model the surrounding environment
    // -------------------------------------------------------------------------
    assign dp_data_i = DP_DATA_VALUE;   // datapath always returns this word
    assign hit_way_i = 2'b01;           // one-hot (unused by FSM, satisfies assert)

    // -------------------------------------------------------------------------
    // Single-line cache model: hits if last-refilled address matches
    // -------------------------------------------------------------------------
    logic [ADDR_WIDTH-1:0] cached_addr;
    logic                  cached_valid;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            cached_addr  <= '0;
            cached_valid <= 1'b0;
        end else if (refill_we_o && refill_sel_o) begin
            cached_addr  <= refill_addr_o;
            cached_valid <= 1'b1;
        end
    end

    assign hit_i = cached_valid &&
                   (req_addr_i[ADDR_WIDTH-1:OFFSET_BITS] ==
                    cached_addr[ADDR_WIDTH-1:OFFSET_BITS]);

    // -------------------------------------------------------------------------
    // Memory model: assert mem_valid_i for one cycle, MEM_LATENCY cycles
    // after mem_req_o rises
    // -------------------------------------------------------------------------
    logic [3:0] mem_cnt;
    logic       mem_active;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            mem_active  <= 1'b0;
            mem_cnt     <= 4'd0;
            mem_valid_i <= 1'b0;
        end else begin
            mem_valid_i <= 1'b0;
            if (!mem_active && mem_req_o) begin
                mem_active <= 1'b1;
                mem_cnt    <= 4'(MEM_LATENCY);
            end else if (mem_active) begin
                if (mem_cnt == 4'd0) begin
                    mem_valid_i <= 1'b1;
                    mem_active  <= 1'b0;
                end else begin
                    mem_cnt <= mem_cnt - 1'b1;
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Check helpers
    // -------------------------------------------------------------------------
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

    // -------------------------------------------------------------------------
    // Request tasks
    // -------------------------------------------------------------------------
    task automatic do_miss_request(input [ADDR_WIDTH-1:0] addr);
        @(posedge clk_i); #1;
        req_valid_i = 1'b1;
        req_addr_i  = addr;

        // MISS state — hold on mem_req_o before sampling
        wait (mem_req_o == 1'b1);
        check1("miss: mem_req_o asserted",        mem_req_o,   1'b1);
        check1("miss: mem_addr offset zero",
               mem_addr_o[OFFSET_BITS-1:0] == '0,              1'b1);
        check1("miss: req_valid held high",       req_valid_i, 1'b1);

        // REFILL state
        wait (refill_we_o == 1'b1);
        check1("refill: refill_we asserted",      refill_we_o,    1'b1);
        check1("refill: refill_sel asserted",     refill_sel_o,   1'b1);
        check1("refill: refill_valid=1",          refill_valid_o, 1'b1);
        check1("refill: way matches lru",
               refill_way_sel_o == lru_way_i,                     1'b1);
        check1("refill: refill_addr offset zero",
               refill_addr_o[OFFSET_BITS-1:0] == '0,              1'b1);

        // Final HIT (post-refill)
        wait (rsp_valid_o == 1'b1);
        check32("miss->hit: rsp_data correct",    rsp_data_o, DP_DATA_VALUE);

        @(posedge clk_i); #1;
        req_valid_i = 1'b0;
        @(posedge clk_i); #1;
    endtask

    task automatic do_hit_request(input [ADDR_WIDTH-1:0] addr);
        @(posedge clk_i); #1;
        req_valid_i = 1'b1;
        req_addr_i  = addr;

        wait (rsp_valid_o == 1'b1);
        check1 ("hit: mem_req_o=0",      mem_req_o,   1'b0);
        check1 ("hit: refill_we=0",      refill_we_o, 1'b0);
        check32("hit: rsp_data correct", rsp_data_o,  DP_DATA_VALUE);

        @(posedge clk_i); #1;
        req_valid_i = 1'b0;
        @(posedge clk_i); #1;
    endtask

    // -------------------------------------------------------------------------
    // Watchdog — fails fast if the FSM hangs
    // -------------------------------------------------------------------------
    initial begin
        #10000;
        $display("=== FAIL : global timeout ===");
        $fatal(1, "tb_s1_icache_controller timed out");
    end

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    initial begin
        rst_ni      = 1'b0;
        req_valid_i = 1'b0;
        req_addr_i  = '0;
        lru_way_i   = '0;

        repeat (2) @(posedge clk_i);
        rst_ni = 1'b1;
        @(posedge clk_i); #1;

        $display("=== tb_s1_icache_controller ===");

        // -------------------------------------------------------------------
        // T1 — Reset state: all outputs idle
        // -------------------------------------------------------------------
        check1("T1 rsp_valid=0 in IDLE", rsp_valid_o, 1'b0);
        check1("T1 mem_req=0 in IDLE",   mem_req_o,   1'b0);
        check1("T1 refill_we=0 in IDLE", refill_we_o, 1'b0);
        check1("T1 rsp_error=0",         rsp_error_o, 1'b0);

        // -------------------------------------------------------------------
        // T2 — No request: stays IDLE
        // -------------------------------------------------------------------
        repeat (3) @(posedge clk_i); #1;
        check1("T2 rsp_valid=0 with no req", rsp_valid_o, 1'b0);
        check1("T2 mem_req=0 with no req",   mem_req_o,   1'b0);

        // -------------------------------------------------------------------
        // T3 — Miss path, LRU victim = way 0
        // -------------------------------------------------------------------
        lru_way_i = 1'b0;
        do_miss_request(40'h0000_1000);

        // -------------------------------------------------------------------
        // T4 — Hit path on the same address
        // -------------------------------------------------------------------
        do_hit_request(40'h0000_1000);

        // -------------------------------------------------------------------
        // T5 — Miss on a new address, LRU victim = way 1
        // -------------------------------------------------------------------
        lru_way_i = 1'b1;
        do_miss_request(40'h0000_2000);

        // -------------------------------------------------------------------
        // Summary
        // -------------------------------------------------------------------
        if (errors == 0) begin
            $display("=== PASS : %0d checks ===", checks);
            $finish;
        end else begin
            $display("=== FAIL : %0d errors of %0d checks ===", errors, checks);
            $fatal(1, "tb_s1_icache_controller failed");
        end
    end

endmodule
