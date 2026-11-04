// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// tb_s1_decode_a : RV64A decode tests
//
// LR/SC and the nine AMOs, with the reserved funct5 and width encodings.
//
// Included by verif/unit/tb_s1_decode.sv inside the testbench module; it uses
// that module's DUT outputs, encoders and scoreboard tasks.
// =============================================================================

  task automatic test_rv64a();
    // ==========================================================================
    // RV64A -- atomics
    // ==========================================================================

    cur_test = "lr.d"; named("lr.d");
    instr = enc_amo(5'b00010, 1'b0, 1'b0, 5'd0, 5'd10, 3'b011, 5'd11); #1;
    expect_common(UNIT_LSU, 1'b0, 1'b1, 1'b1, 1'b0);   // LR reads no rs2
    check_field("amo_op", dec_mxif_on.amo_op, AMO_LR);
    check_field("mem_size", dec_mxif_on.mem_size, LS_DOUBLE);

    cur_test = "LR.D/reserved-rs2-nonzero";
    // RVA (riscv-opcodes rv_a::lr.w: "rd rs1 24..20=0 aq rl ...") requires
    // rs2=0 for LR; rs2!=0 is a reserved encoding, not an ordinary LR.
    instr = enc_amo(5'b00010, 1'b0, 1'b0, 5'd3, 5'd10, 3'b011, 5'd11); #1;
    expect_unrecognised();

    cur_test = "sc.w.aqrl"; named("sc.w");
    instr = enc_amo(5'b00011, 1'b1, 1'b1, 5'd12, 5'd10, 3'b010, 5'd11); #1;
    expect_common(UNIT_LSU, 1'b0, 1'b1, 1'b1, 1'b1);   // SC reads rs2 (value to write)
    check_field("amo_op", dec_mxif_on.amo_op, AMO_SC);
    check_field("aq", dec_mxif_on.aq, 1'b1);
    check_field("rl", dec_mxif_on.rl, 1'b1);
    check_field("mem_size", dec_mxif_on.mem_size, LS_WORD);

    cur_test = "amoswap.d"; named("amoswap.d");
    instr = enc_amo(5'b00001, 1'b0, 1'b0, 5'd12, 5'd10, 3'b011, 5'd11); #1;
    check_field("amo_op", dec_mxif_on.amo_op, AMO_SWAP);
    check_field("rs2_re", dec_mxif_on.rs2_re, 1'b1);

    cur_test = "amoadd.d"; named("amoadd.d");
    instr = enc_amo(5'b00000, 1'b0, 1'b0, 5'd12, 5'd10, 3'b011, 5'd11); #1;
    check_field("amo_op", dec_mxif_on.amo_op, AMO_ADD);

    cur_test = "amoxor.d"; named("amoxor.d");
    instr = enc_amo(5'b00100, 1'b0, 1'b0, 5'd12, 5'd10, 3'b011, 5'd11); #1;
    check_field("amo_op", dec_mxif_on.amo_op, AMO_XOR);

    cur_test = "amoand.d"; named("amoand.d");
    instr = enc_amo(5'b01100, 1'b0, 1'b0, 5'd12, 5'd10, 3'b011, 5'd11); #1;
    check_field("amo_op", dec_mxif_on.amo_op, AMO_AND);

    cur_test = "amoor.d"; named("amoor.d");
    instr = enc_amo(5'b01000, 1'b0, 1'b0, 5'd12, 5'd10, 3'b011, 5'd11); #1;
    check_field("amo_op", dec_mxif_on.amo_op, AMO_OR);

    cur_test = "amomin.d"; named("amomin.d");
    instr = enc_amo(5'b10000, 1'b0, 1'b0, 5'd12, 5'd10, 3'b011, 5'd11); #1;
    check_field("amo_op", dec_mxif_on.amo_op, AMO_MIN);

    cur_test = "amomax.d"; named("amomax.d");
    instr = enc_amo(5'b10100, 1'b0, 1'b0, 5'd12, 5'd10, 3'b011, 5'd11); #1;
    check_field("amo_op", dec_mxif_on.amo_op, AMO_MAX);

    cur_test = "amominu.w"; named("amominu.w");
    instr = enc_amo(5'b11000, 1'b0, 1'b0, 5'd12, 5'd10, 3'b010, 5'd11); #1;
    check_field("amo_op", dec_mxif_on.amo_op, AMO_MINU);
    check_field("mem_size", dec_mxif_on.mem_size, LS_WORD);

    cur_test = "amomaxu.w"; named("amomaxu.w");
    instr = enc_amo(5'b11100, 1'b0, 1'b0, 5'd12, 5'd10, 3'b010, 5'd11); #1;
    check_field("amo_op", dec_mxif_on.amo_op, AMO_MAXU);

    cur_test = "AMO/reserved-f5";
    instr = enc_amo(5'b01111, 1'b0, 1'b0, 5'd12, 5'd10, 3'b010, 5'd11); #1;
    expect_unrecognised();

    cur_test = "AMO/reserved-funct3-byte-width";
    instr = enc_amo(5'b00000, 1'b0, 1'b0, 5'd12, 5'd10, 3'b000, 5'd11); #1;
    expect_unrecognised();
  endtask
