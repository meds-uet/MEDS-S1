// Copyright 2026 Maktab-e-Digital Systems Lahore.
// Licensed under the Apache License, Version 2.0, see LICENSE file for details.
// SPDX-License-Identifier: Apache-2.0
//
// =============================================================================
// s1_dcache_pkg : sizes and signal bundles of the data cache     [WIP -- R-03]
//
// This file holds every size and every signal bundle the data cache uses.
// s1_dcache_basic.sv and s1_dcache_ctrl.sv import this package.
// =============================================================================

package s1_dcache_pkg;

  // Change only these four numbers to change the cache.
  parameter int unsigned ADDR_W     = 40;     // The address is 40 bits wide.
  parameter int unsigned DATA_W     = 64;     // One load or store is 64 bits wide.
  parameter int unsigned LINE_BYTES = 64;     // One cache line holds 64 bytes.
  parameter int unsigned SIZE_BYTES = 8192;   // The cache holds 8 KB; use 16384 for 16 KB.

  // The numbers below are worked out from the four above.
  parameter int unsigned WAYS       = 2;                               // Each set has two lines.
  parameter int unsigned LINE_W     = LINE_BYTES * 8;                  // One line is 512 bits.
  parameter int unsigned SETS       = SIZE_BYTES / (LINE_BYTES * WAYS); // 8 KB gives 64 sets.
  parameter int unsigned OFFSET_W   = $clog2(LINE_BYTES);              // The offset is 6 bits.
  parameter int unsigned INDEX_W    = $clog2(SETS);                    // The index is 6 bits at 8 KB.
  parameter int unsigned TAG_W      = ADDR_W - INDEX_W - OFFSET_W;     // The tag is the rest, 28 bits.
  parameter int unsigned TAG_SRAM_W = ((TAG_W + 7) / 8) * 8;           // The stored tag is rounded up to 32 bits.
  parameter int unsigned WORD_BYTES = DATA_W / 8;                      // One word is 8 bytes.
  parameter int unsigned WORDS      = LINE_BYTES / WORD_BYTES;         // One line holds 8 words.
  parameter int unsigned WORD_IDX_W = $clog2(WORDS);                   // 3 bits pick the word in a line.
  parameter int unsigned BYTE_IDX_W = $clog2(WORD_BYTES);              // 3 bits pick the byte in a word.

  // The LSU sends this bundle to ask for one load or one store.
  typedef struct packed {
    logic                  valid;   // The LSU has a request.
    logic [ADDR_W-1:0]     addr;    // This is the address to read or write.
    logic                  we;      // 0 means load and 1 means store.
    logic [WORD_BYTES-1:0] be;      // These bits pick the bytes a store writes.
    logic [DATA_W-1:0]     wdata;   // This is the data a store writes.
  } dcache_lsu_req_t;

  // The cache sends this bundle back to the LSU.
  typedef struct packed {
    logic                  ready;   // The cache can take a request.
    logic                  valid;   // The request is finished, for one cycle.
    logic [DATA_W-1:0]     rdata;   // This is the data a load reads.
  } dcache_lsu_rsp_t;

  // The cache sends this bundle to memory to move one whole line.
  typedef struct packed {
    logic                  valid;   // The cache has a request for memory.
    logic                  we;      // 0 means fetch a line and 1 means write a line back.
    logic [ADDR_W-1:0]     addr;    // This is the address of the line.
    logic [LINE_W-1:0]     wdata;   // This is the line to write back.
  } dcache_mem_req_t;

  // Memory sends this bundle back to the cache.
  typedef struct packed {
    logic                  ready;   // Memory can take the request.
    logic                  valid;   // The fetched line has arrived.
    logic [LINE_W-1:0]     rdata;   // This is the fetched line.
  } dcache_mem_rsp_t;

  // An address is split into these four parts.
  typedef struct packed {
    logic [TAG_W-1:0]      tag;      // The tag tells which line is stored.
    logic [INDEX_W-1:0]    index;    // The index picks the set.
    logic [WORD_IDX_W-1:0] word;     // This part picks the word inside the line.
    logic [BYTE_IDX_W-1:0] byte_idx; // This part picks the byte inside the word.
  } dcache_addr_t;

  // The cache saves the request in this bundle until it is finished.
  typedef struct packed {
    logic [TAG_W-1:0]      tag;      // This is the tag of the request.
    logic [INDEX_W-1:0]    index;    // This is the set of the request.
    logic [WORD_IDX_W-1:0] word;     // This is the word of the request.
    logic                  we;       // 0 means load and 1 means store.
    logic [WORD_BYTES-1:0] be;       // These bits pick the bytes a store writes.
    logic [DATA_W-1:0]     wdata;    // This is the data a store writes.
  } dcache_req_t;

  // A tag is stored in a word that is a whole number of bytes.
  typedef logic [TAG_SRAM_W-1:0] dcache_tag_t;

  // The controller sends these commands to the rest of the cache.
  typedef struct packed {
    logic ready;        // The cache can take a request.
    logic accept;       // Save the request and read both ways.
    logic hit_done;     // Answer the LSU because the lookup hit.
    logic miss;         // Remember which way will be replaced.
    logic writeback;    // Send the dirty line to memory.
    logic refill_req;   // Ask memory for the missing line.
    logic refill_done;  // Store the line that has arrived.
    logic reread;       // Read both ways again.
  } dcache_ctrl_t;

endpackage
