# `verif/cosim/` — Layer 2 — trace co-simulation against Spike

## What lives here
The integration testbench for the assembled core (`rtl/core/s1_core.sv`), IF to WB: it runs a
program through the core and compares every retirement on RVFI with **spike**'s commit log.

| File | |
|---|---|
| `tb_s1_core.sv` | integration testbench: drives the core, models memory, checks every RVFI retirement against spike |
| `tb_csr_model.sv` | minimal CSR stand-in for the testbench — **not** the CSR file (T-03 builds that) |

The lint waivers for these testbenches are in `verif/verilator.vlt`, scoped to `verif/cosim/`
(R-L2). The core's contract, and where it departs from the SPEC, is in
[`docs/modules/s1_core.md`](../../docs/modules/s1_core.md).

## What does *not* live here
Directed tests, and hand-written expected values: expectations come from spike, the image from
objcopy.

Not in the core either: the **CSR file**, the I$/D$, the PMA/PMP checkers and the RV64M unit. The
core declares them as ports and the testbench stands in for them. The CSR file connects through
`csr_addr_o/re_o/we_o/rdata_i/illegal_i` (EX's side-effect-free query), `csr_commit_o` (the only
write, from WB), `trap_req_o`, `mret_o`, `trap_vec_i`, `mepc_i`, `priv_i`, `priv_data_i`,
`irq_valid_i`, `irq_code_i`, `instret_o` and the `perf_*_o` event lines. `tb_csr_model.sv`
implements only `mstatus` (MIE/MPIE/MPP), `mtvec`, `mepc`, `mcause`, `mtval`, `mscratch`,
`minstret`, `pmpaddr0` and `pmpcfg0` — what a program's trap handler needs — so ECALL, EBREAK and
MRET can still be checked against spike.

## Running it

The testbench takes its program at build time as `prog_<p>.svh`, which sets the image size, entry
point, `tohost` address and the paths of two `$readmemh` files: `<p>.img.hex` (the image, from
objcopy) and `<p>.exp.hex` (one expected retirement per line, from spike). No program is committed
yet, and `make cosim` is R-05's to wire up. Until then, by hand from the repository root (packages
first; the `.hex` paths are relative to the root):

```bash
verilator --binary --timing -Wall verif/verilator.vlt -Iverif/cosim \
  -DPROG_SVH='"prog_<p>.svh"' --top-module tb_s1_core -Mdir build/cosim/<p> -o tb_s1_core \
  rtl/core/s1_pkg.sv $(find rtl/core rtl/common -name '*.sv' ! -name '*_pkg.sv' | sort) \
  verif/cosim/tb_csr_model.sv verif/cosim/tb_s1_core.sv
build/cosim/<p>/tb_s1_core [+stall] [+verilator+seed+N] [+v]
```

`+stall` turns on random memory stalls; `+v` prints every failure instead of the first 30. Use the
Verilator the CI gate installs (5.020).

## What each retirement is checked for

Against spike: `order`, `pc_rdata`, `insn`, `mode`, `trap`, `rd_addr`, `rd_wdata`, `pc_wdata` (a trap's
is the handler, an MRET's is `mepc`), `ixl`, and the memory access — address and byte mask for a
load, address, mask and data for a store, and no access for everything else.

Against a shadow register file built from spike's own writes: `rs1`/`rs2` address is the field or
0, and the value is the architectural one. That checks the operand **EX actually used** — forwarding
the wrong value can still produce the right result.

At the end: the program reached its spin, wrote `tohost` = 1 (its own self-check passed), raised no
store error, dispatched no multiply and issued no FENCE.I.

## The memory model and the stalls

One byte array sits behind both I2 ports, as DRAM does. With `+stall` each port withholds `ready`
about a quarter of the time and delays each response by 0–4 extra cycles (`$urandom`, seeded by
`+verilator+seed+N`). Every cycle both ports are protocol-checked: a presented request stays
presented with an unchanged payload until accepted (R-C10), and there is never a second request
outstanding (INTERFACES.md I2, v1).

The stalls are not decoration: hazards that a one-cycle memory hides only show up under them.

## How to add something
- **A program** `<p>`: commit `prog_<p>.svh`, `<p>.img.hex` and `<p>.exp.hex` here, generated
  from the toolchain and spike, never written by hand. The program must not read a register before
  writing it, must not access memory misaligned, and must end by writing `tohost` and spinning.
- **A unit testbench** for a core module goes in `verif/unit/tb_<module>.sv`, not here.

## Catalogue projects that land here
R-05 RVFI trace port and Spike co-simulation

---
*Conventions: [`docs/guidelines/CODING_STANDARD.md`](../../docs/guidelines/CODING_STANDARD.md) ·
Definition of done: [`PROJECTS.md`](../../PROJECTS.md)*
