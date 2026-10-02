# `s1_execute`

| | |
|---|---|
| **Status** | WIP (unit-verified; waiting on `decoded_op_t` from #4, then integration) |
| **Owner** | Ayesha Anwar (@ayeshaanwaar05) |
| **Backup** | _(assign at the design review)_ |
| **Project** | T-02 (core backend: EX) |
| **Spec** | SPEC §6, §7.3, §8.1, §8.2, §9, §10.2, §12 |
| **Source** | `rtl/core/s1_execute.sv` (uses `rtl/core/s1_alu.sv`) |
| **Testbench** | `verif/unit/tb_s1_execute.sv`: 594 322 checks |

## Purpose

The EX stage. It resolves operands through the forwarding network (SPEC §8.1), executes ALU
operations on `s1_alu`, resolves branches and redirects fetch on a mispredict, computes load/store
addresses and CSR read-modify-write values, and dispatches MUL/DIV to the multi-cycle units.
Everything else is registered into EX/MEM. EX changes no architectural state: CSR writes are
computed here and committed at retire (SPEC §7.3, §9.2).

## Interface contract

| Signal | Dir | Type | Contract |
|---|---|---|---|
| `clk_i`, `rst_ni` | in | 1 | single clock; async assert, sync de-assert |
| `flush_i` | in | 1 | retire flush. Kills the instruction in EX and clears EX/MEM; no redirect, dispatch or CSR query that cycle |
| `priv_i` | in | `priv_lvl_e` | current privilege; selects the ECALL cause |
| `ex_valid_i` / `ex_ready_o` | in / out | 1 | ID/EX handshake. ID holds `ex_i` stable until `ready` (R-C10), except on flush |
| `ex_i` | in | `id_ex_t` | `decoded_op_t` (from #4) plus CB index, RF values, forwarding selects, and from fetch: `compressed`, `pred_taken`, `instr_raw`, fetch exception |
| `memwb_fwd_i`, `cb_rs1_fwd_i`, `cb_rs2_fwd_i` | in | `XLEN` | forwarding sources; the EX/MEM source is EX's own output register |
| `csr_addr_o`, `csr_re_o`, `csr_we_o` | out | 12, 1, 1 | side-effect-free query of the CSR file; intents follow Zicsr (no write for RS/RC with `rs1`/uimm = 0; no read for RW with `rd = x0`) |
| `csr_rdata_i`, `csr_illegal_i` | in | `XLEN`, 1 | old value and access-check result for the query |
| `ex_redirect_valid_o`, `_pc_o`, `_cb_idx_o` | out | 1, `XLEN`, `CB_IDX_W` | mispredict: flush IF (`s1_fetch`), flush ID, free CB entries younger than `cb_idx` |
| `md_valid_o` / `md_ready_i`, `md_req_o` | out / in | `md_req_t` | MUL/DIV dispatch. `valid` never depends on `ready`; payload stable until accepted. The unit answers WB with `md_rsp_t`; EX never sees the result |
| `mem_valid_o` / `mem_ready_i`, `mem_o` | out / in | `ex_mem_t` | EX/MEM register |
| `perf_br_taken_o`, `perf_br_mispredict_o` | out | 1 | one pulse per instruction (SPEC §12 frontend group) |

**What EX assumes of ID:**

- `rs1_fwd`/`rs2_fwd` are correct for the instruction's **first** EX cycle. Producers ahead keep
  moving while EX stalls, so EX captures the resolved operands in that cycle and reuses them. A
  hazard unit therefore never has to re-select a source for an instruction that is already in EX.
- **CSR instructions reach EX only when the CB is empty.** This is SPEC §8.2's serialisation. EX
  reads CSRs, so without it a read could miss an older, not-yet-retired CSR write.
- Operand reads of `x0` are forced to zero whatever the select says.

**What EX leaves to the completion buffer:**

- **A dispatched MUL/DIV can outlive its CB entry.** EX has no kill towards the units. An
  operation accepted on `md_req_o` runs to completion and returns `md_rsp_t` to WB even if a later
  mispredict (`ex_redirect_valid_o`) freed its entry, and that index may have been reallocated by
  then. The completion buffer (R-01) must reject a completion for an entry that is no longer the
  one dispatched; neither EX nor WB can tell. (A retire flush is different: WB drains the units.)

**Latency:** the redirect is combinational in the instruction's first EX cycle, which is what gives
SPEC §8.2's mispredict penalty of 2 together with `s1_fetch`. Otherwise EX takes one instruction per
cycle into EX/MEM.

**Backpressure:** EX stalls when EX/MEM is full and `mem_ready_i` is low, or when a MUL/DIV is
refused (`md_ready_i` low).

**Reset:** EX/MEM empty; no outputs active.

## Parameters

None. Widths come from `s1_pkg`.

## Behaviour

**Operands:** `op1_is_pc`/`op2_is_imm` select PC or the immediate as ALU inputs. Branches always
compare `rs1` with `rs2`.

**Adders:** besides the ALU there are three:
- `pc + len`, used for the link address and fall-through; `len` is 2 when `compressed`.
- `pc + imm`, for branch and JAL targets.
- `rs1 + imm`, which is both the load/store address and the JALR target (bit 0 cleared). AMO/LR/SC
  use `rs1` alone.

**Branch resolution:** by the `s1_fetch` contract, `pred_taken` means fetch already went to
`pc + imm`. EX redirects iff where fetch went ≠ the real successor:

| `pred_taken` | Instruction | Fetch went to | Redirect when |
|---|---|---|---|
| 0 | any | `pc + len` | successor ≠ `pc + len` (taken branch or jump) |
| 1 | branch or JAL | `pc + imm` | successor ≠ `pc + imm` |
| 1 | JALR or anything else | unknowable | always (to the real successor) |

The redirect fires once, in the instruction's first cycle, so a stalled branch does not restart
fetch every cycle.

**Result into EX/MEM:**
- **JAL/JALR:** the link address.
- **CSR:** the old CSR value, with `csr_wdata` = RW → src, RS → old | src, RC → old & ~src.
- **ALU operations:** the ALU result.
- **Loads:** the value is replaced in MEM.
- **MXIF candidates:** pass through with `complete = 0`. They are offloaded at retire (R1.1), so WB
  must not mark their entry done.

**MUL/DIV:** dispatched with both operands and the CB index. They leave the main pipe here (SPEC §6)
and never enter EX/MEM. The unit returns `md_rsp_t` (entry, register, value) to WB; RV64M does not
trap, so the response carries no exception group.

## Exceptions and errors

In priority order:

| Condition | `exccode` | `exctval` |
|---|---|---|
| fetch exception carried in `ex_i` | as given | as given |
| `op.illegal`, or a CSR access the CSR file refuses | `EXC_ILLEGAL_INSTR` | `instr_raw` (the 16-bit parcel for compressed) |
| ECALL | `EXC_ECALL_U/S/M` by `priv_i` | 0 |
| EBREAK | `EXC_BREAKPOINT` | `pc` |

An excepting instruction has **no side effects in EX**: no redirect, no dispatch, no memory
fields, no CSR write in EX/MEM. This holds even if the decoder left side fields set on an illegal
encoding. The trap itself is taken at retire. No instruction-address-misaligned exception can
occur: with C present, branch/JAL offsets are even and JALR clears bit 0.

## Verification status

| Layer | Status | Where |
|---|---|---|
| Lint | clean, no waivers, all four configs | `make lint` |
| Unit test | **594 322 checks**, 42 262 instructions (below). Counts are from Verilator 5.020, the CI version; they shift slightly with the simulator's random stream. | `verif/unit/tb_s1_execute.sv` |
| Mutation | 18 of 18 caught (table below) | |
| Co-simulation | not yet; covered once R-05 lands | |
| Formal | not yet | T-07 |

How the testbench works:

- **Perfect decoder.** Stimulus comes from `verif/common/rv64_golden.svh`, a mask/match table of
  every RV64IMAC_Zicsr_Zifencei instruction. It produces `decoded_op_t` in #4's conventions and
  generates legal encodings of any mnemonic. EX is therefore tested against what a correct decoder
  produces, not against `s1_decode`.
- **Independent model.** Expected results come from an ISA model keyed on the mnemonic, independent
  of both `decoded_op_t` routing and `s1_alu`.
- **Every cycle, the testbench checks:**
  - redirect in the first cycle only, with the right target and CB index;
  - dispatch payload, CSR intents, perf pulses and `ex_ready_o`;
  - valid/payload independent of any ready (probed within the cycle), and stable until accepted;
  - EX/MEM contents in order, ignoring don't-care fields;
  - a watchdog on stuck instructions.
- **Directed tests:**
  - every mnemonic × 64 corner-operand pairs;
  - degenerate predictions: a predicted-taken branch whose target equals the fall-through, a JALR to
    `pc + len`, a predicted JALR, and a non-branch predicted taken;
  - CSR intent combinations, with privilege and read-only faults;
  - ECALL per privilege, and EBREAK;
  - fetch exception priority, and `mtval` for compressed-origin instructions;
  - an illegal AMO/DIV that still has side fields set, and an AMO carrying a stray immediate;
  - operand capture across a 10-cycle DIV stall, and exactly one redirect for a stalled branch;
  - flush of a waiting DIV;
  - ALU throughput.
- **Random soak:** 3 × 20 000 cycles with random backpressure and flushes. Coverage counters (every
  forwarding source, held operands, flush kills, redirects, exceptions, MXIF, CSR writes) must all
  be non-zero.

Mutants, each a copy of `s1_execute.sv` with one line changed. All 18 are caught:

| Mutant | Bug | Caught by |
|---|---|---|
| no x0 force | `x0` operand takes the forwarded value | redirect / result checks |
| no capture | re-muxes forwarded operands while stalled | dispatch payload stability (R-C10) |
| redirect every cycle | stalled branch redirects repeatedly | first-cycle redirect check |
| conservative mispredict | redirects when fetch was already right | degenerate-prediction directed case |
| JALR bit 0 | target bit 0 not cleared | redirect target |
| link always +4 | ignores `compressed` | EX/MEM result |
| RS/RC with x0 writes | CSR write intent with `rs1 = x0` | CSR intent check |
| RW with rd=x0 reads | CSR read intent with `rd = x0` | CSR intent check |
| ECALL always M | cause ignores privilege | EX/MEM `exccode` |
| exception not gating memory | illegal op still issues a memory access | EX/MEM |
| exception not gating dispatch | illegal DIV dispatched | `md_valid_o` check |
| EX/MEM source wired to MEM/WB | wrong forwarding source | EX/MEM result |
| flush keeps EX/MEM | flushed entry reaches MEM | scoreboard |
| md valid on ready | `md_valid_o` gated by `md_ready_i` | ready-independence probe |
| AMO adds imm | AMO address uses `rs1 + imm` | directed AMO-with-immediate case (added after this mutant first survived) |
| tval from expanded instr | `mtval` uses the 32-bit expansion | EX/MEM `exctval` |
| EBREAK tval 0 | `mtval` not `pc` | EX/MEM `exctval` |
| MXIF completes | candidate marked complete | EX/MEM `complete` |

## Known limitations

- **The MUL and DIV units are not here.** EX provides the dispatch port; the units come next.
- **Zicbom/Zicboz and DRET are not executed:** EX ignores `is_cbo`/`cbo_op` and does not act on
  `SYS_DRET`; they pass through as plain instructions.
- **Perf events are counted in EX,** so an instruction later squashed by an older trap is counted.
- **The redirect path is long:** forwarding mux → comparator → mispredict → fetch address. This is
  the price of SPEC §8.2's penalty of 2.
- **Not carried in EX/MEM:** SFENCE.VMA operands (no MMU in v1), and RVFI's `rs1/rs2` data.

## Open questions

1. **Where the forwarding mux lives.** SPEC §8.1 forwards EX/MEM results with penalty 0, which
   needs the mux at the EX input, so it is here. #4's documentation places it in `s1_regfile`;
   agree on one before integration.
2. **Predicted target.** `pred_taken` alone cannot check a predicted JALR (RAS) or a BTB target. A
   swappable predictor (SPEC §6) needs `pred_target` in `fetch_rsp_t` and `id_ex_t`.
3. **CB fields.** `cb_entry_t` has no `sys_op` (MRET/SRET/WFI/FENCE are handled at retire) and no
   CSR-update fields; SPEC §9.1's `csr_update_t` is undefined.
4. **When the register file is written.** SPEC §7.5 says WB writes the register file; §9.2 says the
   architectural write happens at retire. EX assumes §9.2, which is why CB forwarding exists.
5. **MEM/WB forwarding has no valid.** `FWD_MEMWB` is selected in ID and applied one cycle later, on
   the assumption that the producer leaves MEM in that cycle. #18's MEM can hold it longer (a read
   straddling two beats, an I2 stall), and then `memwb_fwd_i` is not the producer's value and
   nothing flags it. Two fixes, to be chosen with #18, #21 and #24:
   - **ID stalls** instead of selecting `FWD_MEMWB` unless MEM guarantees completion next cycle.
     EX is unchanged, but MEM must export that guarantee early enough for ID.
   - **A valid beside `memwb_fwd_i`**, and EX waits for it before its first cycle. Local to EX and
     WB, but an operand selecting `FWD_CB` must then stay readable across the wait.
