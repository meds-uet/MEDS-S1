# `s1_id`

| | |
|---|---|
| **Status** | WIP, unit-verified; not yet reviewed |
| **Project** | T-02 (backend) |
| **Spec** | SPEC §7.2, §8.1 |
| **Source** | `rtl/core/s1_id.sv`, `rtl/core/s1_hazard.sv` (uses `s1_decode`, `s1_regfile`) |
| **Testbench** | `verif/unit/tb_s1_id.sv`, `verif/unit/tb_s1_hazard.sv` |

## Purpose

The ID stage: decodes the IF/ID instruction, resolves `rs1`/`rs2`, stalls on hazards and registers the
result into ID/EX. `s1_hazard` is the combinational operand-dependence check inside it.

## Interface contract

| Ports | Direction | Contract |
|---|---|---|
| `flush_i` | in | retire flush; nothing issues, ID/EX is cleared |
| `ex_redirect_valid_i` | in | mispredict in EX; the instruction in IF/ID is wrong-path and is not issued |
| `fetch_rsp_*` | in/out | IF/ID. `ready` is high when ID/EX can take the instruction and no hazard holds it |
| `rs1_data_i`, `rs2_data_i` | in | register-file read for the IF/ID instruction; the address was given a cycle ahead by `s1_fetch` (`nxt_rs*_addr_o`). The regfile bypasses a write retiring in the same cycle |
| `exmem_valid_i`, `exmem_i` | in | EX/MEM, for bypass and hazard checks |
| `memwb_pend_i`, `memwb_rd_i`, `memwb_rd_we_i` | in | a MEM/WB entry still waiting on the D$ |
| `downstream_busy_i` | in | EX/MEM, MEM/WB, WB and the store buffer are not all empty |
| `ex_valid_o`, `ex_ready_i`, `ex_o` | out/in/out | ID/EX register, `id_ex_t` |
| `perf_load_use_o`, `perf_hazard_stall_o` | out | one pulse per stalled cycle |

## Behaviour

**Operand resolve.** For each source, the youngest older writer is looked for in EX, EX/MEM and a pending
MEM/WB entry, in that order:

| Writer | Result |
|---|---|
| in EX, not a load/AMO | `FWD_EXMEM`: EX reads it from its own EX/MEM register next cycle |
| in EX/MEM, not a load/AMO | value taken from `exmem_i.result`, passed as `FWD_RF` |
| load, AMO, LR or SC in EX or EX/MEM | stall (`perf_load_use_o`) |
| pending in MEM/WB | stall |
| none of the above | register file value |

A writer that has completed in WB is in the register file: `s1_regfile` bypasses a write in the same
cycle and the previous one. `x0` never creates a hazard. An instruction carrying a fetch exception
reads and writes nothing, so it cannot stall.

**Serialisation.** A CSR or SYSTEM instruction waits until ID/EX is empty and `downstream_busy_i` is low.

**Issue.** The instruction moves to ID/EX when ID/EX is free (or leaving), there is no stall, and neither
`flush_i` nor `ex_redirect_valid_i` is set.

## Verification status

| Layer | Status |
|---|---|
| `tb_s1_hazard` | 600,000 checks against a model that walks the writers youngest first |
| `tb_s1_id` | 36 directed checks: flow, both forward selects, load-use at each stage, AMO, `x0`, CSR serialisation, fetch exception, flush, mispredict block, back-pressure, field pass-through |
| Stacked core | a 48-instruction smoke program (not committed) with dependent chains, load-use, a loop, JAL/JALR ran on the stacked core against an independent model, with and without random memory stalls |

## Known limitations

- Younger instructions may execute speculatively behind an older instruction that will trap, until the
  trap reaches WB (a younger load can reach the D$). The same holds for the rest of this pipeline.
- Decode is `s1_decode`'s: it must give loads, stores, JALR and LR/SC/AMO `ALU_ADD` with `op2_is_imm`
  (and `imm = 0` for LR/SC/AMO) because `s1_execute` takes the address from the ALU, and must mark
  `SRET`, `DRET` and `SFENCE.VMA` illegal.
