# `s1_dcache_basic`

| | |
|---|---|
| **Status** | WIP: basic data cache, grows into `s1_dcache` |
| **Owner** | Faisal Habib (FYDP Group 34) |
| **Backup** | Fahad Ali, Abdullah Rasheed Butt |
| **Project** | R-03 (caches, Zicbom and the SRAM wrapper) |
| **Spec** | SPEC §15 (caches), §17 and `specs/INTERFACES.md` §8 (SRAM wrapper) |
| **Source** | `rtl/cache/s1_dcache_basic.sv`, `rtl/cache/s1_dcache_ctrl.sv`, `rtl/cache/s1_dcache_pkg.sv` |
| **Testbench** | `verif/unit/tb_s1_dcache_basic.sv`, which runs the three load tests in `verif/unit/s1_dcache_basic/` |

## Purpose

The SPEC §15 data cache with everything optional removed. The LSU hands it one load or one store at
a time; the layout is: 2-way set-associative, 64-byte lines, 8 KB or 16 KB, blocking, write-back and
write-allocate, tag and data arrays behind `meds_s1_sram`. It is a stepping stone, not the R-03
deliverable. AXI, the uncached bypass, Zicbom / Zicboz / Zicbop, `fence.i` and error responses are
deliberately absent and arrive with `s1_icache` and `s1_dcache`.

## Interface contract

The module has six ports. The four data ports are struct bundles declared in
`rtl/cache/s1_dcache_pkg.sv`. The same file also declares three bundles used only inside the
module: `dcache_addr_t` (an address split into tag, index, word and byte), `dcache_req_t` (the
saved request) and `dcache_tag_t` (a stored tag word).

| Port | Dir | Type | Meaning |
|---|---|---|---|
| `clk_i` | in | `logic` | clock, single domain |
| `rst_ni` | in | `logic` | reset: async assert, sync de-assert; clears valid, dirty and LRU |
| `lsu_req_i` | in | `dcache_lsu_req_t` | one load or one store from the LSU |
| `lsu_rsp_o` | out | `dcache_lsu_rsp_t` | ready, done pulse and load data back to the LSU |
| `mem_req_o` | out | `dcache_mem_req_t` | one whole-line fetch or write-back to memory |
| `mem_rsp_i` | in | `dcache_mem_rsp_t` | ready and the fetched line from memory |

| Bundle | Field | Width | Contract |
|---|---|---|---|
| `dcache_lsu_req_t` | `valid` | 1 | request present; payload stable until `lsu_rsp_o.ready` |
| | `addr` | `ADDR_W` | byte address, word-aligned; the low `$clog2(DATA_W/8)` bits are ignored |
| | `we` | 1 | 0 = load, 1 = store |
| | `be` | `DATA_W/8` | byte enables, stores only; lane-based, as in MEM-REQ |
| | `wdata` | `DATA_W` | store data |
| `dcache_lsu_rsp_t` | `ready` | 1 | high only in `S_IDLE` |
| | `valid` | 1 | **one-cycle pulse, no back-pressure**, for loads and stores |
| | `rdata` | `DATA_W` | load data, valid only while `valid` |
| `dcache_mem_req_t` | `valid` | 1 | depends on state only, never on `mem_rsp_i.ready` (R-C10) |
| | `we` | 1 | 1 = write-back, 0 = refill; stable while `valid` |
| | `addr` | `ADDR_W` | line-aligned; stable while `valid` |
| | `wdata` | `LINE_W` | the dirty line; a write completes on the handshake, there is no write response |
| `dcache_mem_rsp_t` | `ready` | 1 | memory accepts the request |
| | `valid` | 1 | refill line present, one cycle, any latency after the refill handshake |
| | `rdata` | `LINE_W` | the refill line |

**Latency:** a hit answers two cycles after the request is presented. A clean miss adds the refill
handshake, the memory latency, one cycle to write the line and one to re-read the set.

**Reset state:** `S_IDLE`, every line invalid and clean.

## Parameters

The module has no parameter list. Every size, derived width and signal bundle lives in the
package in `rtl/cache/s1_dcache_pkg.sv`, which the module imports. To change the cache, edit the four numbers
at the top of the package; everything else is derived from them.

| Package parameter | Default | Legal range | Effect |
|---|---|---|---|
| `ADDR_W` | 40 | > index + offset bits | physical address width (PLEN) |
| `DATA_W` | 64 | power of two, ≥ 8 | width of one access |
| `LINE_BYTES` | 64 | power of two, ≥ `DATA_W/8` | bytes per line |
| `SIZE_BYTES` | 8192 | power of two; 8192 or 16384 in the named configs | total capacity |

The number of ways is fixed at 2, because the replacement state is then one bit per set.

| `SIZE_BYTES` | Sets | Tag | Index | Offset |
|---|---|---|---|---|
| 8192 | 64 | 28 | 6 | 6 |
| 16384 | 128 | 27 | 7 | 6 |

Because the sizes are package constants, every instance of this module has the same geometry. That
is the intended use (one data cache per core); the SoC generator (R-04) is expected to write these
four numbers from `configs/*.yaml`.

## Structure

The state machine lives in its own module, `s1_dcache_ctrl` (see `docs/modules/s1_dcache_ctrl.md`).
This module holds everything else: the saved request, the valid, dirty and LRU bits, the SRAMs, the
hit logic and the victim choice. The controller sends its commands in a `dcache_ctrl_t` bundle.

## Behaviour

Per way there is one tag SRAM (`SETS` × tag rounded up to a byte) and one data SRAM (`SETS` ×
`LINE_W`). Valid, dirty and LRU bits are flops, because they must clear on reset and
`meds_s1_sram` contents never do.

1. **`S_IDLE`**: accept a request, latch it, read every way of the addressed set.
2. **`S_LOOKUP`**: a way hits when it is valid and its tag matches. On a hit, return the addressed
   word, or write the enabled bytes and set the dirty bit; update the LRU bit. On a miss, pick the
   victim: an invalid way first, otherwise the LRU way.
3. **`S_WRITEBACK`**: only if the victim is valid and dirty. Send its line to memory first.
4. **`S_REFILL_REQ`**, **`S_REFILL_WAIT`**: fetch the line; write tag and data into the victim way,
   mark it valid and clean.
5. **`S_REREAD`**: read the set again and return to `S_LOOKUP`, which now hits. Write-allocate needs
   no extra logic: a write miss refills and then takes the ordinary write-hit path.

## Exceptions and errors

None. There is no error response and no check for non-cacheable regions. No performance-counter
pulses are produced yet.

## Verification status

| Layer | Status | Where |
|---|---|---|
| Lint | clean, all four configs | `make lint` |
| Unit test | 178 checks in three separate tests: load hit (78), load miss without eviction (43), load miss with eviction (57). Every hit is also checked to answer one cycle after the request is taken, for exactly one cycle. Stores and write-back are not tested yet. | `verif/unit/tb_s1_dcache_basic.sv` |
| Co-simulation | not applicable | |
| Formal | not yet | |

## Known limitations

- Memory moves a whole line per transfer. The real caches put an AXI adapter behind this port that
  turns one line into an 8-beat burst.
- The request following a write to the same set reads that set one cycle after the write, so no
  write-forwarding is needed; a faster design would need it (`meds_s1_sram` returns old data on
  read-during-write).
- A 512-bit data SRAM is the simplest layout, not necessarily the best FPGA mapping.

## Open questions

- Data array as `SETS` × 512 bits (this module) or `SETS × 8` × 64 bits, which matches the AXI beat
  and the BRAM primitive better? To be settled at the R-03 design review.
- Valid and dirty bits in flops, or in the tag SRAM with an init walk after reset?
