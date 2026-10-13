// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// tb_dcache_load_miss_no_evict : a load miss while the set still has a free way
// Run through verif/unit/tb_s1_dcache_basic.sv:  make test-unit TB=s1_dcache_basic

module tb_dcache_load_miss_no_evict
  import s1_dcache_pkg::*;
(
  output logic        done,
  output int unsigned checks,
  output int unsigned errors
);

  `include "verif/unit/s1_dcache_basic/dcache_tb_common.svh"

  localparam int unsigned SET = 5;

  initial begin
    done   = 1'b0;
    checks = 0;
    errors = 0;
    reset();

    // Case 1: the set is empty, so the line goes into the first way.
    load_check("miss A (empty set)", addr_of(1, SET, 0), MISS);

    // Case 2: one way is still free, so the new line goes there.
    load_check("miss B (free way)", addr_of(2, SET, 0), MISS);

    // Nothing was evicted: both lines are still in the cache.
    load_check("A still cached", addr_of(1, SET, 0), HIT);
    load_check("B still cached", addr_of(2, SET, 0), HIT);

    // A miss on a word in the middle of a line still fetches the whole line.
    load_check("miss on word 5", addr_of(1, SET + 1, 5), MISS);
    load_check("word 0 came too", addr_of(1, SET + 1, 0), HIT);

    // The first load of every other set is a miss into an empty set.
    for (int unsigned s = SET + 2; s < SET + 6; s++) begin
      load_check($sformatf("miss in set %0d", s), addr_of(1, s, 0), MISS);
    end

    done = 1'b1;
  end

endmodule
