// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// tb_dcache_load_miss_evict : a load miss while both ways of the set are full
// Run through verif/unit/tb_s1_dcache_basic.sv:  make test-unit TB=s1_dcache_basic

module tb_dcache_load_miss_evict
  import s1_dcache_pkg::*;
(
  output logic        done,
  output int unsigned checks,
  output int unsigned errors
);

  `include "verif/unit/s1_dcache_basic/dcache_tb_common.svh"

  // A, B and C have different tags but fall in the same set.
  task automatic fill_a_then_b(input int unsigned set);
    load_check("setup A", addr_of(1, set, 0), MISS);
    load_check("setup B", addr_of(2, set, 0), MISS);
  endtask

  initial begin
    done   = 1'b0;
    checks = 0;
    errors = 0;
    reset();

    // Case 1: B was used last, so A is the least recently used line.
    fill_a_then_b(5);
    load_check("miss C (must evict A)", addr_of(3, 5, 0), MISS);
    load_check("B survived",  addr_of(2, 5, 0), HIT);
    load_check("C is cached", addr_of(3, 5, 0), HIT);
    load_check("A was evicted", addr_of(1, 5, 0), MISS);

    // Case 2: A is touched after B, so now B is the least recently used line.
    fill_a_then_b(9);
    load_check("touch A", addr_of(1, 9, 0), HIT);
    load_check("miss C (must evict B)", addr_of(3, 9, 0), MISS);
    load_check("A survived",  addr_of(1, 9, 0), HIT);
    load_check("C is cached", addr_of(3, 9, 0), HIT);
    load_check("B was evicted", addr_of(2, 9, 0), MISS);

    done = 1'b1;
  end

endmodule
