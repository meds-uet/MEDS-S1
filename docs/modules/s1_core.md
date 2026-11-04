# `s1_core`

| | |
|---|---|
| **Status** | WIP — RV64I verified against spike; M, A, C, interrupts not yet |
| **Owner** | _(assign at Phase-0 review)_ |
| **Backup** | _(assign at Phase-0 review)_ |
| **Project** | T-02 (backend) with T-01 (frontend), T-03 (CSR), R-02 (MEM) |
| **Spec** | SPEC §6–§12; INTERFACES.md I2, I6, I7 |
| **Source** | `rtl/core/s1_core.sv` |
| **Testbench** | `verif/cosim/tb_s1_core.sv` — retirements vs spike over RVFI |

## Purpose

The assembled five-stage RV64 core: `s1_fetch` → `s1_id` (`s1_decode`, `s1_hazard`) → `s1_ex`
(`s1_alu`) → `s1_mem` → `s1_wb`, with `s1_regfile` beside them. It only wires the stages together
and exposes everything external as a port, so the CSR file, caches, fabric, checkers and the
multiplier attach at this boundary without editing a stage.

## Interface contract

| Ports | Interface | Contract |
|---|---|---|
| `clk_i`, `rst_ni` | — | one clock domain; reset async assert, sync de-assert |
| `imem_*` | I2 MEM-REQ | fetch, read-only, one request outstanding; `valid` never a function of `ready`, payload held until accepted (R-C10) |
| `dmem_*` | I2 MEM-REQ | loads, drained stores; same rules; byte lanes AXI-style (byte A on lane A mod 8) |
| `csr_addr_o`, `csr_re_o`, `csr_we_o`, `csr_rdata_i`, `csr_illegal_i` | SPEC §10 | EX's CSR query, side-effect free, answered combinationally by the external CSR file |
| `csr_commit_o`, `trap_req_o`, `mret_o`, `trap_vec_i`, `mepc_i` | SPEC §10.3 | WB's CSR write, trap and xRET requests; `trap_vec_i` may depend combinationally on `trap_req_o` |
| `priv_i`, `priv_data_i` | SPEC §10.1 | current privilege, and effective for loads/stores after MPRV |
| `irq_valid_i`, `irq_code_i` | I7 | a pending, enabled interrupt, already prioritised by the CSR file; taken in WB |
| `instret_o`, `perf_*_o` | SPEC §12 | one instruction retired (not trapped), and the event lines, for the CSR file's counters |
| `rvfi_o` | I6 | one record per committed instruction, trapped ones included (`trap` = 1) |
| `fence_i_o` | — | one cycle when FENCE.I commits: invalidate the I$ |
| `store_err_o`, `store_err_addr_o` | — | bus error while draining an already-committed store; imprecise by construction |
| `chk_*` out, `pma_i`, `pma_fault_i`, `pmp_allow_i` in | SPEC §11 | one query per data access, answered **combinationally in the same cycle** by checkers outside the core |
| `md_*` | — | RV64M outside the core: `md_start_o` in the instruction's first EX cycle, EX holds until `md_done_i` |

**Reset state:** fetch starts at `RESET_PC` in M-mode; no request is presented during reset.

## Parameters

| Parameter | Default | Effect |
|---|---|---|
| `RESET_PC` | `BOOT_ADDR` | first fetch address |
| `MXIF_EN` | 0 | decode unknown encodings as MXIF candidates; with no MXIF port they still trap as illegal |

## Behaviour

In order, single issue, **in-order completion**; WB is the only commit point. Forwarding is
resolved in ID (`s1_hazard`): an EX producer forwards from the EX/MEM register, an EX/MEM producer
by value, and the register file bypasses a same-cycle write. Branches resolve in EX against fetch's
BTFN prediction; a mispredict redirects fetch and blocks the wrong-path issue in ID. Traps, xRET and
FENCE.I redirect from WB. CSR and SYSTEM instructions serialise on an empty pipeline.

## Where this core departs from the SPEC

These are design decisions of this core, not defects found by the test. They are listed so a reader
does not take the SPEC as a description of it.

| SPEC | This core |
|---|---|
| §9 completion buffer, out-of-order completion | none; in-order completion, WB commits |
| §6, §19, INTERFACES I1: MXIF port | none; MXIF candidates trap as illegal |
| §10 CSR file inside the core | outside: another project's, attached at the `csr_*`/trap ports |
| §10.2 external CSR port | none (no coprocessor to route to) |
| §8.2 load-use penalty 1 | 2 cycles: there is no MEM/WB→EX forward |
| §7.4 Zicbom/Zicboz | decoded, **not executed**: a CBO retires as a no-op (`cbo.zero` does not zero) |
| I6 `rvfi_csr_*` groups | not driven |
| §11 PMP on instruction fetch | `chk_ex_o` tied 0: fetch is not checked |

## Exceptions and errors

Illegal instruction, ECALL (U/S/M), EBREAK, load/store access faults (PMA, PMP, misalignment where
`pma_i.align_natural` is set) and instruction access faults; interrupts are taken in WB in place of a
commit. `mtval` is the instruction bits, the pc (EBREAK) or the faulting address.

## Verification status

| Layer | Status | Where |
|---|---|---|
| Lint | clean on Verilator 5.020, `-Wall`, waivers only in `verif/verilator.vlt` | `make lint` |
| Integration vs spike | testbench in place; test programs land separately | `verif/cosim/README.md` |
| Formal | not started | |

Bugs the integration test found in the stages (fixed in github.com/ayeshaanwaar05/core; the stage PRs need the same fixes): a mispredicted branch lost when
MEM stalled; a load waiting on the D$ invisible to the hazard unit (stale operands under memory
latency) and to CSR serialisation; `minstret` counting trapped ECALL/EBREAK; RVFI `mode` fixed at
M, `rs1/rs2_rdata` fixed at 0, and `pc_wdata` wrong for MRET.

## Known limitations

The CSR file itself (the test uses a minimal stand-in, `verif/cosim/tb_csr_model.sv`), RV64M,
RV64A, RV64C, interrupts, misaligned and faulting
accesses are not exercised by the integration test.

## Open questions

Whether the in-order design replaces SPEC §9 for v1.0 needs ratifying at the Phase-0 review; until
then the SPEC and this core disagree on the completion buffer and MXIF.
