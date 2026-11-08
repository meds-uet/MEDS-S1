// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// btfn_golden.svh : reference model of static BTFN prediction    [COMPLETE]
// Description  :
// Testbench-only, `include inside a module.
// =============================================================================

// BTFN on an expanded instruction: {taken, offset}.  JAL always taken, JALR never.
function automatic logic [64:0] btfn_golden(input logic [31:0] i);
  longint off;
  if (i[6:0] == 7'h63) begin
    off = longint'($signed({i[31], i[7], i[30:25], i[11:8], 1'b0}));
    return {off < 0, off};
  end
  if (i[6:0] == 7'h6F) begin
    off = longint'($signed({i[31], i[19:12], i[20], i[30:21], 1'b0}));
    return {1'b1, off};
  end
  return {1'b0, 64'h0};
endfunction
