// Copyright 2026 Maktab-e-Digital Systems Lahore.
// SPDX-License-Identifier: Apache-2.0
//
// Generic accelerator driver API.
//
// Every accelerator's MMIO window begins with the same eight registers
// (SPEC section 20.2), which is what lets this file enumerate and drive any of
// them without accelerator-specific code.
//
// Owner project: R-07.  Copy sw/drivers/template/ for a new accelerator.
#ifndef S1_ACCEL_H
#define S1_ACCEL_H

#include <stdint.h>
#include <stddef.h>

// Mandatory register map -- byte offsets from the accelerator's base address.
#define ACCEL_REG_ID          0x00   // RO  allocated in extensions/REGISTRY.md
#define ACCEL_REG_VERSION     0x04   // RO  {major[15:0], minor[15:0]}
#define ACCEL_REG_CTRL        0x08   // RW  [0] start [1] abort [2] irq_en
#define ACCEL_REG_STATUS      0x0C   // RO  [0] busy [1] done [2] error [7:4] errcode
#define ACCEL_REG_IRQ_STATUS  0x10   // W1C
#define ACCEL_REG_CAPABILITY  0x14   // RO
#define ACCEL_REG_PERF_CYCLES 0x18   // RO  accelerator-local busy cycles
#define ACCEL_REG_PERF_STALLS 0x1C   // RO  accelerator-local memory stalls

#define ACCEL_CTRL_START      (1u << 0)
#define ACCEL_CTRL_ABORT      (1u << 1)
#define ACCEL_CTRL_IRQ_EN     (1u << 2)
#define ACCEL_STATUS_BUSY     (1u << 0)
#define ACCEL_STATUS_DONE     (1u << 1)
#define ACCEL_STATUS_ERROR    (1u << 2)

typedef struct { volatile uint32_t *base; uint32_t id; uint32_t version; int irq; } accel_t;

// Walk the sockets declared in the generated header and return the first
// accelerator reporting this ID, or NULL.
accel_t *accel_open(uint32_t id);

void     accel_start(accel_t *a);
int      accel_wait_irq(accel_t *a);        // WFI until the PLIC fires
uint32_t accel_status(accel_t *a);
void     accel_abort(accel_t *a);

// Cache maintenance for DMA buffers.  Zicbom when available, otherwise the
// caller must place the buffer in the uncached DRAM alias.
//
// These two calls are the ones students forget; the symptom is stale data that
// looks like an accelerator bug (SPEC section 20.3, steps 2 and 10).
void accel_cache_clean(const void *addr, size_t len);       // CPU wrote  -> device reads
void accel_cache_invalidate(void *addr, size_t len);        // device wrote -> CPU reads

#endif // S1_ACCEL_H
