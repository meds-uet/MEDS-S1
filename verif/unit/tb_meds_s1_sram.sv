// Copyright 2026 Maktab-e-Digital Systems Lahore.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// tb_meds_s1_sram : unit testbench for meds_s1_sram              [COMPLETE]
//
// Run:  make test-unit                    (all testbenches)
//       make test-unit TB=meds_s1_sram    (just this one)
// =============================================================================

module tb_meds_s1_sram();

    localparam DW     = 64;
    localparam DEPTH  = 1024;
    localparam ADDR_W = $clog2(DEPTH);

    logic                  clk_i, rst_ni;
    logic                  req_i, we_i;
    logic [ADDR_W-1:0]     addr_i;
    logic [DW/8-1:0]       be_i;
    logic [DW-1:0]         wdata_i;
    logic [DW-1:0]         rdata_o;

    int unsigned checks = 0;
    int unsigned errors = 0;

    logic [DW-1:0]     ref_mem   [0:DEPTH-1];
    logic [ADDR_W-1:0] rand_addr;
    logic [DW-1:0]     rand_data;
    logic [(DW/8)-1:0] rand_be;

    // -------------------------------------------------------------------------
    // DUT
    // -------------------------------------------------------------------------
    meds_s1_sram #(
        .DW    (DW),
        .DEPTH (DEPTH),
        .IMPL  (0)
    ) DUT (
        .clk_i   (clk_i),
        .rst_ni  (rst_ni),
        .req_i   (req_i),
        .we_i    (we_i),
        .addr_i  (addr_i),
        .be_i    (be_i),
        .wdata_i (wdata_i),
        .rdata_o (rdata_o)
    );

    /* verilator lint_off BLKSEQ */
    initial clk_i = 0;
    always #5 clk_i = ~clk_i;
    /* verilator lint_on BLKSEQ */

    // -------------------------------------------------------------------------
    // Reference Model
    //   Computes the expected post-write contents given the current contents,
    //   the write data, and the byte-enable mask.
    // -------------------------------------------------------------------------
    function automatic logic [DW-1:0] ref_write(
        input logic [DW-1:0]     curr_data,
        input logic [DW-1:0]     wdata_in,
        input logic [(DW/8)-1:0] be_in
    );
        logic [DW-1:0] new_data = curr_data;
        for (int i = 0; i < DW/8; i++) begin
            if (be_in[i]) begin
                new_data[i*8 +: 8] = wdata_in[i*8 +: 8];
            end
        end
        return new_data;
    endfunction

    // -------------------------------------------------------------------------
    // Check Helpers
    // -------------------------------------------------------------------------
    task automatic check(
        input string         name,
        input logic [DW-1:0] got,
        input logic [DW-1:0] exp
    );
        checks++;
        if (got !== exp) begin
            errors++;
            $display("  FAIL %-28s got=0x%016h exp=0x%016h", name, got, exp);
        end
    endtask

    // -------------------------------------------------------------------------
    // Write Operation
    // -------------------------------------------------------------------------
    task automatic write_mem(
        input logic [ADDR_W-1:0] addr,
        input logic [DW-1:0]     data,
        input logic [(DW/8)-1:0] be
    );
        @(posedge clk_i);
        req_i = 1; we_i = 1;
        addr_i = addr; be_i = be; wdata_i = data;
        @(posedge clk_i);
        req_i = 0; we_i = 0;
        ref_mem[addr] = ref_write(ref_mem[addr], data, be);
        $display("(Write) @ addr = %h, data = %h, be = %b", addr, data, be);
    endtask

    // -------------------------------------------------------------------------
    // Read Operation
    // -------------------------------------------------------------------------
    task automatic read_mem(
        input logic [ADDR_W-1:0] addr,
        input string             name
    );
        @(negedge clk_i);
        req_i = 1; we_i = 0; addr_i = addr;
        @(negedge clk_i);
        req_i = 0;
        $display("(Read) @ addr = %h, got=0x%016h exp=0x%016h",
                 addr, rdata_o, ref_mem[addr]);
        check(name, rdata_o, ref_mem[addr]);
    endtask

    // -------------------------------------------------------------------------
    // Memory Initialisation
    // -------------------------------------------------------------------------
    task automatic init_memory();
        for (int i = 0; i < DEPTH; i++) begin
            write_mem(ADDR_W'(i), '0, '1);
            ref_mem[i] = '0;
        end
    endtask

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_meds_s1_sram);

        rst_ni = 0;
        @(posedge clk_i);
        rst_ni = 1;

        $display("=== tb_meds_s1_sram : DW=%0d DEPTH=%0d ===", DW, DEPTH);

        $display("Initializing all memory to zero...");
        init_memory();

        $display("Tests started...");

        // T1 — Full word write/read
        write_mem(10'h10, 64'hDEADBEEFDEADBEEF, 8'hFF);
        read_mem (10'h10, "Full word write/read");

        // T2 — Lower half byte-mask
        write_mem(10'h10, 64'hDEADBEEF22222222, 8'h0F);
        read_mem (10'h10, "Lower half byte-mask");

        // T3 — Upper half byte-mask
        write_mem(10'h10, 64'h11111111DEADBEEF, 8'hF0);
        read_mem (10'h10, "Upper half byte-mask");

        // T4 — Single byte write
        write_mem(10'h20, 64'hDEADBEEFDEADBEEF, 8'h01);
        read_mem (10'h20, "Single byte write");

        // T5 — Cross-talk check
        read_mem(10'h10, "Address 0x10 unchanged");
        read_mem(10'h20, "Address 0x20 unchanged");

        // T6 — Address boundaries
        write_mem(0, 64'h1111111111111111, 8'hFF);
        read_mem (0, "Address 0 boundary");
        write_mem(ADDR_W'(DEPTH-1), 64'h2222222222222222, 8'hFF);
        read_mem (ADDR_W'(DEPTH-1), "Address DEPTH-1 boundary");

        // T7 — 20 random write/read pairs
        $display("Running 20 random tests...");
        for (int i = 0; i < 20; i++) begin
            rand_addr = ADDR_W'($urandom() & (DEPTH - 1));
            rand_data = DW'($urandom() | ($urandom() << 32));
            rand_be   = DW'($urandom() & 8'hFF);
            write_mem(rand_addr, rand_data, rand_be);
            read_mem (rand_addr, $sformatf("Random test %0d", i+1));
        end

        // -------------------------------------------------------------------
        // Summary
        // -------------------------------------------------------------------
        if (errors == 0) begin
            $display("=== PASS : %0d checks ===", checks);
            $finish;
        end else begin
            $display("=== FAIL : %0d errors of %0d checks ===", errors, checks);
            $fatal(1, "tb_meds_s1_sram failed");
        end
    end

endmodule

