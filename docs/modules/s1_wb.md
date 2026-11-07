# `s1_wb`

| | |
|---|---|
| **Status** | WIP — unit- and integration-verified |
| **Authorship** | Eman Nasar (fatehulnasareman@gmail.com, GitHub EmanNasar001) — see the file header |
| **Project** | T-02 (core backend) |
| **Spec** | SPEC §7.5, §10.3, §28.2 |
| **Source** | `rtl/core/s1_wb.sv` |
| **Testbench** | `verif/unit/tb_s1_wb.sv` (395,309 checks), plus the integration testbench that lands with `s1_core` |

## Purpose

The WB stage, and **the architectural commit point**. Combinational: the MEM/WB register lives in
`s1_mem`, so by the time an instruction arrives here it is finished, and this stage decides what its
arrival does to architectural state.

Exactly one instruction commits per cycle, in program order, and everything that outlives it happens
here:

1. the register file write, unless it trapped or writes x0
2. the CSR write EX computed
3. the store-buffer entry is marked committed, so it may drain to memory
4. RVFI
5. `minstret`
6. on a trap: none of 1–3, and the pipeline is flushed to the trap vector

**Why commit here rather than in MEM.** A store that has passed MEM has been checked against PMA and
PMP, but it is still younger than nothing — it is the oldest instruction in the machine only once it
reaches WB. Buffer the store in MEM, release it here, and a trap taken by *this* instruction cannot
have already written memory.

Interrupts are taken here too, in place of a commit, so `mepc` names an instruction that has not
executed. And xRET legality is checked here, because this is the last point before privilege changes
(see *Privilege*).

## Interface contract

| Signal | Dir | Width | Meaning |
|---|---|---|---|
| `wb_valid_i`, `wb_i` | in | 1, `mem_wb_t` | the finished instruction from MEM. **No ready** — MEM cannot be told to wait |
| `irq_valid_i`, `irq_code_i` | in | 1, 6 | already masked and prioritised by the CSR file |
| `rf_wr_o` | out | `rf_wr_t` | the architectural register write |
| `csr_commit_o` | out | `csr_upd_t` | the CSR write EX computed |
| `instret_o` | out | 1 | `minstret` — retired, **not** trapped |
| `sb_commit_o` | out | 1 | a store committed: `s1_mem` releases its oldest uncommitted entry. No tag — commit is in order |
| `flush_o`, `flush_cause_o` | out | 1, `flush_cause_e` | pipeline flush and why |
| `redirect_valid_o`, `redirect_pc_o` | out | 1, `XLEN` | where to resume |
| `trap_req_o`, `mret_o` | out | `trap_req_t`, 1 | the trap request to the CSR file |
| `trap_vec_i`, `mepc_i` | in | `XLEN` | what the CSR file answers with |
| `busy_o` | out | 1 | this stage is holding something; ID's CSR serialisation asks |
| `priv_i`, `order_i`, `rvfi_o` | in/out | — | the trace; `priv_i` is the mode the committing instruction ran in |
| `perf_load_retired_o`, `perf_store_retired_o` | out | 1 | perf events |

**Latency:** none. Combinational, because the MEM/WB register is `s1_mem`'s.
**Backpressure:** none in either direction.

## Behaviour

An instruction commits when it arrives, unless something older takes precedence:

| Condition | What happens |
|---|---|
| a trap on the committing instruction | no register, CSR or store-buffer write; `trap_req_o`; flush to `trap_vec_i` |
| an interrupt pending | taken **in place of** the commit, so `mepc` names an instruction that has not executed |
| `MRET` from M-mode | `mret_o`; resume at `mepc_i` |
| `MRET` from U/S, or any `SRET` / `DRET` | illegal-instruction trap, `tval` = the instruction; **never** `mret_o` |
| `fence` | commits like anything else — `s1_mem` only shows one once its store buffer is empty |
| otherwise | all six steps above |

x0 is never written, and a trapping instruction writes nothing — SPEC §9.2's rule, applied here
because this is the only place architectural state changes.

**Privilege.** This core has M- and U-mode only: S-mode is not in v1 (SCOPE_CONTRACT §4) and there
is no debug mode. So `SRET` and `DRET` are always illegal, and `MRET` is legal only from M-mode
(`priv_i`). WB checks this itself rather than trusting earlier stages: without it, `MRET`, `SRET`
or `DRET` from U-mode would jump to `mepc` with `mret_o` set, which is a privilege escalation. An
illegal xRET becomes an ordinary exception: `EXC_ILLEGAL_INSTR`, `tval` = the instruction, nothing
written, `rvfi.trap` set. The decoder and EX should also reject these (they are cheaper to stop
early), but the commit point does not depend on it.

**Fences.** WB no longer waits for the store buffer. `s1_mem` holds a FENCE in MEM/WB until its
buffer is empty and MEM/WB has no ready, so a wait here could only drop the fence.

## Verification status

| Layer | Status |
|---|---|
| Lint | clean once the shared types are available |
| Unit test | `tb_s1_wb` — 395,309 checks, every output against an independent model, Verilator 5.020 |
| Mutation | 10 of 10 non-equivalent mutants of the xRET and commit logic caught (one more, `SRET` driving `mret_o`, is equivalent: `SRET` always traps first) |
| Integration | every retirement compared against spike, over the whole pipeline |

**Unit test.** The stage is combinational, and nine inputs decide what it does, so the unit
testbench sweeps that control space **exhaustively** — valid, interrupt, exception, all ten
`sys_op` values, `rd_we`, `rd == x0`, `csr_we`, `sb_alloc` and the privilege mode (U, S, M) — with a
fresh random payload on each of the 7,680 combinations, then 4,000 fully random cycles on top. The
privilege mode is swept independently of `sys_op`, so every xRET is seen from every mode. Every
output is compared against a model written from the commit rules rather than from the RTL.

Alongside the value comparisons it asserts the contract directly, so a check fails even where the
model and the RTL would agree on a shared mistake:

- a trap suppresses **all three** writes — register file, CSR and the store-buffer commit — and does
  not retire
- `mret_o` only ever comes from `MRET` in M-mode; an illegal xRET traps with the instruction in
  `tval`, writes nothing and never redirects to `mepc` (also tested directly: all three xRETs ×
  all three modes)
- an interrupt replaces a commit rather than following one, so `mepc` names an instruction that has
  not executed and `minstret` does not count it
- `x0` is never written, on any path

**Integration** then runs an RV64I program and a C sorting workload through the whole pipeline with
every retirement compared against spike on RVFI, under random I$/D$ backpressure and latency.

**What neither layer reaches.** The unit testbench drives `irq_valid_i` directly, so it proves what
this stage does with an interrupt, not that the CSR file masks and prioritises one correctly — that
belongs to T-03. `trap_vec_i` and `mepc_i` are likewise supplied, not computed.

## Known limitations

- **One commit per cycle, in order.** There is no completion buffer, so a multi-cycle unit cannot
  complete out of order: EX stalls on `md_*` until it answers, and the result travels down EX/MEM
  like any other. That is a deliberate simplification of SPEC §9, not an oversight.
- **Interrupts are taken in place of a commit**, so an instruction already finished in MEM/WB is
  discarded and re-executed after `mret`. For a non-idempotent read that has already happened, that
  is a replay — see `s1_mem`'s open question on the same point.

## Open questions

1. **Who owns `flush_cause_e`?** It exists so fetch and the caches can tell a trap from an `mret`
   from a `fence.i`. If the debug module wants it too, it belongs in the package rather than here.
2. **`busy_o` is coarse.** ID's CSR serialisation stalls on it whenever this stage holds anything,
   not only when the CSR in question is in flight. SPEC §8.2 permits that — it says CSR writes
   serialise — but it is worth measuring before it is called fine.
