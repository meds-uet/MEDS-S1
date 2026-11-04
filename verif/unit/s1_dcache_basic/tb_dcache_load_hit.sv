// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// tb_dcache_load_hit : a load of a line that is already in the cache
// Run through verif/unit/tb_s1_dcache_basic.sv:  make test-unit TB=s1_dcache_basic

module tb_dcache_load_hit
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

    // Setup: bring line A into the cache.  This first load is a miss.
    load_check("setup A", addr_of(1, SET, 0), MISS);

    // The same word again is a hit.
    load_check("hit A", addr_of(1, SET, 0), HIT);

    // Every other word of the line is a hit too, and each returns its own data.
    for (int unsigned w = 1; w < WORDS; w++) begin
      load_check($sformatf("hit A word %0d", w), addr_of(1, SET, w), HIT);
    end

    // Hits can repeat any number of times without touching memory.
    repeat (4) load_check("hit A repeated", addr_of(1, SET, 3), HIT);

    // A line in the second way hits as well.
    load_check("setup B", addr_of(2, SET, 0), MISS);
    load_check("hit B",   addr_of(2, SET, 0), HIT);
    load_check("hit A after B", addr_of(1, SET, 0), HIT);

    done = 1'b1;
  end

endmodule
