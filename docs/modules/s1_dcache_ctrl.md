# `s1_dcache_ctrl`

| | |
|---|---|
| **Status** | WIP: controller of the basic data cache |
| **Owner** | Faisal Habib (FYDP Group 34) |
| **Backup** | Fahad Ali, Abdullah Rasheed Butt |
| **Project** | R-03 (caches, Zicbom and the SRAM wrapper) |
| **Spec** | SPEC §15 (cache state machine) |
| **Source** | `rtl/cache/s1_dcache_ctrl.sv`, `rtl/cache/s1_dcache_pkg.sv` |
| **Testbench** | tested through `verif/unit/tb_s1_dcache_basic.sv` |

## Purpose

The state machine of `s1_dcache_basic`, kept in its own file. It holds the current step of the cache
and tells the rest of the cache what to do in that step. It stores no addresses and no data: it only
sees five one-bit facts and answers with one bundle of one-bit commands.

## Interface contract

| Port | Dir | Type | Meaning |
|---|---|---|---|
| `clk_i` | in | `logic` | clock, single domain |
| `rst_ni` | in | `logic` | reset: async assert, sync de-assert; returns to `S_IDLE` |
| `lsu_valid_i` | in | `logic` | the LSU has a request |
| `hit_i` | in | `logic` | the lookup found the line; read only in `S_LOOKUP` |
| `victim_dirty_i` | in | `logic` | the line to be replaced is valid and dirty; read only in `S_LOOKUP` |
| `mem_ready_i` | in | `logic` | memory accepts the request |
| `mem_valid_i` | in | `logic` | the fetched line has arrived |
| `ctrl_o` | out | `dcache_ctrl_t` | the commands for this cycle |

Each field of `ctrl_o` is high for the cycles in which the command applies:

| Field | High in | The rest of the cache then |
|---|---|---|
| `ready` | `S_IDLE` | tells the LSU it can send a request |
| `accept` | `S_IDLE` with a request | saves the request and reads both ways |
| `hit_done` | `S_LOOKUP` on a hit | answers the LSU, updates LRU, and writes a store |
| `miss` | `S_LOOKUP` on a miss | remembers the way to replace |
| `writeback` | `S_WRITEBACK` | sends the dirty line to memory |
| `refill_req` | `S_REFILL_REQ` | asks memory for the missing line |
| `refill_done` | `S_REFILL_WAIT` when the line arrives | stores the line and marks it valid and clean |
| `reread` | `S_REREAD` | reads both ways again |

`writeback` and `refill_req` depend on the state only, never on `mem_ready_i`, so the request to
memory stays up until memory takes it (R-C10).

## Parameters

None.

## Behaviour

`S_IDLE` → `S_LOOKUP` on a request. From `S_LOOKUP`: back to `S_IDLE` on a hit; to `S_WRITEBACK` on a
miss with a dirty victim; to `S_REFILL_REQ` on a miss with a clean or empty victim. `S_WRITEBACK` →
`S_REFILL_REQ` → `S_REFILL_WAIT` → `S_REREAD` → `S_LOOKUP`, which then hits.

## Verification status

| Layer | Status | Where |
|---|---|---|
| Lint | clean, all four configs | `make lint` |
| Unit test | exercised by the three load tests of the data cache; no testbench of its own | `verif/unit/tb_s1_dcache_basic.sv` |

## Known limitations

- The write-back state is not reached by the current tests, because they contain no stores.
