# `s1_regfile`

| | |
|---|---|
| **Status** | COMPLETE |
| **Owner** | @Ammarahwakeel |
| **Backup** | _(assign at Phase-0 review)_ |
| **Project** | T-02 (core backend: decode, register file) |
| **Spec** | SPEC §6, §7.2, §9.2, §17; `specs/INTERFACES.md` §8 |
| **Source** | `rtl/core/s1_regfile.sv` |
| **Testbench** | `verif/unit/tb_s1_regfile.sv` — 10180 checks |

## Purpose

The integer register file: `2**REG_ADDR_W` registers of `XLEN` bits, with `x0` reading as zero,
`N_READ` read ports and one write port. It holds architectural state only; forwarding and hazard
detection (SPEC §8) are the hazard unit's job.

## Interface contract

| Signal | Dir | Width | Meaning | Contract |
|---|---|---|---|---|
| `clk_i` | in | 1 | clock | single domain |
| `rst_ni` | in | 1 | reset | async assert, sync de-assert; does **not** clear the registers |
| `raddr_i` | in | `[N_READ-1:0][REG_ADDR_W-1:0]` | read addresses, one per port | sampled every cycle |
| `rdata_o` | out | `[N_READ-1:0][XLEN-1:0]` | read data, one per port | for the address presented in the **previous** cycle |
| `we_i` | in | 1 | write enable | asserted at retire (SPEC §9.2 step 1) |
| `waddr_i` | in | `REG_ADDR_W` | write address | a write to `x0` is discarded |
| `wdata_i` | in | `XLEN` | write data | |

**Handshake:** none. Reads and the write are accepted every cycle and never stall.
**Latency:** one cycle, registered (R-C5). Address in cycle *n*, data in cycle *n+1*.
**Backpressure:** none. To hold a value, hold the address — see below.
**Reset state:** `rdata_o` is not meaningful until one cycle after reset. Register contents are
undefined until written; the ISA does not require otherwise.

### What the caller must do

- **Present the address one cycle early.** `raddr_i` carries the `rs1`/`rs2` fields of the
  instruction that will be in ID in the *next* cycle, so the read happens at the IF/ID boundary and
  the data is there when ID needs it. The fields must come from the 32-bit expanded instruction.
- **Keep presenting the address while ID is stalled.** The read is repeated every cycle, so the data
  keeps tracking writes that retire during the stall.

### What the caller may assume

`rdata_o` is always the architectural value of the register as of the current cycle. A write is
visible to a read whether it arrives in the cycle the address was presented or in the cycle the data
is used. A write retiring in the same cycle as its consumer is in ID is therefore already in
`rdata_o`; the hazard unit does not need to forward it.

## Parameters

| Parameter | Default | Legal range | Effect |
|---|---|---|---|
| `N_READ` | 2 | ≥ 1 | number of read ports (CODING_STANDARD §2) |

## Behaviour

### Storage: two single-port banks per read port

R-C5 puts the register file behind `meds_s1_sram`, which has **one** port and a one-cycle registered
read. A read port is busy every cycle and a write can arrive every cycle, so one memory per read
port is not enough: it would have to read and write in the same cycle.

Each read port therefore owns two banks and a one-bit-per-register pointer, `cur_q`, naming the bank
that holds each register's current value.

- A **read** of register *r* uses bank `cur_q[r]`.
- A **write** in the same cycle goes to the *other* bank of that port and repoints `cur_q` for the
  written register.

No bank ever sees two accesses in one cycle, and nothing stalls. The cost is `2 × N_READ` memories
of `2**REG_ADDR_W × XLEN` bits (four, at the default) and `N_READ × (2**REG_ADDR_W − 1)` pointer
flops (x0 needs none).

### Read data, newest first

1. `x0` reads zero. The memories are not reset, so this is forced on the read side.
2. A write presented **this** cycle to the register being read: `wdata_i`.
3. A write presented **last** cycle, together with the read address: `meds_s1_sram` returns the old
   word on a read-during-write, so last cycle's write is kept in a register and bypassed.
4. Otherwise, the data from the bank that was read.

```
cycle        n          n+1         n+2
raddr_i      r          .           .
rdata_o      .          value(r)    .
write at n   -> case 3 (bypassed from the registered copy)
write at n+1 -> case 2 (bypassed from wdata_i)
```

## Exceptions and errors

None. This module cannot fault.

## Verification status

| Layer | Status | Where |
|---|---|---|
| Lint | clean on all four configs | `make lint CONFIG=<name>` |
| Unit test | **10180 checks** against a shadow register file: `x0`, read-back of every register on every port, both write bypasses, a held address across back-to-back writes, and a 5000-cycle soak with reads on every port every cycle and writes on most | `make test-unit TB=s1_regfile` |
| Co-simulation | not yet — needs the core integrated (R-05) | |
| Formal | not yet | |

## Known limitations

- **Four memories for a 32-entry register file.** That is the cost of a single-port wrapper with no
  stall.
- **`rdata_o` has a combinational path from `wdata_i`** (step 2 of the read order), so retire-to-ID
  is a timing path.
- **Register contents are undefined until written.** Simulation shows whatever the memory model
  initialises to.

## Open questions

- **Dual-port wrapper.** `docs/modules/meds_s1_sram.md` leaves the choice to R-03. With one, each
  read port needs a single memory and no pointer; the ports of this module would not change.
- **Early read address.** The ID stage must drive `raddr_i` from the instruction leaving IF, after
  RV64C expansion, so fetch has to expose those register fields a cycle ahead of the ID register.
