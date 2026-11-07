# `s1_mem`

| | |
|---|---|
| **Status** | WIP — unit- and integration-verified |
| **Authorship** | Eman Nasar (fatehulnasareman@gmail.com, GitHub EmanNasar001) — see the file header |
| **Project** | R-02 (load/store unit, store buffer, PMP and atomics) |
| **Spec** | SPEC §7.4, §11, §14, §8.2; INTERFACES.md §1.5, §2, §9 (P1–P3); RISC-V A |
| **Source** | `rtl/core/s1_mem.sv` |
| **Testbench** | `verif/unit/tb_s1_mem.sv` (4,546,961 checks), plus the integration testbench that lands with `s1_core` |

## Purpose

The MEM stage. It takes one instruction per cycle from the EX/MEM register and does what SPEC §7.4
puts in MEM: the D$ access over I2, the physical-memory checks, store-buffer allocation so a write
reaches memory only after its instruction retires, and AMO / LR / SC sequencing. It owns the MEM/WB
register and produces one `mem_wb_t` per instruction.

## Interface contract

### Ports

| Signal | Dir | Width | Meaning | Contract |
|---|---|---|---|---|
| `clk_i`, `rst_ni` | in | 1 | clock, reset | async assert, sync de-assert |
| `flush_i` | in | 1 | retire flush | blocks the EX/MEM transfer, clears MEM/WB, drops uncommitted writes and the reservation |
| `priv_i` | in | `priv_lvl_e` | effective data privilege | `mstatus.MPRV` already applied |
| `mem_valid_i` / `mem_ready_o` | in / out | 1 | EX/MEM handshake | EX holds `mem_i` until `ready` (R-C10); `ready` is low during `flush_i` and never depends on `dmem_req_ready_i` |
| `mem_i` | in | `ex_mem_t` | EX/MEM register | |
| `wb_valid_o`, `wb_o` | out | 1, `mem_wb_t` | MEM/WB | one per instruction; **no ready** — WB commits whatever it is shown (see *Fences*) |
| `wb_pend_o` | out | 1 | MEM/WB holds something not finished: a read the bus still owes, or a FENCE waiting for the store buffer | the hazard unit and CSR serialisation need this — without it a load in flight is invisible to them whenever memory latency exceeds one cycle |
| `sb_commit_i` | in | 1 | WB committed a store | at most one per cycle, in program order; commits the oldest uncommitted entry. Only for an instruction shown on `wb_o` with `sb_alloc` set, and never while `flush_i` is high. May arrive in the same cycle the entry is allocated (an AMO completing), so **no delay is needed** in `s1_core` |
| `chk_*_o` | out | — | the access in MEM, as a query | **answered combinationally in the same cycle** |
| `pma_i`, `pma_fault_i`, `pmp_allow_i` | in | `pma_t`, 1, 1 | the two checkers' answers | both checkers are **outside this core** |
| `dmem_*` | out/in | I2 MEM-REQ | D$ port | `valid` never depends on `ready`; payload stable while stalled; `rsp_ready` constant 1 |
| `sb_empty_o`, `sb_full_o` | out | 1 | store buffer status | `fence` waits on empty; full is a perf event |
| `store_err_o`, `store_err_addr_o` | out | 1, `XLEN` | a retired write got a bus error | one-cycle pulse; **imprecise** |

**Both physical-memory checks are external.** One query describes the access; two independent
checkers answer in the same cycle, in parallel with the D$ tag lookup. PMA comes from the generated
decoder, PMP from a checker reading the CSRs. Neither is inside the core, which is what lets the
fetch path share the same PMP checker.

## Parameters

| Parameter | Default | Legal range | Effect |
|---|---|---|---|
| `STORE_BUF_N` | `SB_DEPTH` | ≥ 1 (elaboration error below) | store-buffer entries |

## Behaviour

```
 EX/MEM ─► width/sign/kind ─► checks (external) + alignment + atomics ─► fault?
             │
             ├─ read  (load, LR, AMO): merge older SB entries byte-wise ─► bytes left? ─► I2
             ├─ write (store, SC ok) : allocate an SB entry, uncommitted
             ▼
        MEM/WB register ──── response (+ 2nd beat) ──► extend ──► wb_o
             │ AMO: new = op(old, rs2) ──► allocate at completion
             │ LR : set the reservation at completion
 store buffer ──commit at retire──► drain the head over I2 ──► pop
```

**Byte windows and forwarding.** An access covers at most two 8-byte I2 beats, held as a 16-bit
byte mask and 128 bits of data. A read merges every older pending write, oldest first, so each byte
comes from its youngest writer; bytes nobody covers come from the bus, and only beats with an
uncovered byte are requested. A straddling access is two requests, low beat first.

**P1 and P2.** A read from a `!idempotent` or `strong_order` region waits for an empty store buffer
and never merges. A `!idempotent` read also waits until it is the oldest in flight. Issue is in
order and WB holds no state, so that is simply "MEM/WB is empty" (`!mw_valid_q`) — an entry
completing this cycle still counts, because it can still trap. No tag is involved.

**Fences.** A FENCE or FENCE.I is held in MEM/WB, with `wb_pend_o` high, until the store buffer is
empty, and only then shown to WB. Everything older has already committed, so the buffer holds only
entries that are draining, and nothing younger can allocate while the fence occupies MEM/WB, so the
wait always ends. Holding it here rather than in WB is why MEM/WB needs no ready: the store buffer
is MEM's, so MEM is where "drained" is known. `s1_wb`'s `fence_wait` can never be true and can be
deleted.

**LR/SC.** LR records `{address, size}` when it completes. SC checks that reservation in MEM:
without an exact match it fails (`result = 1`) without touching memory and without faulting. Every
SC clears the reservation, and so does `flush_i`.

**The I2 port.** One request at a time. Priority: the second beat of the read in MEM/WB, then a
committed store-buffer head, then the read in MEM. Draining before new reads keeps a committed MMIO
write from being starved by a loop of loads. A presented request is frozen until accepted (R-C10).

**Store buffer.** A circular buffer: `sb_head_q` is the oldest entry, `sb_cnt_q` entries are live,
and the oldest `sb_ncom_q` of them are committed. Commit is in order, so the count is all that
records it: no tag per entry, no associative sweep. An entry is written once, when allocated at the
tail, and never moves. Each edge applies pop (advance the head), commit (`ncom + 1`, which also
covers an AMO allocated in the same cycle), flush (`cnt = ncom`: drop the uncommitted
tail) and allocate, in that order. Forwarding visits live entries oldest first without a rotator:
entries at or above the head are older than those that wrapped below it, and within each run
physical order is age order, so it is two static passes, `[head, N)` then `[0, head)`.
`STORE_BUF_N` need not be a power of two.

## Exceptions and errors

| Condition | `exccode` |
|---|---|
| EX exception | passed through |
| check failure on a load or LR | `EXC_LOAD_ACCESS_FAULT` |
| check failure on a store, SC or AMO | `EXC_STORE_ACCESS_FAULT` |
| bus error on a read | load: load fault; AMO: store fault |
| bus error draining a retired write | none; `store_err_o` pulse |

All but the last are precise. A write's bus error arrives after retire and cannot be.

## Verification status

| Layer | Status | Where |
|---|---|---|
| Lint | clean once the shared types are available | `make lint` |
| Unit test | `tb_s1_mem` — 4,546,961 checks over 13,291 instructions, Verilator 5.020 | `make test-unit TB=s1_mem` |
| Mutation | 12 of 12 mutants of the new logic caught (fence hold, commit count, flush, head/tail pointers, forwarding order, P1) | `rtl/core/s1_mem.sv` |
| Integration | every retirement compared against spike, over the whole pipeline | the integration testbench that lands with `s1_core` |
| Co-simulation, arch tests | not yet | |

**Unit test.** A cycle-accurate golden copy of this module would be a second implementation of the
same design, and would agree with it about any shared mistake. The unit testbench checks it against
**memory** instead, at the two levels this design actually promises:

| Model | Updated when | What it proves |
|---|---|---|
| `prog[]` | an access is accepted into MEM, in program order | every load, LR and AMO reads exactly this, whether the bytes came off the bus, out of the store buffer by forwarding, or from both |
| `phys[]` | a write request fires on I2 | it may lag `prog[]` — that lag **is** the store buffer — but the instant `sb_empty_o` goes high the two must agree byte for byte |

That second property is the one worth having: it says a drained buffer has really drained, which is
what `fence` rests on, and it catches a store that was dropped, duplicated, written to the wrong
address or written with the wrong byte enables — none of which a forwarding-only check would notice.

Each 4 KiB page in the testbench's map carries a different PMA, so one random stream reaches every
path: misaligned (beat-straddling) accesses, non-idempotent and strongly-ordered ordering stalls,
regions that refuse atomics, a PMP that denies writes, an unmapped hole, and a bus that errors on a
read, on a *straddling* read, or on a drained write. The testbench plays WB: it commits each store
either in the very cycle it completes (what `s1_wb` does, and the AMO case that used to need a
delay in `s1_core`) or later, with jitter. FENCE and FENCE.I are mixed in, and a fence shown to WB
with anything still buffered or a write still on the bus is a failure.

Two properties are checked directly rather than through their data effect, because neither has one.
P1 — a non-idempotent read is never speculative — only changes *timing*, so the testbench asserts
the ordering rule itself: such a read may only be accepted when MEM/WB was empty, neither
completing nor pending.
And `store_err_o` is imprecise by construction, so the write-error page is the one place the two
memory models are *meant* to diverge, and it is excluded from the byte comparison rather than
papered over.

It also checks the bus contract and the hang cases, not just the data: `dmem_rsp_ready_o` constant,
no second request outstanding, a response only when one is owed, a presented request frozen under
backpressure (R-C10), `wb_pend_o` exactly whenever MEM/WB holds something with no result yet, and a
watchdog that fails the run if `mem_valid_i` is held for 500 cycles without acceptance.

Because the stimulus is random, the coverage counts are **asserted, not printed** — "passed" and
"did not run" must not look alike. One run reaches:

| | | | |
|---|---|---|---|
| loads 4,994 | stores 5,107 | AMOs 573 | LR 513 |
| SC success 94 | SC failure 406 | straddling 905 | faults 1,291 |
| read bus errors 78 (9 of them straddling) | write bus errors 139 | forwarding hits 616 | buffer-full cycles 3,580 |
| fences 303 | fence-wait cycles 1,331 | same-cycle commits 1,685 | |

**Integration** then runs an RV64I program and a C sorting workload through the whole pipeline with
every retirement compared against spike on RVFI, under random I$/D$ backpressure and latency.

Two bugs that testing found and this version fixes:

- a load still waiting on the D$ in MEM/WB was invisible to the hazard unit and to CSR
  serialisation, giving stale operands whenever memory latency exceeded one cycle. That is what
  `wb_pend_o` is for.
- `rs1_rdata` / `rs2_rdata` were not carried into MEM/WB, so RVFI could not report them.

**What neither layer reaches.** The unit testbench answers `pma_i` / `pmp_allow_i` from its own map,
so it proves what MEM does with a checker's answer, not that the checkers are right — PMA belongs to
the generated decoder and PMP to R-02's checker, each with its own testbench. Zicbom is untested
because the module does not implement it. Under flush, the program-order model stops describing the
machine (a flush discards uncommitted stores), so the flush phase checks liveness, "nothing completes
during a flush", and a third memory model instead: `cmem[]`, every store WB committed, applied in
commit order. After the phase drains, `phys[]` must equal it byte for byte, which proves a flush
keeps every committed store and nothing else. Loads are not scoreboarded in that phase.

## Known limitations

- **No Zicbom.** `decoded_op_t` defines `is_cbo` and `cbo_op`, but MEM does not act on them.
- **Forwarding is by address**, so a load through one mapping after a store through another of the
  same byte is not forwarded.
- **Same-hart writes do not break a reservation**, and a flush or SC always clears it. Both are
  permitted by the A extension.
- **One outstanding I2 request.** With a slower D$, throughput is one access per hit latency.
- **Critical path:** the external checks → `mem_ready_o` / `dmem_req_valid_o`, and I2 `rdata` →
  merge → extend → `wb_o`.

## Proposal: trap misaligned accesses instead of splitting them

**For a ruling.** Today an access in a region without `align_natural` may straddle two I2 beats, and
the hardware splits it. Everything below exists only for that, because `WIN_W = 2*XLEN`:

| Removed by trapping | Now | After |
|---|---|---|
| store-buffer entry data / byte mask | 128 b / 16 b | 64 b / 8 b — about 72 b × `STORE_BUF_N` flops |
| forwarding | same beat, beat + 1, beat − 1 | same beat only |
| I2 arbiter | three requesters (second beat, drain, new read) | two |
| MEM/WB | `mw_lo_rdata_q` (64 b), `mw_need_hi_q`, `mw_hi_sent_q`, `mw_lo_got_q`, 128-b forward window | gone, window 64 b |
| drain | `dr_lo_sent_q` / `dr_hi_sent_q`, two-part pop | one request per entry |
| errors | `exctval` / `store_err_addr_o` choose which half failed | the access address |

The SPEC does not require misaligned support (P3: alignment violations fault), and the privileged
spec allows a misaligned load, store or AMO to raise *address-misaligned* (cause 4 / 6) so M-mode
can emulate it. The proposal: check alignment on every access, independent of `align_natural`, and
raise `EXC_LOAD_ADDR_MISALIGNED` / `EXC_STORE_ADDR_MISALIGNED` (not access fault, so a handler can
tell the two apart and emulate). `pma_t.align_natural` then only needs to mean "misaligned is an
*access fault* here" for MMIO, or can go. The cost is software: misaligned accesses become slow
(trap + emulate), which matters only for code that does them on purpose. Not implemented until
ruled on.

## Changes this asks of other PRs

- **#37 (`s1_core`):** drop `oldest_tag` and the `sb_commit_q` / `sb_commit_tag_q` delay; wire
  `s1_wb.sb_commit_o` straight to `sb_commit_i`. `sb_commit_tag_o` is no longer used.
- **#21 (`s1_wb`):** `fence_wait` can never be true now; delete it (and `sb_empty_i`).
- **#14 (`s1_pkg`):** MEM no longer reads `tag`. If nothing else does, `tag` / `TAG_W` can leave
  `ex_mem_t` and `mem_wb_t`. MEM still copies the field through while it exists.

## Open questions

1. **What does `store_err_o` raise?** Imprecise by construction: a bus-error interrupt, a sticky
   CSR, or debug halt. Needs a ruling.
2. **I2 for split accesses.** Each beat of a straddling access carries the whole access's `size`;
   `be` is authoritative. Settle in INTERFACES.md §2.
3. **Interrupts on a completed non-idempotent read.** Its MMIO read has already happened; retire
   must retire such an instruction rather than replay it.
