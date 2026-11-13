# `s1_trap_unit`

| | |
|---|---|
| **Status** | WIP — cleaned to the PR #19 review; `s1_core` port migration pending |
| **Owner** | @AbdurRahman020 |
| **Backup** | _(assign at Phase-0 review)_ |
| **Project** | T-03 CSR file, trap unit, privilege |
| **Spec** | SPEC §10.1, §10.3; RISC-V privileged spec trap entry and xRET |
| **Source** | `rtl/core/csr/s1_trap_unit.sv` |
| **Testbench** | `verif/unit/tb_s1_trap_unit.sv` |

## Purpose

This module holds the hart's privilege mode. It turns a retiring trap, `mret` or `sret` into one atomic CSR update plus a fetch redirect. It reads the trap CSRs from `s1_csr_file`'s `trap_*_o` taps and writes them back through the CSR file's four `hw_*` slots.

## Interface contract

| Signal | Dir | Width | Meaning | Contract |
|---|---|---|---|---|
| `clk_i` | in | 1 | clock | single domain |
| `rst_ni` | in | 1 | reset | async assert, sync de-assert; privilege resets to M |
| `trap_valid_i` | in | 1 | a trap retires this cycle | one cycle per trap, at retire; always taken |
| `trap_is_interrupt_i` | in | 1 | the trap is an interrupt | sets `xcause[XLEN-1]`; selects `mideleg` over `medeleg` |
| `trap_cause_i` | in | 6 | exception or interrupt code | low field of `xcause` |
| `trap_tval_i` | in | `XLEN` | trap value | written to `xtval` |
| `trap_pc_i` | in | `XLEN` | PC of the trapping instruction | written to `xepc` |
| `mret_valid_i` | in | 1 | an `mret` retires | one cycle, at retire |
| `sret_valid_i` | in | 1 | an `sret` retires | one cycle, at retire |
| `mstatus_rdata_i`, `medeleg_rdata_i`, `mideleg_rdata_i`, `mepc_rdata_i`, `mtvec_rdata_i` | in | `XLEN` | current M-mode trap CSRs | the CSR file's raw taps, valid in the retire cycle |
| `sepc_rdata_i`, `stvec_rdata_i` | in | `XLEN` | current S-mode trap CSRs | used only with S-mode; S status bits come from `mstatus` |
| `hw_we_o[4]`, `hw_addr_o[4]`, `hw_wdata_o[4]` | out | 1, 12, `XLEN` | CSR writes for this action | combinational; slot 0 `xepc`, 1 `xcause`, 2 `xtval`, 3 `mstatus` |
| `redirect_valid_o`, `redirect_pc_o` | out | 1, `XLEN` | fetch redirect | combinational, in the same cycle as the request |
| `priv_mode_o` | out | `priv_lvl_e` | current privilege | registered |

**Handshake:** none. Requests are single-cycle pulses at retire.
**Latency:** the CSR writes and the redirect are combinational. The privilege updates on the next edge.
**Backpressure:** none.
**Reset state:** priv = M, no writes, no redirect.

**Trap entry beats a software CSR write.**
- If a retiring CSR write (`csr_commit`, today the CSR file's `csr_we_i`) and trap entry write the same CSR in the same cycle, the trap entry value is stored.
- `s1_csr_file` applies the `hw_*` writes after the software write on the same edge.
- WB never commits a trapping instruction, so the overlap happens only when an interrupt replaces a commit. The rule makes the result defined either way.

## Parameters

| Parameter | Default | Legal range | Effect |
|---|---|---|---|
| `U_MODE_PRESENT` | 1 | 0, 1 | after `mret`, MPP becomes U; without U it becomes M |
| `S_MODE_PRESENT` | 0 | 0, 1 | enables delegation to S and `sret` |

Set both from the config (SPEC §5.3), with the same values as `s1_csr_file`.

## Behaviour

- **Every retiring trap is taken.** That includes a trap raised inside a handler; there is no in-trap state.
- **Delegation.** A trap goes to S only when `S_MODE_PRESENT`, priv ≠ M, and its `medeleg`/`mideleg` bit is set. Otherwise it goes to M.
- **M trap.**
  - It writes `mepc`, `mcause = {interrupt, 0…, cause}` and `mtval`.
  - It writes `mstatus` with MPP = priv, MPIE = MIE and MIE = 0. Priv becomes M.
  - It redirects to `{mtvec[XLEN-1:2], 2'b00}`, plus `4 × cause` for an interrupt in Vectored mode. The mode bits never reach the PC.
- **S trap.**
  - It writes `sepc`, `scause` and `stval`.
  - It writes `mstatus` with SPP = (priv == S), SPIE = SIE and SIE = 0. It writes `mstatus`, not `sstatus`, because `sstatus` is a view in the CSR file.
  - It redirects through `stvec` in the same way as an M trap.
- **`mret` in M.**
  - Priv becomes MPP. MIE = MPIE, MPIE = 1, and MPP = U (or M without U).
  - MPRV clears if the new mode is below M.
  - It redirects to `mepc`.
  - MPP is not rechecked here: its legality is enforced once, when MPP is written (`s1_csr_legalize`), and this unit only ever writes legal values.
- **`sret` in S (with S-mode).** Priv becomes S or U from SPP, SIE = SPIE, SPIE = 1, SPP = U and MPRV = 0. It redirects to `sepc`.
- **Priority:** trap, then `mret`, then `sret`.

## Exceptions and errors

This module raises nothing. An `mret` outside M, or an `sret` outside S, changes no state and does not redirect.

## Verification status

| Layer | Status | Where |
|---|---|---|
| Lint | clean | `make lint` |
| Unit test | about 36,500 checks (the random phase varies the count) on Verilator 5.046 and 5.020. Runs against `s1_csr_file`; the scoreboard compares redirect and CSR state every cycle against a field-level reference model. M and U only: the S-mode paths (delegation, `sret`) are not covered yet. | `verif/unit/tb_s1_trap_unit.sv` |
| Co-simulation | not applicable yet | |
| Formal | none | |

## Known limitations

- **xRET outside its mode does not trap.**
  - Ignoring an `mret` below M keeps the state, but the core's WB (PR #21) still redirects to `mepc`, and the instruction retires instead of raising illegal-instruction.
  - EX does not query the CSR file for xRET, and `s1_core`'s `mret_o` merges MRET, SRET and DRET.
  - The fix is on the core side; see `csr_access_matrix.md` ASSUMPTION-9.
- **`sret` is honoured only in S.** The privileged spec also allows `sret` in M (when TSR is clear). `mstatus.TSR` is not implemented (ASSUMPTION-13).
- **The ports are not the `s1_core` set.** `s1_core` expects:
  - `trap_req_t` in, and one `mret` in;
  - `trap_vec`/`mepc` out instead of a redirect;
  - `priv`/`priv_data` out;
  - `irq_*` out, produced by `s1_irq_prio`.

  The migration waits for the owner of `trap_req_t`/`csr_upd_t`, which are defined only in open PR #14.
- **Debug Mode is out of scope for T-03** and not implemented here.
- **MPP legality is not config-aware yet.** `s1_csr_legalize` accepts only U and M. So with S-mode a software write of MPP = S becomes U, and on S1-Nano (no U) the reset value of MPP (U) is not legal.
- **The `hw_*` writes bypass the CSR file's masks**, so this module writes only legal values.

## Open questions

- See `rtl/core/csr/csr_access_matrix.md` ASSUMPTION-1, -2, -9 and -13.
