# `s1_fetch`

| | |
|---|---|
| **Status** | WIP (unit-verified; waiting on ratification of the fetch interface, then integration) |
| **Owner** | Ayesha Anwar (@ayeshaanwaar05) |
| **Backup** | _(assign at the T-01 design review)_ |
| **Project** | T-01 (core frontend) |
| **Spec** | SPEC §6, §7.1, §8.2; INTERFACES.md §2 (I2 MEM-REQ) |
| **Source** | `rtl/core/s1_fetch.sv`; instantiates `s1_rvc_expand` ([page](s1_rvc_expand.md), separate PR) |
| **Testbench** | `verif/unit/tb_s1_fetch.sv`: 326 434 checks |

## Purpose

The IF stage. It generates the PC, fetches instruction words from the I$ over I2 MEM-REQ, realigns
16- and 32-bit instructions out of the fetch-word stream, expands compressed instructions, applies
static BTFN prediction, and hands one instruction per cycle to ID. Everything that must change when
someone replaces the branch predictor or the I$ lives here, behind the interface below. SPEC §6 calls
this the property that turns a v2 predictor into a bounded thesis project instead of a pipeline
rewrite.

## Interface contract

### How this maps onto SPEC §6 `fetch_req` / `fetch_rsp`

SPEC §6 says the frontend "sits behind a `fetch_req`/`fetch_rsp` interface", but INTERFACES.md does
not define that interface (see *Open questions*). This module proposes:

- **`fetch_rsp`** is the instruction stream to ID: `fetch_rsp_valid_o` / `fetch_rsp_ready_i` /
  `fetch_rsp_o`, with the payload type `fetch_rsp_t` in `s1_pkg`.
- **`fetch_req`** is the backend's commands to the frontend: the two redirect inputs and `priv_i`.
- The **I$ side** is a plain I2 MEM-REQ port (`imem_*`), exactly as INTERFACES.md §2 specifies,
  with no local amendments.

### Ports

| Signal | Dir | Width | Meaning | Contract |
|---|---|---|---|---|
| `clk_i` | in | 1 | clock | single domain |
| `rst_ni` | in | 1 | reset | async assert, sync de-assert (R-C4) |
| `ex_redirect_valid_i` | in | 1 | EX found a mispredict | flushes IF/ID in the same cycle; see *Redirects* |
| `ex_redirect_pc_i` | in | `XLEN` | correct next PC | bit 0 ignored |
| `retire_redirect_valid_i` | in | 1 | trap, xRET, `fence.i`, debug entry/exit | beats EX in the same cycle |
| `retire_redirect_pc_i` | in | `XLEN` | vector / `mepc` / `dpc` / `pc+4` | bit 0 ignored |
| `priv_i` | in | `priv_lvl_e` | effective fetch privilege | copied into every new request; **must change only at the edge that ends a retire-redirect cycle**; drive `PRIV_M` in debug mode |
| `imem_req_valid_o` | out | 1 | I2 request | never a function of any `ready` input |
| `imem_req_ready_i` | in | 1 | I2 grant | may depend on `valid` (I2 allows a single-cycle grant) |
| `imem_req_o` | out | `mem_req_t` | I2 payload | `addr` word-aligned, `we=0`, `size=2` (4 B), `be` selects the word's lane, `mode=priv_i`, `id=0`; **stable while `valid && !ready`** |
| `imem_rsp_valid_i` | in | 1 | I2 response | only while a request is outstanding; in request order |
| `imem_rsp_ready_o` | out | 1 | | **constant 1**; space is reserved at issue |
| `imem_rsp_i` | in | `mem_rsp_t` | I2 response payload | `rdata` byte-lane aligned; `err=1` means access fault; `id` and `errcode` are ignored |
| `fetch_rsp_valid_o` | out | 1 | instruction for ID | registered |
| `fetch_rsp_ready_i` | in | 1 | ID accepts | |
| `fetch_rsp_o` | out | `fetch_rsp_t` | instruction bundle | registered; fields below |

### `fetch_rsp_t` (in `s1_pkg`)

| Field | Meaning |
|---|---|
| `pc` | address of the instruction's first parcel |
| `instr` | the 32-bit encoding ID decodes. Compressed instructions are already expanded (SPEC §7.1). All-zero when `exc` |
| `instr_raw` | the bits as fetched; a 16-bit parcel is zero-extended. RVFI's `rvfi_insn` and `mtval` for illegal instructions need this, and it cannot be recovered from `instr` |
| `compressed` | the sequential successor is `pc+2`, not `pc+4` (link address, `rvfi_pc_wdata`) |
| `pred_taken` | the frontend has already redirected to the PC-relative target. EX redirects iff the real outcome differs |
| `exc`, `exccode` | fetch-time exception: `EXC_INSTR_ACCESS_FAULT` or `EXC_ILLEGAL_INSTR`. ID must give it priority over whatever `instr` decodes to |
| `exctval` | `mtval`: the faulting *portion's* address for an access fault; the parcel bits for an illegal instruction |

### Handshakes

- **I2 (`imem_*`):** INTERFACES.md §2 and R-C10. `valid` does not depend on `ready`, and the payload
  is held until accepted. At most one request is outstanding, and a new request may be issued in
  the cycle its predecessor's response arrives, so a 1-cycle I$ sustains one word per cycle. A
  redirect cannot retarget a request that is already presented. That request is completed and its
  response dropped.
- **`fetch_rsp`:** valid/ready, registered. Once asserted, `valid` and the payload are held until
  `ready`, **with one exception: a redirect withdraws `valid` without a handshake.** That is safe
  because ID is flushed by the same redirect. Likewise, **any transfer in a cycle where either
  redirect is asserted is wrong-path, and ID must discard it.**

### Latency (with a 1-cycle I$)

| Event in cycle *t* | Target instruction presented to ID | Cycles lost | vs. SPEC §8.2 |
|---|---|---|---|
| `ex_redirect_valid_i` | *t*+2 | 2 | matches "branch mispredict: 2" |
| `retire_redirect_valid_i` | *t*+3 | 3 | inside "trap/interrupt: 3–4" |
| BTFN predicted-taken branch presented at *t* | *t*+2 | 1 | |
| Sequential stream | every cycle | 0 | 1 instruction/cycle at every alignment |

**Backpressure:** when ID stalls, the realign buffer fills and requests stop. At most
`FETCH_BUF_HW/2 + 1` requests are accepted after the stall begins. The I$ request path never waits
on `fetch_rsp_ready_i`, which keeps ID's hazard logic out of the I$ address timing.

**Reset state:** `fetch_rsp_valid_o = 0`; the first request, to `RESET_PC` in M-mode, is presented
in the first cycle after reset.

## Parameters

| Parameter | Default | Legal range | Effect |
|---|---|---|---|
| `RESET_PC` | `s1_pkg::BOOT_ADDR` | any parcel-aligned address | first fetch address; a constant, so the reset value is constant (an input-driven async-reset value is not synthesisable cleanly) |
| `FETCH_BUF_HW` | 6 | ≥ 4 (elaboration error below) | realign-buffer capacity in 16-bit parcels. 4 guarantees progress but halves throughput on word-straddling 32-bit streams; 6 sustains one instruction per cycle at every alignment |

## Behaviour

```
             ex / retire / BTFN redirect
                        │
   pc_q ──► next_pc ──►─┴─► imem_req (I2) ──► I$ ──► imem_rsp
                                                        │ 32-bit word, 1 or 2 parcels
                                                        ▼
                         realign buffer  [p0 p1 p2 p3 p4 p5]  (+ this cycle's response = "window")
                                                        │ head: 1 parcel (C) or 2 (32-bit)
                                                        ▼
                             s1_rvc_expand ──► BTFN check ──► IF/ID register ──► ID
                                                                   │
                                        predicted taken: next cycle, pc + imm ──┘
```

**Realign buffer.** Responses are split into 16-bit parcels, each tagged with its word's `err`.
The head instruction is carved from a *window*: the registered buffer with this cycle's response
appended. Carving from the window rather than from the register is what lets a response reach the
IF/ID register in the cycle it arrives. Without it the mispredict penalty would be 3. A 32-bit
instruction straddling two fetch words is not a special case, because it is just two parcels. After
a redirect to `pc[1] = 1`, the first word's low parcel is dropped at push.

**Credit rule.** A request is issued only if
`parcels buffered + 2·(fresh response pending) + 2 ≤ FETCH_BUF_HW`. Pops are not credited. That is
what keeps `fetch_rsp_ready_i` out of the request path, and it is also why the response port can
be constant-ready.

**Held and stale requests.** A presented-but-unaccepted request is frozen in `hold_req_q` (R-C10).
A redirect marks it stale rather than changing it. A redirect while a response is in flight marks
that response stale. Stale responses are dropped, and the target request goes out as soon as the
single outstanding slot frees.

**Redirect timing.** This is the design note T-01 asks for, in short:

```
EX mispredict (1-cycle I$)
cycle          t          t+1        t+2        t+3
EX             branch     (flushed)  bubble     target
ex_redirect    1
imem_req       target
imem_rsp                  target ──► IF/ID
ID             wrong-path  --        target
```

- *EX redirect*: combinational into the request address in cycle *t*. The one long path this
  creates (EX compare → `imem_req_o.addr`) is the price of SPEC §8.2's penalty of 2. It is the same
  choice Ibex makes.
- *Retire redirect*: registered. Nothing is issued in cycle *t*, and the target goes out at *t*+1.
  This costs one cycle on a rare event and buys a correct `mode` on the first request: `mret` to
  U-mode updates `priv_i` at the edge ending *t*, so a combinational redirect would fetch the first
  U-mode word with M-mode PMP permissions. It also gives the I$ a free cycle to see a `fence.i`
  invalidate before the refetch arrives.
- *BTFN*: predicted from the registered IF/ID contents in the cycle after the branch is registered.
  That costs one bubble, but keeps the immediate adder out of the path from I$ data to I$ address.

**BTFN.** A conditional branch is predicted taken iff `instr[31]` (the sign of its offset) is set.
`JAL` is always predicted taken: it is unconditional and its target is exact, and predicting a
forward `JAL` not-taken would guarantee a mispredict on every forward call. `JALR` is not predicted,
because its target is unknown in IF. Prediction runs on the expanded instruction, so `C.J`,
`C.BEQZ` and `C.BNEZ` are predicted like their 32-bit forms.

**Halt after a fault.** Once an instruction with `exc` is loaded into IF/ID, fetch stops requesting
and delivering until the next redirect. Everything after it is dead, and fetching it only spends
I$ and bus bandwidth. The trap itself arrives as a retire redirect and restarts the frontend.

## Exceptions and errors

| Condition | `exccode` | `exctval` (`mtval`) | `pc` (`mepc`) |
|---|---|---|---|
| `err` on the word holding the first parcel | `EXC_INSTR_ACCESS_FAULT` | `pc` | `pc` |
| 32-bit instruction, `err` only on the word holding its second parcel | `EXC_INSTR_ACCESS_FAULT` | `pc + 2` | `pc` |
| reserved compressed encoding | `EXC_ILLEGAL_INSTR` | the 16-bit parcel, zero-extended | `pc` |

Precision is automatic: the exception travels with its instruction and is taken at retire, so a
fault on a wrong-path fetch is simply flushed. Fetch never raises
instruction-address-misaligned: `IALIGN = 16` with C always present, and bit 0 of every redirect
target is dropped. There are no page faults in v1 (no MMU); see open question 3.

## Verification status

| Layer | Status | Where |
|---|---|---|
| Lint | clean, no waivers, all four configs | `make lint` |
| Unit test | **326 434 checks.** Every instruction delivered is scoreboarded against a reference model that walks the memory image with the golden expander and golden BTFN (20 983 instructions). Protocol properties are checked every cycle. Counts are from Verilator 5.020, the CI version; they shift slightly with the simulator's random stream. | `verif/unit/tb_s1_fetch.sv` |
| Mutation | 12 hand-inserted bugs, 12 caught (table below) | |
| Co-simulation | not yet; covered once R-05 lands | |
| Formal | not yet. Good candidates: payload stability, ≤1 outstanding, credit invariant | T-07 |

What the testbench covers:

- **Directed.** Reset vector and mode; 1 instruction/cycle for aligned 32-bit, compressed, and
  word-straddling 32-bit streams; exact EX / retire / BTFN penalties against SPEC §8.2; backward
  branch, forward branch, forward `JAL`, `JALR` and compressed-branch prediction; illegal parcel,
  first-parcel fault and second-parcel fault (`mtval`), with no delivery and no new request after
  the fault; a redirect while a request is held; a redirect with a response in flight; EX and
  retire in the same cycle; back-to-back redirects; the request bound under a 50-cycle ID stall.
- **Random soak.** 3 × 20 000 cycles (ideal / busy / starved I$ and ID), random images with 1–2 %
  faulting words, random EX and retire redirects to any parcel, and privilege changes at retire.
  Coverage counters (compressed, straddling, predicted-taken, fault, illegal, redirect-while-held,
  stale response, simultaneous redirects) must all be non-zero.
- **Every cycle.** `valid` independent of `ready` on both handshakes (probed by toggling `ready`
  within the cycle); payload stability; ≤ 1 I2 request outstanding; fields of every fresh request;
  `imem_rsp_ready_o` high; a watchdog on forward progress.

Mutants, each built from a copy of `s1_fetch.sv` with one line changed:

| Mutant | Bug injected | Caught by |
|---|---|---|
| no stale mark | redirect with a response in flight does not mark it stale | scoreboard |
| JAL by sign | forward `JAL` predicted not-taken (the first version's behaviour) | scoreboard (`pred_taken`) |
| BTFN no flush | a taken prediction does not flush the realign buffer (the first version's bug) | scoreboard |
| hold unstable | a held request follows `next_pc` instead of staying frozen | R-C10 stability check |
| tval of 2nd parcel | second-parcel fault reports `mtval = pc` | scoreboard (`exctval`) |
| no halt | keeps fetching past a faulting instruction | "no request past a fault" check |
| no credit | issues without reserving buffer space | throughput check, then scoreboard |
| lane 0 | always takes `rdata[31:0]` (the first version's bug) | scoreboard |
| retire combinational | issues in the retire-redirect cycle | scoreboard |
| valid on ready | `imem_req_valid_o` gated by `imem_req_ready_i` | reset-vector check, then R-C10 probe |
| no skip | redirect to `pc[1] = 1` keeps the preceding parcel | scoreboard |

A twelfth mutant, removing the flush gate on the response push, survived. It turned out to be
equivalent (the flush empties the buffer at the same edge anyway), so the redundant term was
removed from the RTL.

## Known limitations

- **One outstanding I2 request** (I2's v1 rule). With an I$ hit latency above one cycle, throughput
  is one word per hit latency.
- **`JALR` always costs a mispredict**, and returns are `JALR`s. A return-address stack is the
  obvious first v2 predictor improvement.
- **The I$ invalidate for `fence.i` is not routed through this module.** Retire drives the I$
  directly. Correctness needs the I$ to refuse (`ready = 0`) requests until the invalidation is
  done. The registered retire redirect gives it one cycle's head start.
- `errcode` is ignored; every fetch error is an access fault.
- Tested only at `XLEN = 64`, `FETCH_BUF_HW = 6`.

## Open questions

1. **`fetch_req`/`fetch_rsp` is not defined in INTERFACES.md.** SPEC §6, SPEC §7.1, `rtl/core/README.md`
   and catalogue T-01 ("matches INTERFACES.md with no local amendments") all refer to it. §6 places
   it between frontend and decode ("predictor and I$ can be replaced without touching decode"),
   while §7.1 says "I$ access via `fetch_req`/`fetch_rsp`". This module takes the §6 reading. It needs
   a ruling and an INTERFACES.md section before the frontend can be called complete.
2. **Predictor training channel.** BTFN needs no feedback, but any dynamic predictor needs branch
   outcomes from EX. If the swappable-predictor promise is to hold "without touching the pipeline",
   the outcome port should exist from v1, just as the MXIF commit channel does (R1.3).
3. **I2 `errcode` encoding** is undefined. Phase 5 needs at least access-fault vs page-fault.
4. **I2 byte-lane convention** for a 4-byte request on a 64-bit port is not stated. This module
   assumes AXI-style lanes (byte *A* on lane *A* mod 8); the I$ and D$ must agree.
5. **`cb_entry_t` has one `instr` field**, but RVFI needs the raw bits and MXIF needs the expanded
   ones. The completion buffer needs `instr_raw` (or `compressed` plus the parcel) as well.
