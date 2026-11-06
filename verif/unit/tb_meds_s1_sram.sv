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

  // Parameter-derived test constants (R-V2)
  localparam logic [ADDR_W-1:0] ADDR_A   = ADDR_W'(16);
  localparam logic [ADDR_W-1:0] ADDR_B   = ADDR_W'(32);
  localparam logic [ADDR_W-1:0] ADDR_0   = '0;
  localparam logic [ADDR_W-1:0] ADDR_MAX = ADDR_W'(DEPTH - 1);
  localparam logic [DW-1:0]     PAT_A    = {DW/8{8'hDE}};
  localparam logic [DW-1:0]     PAT_B    = {DW/8{8'h11}};
  localparam logic [DW/8-1:0]   BE_ALL   = '1;
  localparam logic [DW/8-1:0]   BE_LOWER = {{(DW/8-4){1'b0}}, 4'hF};
  localparam logic [DW/8-1:0]   BE_UPPER = {4'hF, {(DW/8-4){1'b0}}};
  localparam logic [DW/8-1:0]   BE_BYTE0 = {{(DW/8-1){1'b0}}, 1'b1};

  logic                  clk_i, rst_ni;
  logic                  req_i, we_i;
  logic [ADDR_W-1:0]     addr_i;
  logic [DW/8-1:0]       be_i;
  logic [DW-1:0]         wdata_i;
  logic [DW-1:0]         rdata_o;

  int unsigned checks = 0;
  int unsigned errors = 0;

  logic [DW-1:0]     ref_mem [0:DEPTH-1];
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

  // Clock generation (no inline BLKSEQ waiver)
  initial begin
    clk_i = 0;
    forever #5 clk_i = ~clk_i;
  end

  // -------------------------------------------------------------------------
  // Reference Model
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
  // Write Operation (Driven on negedge to avoid clock race)
  // -------------------------------------------------------------------------
  task automatic write_mem(
    input logic [ADDR_W-1:0] addr,
    input logic [DW-1:0]     data,
    input logic [(DW/8)-1:0] be
  );
    @(negedge clk_i);
    req_i = 1; we_i = 1;
    addr_i = addr; be_i = be; wdata_i = data;
    @(negedge clk_i);
    req_i = 0; we_i = 0;
    ref_mem[addr] = ref_write(ref_mem[addr], data, be);
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
    // No VCD dumps in CI (R-G5)

    rst_ni = 0;
    @(posedge clk_i);
    rst_ni = 1;

    $display("=== tb_meds_s1_sram : DW=%0d DEPTH=%0d ===", DW, DEPTH);

    init_memory();

    // T1 — Full word write/read
    write_mem(ADDR_A, PAT_A, BE_ALL);
    read_mem (ADDR_A, "Full word write/read");

    // T2 — Lower half byte-mask
    write_mem(ADDR_A, PAT_A, BE_LOWER);
    read_mem (ADDR_A, "Lower half byte-mask");

    // T3 — Upper half byte-mask
    write_mem(ADDR_A, PAT_B, BE_UPPER);
    read_mem (ADDR_A, "Upper half byte-mask");

    // T4 — Single byte write
    write_mem(ADDR_B, PAT_A, BE_BYTE0);
    read_mem (ADDR_B, "Single byte write");

    // T5 — Cross-talk check
    read_mem(ADDR_A, "Address A unchanged");
    read_mem(ADDR_B, "Address B unchanged");

    // T6 — Address boundaries
    write_mem(ADDR_0, PAT_B, BE_ALL);
    read_mem (ADDR_0, "Address 0 boundary");
    write_mem(ADDR_MAX, PAT_A, BE_ALL);
    read_mem (ADDR_MAX, "Address DEPTH-1 boundary");

    // T7 — 20 random write/read pairs
    for (int i = 0; i < 20; i++) begin
      rand_addr = ADDR_W'($urandom_range(DEPTH - 1));
      rand_data = DW'($urandom() | ($urandom() << 32));
      rand_be   = (DW/8)'($urandom());
      write_mem(rand_addr, rand_data, rand_be);
      read_mem (rand_addr, $sformatf("Random test %0d", i+1));
    end

    // T8 — Read-during-write returns OLD contents
    // 1. Ensure ADDR_B holds PAT_A
    write_mem(ADDR_B, PAT_A, BE_ALL);
    // 2. Perform a write of PAT_B to ADDR_B.
    // The output rdata_o must return the OLD contents (PAT_A).
    @(negedge clk_i);
    req_i = 1; we_i = 1; addr_i = ADDR_B; be_i = BE_ALL; wdata_i = PAT_B;
    @(negedge clk_i);
    req_i = 0; we_i = 0;
    check("Read-during-write OLD", rdata_o, PAT_A);

    // T9 — Reset clears rdata_o
    rst_ni = 0;
    @(negedge clk_i);
    @(negedge clk_i);
    check("Reset clears rdata_o", rdata_o, '0);
    rst_ni = 1;

    // Summary
    if (errors == 0) begin
      $display("=== PASS : %0d checks ===", checks);
      $finish;
    end else begin
      $display("=== FAIL : %0d errors of %0d checks ===", errors, checks);
      $fatal(1, "tb_meds_s1_sram failed");
    end
  end

endmodule
