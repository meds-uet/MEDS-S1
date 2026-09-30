# `s1_regfile`

| | |
|---|---|
| **Status** | WIP -- T-02 |
| **Owner** | @Ammarahwakeel |
| **Backup** | _(assign at Phase-0 review)_ |
| **Project** | T-02 (decode stage, register file) |
| **Spec** | SPEC §6, §7.2, §8.1, §9.2 |
| **Source** | `rtl/core/s1_regfile.sv` |
| **Testbench** | `verif/unit/tb_s1_regfile.sv` — 10028 checks |

## Purpose

The 32x64 integer register file for the ID stage, sitting between `s1_decode.sv` and
`s1_execute.sv` in the pipeline. It has two jobs, both from SPEC §7.2's ID-stage list ("register file read (2 ports) ... forwarding-source
selection"), as split between modules by PR #4's `docs/modules/s1_decode.md`:

1. **Storage and reads.** Two read ports (`rs1`, `rs2`), one retire-time write port (SPEC §9.2
   step 1, "architectural register file write, if `rd_we`"). `x0` is hardwired to zero: reads of it
   always return zero, writes to it are discarded.
2. **Forwarding-source selection**, the first half of SPEC §8.1's four-source network. For each of
   `rs1`/`rs2` this module decides which of {register file, EX/MEM, MEM/WB, completion buffer} EX
   should read its operand from. It does **not** resolve that choice into a value -- the value itself
   is either this module's own raw read (`FWD_RF`), or one EX pulls from elsewhere (`FWD_EXMEM` from
   EX's own EX/MEM register, `FWD_MEMWB`/`FWD_CB` from ports on `s1_execute.sv` driven by
   `s1_mem_stage.sv` and `s1_completion_buffer.sv`, matching PR #15's already-built
   `memwb_fwd_i`/`cb_rs1_fwd_i`/`cb_rs2_fwd_i` ports). Splitting the *selection* from the *mux* this
   way is what SPEC §8.1's diagram and PR #15's RTL already agree on; see Known limitations for the
   one place that still needs the architect's ruling.

## Interface contract

| Signal | Dir | Width | Meaning | Contract |
|---|---|---|---|---|
| `clk_i` / `rst_ni` | in | 1 | clock / reset | single domain; async assert, sync de-assert |
| `rs1_addr_i` / `rs2_addr_i` | in | `REG_ADDR_W` | `decoded_op_t.rs1` / `.rs2` | combinational; no `valid` -- this module is always "on" |
| `rs1_val_o` / `rs2_val_o` | out | `XLEN` | raw register value | same-cycle write-bypassed (see Behaviour); zero for `x0` regardless of storage contents |
| `rs1_fwd_o` / `rs2_fwd_o` | out | `fwd_src_e` | which source EX should use | `FWD_RF` for `x0` unconditionally, even if some in-flight entry's `rd_we` happens to be set for `rd==x0` (`s1_decode.sv` does not special-case `x0`) |
| `rd_we_i` / `rd_addr_i` / `rd_wdata_i` | in | 1 / `REG_ADDR_W` / `XLEN` | retire-time architectural write | driven by the completion buffer (SPEC §9.2 step 1); a write to `x0` is silently discarded |
| `ex_valid_i` / `ex_rd_i` / `ex_rd_we_i` | in | 1 / `REG_ADDR_W` / 1 | instruction currently in EX | SPEC §8.1's EX/MEM bypass source; ignored unless `ex_valid_i` |
| `mem_valid_i` / `mem_rd_i` / `mem_rd_we_i` | in | 1 / `REG_ADDR_W` / 1 | instruction currently in MEM | SPEC §8.1's MEM/WB bypass source; ignored unless `mem_valid_i` |
| `cb_rs1_hit_i` / `cb_rs2_hit_i` | in | 1 | completed-but-not-retired CB entry exists for rs1/rs2 | provisional query into `s1_completion_buffer.sv` -- see Known limitations |

**Handshake:** none. Every input is sampled combinationally every cycle; there is no `valid`/`ready`
because this module never stalls on its own account.
**Latency:** `rs1_val_o`/`rs2_val_o`/`rs1_fwd_o`/`rs2_fwd_o` are combinational functions of this
cycle's inputs. The write itself commits on the next clock edge.
**Backpressure:** none; not applicable.
**Reset state:** all 32 registers cleared to zero (real hardware would not need this -- `x0` is the
only register architecturally guaranteed zero -- but it costs nothing in the behavioural model and
keeps the testbench's shadow model exact).

## Parameters

None. Widths come from `s1_pkg` (`REG_ADDR_W`, `XLEN`).

## Behaviour

**Write happens at retire, not WB.** SPEC §7.5 lists "register file writeback" under WB, but §6
(decision 2) and §9.2 step 1 put every architectural write at the retire pointer. This module follows
§6/§9.2, the same reading as PR #15 (execute, open question 4) and PR #21 (WB writes the CB entry,
not the register file); the write port is therefore driven by the completion buffer.

**Same-cycle write-read bypass.** A retire-time write and a decode read of the same address in the
same cycle must return the new value, not the value the storage holds until the next edge --
otherwise an instruction retiring the same cycle its immediate successor is decoded would read a
stale operand. `read_port()` checks `rd_we_i && rd_addr_i == addr` before falling back to storage.

**Forwarding-source priority: EX/MEM > MEM/WB > CB > RF.** A more recently issued producer always
shadows an older, not-yet-retired one to the same register. The instruction in EX is the youngest
possible in-flight producer (closest, in program order, to the instruction now in ID); the
instruction in MEM is older; a completed CB entry could be older still (a MUL/DIV/MXIF result that
finished after the main pipe moved on). See `select_fwd()`.

**Why EX doesn't need a stall check here.** SPEC §8.2's load-use hazard ("RAW, load in MEM
(load-use) -> stall 1"; in this module's timing, a load in EX while its consumer is in ID, because
the D$ access hasn't happened yet) is a **stall** decision, which PR #4's `docs/modules/s1_decode.md`
assigns to `s1_completion_buffer.sv`'s hazard/stall table, not to this module. This module's comparison logic doesn't special-case loads at all -- it assumes that if a
load-use hazard exists, the stall unit has already held decode for a cycle before this module is
asked to resolve `rs1_fwd`/`rs2_fwd` for that instruction, by which point the load has moved from EX
to MEM and the ordinary MEM/WB path applies.

## Exceptions and errors

None. This module cannot fault.

## Verification status

| Layer | Status | Where |
|---|---|---|
| Lint | clean | `make lint` |
| Unit test | **10028 checks** -- x0 semantics (read-as-zero, write-discarded, both directly and through the same-cycle bypass), write/read timing across a cycle boundary, reset, every forwarding-source priority combination and its negative (not-valid, not-rd_we) case, independent per-operand source resolution, and a 5000-cycle random soak against a behavioural shadow register file | `verif/unit/tb_s1_regfile.sv` |
| Co-simulation | not applicable at this level | |
| Formal | not yet | |

## Known limitations

- **`make check` currently fails this file's structure check (rule S7 / R-C5).** Storage is a plain
  `always_ff`-driven array, not routed through `meds_s1_sram`. This is not an oversight -- it is a
  direct consequence of an already-documented, unresolved project question. `docs/modules/
  meds_s1_sram.md`'s own "Open questions" section states: *"Does the register file duplicate this
  wrapper for its second read port, or do we add a dual-port variant? ... R-03 owns this."*
  `meds_s1_sram` is single-port with one-cycle registered read latency and no same-cycle
  different-address read+write. A register file needs, every cycle in the general case, two
  independent reads (`rs1`, `rs2`) *and* one write (retire) to three potentially different addresses
  -- which duplicating the wrapper across two instances does not by itself resolve (each instance
  still has only one address bus, so a write to one address and a read of a different address cannot
  share one instance's port in the same cycle). Solving this correctly needs either a dual-port SRAM
  variant (`meds_s1_sram_dp`, not built) or a stall path on every same-cycle address conflict, which
  would regress a register write into a pipeline bubble on or near every retiring instruction --
  exactly the cost R-03 is meant to weigh. I did not pick one unilaterally. Until R-03 resolves this,
  this module should be treated as WIP, and `make check`'s S7 finding on this file as expected, not a
  bug to silently waive.
- **The CB hazard-snoop interface (`cb_rs1_hit_i`/`cb_rs2_hit_i`) is provisional.** `s1_completion_
  buffer.sv` does not exist yet (`rtl/core/README.md`: TODO, R-01). A single hit bit per operand
  (rather than a raw entry-array snoop) was chosen deliberately: resolving ties between multiple
  in-flight producers of the same register requires knowing the CB's internal age/index scheme, which
  only the CB module can own correctly (SPEC §8.2's hazard/stall table is already assigned there).
  This keeps the CB's internals out of this module, at the cost of the interface being a proposal, not
  a settled contract -- confirm with whoever builds R-01.
- **Not built here:** the actual ID/EX pipeline register that assembles `id_ex_t` (this module's
  outputs, `decoded_op_t`, and fetch's pass-through fields) and the completion-buffer allocation that
  produces `cb_idx`. Those live at a higher integration level (`s1_core.sv` or an ID-stage wrapper,
  neither built yet), not in this module -- matching the project's one-module-per-file convention.

## Open questions

- **MEM/WB compare location vs PR #21.** `s1_wb_stage` (PR #21) exposes `fwd_raddr_i`/`fwd_hit_o`
  and does the MEM/WB address compare itself, while this module compares `mem_rd_i` directly. Agree
  on one before integration. Related: the instruction sitting in WB during this cycle is not in EX
  or MEM, and it only becomes a CB entry on the next edge. So `cb_rs1_hit_i`/`cb_rs2_hit_i` must
  also cover it (for example by OR-ing in WB's `fwd_hit_o`), or that operand reads a stale RF value.
- R-03: dual-port SRAM variant vs. duplicated `meds_s1_sram` vs. an accepted stall path for the
  register file specifically (see Known limitations). This module's current flop-based storage should
  be revisited once that lands, regardless of which way it's decided.
- Confirm the `cb_rs1_hit_i`/`cb_rs2_hit_i` query shape with whoever builds `s1_completion_buffer.sv`
  (R-01) -- a single hit bit per operand vs. also exposing the CB's resolved value directly to this
  module (redundant with `s1_execute.sv`'s `cb_rs1_fwd_i`/`cb_rs2_fwd_i`, so probably unnecessary, but
  worth a second opinion).
