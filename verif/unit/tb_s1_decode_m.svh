// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// tb_s1_decode_m : RV64M decode tests
//
// The 13 multiply/divide instructions, and the word forms that do not exist.
//
// Included by verif/unit/tb_s1_decode.sv inside the testbench module; it uses
// that module's DUT outputs, encoders and scoreboard tasks.
// =============================================================================

  task automatic test_rv64m();
    // ==========================================================================
    // RVM: 13 instructions (8 base + 5 RV64-only *w forms; mulhw/
    // mulhsuw/mulhuw do not exist).
    // ==========================================================================

    cur_test = "mul"; named("mul");
    instr = enc_r(7'b0000001, 5'd3, 5'd2, 3'b000, 5'd1, OP_OP); #1;
    expect_common(UNIT_MUL, 1'b0, 1'b1, 1'b1, 1'b1);
    check_field("muldiv_op", dec_mxif_on.muldiv_op, MULDIV_MUL);

    cur_test = "mulh"; named("mulh");
    instr = enc_r(7'b0000001, 5'd3, 5'd2, 3'b001, 5'd1, OP_OP); #1;
    check_field("muldiv_op", dec_mxif_on.muldiv_op, MULDIV_MULH);
    check_field("unit", dec_mxif_on.unit, UNIT_MUL);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "mulhsu"; named("mulhsu");
    instr = enc_r(7'b0000001, 5'd3, 5'd2, 3'b010, 5'd1, OP_OP); #1;
    check_field("muldiv_op", dec_mxif_on.muldiv_op, MULDIV_MULHSU);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "mulhu"; named("mulhu");
    instr = enc_r(7'b0000001, 5'd3, 5'd2, 3'b011, 5'd1, OP_OP); #1;
    check_field("muldiv_op", dec_mxif_on.muldiv_op, MULDIV_MULHU);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "div"; named("div");
    instr = enc_r(7'b0000001, 5'd3, 5'd2, 3'b100, 5'd1, OP_OP); #1;
    expect_common(UNIT_DIV, 1'b0, 1'b1, 1'b1, 1'b1);
    check_field("muldiv_op", dec_mxif_on.muldiv_op, MULDIV_DIV);

    cur_test = "divu"; named("divu");
    instr = enc_r(7'b0000001, 5'd3, 5'd2, 3'b101, 5'd1, OP_OP); #1;
    check_field("muldiv_op", dec_mxif_on.muldiv_op, MULDIV_DIVU);
    check_field("unit", dec_mxif_on.unit, UNIT_DIV);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "rem"; named("rem");
    instr = enc_r(7'b0000001, 5'd3, 5'd2, 3'b110, 5'd1, OP_OP); #1;
    check_field("muldiv_op", dec_mxif_on.muldiv_op, MULDIV_REM);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "remu"; named("remu");
    instr = enc_r(7'b0000001, 5'd3, 5'd2, 3'b111, 5'd1, OP_OP); #1;
    check_field("muldiv_op", dec_mxif_on.muldiv_op, MULDIV_REMU);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "mulw"; named("mulw");   // RV64M, op=59 decimal == 0111011 == OP_OP_32
    instr = enc_r(7'b0000001, 5'd3, 5'd2, 3'b000, 5'd1, OP_OP_32); #1;
    check_field("muldiv_op", dec_mxif_on.muldiv_op, MULDIV_MULW);
    check_field("unit", dec_mxif_on.unit, UNIT_MUL);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "divw"; named("divw");
    instr = enc_r(7'b0000001, 5'd3, 5'd2, 3'b100, 5'd1, OP_OP_32); #1;
    check_field("muldiv_op", dec_mxif_on.muldiv_op, MULDIV_DIVW);
    check_field("unit", dec_mxif_on.unit, UNIT_DIV);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "divuw"; named("divuw");
    instr = enc_r(7'b0000001, 5'd3, 5'd2, 3'b101, 5'd1, OP_OP_32); #1;
    check_field("muldiv_op", dec_mxif_on.muldiv_op, MULDIV_DIVUW);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "remw"; named("remw");
    instr = enc_r(7'b0000001, 5'd3, 5'd2, 3'b110, 5'd1, OP_OP_32); #1;
    check_field("muldiv_op", dec_mxif_on.muldiv_op, MULDIV_REMW);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "remuw"; named("remuw");
    instr = enc_r(7'b0000001, 5'd3, 5'd2, 3'b111, 5'd1, OP_OP_32); #1;
    check_field("muldiv_op", dec_mxif_on.muldiv_op, MULDIV_REMUW);
    check_field("illegal", dec_mxif_on.illegal, 1'b0);

    cur_test = "OP32/RVM-reserved-mulhw"; // no mulh/mulhsu/mulhu word forms
    instr = enc_r(7'b0000001, 5'd3, 5'd2, 3'b001, 5'd1, OP_OP_32); #1;
    expect_unrecognised();
    check_field("muldiv_op", dec_mxif_on.muldiv_op, MULDIV_NONE);

    cur_test = "OP32/RVM-reserved-mulhsuw";
    instr = enc_r(7'b0000001, 5'd3, 5'd2, 3'b010, 5'd1, OP_OP_32); #1;
    expect_unrecognised();

    cur_test = "OP32/RVM-reserved-mulhuw";
    instr = enc_r(7'b0000001, 5'd3, 5'd2, 3'b011, 5'd1, OP_OP_32); #1;
    expect_unrecognised();
  endtask
