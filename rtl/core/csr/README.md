# `rtl/core/csr/` — CSR file, trap unit, privilege

## What lives here
The T-03 machine-mode state:
- `s1_csr_file.sv` (decode, storage, access checks)
- `s1_csr_legalize.sv` (WARL fields)
- `s1_trap_unit.sv` (trap entry, xRET, privilege)
- `s1_irq_prio.sv` (which pending, enabled interrupt to take)

`csr_access_matrix.md` is the access-control design: who may access each CSR, and the assumptions behind it.

## What does *not* live here
- The CSR table itself. It is `rtl/core/defines/core_csr.yaml`, compiled by `gen/s1_csr_gen.py` into `rtl/generated/s1_csr_pkg.sv`.
- Coprocessor CSRs, which live in `extensions/<name>/csr.yaml`.
- Performance counters and the debug FSM.

## How to add something
1. Add the CSR to `core_csr.yaml` and run `make csr-gen`.
2. Update the row in `csr_access_matrix.md`.
3. `make check` fails if the generated package is stale.

## Interface contract
The CSR side of the `s1_core` ports (`csr_*`, `trap_req_t`, `mret_o`, `trap_vec_i`, `mepc_i`, `priv_*`, `irq_*`; SPEC §10). The modules here do not match those ports yet; see `csr_access_matrix.md` ASSUMPTION-9 and the T-03 rework.

## Catalogue projects that land here
T-03 CSR file, trap unit, privilege

---
*Conventions: [`docs/guidelines/CODING_STANDARD.md`](../../../docs/guidelines/CODING_STANDARD.md)*
