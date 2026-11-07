// Copyright 2026 Maktab-e-Digital Systems Lahore.
// SPDX-License-Identifier: Apache-2.0
//
// libs1_perf -- the performance measurement library.
//
// If measurement is not trivially easy, nobody does it, and every result in the
// lab becomes incomparable.  This header is the whole user-facing API.
//
// Owner project: M-09.  Spec: SPEC section 12.1 and section 34.
#ifndef S1_PERF_H
#define S1_PERF_H

#include <stdint.h>

// Hardware event selectors for mhpmevent3..15 (SPEC section 12).
typedef enum {
    EV_NONE = 0,
    EV_ICACHE_MISS, EV_ICACHE_STALL_CYCLES, EV_BRANCH_TAKEN,
    EV_BRANCH_MISPREDICT, EV_FETCH_STALL,
    EV_LOAD_USE_STALL, EV_CSR_SERIALISE_STALL, EV_CB_FULL_STALL, EV_DIV_BUSY_CYCLES,
    EV_DCACHE_MISS, EV_DCACHE_WRITEBACK, EV_STORE_BUFFER_FULL,
    EV_DTLB_MISS, EV_ITLB_MISS,
    // The two groups that make accelerator research possible: they are what let
    // a student distinguish "my accelerator is slow" from "the core cannot feed
    // it" from "the bus is contended".  SPEC section 12 attribution table.
    EV_MXIF_OFFLOAD_COUNT, EV_MXIF_ISSUE_STALL_CYCLES,
    EV_MXIF_BUSY_CYCLES, EV_MXIF_WB_STALL_CYCLES,
    EV_AXI_READ_BEATS, EV_AXI_WRITE_BEATS,
    EV_AXI_READ_LATENCY_SUM, EV_AXI_ARB_STALL_CYCLES,
    EV_EXCEPTION_TAKEN, EV_INTERRUPT_TAKEN,
    EV_MAX
} s1_perf_event_t;

#define S1_PERF_NCTR 13          // mhpmcounter3..15

typedef struct {
    uint64_t cycles;
    uint64_t instret;
    uint64_t ctr[S1_PERF_NCTR];
} s1_perf_region_t;

// Bind a hardware counter to an event.  idx is 0..S1_PERF_NCTR-1.
void s1_perf_config(unsigned idx, s1_perf_event_t ev);

void s1_perf_begin(s1_perf_region_t *r);
void s1_perf_end(s1_perf_region_t *r);      // leaves deltas in *r

// Print in the SPEC section 34 reporting format, so results from different
// students in different years are comparable.
void s1_perf_report(const s1_perf_region_t *r, const char *label);

#define PERF_BEGIN(r) s1_perf_begin(r)
#define PERF_END(r)   s1_perf_end(r)

#endif // S1_PERF_H
