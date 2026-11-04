// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// tb_s1_dcache_basic : runs the data-cache load tests            [WIP -- R-03]
//
// The three tests live in verif/unit/s1_dcache_basic/, one file each.  Each
// test has its own cache, so they do not depend on each other.  This file only
// starts them and adds up their results.
//
// Run:  make test-unit TB=s1_dcache_basic
// The include paths start at the top of the repository, which is where make runs.
// =============================================================================

`include "verif/unit/s1_dcache_basic/tb_dcache_load_hit.sv"
`include "verif/unit/s1_dcache_basic/tb_dcache_load_miss_no_evict.sv"
`include "verif/unit/s1_dcache_basic/tb_dcache_load_miss_evict.sv"

module tb_s1_dcache_basic;

  logic        done_hit,   done_no_evict,   done_evict;
  int unsigned checks_hit, checks_no_evict, checks_evict;
  int unsigned errors_hit, errors_no_evict, errors_evict;

  tb_dcache_load_hit           u_hit      (.done(done_hit),      .checks(checks_hit),      .errors(errors_hit));
  tb_dcache_load_miss_no_evict u_no_evict (.done(done_no_evict), .checks(checks_no_evict), .errors(errors_no_evict));
  tb_dcache_load_miss_evict    u_evict    (.done(done_evict),    .checks(checks_evict),    .errors(errors_evict));

  task automatic report(input string name, input int unsigned checks, input int unsigned errors);
    $display("  %-28s %s  (%0d checks, %0d errors)", name, (errors == 0) ? "PASS" : "FAIL", checks, errors);
  endtask

  initial begin
    wait (done_hit && done_no_evict && done_evict);
    report("load hit",               checks_hit,      errors_hit);
    report("load miss, no eviction", checks_no_evict, errors_no_evict);
    report("load miss, eviction",    checks_evict,    errors_evict);

    if (errors_hit + errors_no_evict + errors_evict == 0) begin
      $display("=== PASS : %0d checks ===", checks_hit + checks_no_evict + checks_evict);
      $finish;
    end else begin
      $display("=== FAIL : %0d errors of %0d checks ===",
               errors_hit + errors_no_evict + errors_evict,
               checks_hit + checks_no_evict + checks_evict);
      $fatal(1, "tb_s1_dcache_basic failed");
    end
  end

  // A cache that never answers must fail the test, not hang it.
  initial begin
    #100000;
    $display("=== FAIL : timeout, a test did not finish ===");
    $fatal(1, "tb_s1_dcache_basic timeout");
  end

endmodule
