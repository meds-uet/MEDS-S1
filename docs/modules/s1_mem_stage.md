# `s1_mem_stage`

| | |
|---|---|
| **Status** | WIP (unit-verified; not yet integrated) |
| **Owner** | @EmanNasar001 |
| **Backup** | _(assign at the R-02 design review)_ |
| **Project** | R-02 (load/store unit, store buffer, PMP and atomics) |
| **Spec** | SPEC §7.4, §11, §14, §8.2; INTERFACES.md §1.5 (interlock), §2 (I2 MEM-REQ), §9 (P1–P3); RISC-V A extension; privileged spec PMP |
| **Source** | `rtl/core/s1_mem_stage.sv` |
| **Testbench** | `verif/unit/tb_s1_mem_stage.sv` (models in `verif/common/s1_mem_stage_model.svh`): 891 978 checks |

## Purpose

The MEM stage of the five-stage pipeline. It takes one instruction per cycle from the EX/MEM
register that `s1_execute` fills (#15) and does everything SPEC §7.4 puts in MEM:

- D$ access over I2 MEM-REQ, for loads, LR and AMO reads;
- PMP checks (here) and PMA checks (attributes from the generated decoder), in parallel with the
  access;
- store-buffer allocation, so a write reaches memory only after its instruction retires (SPEC §14);
- AMO and LR/SC sequencing.

It owns the MEM/WB register and produces one `mem_wb_t` completion per instruction, carrying
everything WB, the completion buffer and RVFI need.

## Interface contract

### Ports

| Signal | Dir | Width | Meaning | Contract |
|---|---|---|---|---|
| `clk_i`, `rst_ni` | in | 1 | clock, reset | single domain; async assert, sync de-assert |
| `flush_i` | in | 1 | retire flush | see *Flush* |
| `priv_i` | in | `priv_lvl_e` | effective data privilege | `mstatus.MPRV` already applied; sampled with the access |
| `mem_valid_i` / `mem_ready_o` | in / out | 1 | EX/MEM handshake | EX holds `mem_i` until `ready` (R-C10); **`ready` is low in a `flush_i` cycle** and never depends on `dmem_req_ready_i` |
| `mem_i` | in | `ex_mem_t` | EX/MEM register (#15) | `mem_addr`, `mem_wdata`, `mem_size`, `mem_signed`, `is_load`/`is_store`/`is_amo`, `amo_op` are used; `result`, `rd`, `next_pc`, `complete`, `csr_*`, `exc*` pass through |
| `wb_valid_o` | out | 1 | completion | one cycle per instruction; **no ready**, because CB entries are allocated in ID |
| `wb_o` | out | `mem_wb_t` | MEM/WB | see below |
| `cb_head_idx_i` | in | `CB_IDX_W` | CB head | holds non-idempotent reads back (P1) |
| `sb_commit_i`, `sb_commit_idx_i` | in | 1, `CB_IDX_W` | a write retires | one per cycle; the index of a `wb_o.sb_alloc` completion |
| `mxif_mem_busy_i` | in | 1 | coprocessor memory outstanding | INTERFACES.md §1.5 interlock |
| `pmpcfg_i`, `pmpaddr_i` | in | `PMP_REGIONS`×8, ×`PLEN-2` | PMP CSRs | WARL legalisation (granularity, locked-entry writes) is the CSR file's job |
| `pma_addr_o`, `pma_size_o` | out | `XLEN`, 3 | the access in MEM | `size` is log2 bytes |
| `pma_i`, `pma_fault_i` | in | `pma_t`, 1 | region attributes; unmapped or width not allowed | **combinational** from `pma_addr_o`/`pma_size_o` |
| `dmem_req_*` | out/in | `mem_req_t` | I2 request | `valid` never depends on `ready`; payload stable while stalled |
| `dmem_rsp_*` | in/out | `mem_rsp_t` | I2 response | `rsp_ready` constant 1; `rdata` byte-lane aligned; `err=1` is an access fault; `id`, `errcode` ignored |
| `sb_empty_o` | out | 1 | store buffer empty | `fence` waits for this |
| `sb_full_o` | out | 1 | store buffer full | perf event `store_buffer_full` (SPEC §12) |
| `store_err_o`, `store_err_addr_o` | out | 1, `XLEN` | a retired write got a bus error | one-cycle pulse; **imprecise** |

### `mem_wb_t` (new in `s1_pkg`)

| Field | Contents |
|---|---|
| `cb_idx`, `complete`, `rd`, `rd_we`, `next_pc`, `csr_we`, `csr_addr`, `csr_wdata` | from EX/MEM, unchanged |
| `result` | load value (extended), LR/AMO value (sign-extended), SC status (0 success, 1 failure), otherwise EX's `result` |
| `sb_alloc` | the instruction owns a store-buffer entry (store, successful SC, AMO); retire must pulse `sb_commit_i` with its `cb_idx` |
| `exc`, `exccode`, `exctval` | EX's exception, an access fault, or a read bus error |
| `mem_addr`, `mem_rmask`, `mem_wmask`, `mem_rdata`, `mem_wdata` | RVFI memory fields: the access address, byte masks relative to it, raw bytes right-justified. Masks are 0 for a trapping or memory-less instruction |

### Latency (with a 1-cycle I2 slave)

| Instruction accepted in cycle *t* | `wb_valid_o` |
|---|---|
| no memory access, faulting, EX exception, failed SC | *t*+1 |
| store, successful SC | *t*+1 (the bus write happens after retire) |
| read fully covered by pending writes | *t*+1 |
| read within one I2 beat | *t*+1 |
| read straddling two beats | *t*+2 |

One instruction per cycle is sustained. The exception is LR and AMO: nothing enters MEM in the cycle
they complete, because they change state (the reservation, a store-buffer entry) that the next
instruction reads. That costs one cycle per LR or AMO.

**Stalls (`mem_ready_o` low):** MEM/WB still waiting on I2; the I2 port taken by the second half of
a straddling read, a drain, or a held request; store buffer full (writes and AMO);
`mxif_mem_busy_i`; P1/P2 waits; LR/AMO completing; `flush_i`.

**Reset state:** no completion, no request, empty store buffer, no reservation.

## Parameters

| Parameter | Default | Legal range | Effect |
|---|---|---|---|
| `STORE_BUF_N` | `SB_DEPTH` (4) | ≥ 1 (elaboration error below) | store-buffer entries |
| `PMP_REGIONS` | `PMP_N` (16) | 0–64 | implemented PMP entries; with 0, S/U accesses are not PMP-restricted |

## Behaviour

```
 EX/MEM ─► width/sign/kind ─► PMP (here) + PMA (outside) + alignment + atomics ─► fault?
             │
             ├─ read  (load, LR, AMO): merge older SB entries byte-wise ─► bytes left? ─► I2 (B)
             ├─ write (store, SC ok) : allocate SB entry, uncommitted
             ▼                                                                       │
        MEM/WB register ─────────────── response (+ 2nd beat, A) ──► extend ──► wb_o  ▼
             │ AMO: new = op(old, rs2) ──► allocate SB entry at completion
             │ LR : set reservation at completion
 store buffer [e0 .. eN-1] ──commit at retire──► drain head over I2 (C) ──► pop
```

**Checks.** An access faults on `pma_fault_i`, on misalignment in an `align_natural` region (P3), on
LR/SC in a region without `atomic_lrsc` or AMO without `atomic_amo`, or on a PMP denial. Loads and
LR raise `EXC_LOAD_ACCESS_FAULT`; stores, SC and AMO raise `EXC_STORE_ACCESS_FAULT` (an AMO needs
both R and W). PMP follows the privileged spec: the lowest-numbered entry matching any byte decides
and must match every byte; M-mode is bound only by locked entries; no match lets M through and
stops S/U. Bounds use `XLEN+2`-bit compares, so a NAPOT entry covering the whole space works.

**Byte windows and forwarding.** An access covers at most two 8-byte I2 beats and is kept as a
16-bit byte mask plus 128 bits of data. A read merges every older pending store, oldest first, so
each byte comes from its youngest writer; bytes nobody covers come from the bus, and only beats with
an uncovered byte are requested. A straddling access (DRAM is `align: any`) is two requests, low
beat first.

**P1 and P2.** A read from a `!idempotent` or `strong_order` region waits for an empty store buffer
and never merges. A `!idempotent` read also waits until it is at the CB head.

**LR/SC.** LR is a read that records `{address, size}` when it completes. SC checks that
reservation in MEM: without an exact match it fails (`result = 1`) without touching memory and
without faulting, as Sail does; with a match it is checked and written like a store (`result = 0`).
Every SC that does not already carry an exception clears the reservation, and so does `flush_i`.

**AMO.** An AMO reads like a load, then at completion computes `new = op(old, rs2)` at the access
width (32-bit operands are sign-extended, so MIN/MAX and MINU/MAXU order correctly) and allocates a
store-buffer entry with it. `result` is the old value, sign-extended.

**The I2 port.** One request at a time. Priority: **A** the second beat of the read in MEM/WB,
then **C** a committed store-buffer head, then **B** the read in MEM. Draining before new reads
keeps a committed MMIO write from being starved by a loop of loads. A presented request is frozen
until accepted (R-C10).

**Store buffer.** Shift register, entry 0 oldest; committed entries are always a prefix. Each edge
applies commit (by `cb_idx`), pop (when the head's last beat is answered), flush (keep the committed
prefix) and allocate, in that order.

**Flush.** `flush_i` blocks the EX/MEM transfer, suppresses `wb_valid_o`, clears MEM/WB, drops
uncommitted entries and the reservation. Committed entries keep draining. A read request already
presented completes on the bus and its response is dropped. That needs no stale flag, since a new
read cannot enter MEM/WB until the port frees.

**Interlock.** While `mxif_mem_busy_i` is high, a non-faulting memory instruction stalls in MEM and
no new drain starts.

## Exceptions and errors

| Condition | `exccode` | `exctval` |
|---|---|---|
| EX exception | passed through | passed through |
| check failure on load or LR | `EXC_LOAD_ACCESS_FAULT` | address |
| check failure on store, SC (with reservation) or AMO | `EXC_STORE_ACCESS_FAULT` | address |
| bus error on a read's low / high beat | load: `EXC_LOAD_ACCESS_FAULT`, AMO: `EXC_STORE_ACCESS_FAULT` | address / first byte of the high beat |
| bus error draining a retired write | none; `store_err_o` pulse | |

All but the last are precise. A write's bus error arrives after retire and cannot be; the checks in
MEM catch unmapped and misaligned writes before that.

## Verification status

| Layer | Status | Where |
|---|---|---|
| Lint | clean, no waivers | `make lint` |
| Unit test | **891 978 checks**; also passes with `SB_DEPTH` 1, 2 and 8 | `verif/unit/tb_s1_mem_stage.sv` |
| Mutation | 24 hand-inserted bugs, 24 caught | table below |
| Integration, co-simulation, arch tests | not yet | needs #4, #15 and the rest of the core |

The testbench plays EX, the completion buffer (head, commit, flush, random interrupts), the CSR file
(PMP), the PMA decoder (DRAM `rvwmo` with both atomics; a strongly-ordered region with AMO only; an
MMIO region that is non-idempotent, 4/8-byte and without atomics) and the D$ (random grant and
latency, garbage on unselected lanes, a bus-error beat). The reference models are written
independently of the RTL: PMP matches byte by byte, AMO compares at the access width, memory is a
byte map.

- **Scoreboard.** Each completion is checked against program-order memory (architectural memory
  plus every older unflushed write) and the program-order reservation: result, extension, SC status,
  exception, `mtval`, `sb_alloc`, every pass-through field, all five RVFI fields, completion order.
  Every bus write is checked, in order, against retired writes: address, lanes, data, mode. At the
  end bus memory must equal architectural memory.
- **Every cycle.** `dmem_req_valid_o`, its payload, `mem_ready_o` and `wb_valid_o` independent of
  `dmem_req_ready_i`; payload held while stalled; ≤ 1 outstanding request; `addr` on its lane; no
  access to unmapped bytes; `sb_empty_o`/`sb_full_o` against an occupancy model; at every new read,
  a legal owner, P2 for ordered regions and P1 for non-idempotent ones; a hang watchdog.
- **Directed.** Every load width and signedness at every offset with exact latency; one load per
  cycle; full and partial forwarding including an AMO in the buffer; LR/SC success, no reservation,
  address and size mismatch, unmapped SC with no reservation, LR without `atomic_lrsc`; all nine AMO
  ops at both widths on sign-boundary values, AMO without `atomic_amo`, AMO bus error; locked PMP
  entry for M, U partial match, U with no entry, read-only MMIO for U; misalignment, width, unmapped,
  past the region end; EX exceptions; low/high-beat bus errors; drain error; store buffer full;
  flush discarding writes; MMIO read after a drain; both halves of the interlock; flush with a held
  request.
- **Random soak.** 3 × 20 000 cycles (ideal / busy / starved D$, retire and interlock, random
  interrupts), with the default PMP map and two fuzzed maps. All coverage bins must be hit; the last
  run: forwarded 259 full / 453 partial, straddling reads 2725 / drains 1521, buffer full 373, P2
  5893, P1 2117, dropped flushed responses 420, drain over read 1455, flush with uncommitted writes
  1063, bus errors 31 / 32, faults 2902 (PMP 977, misalign 235, atomics 679), EX exceptions 959,
  interlock 1083, LR 772, SC success 123 / failure 1277, AMO 1234.

Mutants, each a copy of `s1_mem_stage.sv` with one change:

| Mutant | Bug injected | Caught by |
|---|---|---|
| oldest wins | forwarding lets an older store override a younger one | scoreboard (`result`) |
| merge ignores forwarding | reads use bus bytes only | scoreboard (`result`) |
| drain uncommitted | a write drains before it retires | "bus write only for a retired write" |
| flush keeps uncommitted | flush leaves speculative entries | occupancy model |
| pop on first beat | a straddling drain pops after its low beat | occupancy model |
| no P2 | ordered reads do not wait for older writes | directed MMIO ordering check |
| no P1 | non-idempotent reads issue before the head | P1 check |
| hold unstable | a stalled request follows the instruction in MEM | R-C10 stability check |
| valid on ready | `dmem_req_valid_o` gated by `dmem_req_ready_i` | R-C10 probe |
| complete during flush | `wb_valid_o` not suppressed by `flush_i` | "completion has an owner" |
| PMP last entry wins | a higher-numbered entry overrides a lower one | occupancy model / scoreboard |
| PMP ignores lock | M-mode ignores locked entries | scoreboard |
| PMP any, not all | a partial match passes | read-owner check |
| NAPOT one short | NAPOT region half its size | scoreboard (`exc`) |
| no alignment check | P3 misalignment not faulted | read-owner check |
| no atomics check | LR/SC/AMO in regions without atomics | read-owner check |
| AMO skips W permission | AMO checked as a read only | scoreboard (`sb_alloc`) |
| AMO fault code | AMO bus error reported as a load fault | scoreboard (`exccode`) |
| SC ignores size | LR.W reservation satisfies SC.D | scoreboard / occupancy |
| LR survives flush | reservation kept across a trap | scoreboard / occupancy |
| AMO no stall | the next instruction enters as an AMO completes | scoreboard (stale forwarded value) |
| AMOMINU signed | unsigned compare done signed | RVFI `wdata` |
| AMO W operand | 32-bit AMO operand not sign-extended | RVFI `wdata` |
| RVFI rdata extended | `mem_rdata` carries the extended value | RVFI `rdata` |

## Known limitations

- **No Zicbom.** `decoded_op_t` (#4) now defines `is_cbo` and `cbo_op`, but MEM does not act on
  them: `cbo.*` will issue here and must be ordered with the store buffer.
- **Forwarding is by address.** A load through `dram` after a store through `dram_uncached` of the
  same byte is not forwarded (the uncached read waits for the drain, so the reverse case is safe).
  That is the D$ coherence problem P4 and Zicbom already hand to software.
- **Same-hart writes do not break a reservation**, and a flush or SC always clears it. Both are
  permitted by the A extension; a flush between LR and SC makes the SC fail.
- **One outstanding I2 request**; with a slower D$, throughput is one access per hit latency.
- **Critical paths:** PMP (16 × two 66-bit compares) and PMA → `mem_ready_o`/`dmem_req_valid_o`;
  store-buffer compares → `need_lo/hi`; I2 `rdata` → merge → extend (and AMO compute) → `wb_o`.
  PMP on the MEM address in parallel with the D$ request is SPEC §11's arrangement; if it does not
  meet timing, registering the PMP result is the first thing to try.
- Tested at `XLEN = 64`, `PMP_REGIONS = 16`, `STORE_BUF_N` 1, 2, 4, 8.

## Open questions

1. **Interrupts on a completed non-idempotent read.** Its MMIO read has already happened; if retire
   takes an interrupt there instead of retiring it, the read is replayed after `mret` (P1). Retire
   (T-03/R-01) must retire such an instruction first. The testbench does not interrupt those heads.
2. **What does `store_err_o` raise?** Imprecise by construction: a bus-error interrupt, a sticky
   CSR, or debug halt. Needs a ruling.
3. **I2 for split accesses.** Each beat of a straddling access carries the whole access's `size`;
   `be` is authoritative. Settle in INTERFACES.md §2 together with the lane convention (`s1_fetch`
   open question 4).
4. **RVFI address convention.** `mem_addr` is unaligned with masks relative to it (riscv-formal
   without `RISCV_FORMAL_ALIGNED_MEM`). R-05 should confirm.
5. **`sb_commit_idx_i`** assumes CB indices of in-flight instructions are unique, which an 8-entry
   CB guarantees. A deeper CB with index reuse would need the entry pointer instead (SPEC §9.1
   `stp`).
