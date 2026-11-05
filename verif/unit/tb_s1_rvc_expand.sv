// =============================================================================
// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// Author(s)    : Ayesha Anwar (ayesha.anwaar2005@gmail.com) (Sep,2026)
// Modified By  :
//
// tb_s1_rvc_expand : unit testbench for s1_rvc_expand             [COMPLETE]
// Description  :
// All 65536 inputs against verif/common/rvc_golden.svh, plus GNU-assembler
// vectors and named reserved/HINT encodings.
//
// Run:  make test-unit TB=s1_rvc_expand
// =============================================================================

module tb_s1_rvc_expand
  import s1_pkg::*;
;

  `include "verif/common/rvc_golden.svh"

  logic [CLEN-1:0] c;
  logic [ILEN-1:0] instr;
  logic            illegal;

  int unsigned checks = 0;
  int unsigned errors = 0;

  s1_rvc_expand dut (
    .instr_i   (c),
    .instr_o   (instr),
    .illegal_o (illegal)
  );

  task automatic check32(input string name, input logic [ILEN-1:0] got,
                         input logic [ILEN-1:0] exp);
    checks++;
    if (got !== exp) begin
      errors++;
      if (errors <= 20) $display("  FAIL %-34s got=0x%h exp=0x%h", name, got, exp);
    end
  endtask

  task automatic check1(input string name, input logic got, input logic exp);
    checks++;
    if (got !== exp) begin
      errors++;
      if (errors <= 20) $display("  FAIL %-34s got=%0d exp=%0d", name, got, exp);
    end
  endtask

  // {compressed, expansion} from riscv64-unknown-elf-as
  typedef struct packed {
    logic [15:0] c;
    logic [31:0] e;
  } vec_t;

  localparam vec_t VECS [44] = '{
    '{16'h1fe0, 32'h3fc10413}, // c.addi4spn x8, sp, 1020
    '{16'h005c, 32'h00410793}, // c.addi4spn x15, sp, 4
    '{16'h5d64, 32'h07c52483}, // c.lw x9, 124(x10)
    '{16'h7c7c, 32'h0f843783}, // c.ld x15, 248(x8)
    '{16'hdd64, 32'h06952e23}, // c.sw x9, 124(x10)
    '{16'hfc7c, 32'h0ef43c23}, // c.sd x15, 248(x8)
    '{16'h3ce0, 32'h0f84b407}, // c.fld f8, 248(x9)
    '{16'hbce0, 32'h0e84bc27}, // c.fsd f8, 248(x9)
    '{16'h0001, 32'h00000013}, // c.nop
    '{16'h1281, 32'hfe028293}, // c.addi x5, -32
    '{16'h0ffd, 32'h01ff8f93}, // c.addi x31, 31
    '{16'h337d, 32'hfff3031b}, // c.addiw x6, -1
    '{16'h5381, 32'hfe000393}, // c.li x7, -32
    '{16'h7101, 32'he0010113}, // c.addi16sp sp, -512
    '{16'h617d, 32'h1f010113}, // c.addi16sp sp, 496
    '{16'h7481, 32'hfffe04b7}, // c.lui x9, 0xfffe0
    '{16'h6ffd, 32'h0001ffb7}, // c.lui x31, 0x1f
    '{16'h907d, 32'h03f45413}, // c.srli x8, 63
    '{16'h9481, 32'h4204d493}, // c.srai x9, 32
    '{16'h997d, 32'hfff57513}, // c.andi x10, -1
    '{16'h8c1d, 32'h40f40433}, // c.sub x8, x15
    '{16'h8cb9, 32'h00e4c4b3}, // c.xor x9, x14
    '{16'h8d55, 32'h00d56533}, // c.or x10, x13
    '{16'h8df1, 32'h00c5f5b3}, // c.and x11, x12
    '{16'h9e0d, 32'h40b6063b}, // c.subw x12, x11
    '{16'h9ea9, 32'h00a686bb}, // c.addw x13, x10
    '{16'hb001, 32'h801ff06f}, // c.j .-2048
    '{16'haffd, 32'h7fe0006f}, // c.j .+2046
    '{16'hd001, 32'hf00400e3}, // c.beqz x8, .-256
    '{16'heffd, 32'h0e079f63}, // c.bnez x15, .+254
    '{16'h10fe, 32'h03f09093}, // c.slli x1, 63
    '{16'h30fe, 32'h1f813087}, // c.fldsp f1, 504(sp)
    '{16'h5ffe, 32'h0fc12f83}, // c.lwsp x31, 252(sp)
    '{16'h70fe, 32'h1f813083}, // c.ldsp x1, 504(sp)
    '{16'h6092, 32'h10013083}, // c.ldsp x1, 256(sp)     offset bit 8 alone
    '{16'h8082, 32'h00008067}, // c.jr x1
    '{16'h829a, 32'h006002b3}, // c.mv x5, x6
    '{16'h9002, 32'h00100073}, // c.ebreak
    '{16'h9382, 32'h000380e7}, // c.jalr x7
    '{16'h929a, 32'h006282b3}, // c.add x5, x6
    '{16'hbffe, 32'h1ff13c27}, // c.fsdsp f31, 504(sp)
    '{16'hdf8a, 32'h0e212e23}, // c.swsp x2, 252(sp)
    '{16'hfffe, 32'h1ff13c23}, // c.sdsp x31, 504(sp)
    '{16'he27e, 32'h11f13023}  // c.sdsp x31, 256(sp)    offset bit 8 alone
  };

  // Reserved encodings (RV64C) and the rule that makes each one reserved.
  localparam logic [15:0] RESERVED [10] = '{
    16'h0000,   // all-zero parcel: defined illegal
    16'h0004,   // C.ADDI4SPN with nzuimm = 0
    16'h8000,   // quadrant 0, funct3 100
    16'h2001,   // C.ADDIW rd = x0
    16'h6101,   // C.ADDI16SP nzimm = 0  (objdump decodes this one; the spec reserves it)
    16'h6081,   // C.LUI x1, nzimm = 0
    16'h9c41,   // quadrant 1 funct6 100111, funct2 10: reserved
    16'h4002,   // C.LWSP rd = x0
    16'h6002,   // C.LDSP rd = x0
    16'h8002    // C.JR rs1 = x0
  };

  // HINTs look odd but are legal and must expand like their base form.
  localparam logic [15:0] HINTS [6] = '{
    16'h0005,   // C.NOP imm=1            -> addi x0, x0, 1
    16'h4005,   // C.LI x0, 1
    16'h6005,   // C.LUI x0, 1
    16'h8006,   // C.MV x0, x1
    16'h0082,   // C.SLLI x1, 0 (RV64 shamt=0)
    16'h8001    // C.SRLI x8, 0 (RV64 shamt=0)
  };

  initial begin
    logic [32:0] g;
    int unsigned n_legal = 0;
    int unsigned n_illegal = 0;

    $display("=== tb_s1_rvc_expand : CLEN=%0d ILEN=%0d ===", CLEN, ILEN);

    // --- exhaustive -----------------------------------------------------------
    for (int unsigned v = 0; v < (1 << CLEN); v++) begin
      c = CLEN'(v);
      #1;
      g = rvc_golden(c);
      check1($sformatf("illegal(%04h)", c), illegal, g[ILEN]);
      // The expansion of an illegal parcel is don't-care by contract, but the
      // RTL promises all-zero so nothing half-decoded leaks downstream.
      check32($sformatf("expand(%04h)", c), instr, g[ILEN] ? '0 : g[ILEN-1:0]);
      if (g[ILEN]) n_illegal++;
      else         n_legal++;
    end
    $display("  exhaustive: %0d legal, %0d illegal (incl. %0d non-compressed)",
             n_legal, n_illegal, 1 << (CLEN - 2));

    // Sanity on the sweep itself: every value with [1:0]==11 is a 32-bit
    // instruction's first parcel and must be rejected.  If this count moves,
    // the sweep above did not cover what it claims to.
    checks++;
    if (n_illegal < (1 << (CLEN - 2))) begin
      errors++;
      $display("  FAIL fewer illegal than non-compressed parcels: %0d", n_illegal);
    end

    // --- assembler vectors ----------------------------------------------------
    foreach (VECS[k]) begin
      c = VECS[k].c;
      #1;
      check1 ($sformatf("asm[%0d] %04h legal", k, c), illegal, 1'b0);
      check32($sformatf("asm[%0d] %04h", k, c), instr, VECS[k].e);
    end

    // --- reserved and hint encodings, by name --------------------------------
    foreach (RESERVED[k]) begin
      c = RESERVED[k];
      #1;
      check1($sformatf("reserved %04h is illegal", c), illegal, 1'b1);
    end
    foreach (HINTS[k]) begin
      c = HINTS[k];
      #1;
      check1($sformatf("hint %04h is legal", c), illegal, 1'b0);
    end

    // ---------------------------------------------------------------------------
    if (errors == 0) begin
      $display("=== PASS : %0d checks ===", checks);
      $finish;
    end else begin
      $display("=== FAIL : %0d errors of %0d checks ===", errors, checks);
      $fatal(1, "tb_s1_rvc_expand failed");
    end
  end

endmodule
