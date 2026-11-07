// Copyright 2026 Maktab-e-Digital Systems Lahore.
// SPDX-License-Identifier: Apache-2.0
//
// The smallest complete MEDS-S1 program.  If this runs, the toolchain, linker
// script, crt0, UART driver and newlib syscall stubs are all working.
//
//   make run BOARD=verilator PROG=hello
#include <stdio.h>
#include "s1_perf.h"

int main(void)
{
    printf("Hello from MEDS-S1\n");

    s1_perf_region_t r;
    s1_perf_config(0, EV_ICACHE_MISS);
    PERF_BEGIN(&r);

    volatile unsigned long acc = 0;
    for (unsigned long i = 0; i < 10000; i++) acc += i;

    PERF_END(&r);
    s1_perf_report(&r, "sum-10k");

    printf("acc = %lu\n", acc);
    return 0;
}
