# `s1_wb_stage`

| | |
|---|---|
| **Status** | WIP (unit-verified; not yet integrated) |
| **Authorship** | see the file header (`Author(s)` / `Modified By`) — CODING_STANDARD.md §5 |
| **Project** | T-02 (core backend), against the completion buffer R-01 will build |
| **Spec** | SPEC §6, §7.5, §8.1, §8.2, §9.1, §9.2, §28.2; INTERFACES.md §1.4a |
| **Source** | `rtl/core/s1_wb_stage.sv` |
| **Testbench** | `verif/unit/tb_s1_wb_stage.sv` (models in `verif/common/s1_wb_stage_model.svh`): 2 548 090 checks |

## Purpose

Stage five. Every result the core produces reaches the completion buffer through here. WB picks one
per cycle, writes the entry it names, and answers ID's operand reads for that value in the same
cycle.

It is the junction between four things other projects own, and its job is to be the place they meet:

| Counterparty | Owner | What crosses |
|---|---|---|
| `s1_mem_stage` | R-02, #18 | `mem_wb_t` in — the main pipe's completion |
| MUL / DIV | T-02 | `md_rsp_t` in on `N_UC` channels, `uc_ready_o` back — the return leg of #15's `md_req_t` |
| `s1_completion_buffer` | **R-01** | `cb_we_o` / `cb_idx_o` / `cb_upd_o` out — everything retire needs to commit the instruction |
| `s1_execute` (again) | T-02, #15 | `fwd_data_o` out — SPEC §8.1's MEM/WB source, consumed as `memwb_fwd_i` |

**This module does not build any of those.** It carries signals to and from them. Retire itself —
the retire pointer, the architectural register and CSR writes, the store-buffer commit, the trap and
the RVFI channel — is R-01's, at the retire pointer, not here. What WB owes retire is a complete,
already-gated record of what the instruction did, and that is what `wb_upd_t` is.

## Interface contract

### Ports

| Signal | Dir | Width | Meaning | Contract |
|---|---|---|---|---|
| `clk_i`, `rst_ni` | in | 1 | clock, reset | async assert, sync de-assert; the only state is the grant rotation |
| `flush_i` | in | 1 | **retire flush only** | discards the completion presented in the same cycle, drains every unit, suppresses the bypass. **Never wire a branch mispredict here** — see *Which flush* |
| `wb_valid_i` | in | 1 | the main pipe presents a completion | **no `ready`**: the entry was allocated in ID, so WB cannot refuse and never stalls MEM |
| `wb_i` | in | `mem_wb_t` | MEM/WB register (#18) | sampled only when `wb_valid_i` |
| `uc_valid_i` | in | `N_UC` × 1 | a unit presents a result | `valid` must not depend on `uc_ready_o` (R-C10); hold the payload until accepted |
| `uc_ready_o` | out | `N_UC` × 1 | that result is taken this cycle | may depend on `uc_valid_i`; 1 for **every** channel during a flush |
| `uc_i` | in | `N_UC` × `md_rsp_t` | entry, register, value | mirrors #15's `md_req_t`. No exception group (RV64M does not trap) and no `rd_we` (every multiply and divide writes its destination; x0 is gated here) |
| `cb_we_o` | out | 1 | write the entry `cb_idx_o` names | at most one per cycle, from one source |
| `cb_idx_o` | out | `CB_IDX_W` | which entry | meaningful only with `cb_we_o` |
| `cb_upd_o` | out | `wb_upd_t` | what to write | meaningful only with `cb_we_o` |
| `fwd_data_o` | out | `XLEN` | SPEC §8.1's MEM/WB forwarding value | #15's `memwb_fwd_i`. Already gated: reads zero when nothing completes, on a trap, with no destination, and for x0. **There is deliberately no match output** — see *Why there is no match here* |
| `uc_stall_o` | out | 1 | a unit result was held off | perf event; 0 during a flush, which drains rather than stalls |

**Handshake:** the main-pipe channel has no `ready` in either direction. The unit channels are
AXI-style and WB is the only consumer.
**Latency:** zero. The entry is written at the end of the cycle the completion arrives, so the
bypass and the write are the same event.
**Backpressure:** never towards MEM. Towards a unit, for as long as the main pipe keeps the port.
**Reset state:** `cb_we_o = 0`, `fwd_data_o = 0`, `uc_stall_o = 0`, grant pointing at channel 0.

### `wb_upd_t` (new in `s1_pkg`)

| Field | Contents |
|---|---|
| `done`, `norollback` | both 1. `cb_we_o` is asserted only for a completion its producer has resolved, and neither the main pipe nor a MUL/DIV result can fault afterwards (SPEC §9.1) |
| `from_main` | 1 = the main pipe produced this, so the group below is live. 0 = a multi-cycle unit, and the entry keeps what allocation put there |
| `rd`, `rd_we`, `result` | the architectural register write, **already gated**: 0 / 0 / 0 unless the instruction really updates a register |
| `next_pc` | RVFI `pc_wdata`, from EX |
| `exc`, `exccode`, `exctval` | passed through from MEM |
| `csr` | `{we, addr, wdata}`; `we` is suppressed by an exception |
| `sb_alloc` | passed through unchanged — deliberately, see *Behaviour* |
| `rvfi` | `{addr, rmask, wmask, rdata, wdata}` repacked from MEM's `mem_*` group and carried unchanged |

`from_main` exists because a multi-cycle unit knows an entry, a register and a value, and nothing
else. It has never seen a branch target, a CSR write, a store-buffer slot or a memory access. The
alternative — making the units drive those fields with zeros — would have the completion buffer
unable to tell "no branch target" from "branch target zero", and would quietly erase the instruction
information allocation had already put in the entry.

## Parameters

| Parameter | Default | Legal range | Effect |
|---|---|---|---|
| `N_UC` | 2 | ≥ 1 (elaboration error below) | multi-cycle completion channels. MUL and DIV. With no M extension, tie `uc_valid_i[0]` low rather than setting this to 0 |

## Behaviour

```
  wb_valid_i ──► resolved? ─────────────┬──► cb_we_o ──► entry cb_idx_o
                                        │
  uc_valid_i[0] ──┐                     │
  uc_valid_i[1] ──┤ rotate ──► uc_gnt ──┘
       ...        │                     └──► writes a register? ──► fwd_data_o
                  └──► uc_ready_o[k]
```

### Which flush

`flush_i` is the retire flush — a trap, an `mret` or a `fence.i` at the retire pointer — and nothing
else. It is total, and it is safe to be total precisely because the instruction that caused it is at
the head: everything else in the core is younger.

The branch mispredict is **not** that flush and must not be wired here. #15 resolves a mispredict in
EX and frees the completion-buffer entries younger than the branch (`ex_redirect_cb_idx_o`); SPEC
§8.2 prices it at two cycles and flushes IF and ID only. Everything in MEM and in MEM/WB is *older*
than the branch and has to survive. Connecting the redirect to `flush_i` would discard an older
instruction's completion and drain a unit whose result is still wanted — and nothing downstream
would notice, because the symptom is an entry that never completes and a head that never retires.

One consequence belongs to R-01 rather than here: because no flush reaches WB on a mispredict, a
MUL or DIV already dispatched for an entry the mispredict freed keeps running and will present its
result to this module, which will write it. The completion buffer has to reject a result whose entry
is no longer live. WB cannot do it — it does not know which entries are allocated.

### Who gets the port

**The main pipe always wins.** Its channel has no `ready`, because the completion buffer entry was
allocated in ID and MEM cannot be told to wait; a unit holds its result until WB takes it. That
asymmetry is not a preference, it is the only arrangement the two contracts allow.

**Between units the grant rotates.** Fixed priority would be smaller, but MUL completes far more
often than DIV and would starve it for as long as a multiply-heavy loop runs. The rotation costs one
pointer and turns "no channel waits for ever" into something the testbench checks rather than a
claim about workloads.

**A flush drains every unit at once.** `uc_ready_o` is 1 on every channel in a flush cycle and
nothing is written. A unit holding a result for an entry the flush removed would otherwise wait for
a ready that will never mean anything, and would never free itself — a stall that outlives the
instruction that caused it.

### What gets written

Three questions decide the rest.

**1. Is this entry the main pipe's to write?** An MXIF candidate travels the main pipe as a
placeholder. It carries `complete = 0`, and from the moment it is offloaded its entry belongs to the
MXIF port, which marks it done and clears its rollback when the coprocessor answers
(INTERFACES.md §1.4a). Offload happens at the head — *after* WB. So WB must leave that entry
completely alone: the `rd` and `rd_we` the decoder put in it at ID are the live copy, and writing
the placeholder's fields over them would lose the register the coprocessor is going to write.

The exception is a candidate that trapped on the way down, from a fetch or address fault carried
from IF or EX. It will never be offered to a coprocessor, so nobody else will ever resolve it, and
WB does.

**2. Does it update an architectural register?** Three independent reasons it may not: it has no
destination, it trapped (SPEC §9.2 step 6 skips steps 1–3), or the destination is x0. All three
produce `rd = 0`, `rd_we = 0`, `result = 0` and no bypass hit. A unit result has only the last two —
RV64M raises no exceptions, so there is no trap to suppress.

x0 is dropped *here* rather than at retire because the bypass is fed from the same signal. Retire
writing x0 is harmless — the register file discards it — but a bypass that answers with it turns
`addi x0, x1, 1` into a corrupted operand for the next reader of x0, and that reader is entitled to
zero. Zeroing `rd` and `result` alongside `rd_we` also makes RVFI's "`rd_wdata` is 0 when `rd_addr`
is 0" structural instead of something retire has to remember.

A pending CSR write is suppressed by the same rule and for the same reason: a CSR write that
survived its instruction's trap would be architectural state from an instruction that never
executed.

**3. Is the store-buffer entry passed through?** Yes, ungated, and this is the one place the module
deliberately does *not* apply rule 2. MEM allocates a store-buffer entry only for an access that
already passed every check, so `sb_alloc` and `exc` are mutually exclusive at the source. Gating it
here would look defensive and would be a leak: the entry is allocated in MEM, never committed at
retire, never drained, and the buffer is one slot smaller for the rest of time. If the two are ever
seen together, the bug is upstream and should be found there.

### The bypass covers exactly one cycle

The entry is written at the end of this cycle, so from the next one the completion buffer's own
bypass — SPEC §8.1's fourth source — answers for it. Until then nothing else can, because the value
exists only on this port. Without it, every consumer of a load or a multi-cycle result would stall a
cycle for a value already in hand.

### Why there is no match here

This module exports the forwarding **value** and no "does this match `rs1`" output, and that
omission is part of the contract.

```
  cycle          t              t+1
  ID             consumer C     -
  EX/MEM reg     M              -
  this module    P              M        <- fwd_data_o at t+1 is M's
```

`s1_execute` (#15) fixes the forwarding select in ID and applies it in the consumer's first EX
cycle, so a select made at *t* is spent at *t+1*, when this bus carries **M** — the instruction
sitting in the EX/MEM register at *t*, not the one this module completed at *t*. A match computed
here would compare against **P** and be exactly one instruction stale. The ID-stage MEM/WB match
belongs with the EX/MEM register, where M is visible.

An earlier revision of this module did export `fwd_hit_o`. It was removed rather than documented,
because a `fwd_hit_o` sitting on the WB stage is precisely what an integrator wiring SPEC §8.1's
MEM/WB source would reach for, and the resulting off-by-one-instruction bug has no symptom at the
point it is made.

### Where §7.5's four bullets actually land

§7.5 lists four things under "WB / retire". Read against §6 and §9.2, only the second is WB's:

| §7.5 says | Where it happens | Why |
|---|---|---|
| "Register file writeback for main-pipe instructions" | **retire** (§9.2 step 1) | §6 decision 2: *all* architectural state updates happen at the retire pointer. WB writes the result into the entry and answers the bypass from it; the register file is written when the entry retires |
| "Completion buffer update" | **WB** — this module | |
| "Retire pointer advance" | **retire** (§9.2), R-01 | |
| "RVFI trace emission" | **retire** (§28.2), R-05 | WB carries the RVFI memory group into the entry so retire has it; it does not drive the port |

§7.5's first bullet reads as a five-stage-textbook line that survived the move to
commit-at-retire. It is listed as an open question below rather than silently contradicted.

## Exceptions and errors

WB raises nothing of its own. It is the point where an exception stops being something the pipeline
carries and becomes something the entry records: `exc`, `exccode` and `exctval` pass through, the
entry is marked `done` so the head can retire and take the trap, and the register and CSR writes
that would have accompanied the instruction are suppressed. The store-buffer flag is not (above).

## Verification status

| Layer | Status | Where |
|---|---|---|
| Lint | clean, no waivers | `make lint` |
| Unit test | **2 548 090 checks**; runs three instances at `N_UC` 1, 2 and 3 | `verif/unit/tb_s1_wb_stage.sv` |
| Mutation | 30 hand-inserted bugs, 30 caught | table below |
| Integration, co-simulation, arch tests | not yet | needs #18, R-01's completion buffer and the rest of the core |

The testbench plays MEM, the multi-cycle units, the completion buffer, retire and ID. The reference
model is written independently of the RTL: a test case is an abstract statement of what the
instruction did, rendered twice with no shared code — once into the `mem_wb_t` MEM would have built,
once into the completion-buffer write SPEC §9.1 and §9.2 require. The arbiter model keeps its own
rotation pointer, advanced by the rule the module documents rather than copied from the DUT, because
a pointer read out of the RTL would agree with a broken arbiter too.

- **Exhaustive over the control space.** All 256 combinations of `wb_valid_i`, `flush_i`,
  `complete`, `exc`, `rd_we`, `rd == x0`, `csr_we` and `sb_alloc`, 48 times each with independent
  random payloads and random unit traffic alongside.
- **Exhaustive over the forwarding bus.** Every destination register 0–31, writing and not,
  trapping and not, 8 payloads each — and on every one the bus is checked against the value the
  completion buffer is told to write, including every case where it must read zero.
- **Three instances at `N_UC` 1, 2 and 3** run the same stimulus, each checked against its own
  modelled rotation, so nothing here depends on the channel count (R-V2).
- **Directed, main pipe.** One completion of each class with the fields that matter checked by name;
  x0; traps; MXIF candidates both untouched and faulted; flush; a store-buffer entry surviving an
  exception; every completion-buffer index addressable.
- **Directed, units.** A unit result writes `done`, `norollback`, `rd` and `result` and **nothing
  else** — `from_main` clear and the whole pass-through group zero. The main pipe wins contention
  and both units hold. The grant rotates: over eight contended cycles exactly one unit is accepted
  each cycle and the two alternate. A flush drains both units, writes nothing, and is not counted as
  a stall.
- **Every case.** A main-pipe completion is written or flushed in the cycle it is offered — the
  property that stands in for a liveness check on a channel with no handshake. `uc_ready_o` is
  checked against the modelled grant on every channel every cycle. `wb_i` is ignored entirely while
  `wb_valid_i` is low. The completion-buffer write is independent of the operand read addresses,
  checked on every case against the value written. Each `N_UC` instance is checked against its own
  grant, not against the others.
- **Random soak.** 60 000 cases with the main pipe and both units contending, 10% flushed. The last
  run: register writes 30 942, x0 5 689, traps 6 684, MXIF candidates 3 163 (1 329 faulted),
  store-buffer allocations 6 643, bypass one port 9 106 / both 2 936 / neither 18 900, unit grants
  15 225 split 7 552 / 7 673 between the two channels with 9 732 alternations, unit results blocked
  30 545, both units contending 14 006, units drained by a flush 8 263.

Mutants, each a lint-clean copy of `s1_wb_stage.sv` with one change:

| Mutant | Bug injected | Caught by |
|---|---|---|
| x0 forwarded | `rd != 0` dropped from the main-pipe write condition | `upd.rd_we` |
| trap writes rd | `~exc` dropped from the write condition | `upd.rd` |
| CSR survives trap | `~exc` dropped from `csr.we` | `upd.csr.we` |
| CSR write gated on rd_we | `csr.we` also requires a register write | `upd.csr.we` |
| flush ignored on the main pipe | `~flush_i` dropped from the main-pipe grant | `cb_we` |
| resolved uses xor not or | `complete ^ exc` — a trapping instruction is dropped | `cb_idx` |
| faulted candidate dropped | an MXIF candidate that trapped is never resolved | `cb_idx` |
| sb_alloc gated on exc | the defensive gate that strands a store-buffer entry | `upd.sb_alloc` |
| rd leaks when not writing | `rd` passed through when the instruction writes nothing | `upd.rd` |
| result leaks when not writing | `result` passed through likewise | `upd.result` |
| norollback cleared | main-pipe completion marked rollback-able (SPEC §9.1) | `upd.norollback` |
| RVFI masks swapped | `rmask` and `wmask` exchanged | `upd.rvfi.rmask` |
| RVFI data swapped | `rdata` and `wdata` exchanged | `upd.rvfi.rdata` |
| mtval and pc_wdata swapped | `exctval` and `next_pc` exchanged | `upd.next_pc` |
| wrong entry addressed | main-pipe `cb_idx` off by one | `cb_idx` |
| forwarding bus not gated on a grant | the `uc_go` term dropped, so the bus carries a channel's value in cycles when nothing is accepted | `fwd_data` |
| forwarding bus bypasses the gating | `fwd_data_o` driven from the raw selected result | `fwd_data` |
| unit result writes x0 | the x0 gate dropped on the unit path only | `upd.rd_we` |
| unit entry misaddressed | a unit's `cb_idx` xored with 1 | `cb_idx` |
| a unit outranks the main pipe | the port is offered to a unit while MEM is presenting | `uc_ready[1]` |
| unit accepted while the main pipe holds the port | `uc_ready_o` ignores who has the port | `uc_ready[1]` |
| flush does not drain the units | a unit is left holding a result for a flushed entry | `uc_ready[0]` |
| grant does not rotate | the rotation pointer never advances: fixed priority | `cb_idx` |
| rotation stops on the granted channel | pointer set to the winner instead of past it | `upd.rd` |
| two units granted at once | the first-match guard dropped from the arbiter | `upd.rd` |
| unit result claims the main pipe's fields | `from_main` tied 1 | `upd.from_main` |
| unit result carries MEM's pass-through group | the `from_main` guard dropped around the group | `upd.next_pc` |
| unit bypass uses the main pipe's rd | `sel_rd` never switches to the unit | `upd.rd` |
| unit result value from the main pipe | `sel_result` sources inverted | `upd.result` |
| stall reported during a flush | `uc_stall_o` not suppressed by `flush_i` | `uc_stall` |

**A testbench bug worth repeating.** The first version drew each operand read address as
`(($urandom % 100) < 35) ? rd : REG_ADDR_W'($urandom)`. Verilator 5.036 hoists a `$urandom` call
out of a conditional expression, and consecutive read addresses came out equal 95% of the time
instead of 37% — so the two-port case the bypass most needs, one port hitting while the other
misses, was generated 1 781 times in 120 000 rather than 20 638. Every check passed throughout; the
testbench had simply stopped testing what it claimed to. Anything random in these files is now drawn
into a named variable before it is used. `tb_s1_mem_stage` (#18) has the same pattern in `rand_ins`
(instruction class, width and address) and in `pmp_fuzz`; its coverage bins are all still hit, but
the distribution behind them should be re-measured before that number is quoted as a soak result.

## Known limitations

- **One completion per cycle.** With the main pipe and two units all presenting, two results wait.
  That is the right trade at this width — a second completion-buffer write port costs an entire
  extra write path through an 8-entry × ~200-bit array to serve a case that needs MUL and DIV and a
  load all finishing together — but it is a parameter of the design, not a law. If `uc_stall_o`
  shows up in a profile, a second port is the answer.
- **`cb_upd_o` is a subset of `cb_entry_t`, not the entry.** `valid`, `pc`, `instr`, `is_mxif`,
  `mxif_id` and `unit` are ID's and are not touched here. `wb_upd_t` exists because R-01 owns
  `cb_entry_t` and this module should not pre-empt its shape.
- **Combinational into the completion buffer, and on MEM's critical path.** `s1_mem_stage` already
  lists `I2 rdata → merge → extend → wb_o` as a critical path; this module adds the source mux, the
  x0/exception gate and the bypass comparators on top of it. If it does not meet timing, the fix is
  not to register this module — that would cost a forwarding bubble on every load — but to register
  MEM's extend stage and accept the extra cycle there.
- **The forwarding bus has no valid bit.** If ID selects `FWD_MEMWB` in a cycle where nothing
  completes, EX reads zero and nothing says so. Zero beats leaving the previous value because it is
  at least deterministic, but the real answer is that the hazard unit must not make that select —
  and whoever integrates this should assert it rather than trust it. See the open question raised
  on #15: MEM's completion latency is variable, so "the instruction in the EX/MEM register will be
  on this bus next cycle" is not something ID can assume.
- **The bypass does not know about age**, because it answers for one completion and there is nothing
  to arbitrate. SPEC §8.1's other three sources are ordered by whoever combines them, which is the
  hazard unit's job, not this module's.
- **Nothing here checks that a unit's `cb_idx` names a live entry.** A unit that answers for an
  entry that was flushed writes a stale value into whatever now occupies that index. The completion
  buffer can catch it — it knows which entries are allocated — and the flush drain makes it unlikely,
  but the check belongs at the far end and R-01 should add it.
- Tested at `XLEN = 64`, `CB_DEPTH = 8`, `N_UC` 1, 2 and 3.

## Open questions

1. **SPEC §7.5's first bullet is wrong, or §6's second decision is.** "Register file writeback for
   main-pipe instructions" at WB cannot coexist with "all architectural state updates happen at the
   retire pointer" and §9.2 step 1. This module implements the §6/§9.2 reading. If that is right,
   §7.5 should say "result writeback into the completion buffer entry" — a one-line spec fix, and
   worth making before three more people read it the other way.
2. **Does `md_rsp_t` belong to this module or to #15?** #15 defines `md_req_t`, the dispatch leg.
   The response leg is defined here because nothing in #15 consumes it, but the pair should live
   together — most naturally in #15, with this module rebasing onto it as it already does for
   `mem_wb_t`.
3. **Does retire need to distinguish "no register write" from "wrote x0"?** WB erases the
   difference, which is what RVFI wants. If the debug module ever wants to show the instruction's
   nominal destination, the entry needs the ungated `rd` as well.
4. **Who marks an MXIF candidate's entry when the coprocessor rejects it?** §9.2 says the rejection
   becomes an illegal-instruction trap, but the entry is at the head by then and has already passed
   WB. R-01's offload path has to write it, not this module — confirm when the MXIF port lands.
