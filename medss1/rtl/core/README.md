# `rtl/core/` — S1-Core — the scalar RV64 CPU

## What lives here
Pipeline stages, register file, ALU, CSR file, completion buffer, LSU, MXIF port, and `s1_pkg.sv` which holds every shared type.

## What does *not* live here
Caches (`rtl/cache/`), anything that speaks AXI directly — the pipeline speaks MEM-REQ only (INTERFACES.md §2).

## How to add something
Add the module, add its testbench, then add a row to the interface table below. Any new struct shared between two modules goes in `s1_pkg.sv`, never in a module file.

## Catalogue projects that land here
T-01 frontend · T-02 backend · T-03 CSR/traps · R-01 completion buffer + MXIF · R-02 LSU

## Module status

Status tags follow CODING_STANDARD.md §5. This table is the fastest way to see what exists.

| Module | Status | Project | Testbench | Docs |
|---|---|---|---|---|
| `s1_pkg.sv` | COMPLETE | — | n/a | shared types |
| `s1_alu.sv` | **COMPLETE — REFERENCE** | T-02 | `tb_s1_alu` (4206 checks) | [page](../../docs/modules/s1_alu.md) |
| `s1_fetch.sv` | TODO | T-01 | | |
| `s1_decode.sv` | TODO | T-02 | | |
| `s1_regfile.sv` | TODO | T-02 | | |
| `s1_csr.sv` | TODO | T-03 | | |
| `s1_completion_buffer.sv` | TODO | **R-01 (critical path)** | | |
| `s1_mxif_port.sv` | TODO | **R-01 (critical path)** | | |
| `s1_lsu.sv` | TODO | R-02 | | |
| `s1_pmp.sv` | TODO | R-02 | | |
| `s1_core.sv` | TODO | T-02 / R-01 | | |

## Rules specific to this directory

1. **The pipeline never speaks AXI.** Memory ports use MEM-REQ (`specs/INTERFACES.md` §2). Coupling
   pipeline timing to bus latency is permanent, and every future bus change would touch the core.
2. **Every shared struct lives in `s1_pkg.sv`.** If two modules must agree on a shape, it goes in the
   package — a struct declared in a module file that another module also needs is how field-order
   bugs happen.
3. **`s1_alu.sv` is the style reference.** New modules are reviewed against it.
4. **The frontend sits behind `fetch_req`/`fetch_rsp`.** That interface is what makes the branch
   predictor a swappable v2 project rather than a pipeline rewrite — do not bypass it.

---
*Conventions: [`docs/guidelines/CODING_STANDARD.md`](../../docs/guidelines/CODING_STANDARD.md) ·
Definition of done: [`EXECUTION_PLAN.md`](../../EXECUTION_PLAN.md) §8*
