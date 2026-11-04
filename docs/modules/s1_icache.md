# `s1_icache`

| | |
|---|---|
| **Status** | COMPLETE — behavioural model verified |
| **Owner** | @MuhammadUsman0001 |
| **Backup** | _(assign)_ |
| **Project** | R-03 (caches, Zicbom and the SRAM wrapper) |
| **Spec** | SPEC §15, INTERFACES.md §8 |
| **Source** | `rtl/core/s1_icache.sv` (top), `rtl/core/s1_icache_controller.sv`, `rtl/core/s1_icache_datapath.sv` |
| **Testbench** | `verif/unit/tb_s1_icache.sv` (33 checks), `tb_s1_icache_controller.sv` (25 checks), `tb_s1_icache_datapath.sv` (28 checks) |

## Purpose

The S1-Core instruction cache. Read-only, blocking, 2-way set-associative
fetch cache. Serves instruction fetches from the IF stage and issues a
line-aligned refill request to memory on a miss. Carries no dirty state
and never writes memory.

Three cooperating modules:

- **`s1_icache`** — top-level wrapper. Instantiates controller + datapath,
  wires them together, exposes the CPU and memory interfaces.
- **`s1_icache_controller`** — FSM that sequences the datapath, talks to
  memory on a miss, and hands the fetched instruction back to the CPU.
- **`s1_icache_datapath`** — passive storage + comparison logic. Owns the
  tag array, data array, and per-set LRU state — all through
  `meds_s1_sram` (NFR-5).

## Interface contract — `s1_icache` (top)

| Signal | Dir | Width | Meaning | Contract |
|---|---|---|---|---|
| `clk_i` | in | 1 | clock | single domain |
| `rst_ni` | in | 1 | reset | async assert, sync de-assert; clears controller state and the LRU output register |
| `req_valid_i` | in | 1 | CPU fetch request | held HIGH from IDLE until `rsp_valid_o` asserts |
| `req_addr_i` | in | `ADDR_WIDTH` (40) | fetch address | held STABLE for the same window; broadcast to controller + datapath |
| `rsp_valid_o` | out | 1 | fetch response valid | asserted for one cycle in the HIT state |
| `rsp_data_o` | out | 32 | 32-bit instruction | valid on the cycle `rsp_valid_o` is HIGH |
| `rsp_error_o` | out | 1 | fetch fault | tied 0 in v1.0 (no PMA/PMP path) |
| `mem_req_o` | out | 1 | refill request | asserted in MISS; held until `mem_valid_i` |
| `mem_addr_o` | out | `ADDR_WIDTH` | refill address | line-aligned (offset bits cleared) |
| `mem_valid_i` | in | 1 | refill data valid | asserted by memory for one cycle per line |
| `mem_data_i` | in | `LINE_SIZE_BYTES*8` (512) | refill data | BYPASSES the controller — wires directly into the datapath's `refill_data_i` |

**Latency:** HIT completes in 3 cycles from `req_valid_i` (IDLE → LOOKUP →
HIT). MISS adds memory latency + 3 extra cycles (REFILL → WAIT → LOOKUP).

**Reset:** memory contents are undefined at reset. A post-reset
invalidation sweep, or a fence.i, must write INVALID tag entries across
every set before any lookup may be trusted.

## Parameters — `s1_icache`

| Parameter | Default | Legal range | Effect |
|---|---|---|---|
| `CACHE_SIZE_KB` | 16 | 8, 16 | cache capacity |
| `LINE_SIZE_BYTES` | 64 | 64 | line size in bytes |
| `ASSOCIATIVITY` | 2 | 2 | ways per set |
| `ADDR_WIDTH` | 40 | — | physical address width |

`ASSOCIATIVITY != 2` is accepted by the datapath but fails loudly at
elaboration (the replacement policy is only implemented for true 2-way LRU).

## Interface contract — `s1_icache_controller` (internal)

| Signal | Dir | Meaning |
|---|---|---|
| `req_valid_i`, `req_addr_i` | in | CPU fetch request |
| `hit_i`, `hit_way_i`, `lru_way_i`, `dp_data_i` | in | from the datapath |
| `refill_sel_o`, `refill_addr_o`, `refill_we_o`, `refill_valid_o`, `refill_way_sel_o` | out | to the datapath |
| `mem_req_o`, `mem_addr_o`, `mem_valid_i` | out/in | memory handshake |

FSM states: `IDLE → LOOKUP → (HIT | MISS → REFILL → WAIT → LOOKUP)`.

## Interface contract — `s1_icache_datapath` (internal)

| Signal | Dir | Meaning |
|---|---|---|
| `req_addr_i` | in | CPU fetch address (broadcast) |
| `refill_sel_i`, `refill_addr_i`, `refill_we_i`, `refill_valid_i`, `refill_way_sel_i`, `refill_data_i` | in | from the controller |
| `hit_o`, `hit_way_o` (one-hot), `lru_way_o`, `rsp_data_o` | out | to the controller |

Read latency is one cycle, registered output, per `meds_s1_sram`.
`hit_o` is combinational, valid one cycle after `req_addr_i` is applied.

## Verification status

| Layer | Status | Where |
|---|---|---|
| Lint | clean | `make lint` |
| Unit test — datapath | **28 checks, all passing** | `verif/unit/tb_s1_icache_datapath.sv` |
| Unit test — controller | **25 checks, all passing** | `verif/unit/tb_s1_icache_controller.sv` |
| Integration test | **33 checks, all passing** | `verif/unit/tb_s1_icache.sv` |
| Formal | not yet | — |

**Testbench evidence:**
```
=== PASS : 33 checks ===   (tb_s1_icache)
=== PASS : 28 checks ===   (tb_s1_icache_datapath)
=== PASS : 25 checks ===   (tb_s1_icache_controller)
```

## Known limitations

- **Read-only.** No writeback, no dirty bits, no Zicbom. D$ / store-buffer
  / cache-management state lives in the LSU side of the design.
- **Blocking.** A miss stalls the pipeline until refill completes.
  Non-blocking is a v2 project with this cache as the baseline.
- **No fence.i FSM.** Invalidation is done externally (post-reset sweep
  or a future Zicbom driver). `refill_valid_i = 0` on the datapath is the
  write port for that sweep.
- **No PMA/PMP.** Every address is treated as cacheable; `rsp_error_o` is
  tied 0.
- **2-way only.** True LRU for 2-way is implemented; wider associativity
  fails loudly at elaboration rather than silently returning a meaningless
  victim way.

## Open questions

-None for now
