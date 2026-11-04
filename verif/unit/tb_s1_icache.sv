// Copyright 2026 Maktab-e-Digital Systems Lahore.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// tb_s1_icache : integration testbench for s1_icache             [COMPLETE]
//
// Run:  make test-unit                  (all testbenches)
//       make test-unit TB=s1_icache     (just this one)
// =============================================================================

module tb_s1_icache();

    localparam int unsigned CACHE_SIZE_KB   = 16;
    localparam int unsigned LINE_SIZE_BYTES = 64;
    localparam int unsigned ASSOCIATIVITY   = 2;
    localparam int unsigned ADDR_WIDTH      = 40;

    localparam int unsigned LINE_SIZE_BITS = LINE_SIZE_BYTES * 8;
    localparam int unsigned WORDS_PER_LINE = LINE_SIZE_BYTES / 4;
    localparam int unsigned MEM_LATENCY    = 4;

    // DUT signals
    logic                       clk_i, rst_ni;
    logic                       req_valid_i;
    logic [ADDR_WIDTH-1:0]      req_addr_i;
    logic                       rsp_valid_o;
    logic [31:0]                rsp_data_o;
    logic                       rsp_error_o;
    logic                       mem_req_o;
    logic [ADDR_WIDTH-1:0]      mem_addr_o;
    logic                       mem_valid_i;
    logic [LINE_SIZE_BITS-1:0]  mem_data_i;

    int unsigned checks = 0;
    int unsigned errors = 0;

    // -------------------------------------------------------------------------
    // DUT
    // -------------------------------------------------------------------------
    s1_icache #(
        .CACHE_SIZE_KB   (CACHE_SIZE_KB),
        .LINE_SIZE_BYTES (LINE_SIZE_BYTES),
        .ASSOCIATIVITY   (ASSOCIATIVITY),
        .ADDR_WIDTH      (ADDR_WIDTH)
    ) DUT (
        .clk_i       (clk_i),
        .rst_ni      (rst_ni),
        .req_valid_i (req_valid_i),
        .req_addr_i  (req_addr_i),
        .rsp_valid_o (rsp_valid_o),
        .rsp_data_o  (rsp_data_o),
        .rsp_error_o (rsp_error_o),
        .mem_req_o   (mem_req_o),
        .mem_addr_o  (mem_addr_o),
        .mem_valid_i (mem_valid_i),
        .mem_data_i  (mem_data_i)
    );

    initial clk_i = 0;
    always #5 clk_i = ~clk_i;

    // -------------------------------------------------------------------------
    // Memory Model
    //   line pattern: word i = base + i
    // -------------------------------------------------------------------------
    function automatic logic [LINE_SIZE_BITS-1:0] make_line(input logic [31:0] base);
        logic [LINE_SIZE_BITS-1:0] line;
        for (int i = 0; i < WORDS_PER_LINE; i++) line[i*32 +: 32] = base + i[31:0];
        return line;
    endfunction

    logic                       mem_pending;
    logic [3:0]                 mem_cnt;
    logic [LINE_SIZE_BITS-1:0]  mem_data_r;

    assign mem_data_i = mem_data_r;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            mem_pending <= 1'b0;
            mem_cnt     <= '0;
            mem_valid_i <= 1'b0;
            mem_data_r  <= '0;
        end else begin
            mem_valid_i <= 1'b0;
            if (!mem_pending && mem_req_o && !mem_valid_i) begin
                mem_pending <= 1'b1;
                mem_cnt     <= 4'(MEM_LATENCY);
                mem_data_r  <= make_line(mem_addr_o[31:0]);
            end else if (mem_pending) begin
                if (mem_cnt == 4'd0) begin
                    mem_valid_i <= 1'b1;
                    mem_pending <= 1'b0;
                end else begin
                    mem_cnt <= mem_cnt - 1'b1;
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Check Helpers
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
    // CPU Request Task
    //   Issues a fetch, waits for rsp_valid_o, checks the returned instruction
    //   and whether memory traffic was seen (miss) or not (hit).
    // -------------------------------------------------------------------------
    task automatic cpu_request(
        input [ADDR_WIDTH-1:0] addr,
        input [31:0]           expected,
        input string           name,
        input logic            expect_miss
    );
        logic mem_req_seen;
        mem_req_seen = 1'b0;

        @(posedge clk_i); #1;
        req_valid_i = 1'b1;
        req_addr_i  = addr;

        while (rsp_valid_o !== 1'b1) begin
            @(posedge clk_i); #1;
            if (mem_req_o === 1'b1) mem_req_seen = 1'b1;
        end

        check32(name, rsp_data_o, expected);
        check1({name, " rsp_error=0"}, rsp_error_o, 1'b0);

        if (expect_miss) check1({name, " miss seen"}, mem_req_seen,  1'b1);
        else             check1({name, " no miss"},   ~mem_req_seen, 1'b1);

        @(posedge clk_i); #1;
        req_valid_i = 1'b0;
        req_addr_i  = '0;
        repeat (2) @(posedge clk_i); #1;
    endtask

    // -------------------------------------------------------------------------
    // Watchdog — fail fast if the FSM hangs
    // -------------------------------------------------------------------------
    initial begin
        #10000;
        $display("=== FAIL : global timeout ===");
        $fatal(1, "tb_s1_icache timed out");
    end

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    initial begin
        rst_ni      = 1'b0;
        req_valid_i = 1'b0;
        req_addr_i  = '0;

        repeat (2) @(posedge clk_i);
        rst_ni = 1'b1;
        @(posedge clk_i); #1;

        $display("=== tb_s1_icache ===");

        // -------------------------------------------------------------------
        // T1 — Reset state: all outputs idle
        // -------------------------------------------------------------------
        check1("T1 rsp_valid=0 in IDLE", rsp_valid_o, 1'b0);
        check1("T1 mem_req=0 in IDLE",   mem_req_o,   1'b0);
        check1("T1 rsp_error=0",         rsp_error_o, 1'b0);

        // -------------------------------------------------------------------
        // T2 — Cold miss on line A (0x1000)
        // -------------------------------------------------------------------
        cpu_request(40'h0000_1000, 32'h0000_1000, "T2 miss 0x1000", 1'b1);

        // -------------------------------------------------------------------
        // T3 — Hit on line A
        // -------------------------------------------------------------------
        cpu_request(40'h0000_1000, 32'h0000_1000, "T3 hit 0x1000",  1'b0);

        // -------------------------------------------------------------------
        // T4–T6 — Word-select within line A
        // -------------------------------------------------------------------
        cpu_request(40'h0000_1004, 32'h0000_1001, "T4 word 1",      1'b0);
        cpu_request(40'h0000_1008, 32'h0000_1002, "T5 word 2",      1'b0);
        cpu_request(40'h0000_103C, 32'h0000_100F, "T6 word 15",     1'b0);

        // -------------------------------------------------------------------
        // T7 — Miss on line B (0x3000, same set, second way)
        // -------------------------------------------------------------------
        cpu_request(40'h0000_3000, 32'h0000_3000, "T7 miss 0x3000", 1'b1);

        // -------------------------------------------------------------------
        // T8 — Hit on line A still works (both ways valid)
        // -------------------------------------------------------------------
        cpu_request(40'h0000_1000, 32'h0000_1000, "T8 hit 0x1000",  1'b0);

        // -------------------------------------------------------------------
        // T9 — Miss on line C (0x0000, different set, no cross-talk)
        // -------------------------------------------------------------------
        cpu_request(40'h0000_0000, 32'h0000_0000, "T9 miss 0x0000", 1'b1);

        // -------------------------------------------------------------------
        // T10–T11 — Hits on both previously-cached lines
        // -------------------------------------------------------------------
        cpu_request(40'h0000_1000, 32'h0000_1000, "T10 hit 0x1000", 1'b0);
        cpu_request(40'h0000_3000, 32'h0000_3000, "T11 hit 0x3000", 1'b0);

        // -------------------------------------------------------------------
        // Summary
        // -------------------------------------------------------------------
        if (errors == 0) begin
            $display("=== PASS : %0d checks ===", checks);
            $finish;
        end else begin
            $display("=== FAIL : %0d errors of %0d checks ===", errors, checks);
            $fatal(1, "tb_s1_icache failed");
        end
    end

endmodule
