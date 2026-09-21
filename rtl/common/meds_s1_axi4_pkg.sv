// SPDX-License-Identifier: Apache-2.0
// Copyright (c) Maktab-e-Digital Systems Lahore
//
// meds_s1_axi4_pkg -- the ONE package for the MEDS-S1 bus fabric (SPEC sec18,
// sec24, sec26, Appendix B). Every fabric module imports this and nothing
// else, so widths and the memory map have a single source of truth.
//
// NOTE: in the real flow this file is generated from soc.yaml by
// meds_s1_gen (SPEC sec26). It is hand-written until the generator exists;
// keep it in sync with Appendix B by hand until then.

package meds_s1_axi4_pkg;

  // ---------------------------------------------------------------------------
  // Backbone (SPEC sec18.2): AXI4, 256-bit data, 40-bit address, 6-bit ID
  // ---------------------------------------------------------------------------
  parameter int unsigned AXI_ADDR_W = 40;
  parameter int unsigned AXI_DATA_W = 256;
  parameter int unsigned AXI_STRB_W = AXI_DATA_W / 8;
  parameter int unsigned AXI_ID_W   = 6;

  // Narrow masters (I$, D$, Debug DM) are 64-bit and go through an upsizer.
  parameter int unsigned NARROW_DATA_W = 64;
  parameter int unsigned NARROW_STRB_W = NARROW_DATA_W / 8;

  // Crossbar masters (SPEC Figure 10)
  parameter int unsigned NUM_MASTERS = 6;
  parameter int unsigned MIDX_W      = 3;
  parameter int unsigned MST_ICACHE  = 0;
  parameter int unsigned MST_DCACHE  = 1;
  parameter int unsigned MST_MXIF    = 2;
  parameter int unsigned MST_SOCKET0 = 3;
  parameter int unsigned MST_SOCKET1 = 4;
  parameter int unsigned MST_DEBUG   = 5;

  // Crossbar slaves (SPEC Figure 10). Index NUM_SLAVES is the internal
  // DECERR sink that answers any address outside the map.
  parameter int unsigned NUM_SLAVES   = 6;
  parameter int unsigned SIDX_W       = 3;
  parameter int unsigned SLV_BOOTROM  = 0;
  parameter int unsigned SLV_SRAM     = 1;
  parameter int unsigned SLV_DRAM     = 2;
  parameter int unsigned SLV_SOCKET0  = 3;
  parameter int unsigned SLV_SOCKET1  = 4;
  parameter int unsigned SLV_PERIPH   = 5;
  parameter int unsigned SLV_DECERR   = NUM_SLAVES;

  // At a slave port the crossbar prepends the master index to the ID.
  parameter int unsigned AXI_SID_W = AXI_ID_W + MIDX_W;

  // Outstanding transactions a master may have in flight per direction.
  parameter int unsigned MAX_OUTSTANDING = 4;
  parameter int unsigned OUT_CNT_W       = 3;

  // ---------------------------------------------------------------------------
  // AXI4-Lite peripheral subtree (SPEC sec18.2): 32-bit data, 40-bit address
  // ---------------------------------------------------------------------------
  parameter int unsigned AXIL_ADDR_W = 40;
  parameter int unsigned AXIL_DATA_W = 32;
  parameter int unsigned AXIL_STRB_W = AXIL_DATA_W / 8;
  // Local offset width used by a single 64 KB slave window (socket cfg).
  parameter int unsigned AXIL_LOCAL_ADDR_W = 16;

  // ---------------------------------------------------------------------------
  // AXI encodings
  // ---------------------------------------------------------------------------
  parameter logic [1:0] RESP_OKAY   = 2'b00;
  parameter logic [1:0] RESP_EXOKAY = 2'b01;
  parameter logic [1:0] RESP_SLVERR = 2'b10; // slave exists, access refused
  parameter logic [1:0] RESP_DECERR = 2'b11; // nothing at this address

  parameter logic [1:0] BURST_FIXED = 2'b00;
  parameter logic [1:0] BURST_INCR  = 2'b01;
  parameter logic [1:0] BURST_WRAP  = 2'b10;

  // ---------------------------------------------------------------------------
  // Memory map (SPEC Appendix B)
  // ---------------------------------------------------------------------------
  parameter logic [AXI_ADDR_W-1:0] DEBUG_ROM_BASE = 40'h00_0000_0000, DEBUG_ROM_SIZE = 40'h00_0000_1000; //   4 KB
  parameter logic [AXI_ADDR_W-1:0] BOOT_ROM_BASE  = 40'h00_0000_1000, BOOT_ROM_SIZE  = 40'h00_0000_8000; //  32 KB
  parameter logic [AXI_ADDR_W-1:0] CLINT_BASE     = 40'h00_0200_0000, CLINT_SIZE     = 40'h00_0001_0000; //  64 KB
  parameter logic [AXI_ADDR_W-1:0] PLIC_BASE      = 40'h00_0C00_0000, PLIC_SIZE      = 40'h00_0040_0000; //   4 MB
  parameter logic [AXI_ADDR_W-1:0] PERIPH_BASE    = 40'h00_1000_0000, PERIPH_SIZE    = 40'h00_1000_0000; // 256 MB
  parameter logic [AXI_ADDR_W-1:0] UART0_BASE     = 40'h00_1000_0000, UART0_SIZE     = 40'h00_0000_1000; //   4 KB
  parameter logic [AXI_ADDR_W-1:0] SPI0_BASE      = 40'h00_1000_1000, SPI0_SIZE      = 40'h00_0000_1000; //   4 KB
  parameter logic [AXI_ADDR_W-1:0] GPIO0_BASE     = 40'h00_1000_2000, GPIO0_SIZE     = 40'h00_0000_1000; //   4 KB
  parameter logic [AXI_ADDR_W-1:0] TIMER0_BASE    = 40'h00_1000_3000, TIMER0_SIZE    = 40'h00_0000_1000; //   4 KB
  parameter logic [AXI_ADDR_W-1:0] SOCKET0_BASE   = 40'h00_2000_0000, SOCKET0_SIZE   = 40'h00_0001_0000; //  64 KB
  parameter logic [AXI_ADDR_W-1:0] SOCKET1_BASE   = 40'h00_2001_0000, SOCKET1_SIZE   = 40'h00_0001_0000; //  64 KB
  parameter logic [AXI_ADDR_W-1:0] SRAM_BASE      = 40'h00_4000_0000, SRAM_SIZE      = 40'h00_0004_0000; // 256 KB
  parameter logic [AXI_ADDR_W-1:0] DRAM_BASE      = 40'h00_8000_0000, DRAM_SIZE      = 40'h00_4000_0000; //   1 GB
  parameter logic [AXI_ADDR_W-1:0] DRAM_UC_BASE   = 40'h01_0000_0000, DRAM_UC_SIZE   = 40'h00_4000_0000; //   1 GB alias

  // Peripheral ports behind the AXI4-Lite bridge (crossbar slave SLV_PERIPH).
  // The Debug Module's ROM/scratch window (0x0, 4 KB) is on this subtree so
  // the core can fetch the debug ROM (SPEC sec13, Appendix B).
  parameter int unsigned NUM_PERIPH   = 7;
  parameter int unsigned PIDX_W       = 3;
  parameter int unsigned PER_DEBUG    = 0;
  parameter int unsigned PER_CLINT    = 1;
  parameter int unsigned PER_PLIC     = 2;
  parameter int unsigned PER_UART0    = 3;
  parameter int unsigned PER_SPI0     = 4;
  parameter int unsigned PER_GPIO0    = 5;
  parameter int unsigned PER_TIMER0   = 6;

  function automatic logic in_region(input logic [AXI_ADDR_W-1:0] a,
                                     input logic [AXI_ADDR_W-1:0] base,
                                     input logic [AXI_ADDR_W-1:0] size);
    return (a >= base) && (a < base + size);
  endfunction

  // Crossbar decode. Returns SLV_DECERR for an address outside the map.
  function automatic logic [SIDX_W-1:0] xbar_decode(input logic [AXI_ADDR_W-1:0] a);
    if      (in_region(a, BOOT_ROM_BASE,  BOOT_ROM_SIZE))  return SIDX_W'(SLV_BOOTROM);
    else if (in_region(a, SRAM_BASE,      SRAM_SIZE))      return SIDX_W'(SLV_SRAM);
    else if (in_region(a, DRAM_BASE,      DRAM_SIZE))      return SIDX_W'(SLV_DRAM);
    else if (in_region(a, DRAM_UC_BASE,   DRAM_UC_SIZE))   return SIDX_W'(SLV_DRAM);
    else if (in_region(a, SOCKET0_BASE,   SOCKET0_SIZE))   return SIDX_W'(SLV_SOCKET0);
    else if (in_region(a, SOCKET1_BASE,   SOCKET1_SIZE))   return SIDX_W'(SLV_SOCKET1);
    else if (in_region(a, DEBUG_ROM_BASE, DEBUG_ROM_SIZE)) return SIDX_W'(SLV_PERIPH);
    else if (in_region(a, CLINT_BASE,     CLINT_SIZE))     return SIDX_W'(SLV_PERIPH);
    else if (in_region(a, PLIC_BASE,      PLIC_SIZE))      return SIDX_W'(SLV_PERIPH);
    else if (in_region(a, PERIPH_BASE,    PERIPH_SIZE))    return SIDX_W'(SLV_PERIPH);
    else                                                   return SIDX_W'(SLV_DECERR);
  endfunction

  // Peripheral decode inside the AXI4-Lite subtree. hit=0 -> DECERR.
  function automatic logic [PIDX_W:0] periph_decode(input logic [AXI_ADDR_W-1:0] a);
    if      (in_region(a, DEBUG_ROM_BASE, DEBUG_ROM_SIZE)) return {1'b1, PIDX_W'(PER_DEBUG)};
    else if (in_region(a, CLINT_BASE,     CLINT_SIZE))     return {1'b1, PIDX_W'(PER_CLINT)};
    else if (in_region(a, PLIC_BASE,      PLIC_SIZE))      return {1'b1, PIDX_W'(PER_PLIC)};
    else if (in_region(a, UART0_BASE,     UART0_SIZE))     return {1'b1, PIDX_W'(PER_UART0)};
    else if (in_region(a, SPI0_BASE,      SPI0_SIZE))      return {1'b1, PIDX_W'(PER_SPI0)};
    else if (in_region(a, GPIO0_BASE,     GPIO0_SIZE))     return {1'b1, PIDX_W'(PER_GPIO0)};
    else if (in_region(a, TIMER0_BASE,    TIMER0_SIZE))    return {1'b1, PIDX_W'(PER_TIMER0)};
    else                                                   return '0;
  endfunction

  // ---------------------------------------------------------------------------
  // PMA attributes per region (SPEC sec11, Appendix B). Enforced by the core's
  // PMA checker (and the copy on the coprocessor port); kept here so the
  // checker and the fabric read the same table.
  // ---------------------------------------------------------------------------
  typedef struct packed {
    logic valid;        // address is mapped
    logic cacheable;
    logic icache_only;  // Boot ROM: cacheable for instruction fetch only
    logic idempotent;
    logic strong_order; // order: strong (P2)
    logic amo;
    logic lrsc;
    logic misaligned_ok;
  } pma_t;

  function automatic pma_t pma_lookup(input logic [AXI_ADDR_W-1:0] a);
    //                                  vld  c  i  idem strong amo lrsc mis
    if (in_region(a, DEBUG_ROM_BASE, DEBUG_ROM_SIZE)) return '{1, 0, 0, 1, 0, 0, 0, 0};
    if (in_region(a, BOOT_ROM_BASE,  BOOT_ROM_SIZE))  return '{1, 1, 1, 1, 0, 0, 0, 0};
    if (in_region(a, CLINT_BASE,     CLINT_SIZE))     return '{1, 0, 0, 0, 1, 0, 0, 0};
    if (in_region(a, PLIC_BASE,      PLIC_SIZE))      return '{1, 0, 0, 0, 1, 0, 0, 0};
    if (in_region(a, PERIPH_BASE,    PERIPH_SIZE))    return '{1, 0, 0, 0, 1, 0, 0, 0};
    if (in_region(a, SOCKET0_BASE,   SOCKET0_SIZE))   return '{1, 0, 0, 0, 1, 0, 0, 0};
    if (in_region(a, SOCKET1_BASE,   SOCKET1_SIZE))   return '{1, 0, 0, 0, 1, 0, 0, 0};
    if (in_region(a, SRAM_BASE,      SRAM_SIZE))      return '{1, 1, 0, 1, 0, 1, 1, 1};
    if (in_region(a, DRAM_BASE,      DRAM_SIZE))      return '{1, 1, 0, 1, 0, 1, 1, 1};
    if (in_region(a, DRAM_UC_BASE,   DRAM_UC_SIZE))   return '{1, 0, 0, 1, 1, 1, 0, 0};
    return '0;
  endfunction

  // ---------------------------------------------------------------------------
  // Mandatory accelerator cfg register map (SPEC sec20.2, normative). Every
  // accelerator implements these in its own cfg slave; the constants live
  // here for drivers/BSP and the socket conformance testbench (sec28.3).
  // ---------------------------------------------------------------------------
  parameter logic [15:0] ACC_REG_ID          = 16'h0000; // RO
  parameter logic [15:0] ACC_REG_VERSION     = 16'h0004; // RO {major[15:0], minor[15:0]}
  parameter logic [15:0] ACC_REG_CTRL        = 16'h0008; // RW [0]start [1]abort [2]irq_en
  parameter logic [15:0] ACC_REG_STATUS      = 16'h000C; // RO [0]busy [1]done [2]error [7:4]errcode
  parameter logic [15:0] ACC_REG_IRQ_STATUS  = 16'h0010; // W1C
  parameter logic [15:0] ACC_REG_CAPABILITY  = 16'h0014; // RO
  parameter logic [15:0] ACC_REG_PERF_CYCLES = 16'h0018; // RO
  parameter logic [15:0] ACC_REG_PERF_STALLS = 16'h001C; // RO
  parameter logic [15:0] ACC_REG_CUSTOM_BASE = 16'h0020; // accelerator-specific

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------
  // Address of the next beat of a burst (AXI4 spec A3.4.1).
  function automatic logic [AXI_ADDR_W-1:0] axi_next_addr(input logic [AXI_ADDR_W-1:0] addr,
                                                          input logic [2:0] size,
                                                          input logic [7:0] len,
                                                          input logic [1:0] burst);
    logic [AXI_ADDR_W-1:0] step, aligned, wrap_bytes, wrap_base, nxt;
    step       = AXI_ADDR_W'(1) << size;
    aligned    = addr & ~(step - 1);
    wrap_bytes = step * (AXI_ADDR_W'(len) + 1);
    wrap_base  = addr & ~(wrap_bytes - 1);
    nxt        = aligned + step;
    if (burst == BURST_FIXED) return addr;
    if (burst == BURST_WRAP && nxt == wrap_base + wrap_bytes) return wrap_base;
    return nxt;
  endfunction

  // Worst of two responses (DECERR > SLVERR > OKAY).
  function automatic logic [1:0] resp_merge(input logic [1:0] a, input logic [1:0] b);
    return (a > b) ? a : b;
  endfunction

endpackage : meds_s1_axi4_pkg
