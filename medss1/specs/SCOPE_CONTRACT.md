# MEDS-S1 Platform v1.0 — Scope Contract

**Status:** UNSIGNED DRAFT. To be argued in the Phase-0 design review and signed in week 4.
**Modelled on:** `MEDS/RVV/book/appendix/E-scope-contract.md`, which is the proven MEDS pattern.

> A written, agreed scope makes "no" cheap, converts omissions into decisions, and defines done.
> An unimplemented feature that appears in §3 below is a **choice**. The same feature missing
> without explanation is a **gap**. Reviewers read the two very differently.

---

## 1. Signatories

| Role | Name | Signed |
|---|---|---|
| Platform architect | Umer Shahid | ☐ |
| Faculty sponsor | Dr. Tahir | ☐ |
| Verification owner | _(assign)_ | ☐ |
| Core owner | _(assign)_ | ☐ |
| Fabric / SoC owner | _(assign)_ | ☐ |
| MEDS-V owner | _(assign)_ | ☐ |

Nobody signs until they have read §3 and can state, from memory, two things on it and why.

---

## 2. What MEDS-S1 v1.0 delivers

### 2.1 The core — S1-Core

**`RV64IMAC_Zicsr_Zifencei_Zicbom_Zicboz`**, machine and user mode, PMP.

- In-order, single-issue, 5-stage: IF → ID → EX → MEM → WB
- **In-order issue, out-of-order completion, in-order retire** via an 8-entry completion buffer
- Full EX→EX and MEM→EX forwarding; single-cycle load-use stall
- Static BTFN branch prediction; the frontend sits behind a `fetch_req`/`fetch_rsp` interface so the
  predictor is swappable without touching the pipeline
- Multi-cycle unit port: MUL (3-cycle pipelined), DIV (iterative), MXIF coprocessor
- Full M-mode trap architecture; **S-mode CSRs and trap delegation logic architected and present**,
  S-mode behaviour stubbed (see §4)
- 16 PMP regions
- `mcycle`, `minstret`, `mhpmcounter3–15` with programmable event selectors, `mcountinhibit`
- RVFI trace port, driven from the first pipeline commit
- Debug: `DebugMode` in the privilege FSM, `dcsr`/`dpc`/`dscratch*`, 2 instruction-address triggers
- Target: 50–100 MHz on Kintex-7, ~1.0–1.2 CoreMark/MHz class

### 2.2 The SoC

- 256-bit AXI4 backbone, 32-bit AXI4-Lite peripheral subtree
- I$ and D$: parameterised, 2-way, 64 B lines, write-back D$ with write buffer, blocking
- CLINT + PLIC
- UART, SPI, GPIO, timer (reused IP — see §5)
- Boot ROM + second-stage loader
- DDR3 via MIG on KC705
- **Two accelerator sockets**, frozen interface per `specs/INTERFACES.md` §4
- RISC-V Debug Module + JTAG DTM

### 2.3 The generator

`soc.yaml` → `meds_s1_soc_top.sv`, `link.ld`, `meds_s1_soc.h`, `meds_s1.dtsi`, `memory_map.md`,
Verilator top, OpenOCD config, PMA decode logic. **One source of truth, no hand-maintained
duplicates.**

### 2.4 Verification

- Directed unit testbenches per module
- RISCOF / `riscv-arch-test` against Sail, green on every merge
- Spike co-simulation over RVFI, every retired instruction
- `riscv-formal` bounded model check on the core
- Constrained-random + a functional coverage model of the implemented ISA
- Frozen benchmark suite: CoreMark, Embench-IoT, Dhrystone, MEDS-V kernels

### 2.5 Software

`crt0.S`, newlib + syscall stubs, working `malloc`, `printf` over UART **and** semihosting,
per-peripheral HAL, `libs1_perf`, `make run BOARD=<b> PROG=<x>.elf`, and a Verilator
"virtual FPGA" model.

### 2.6 Boards

**Verilator** and **KC705**, both from Phase 2, each a 4-file port.

---

## 3. What MEDS-S1 v1.0 does **not** deliver

Every row states a reason. A deferral without a reason is a gap.

| Deferred | Reason | Revisit |
|---|---|---|
| **Superscalar / out-of-order issue** | The innovation budget goes into interfaces and tooling. An in-order core with excellent interfaces is reused for a decade; a brilliant pipeline with none is rewritten by the next cohort. | v3 |
| **S-mode *behaviour*, Sv39 MMU, Linux** | The CSRs and delegation logic are present (§2.1); the translation datapath is not. Architecting it now is cheap, implementing it now delays the FPGA milestone that unblocks the whole lab. | Phase 5 |
| **Coprocessor address translation (M3)** | v1 coprocessor memory is physical-address, M-mode only. The PTW's second port exists and is tied off (`INTERFACES.md` R1.7), so this is a drop-in later. | Phase 5 |
| **Hardware cache coherence** | Software-managed via `Zicbom` + the uncached DRAM alias. A coherence protocol is a multi-year project and single-core does not need one. | v3 / multicore |
| **Multicore, SMP** | One core is enough to prove every interface in this document. Multicore multiplies the verification burden without teaching anything new about extensibility. | v3 |
| **Speculative MXIF issue (MXIF-1.1)** | Non-speculative issue costs ~2 cycles per offload and eliminates an entire class of correctness bug. Revisit only when a measurement shows it matters. | v2 |
| **F / D floating point** | An FPU is a separate project with its own verification burden. If it is needed, integrate `fpnew` rather than building one — the same conclusion MEDS-V Ch 16.3 reached. | v2 |
| **The V extension in the core** | Vectors arrive as MEDS-V over MXIF, not as core datapath. That decoupling is the whole point of the interface. | via MEDS-V |
| **Branch target buffer / gshare** | Static BTFN in v1. The frontend interface makes the predictor swappable, which converts this into a clean, measurable v2 project with a v1 baseline. | v2 |
| **Non-blocking caches, prefetch** | Blocking is correct and adequate. Non-blocking is a measurable optimisation and therefore a better v2 project than a v1 requirement. | v2 |
| **L2 cache** | Nothing in v1 needs one. Adding it changes the fabric, not the core. | v2 |
| **Scalar/vector memory disambiguation** | v1 stalls scalar memory while coprocessor memory is outstanding (`INTERFACES.md` §1.5). One comparator, obviously correct. Measure the cost and report it. | v2 |
| **Partial reconfiguration** | Out-of-context synthesis of the frozen SoC gets most of the turnaround benefit at a fraction of the flow complexity. | if OOC proves insufficient |
| **ASIC tape-out** | The RTL is written to be ASIC-clean (no inferred latches, no direct FPGA primitives, all memory behind `meds_sram_wrapper`) so the option stays open. Taking the option is a separate project with its own funding. | when funded |
| **Zynq / ZCU104 port** | KC705 is owned and sufficient. A board with an ARM PS is genuinely useful for ML host/DMA work, but it is a port, not a platform requirement. | Phase 4+ |
| **Custom ML instructions** | v1 delivers the *mechanism* (MXIF + the 7-item extension checklist), not instances. Shipping the mechanism with zero instances proves it is general; shipping one instance proves nothing. | per project |
| **Compressed-instruction MXIF channel** | `C` instructions are expanded before offload. The CV-X-IF compressed channel is only needed for custom 16-bit encodings, which nobody has proposed. | on demand |

---

## 4. Documented implementation choices

Not omissions — deliberate decisions a reviewer should be told about.

**S-mode is architected but stubbed.** The CSR file, the trap-delegation matrix (`medeleg`,
`mideleg`) and the privilege FSM include S-mode from v1.0; `satp` is present and writable but
translation is bypassed. This costs a few weeks now and saves rewriting the trap logic, the CSR
access-control matrix and the LSU during Linux bring-up. The intermediate state is honest: **v1.0
reports S-mode in `misa` only once translation works.**

**MXIF offloads non-speculatively.** See `INTERFACES.md` R1.1. This trades ~2 cycles of offload
latency for the elimination of speculative coprocessor side effects. It is also what makes MEDS-V
legal as designed, without a commit/kill channel it never had.

**Coprocessor memory is non-coherent and physical.** Model M2. Shared buffers live in the uncached
DRAM alias or are maintained with `Zicbom`. The alternative — routing MEDS-V's VLEN-wide traffic
through the 64-bit scalar LSU — would throttle the vector unit to scalar bandwidth and defeat its
purpose.

**Backbone is 256-bit, not 64.** A 64-bit AXI backbone at 100 MHz delivers 0.8 GB/s, which is below
the demand of MEDS-V at its *development* configuration. The width is a parameter; 256 and 64 are
both validated, 256 is the default.

**Tail behaviour of the completion buffer.** 8 entries is chosen so a single outstanding DIV plus a
long coprocessor operation cannot deadlock retire. If a workload shows it is the bottleneck, it is a
parameter.

**PMAs are generated, never hand-written.** The address decoder, the PMA check unit, the linker
script, the device tree and the C headers all come from `soc.yaml`. The failure mode this prevents —
a memory map that is correct in the RTL and wrong in the device tree — is otherwise inevitable and
extremely hard to debug.

---

## 5. Reuse policy

Writing new infrastructure IP requires written justification at design review. Default to reuse:

| Function | Source | Licence to verify |
|---|---|---|
| AXI crossbar, FIFOs, CDC, arbiters | `pulp-platform/axi`, `pulp-platform/common_cells` | ☐ |
| Debug Module + JTAG DTM | `pulp-platform/riscv-dbg` | ☐ |
| UART / SPI / GPIO / I²C / timer | OpenTitan or PULP peripherals | ☐ |
| Coprocessor interface **spec** | OpenHW CV-X-IF (profiled as MXIF-1.0) | ☐ |
| Golden reference models | Spike, Sail | ☐ |
| Compliance framework | RISCOF, `riscv-arch-test` | ☐ |
| Formal | `riscv-formal` | ☐ |
| Vector unit | MEDS-V (in-house) | n/a |
| FPU, if ever | `fpnew` (ETH Zürich) | ☐ |

**Written from scratch:** the core pipeline, the caches, the MMU, the generator, the BSP, the
verification harness, and every interface in `INTERFACES.md`. That list is the identity of the
project. Everything else is undifferentiated and rewriting it is student-months for zero gain.

---

## 6. Definition of done for v1.0

All must be true simultaneously on a tagged release:

- ☐ RISCOF `riscv-arch-test` green for `RV64IMAC_Zicsr_Zifencei_Zicbom` against Sail
- ☐ Spike co-simulation green over the full benchmark suite plus the random regression
- ☐ `riscv-formal` bounded check green on the core
- ☐ Verible lint clean, zero waivers without a written justification
- ☐ Functional coverage target met and the report published
- ☐ Synthesis timing met at the declared frequency on KC705, report published
- ☐ `openocd` + `gdb` can load and debug an arbitrary ELF over JTAG with **no resynthesis**
- ☐ **Two accelerators, written by two people who did not write the core, attach through the socket
  and MXIF with zero modification to core RTL** ← *the real test of the whole project*
- ☐ MEDS-V attached over the MXIF adapter, vector arch-tests passing
- ☐ Every module has a `README.md` stating its interface contract
- ☐ Benchmark numbers published and tracked over time
- ☐ Compliance evidence downloadable as a release artefact
- ☐ A student who has completed only `rv-workshop` can add a peripheral via `soc.yaml` and see it
  from C, following the docs alone, in under a day

The second-to-last item is the certification identity. The last one is the teaching identity. The
bold one is the extensibility identity. **If only three things ship, ship those three.**

---

## 7. What to cut, in order, when time runs short

Decided in advance, so the decision is not made at 2 a.m. in week 30:

1. Second accelerator socket → one socket
2. `riscv-formal` → defer to v1.1 (keep the RVFI port; it costs nothing to have)
3. Constrained-random layer → defer (keep arch-test and cosim; those are non-negotiable)
4. SPI, GPIO, I²C → UART only
5. 2-way caches → direct-mapped
6. `Zicboz` → `Zicbom` only
7. Embench-IoT → CoreMark only

**Never cut:** RISCOF, Spike co-simulation, the Debug Module, the generator, or the socket/MXIF
freeze. Those five *are* the platform. Everything above them is decoration.

---

*Signed copies go in `docs/reviews/`. This contract is reproduced verbatim in every project report
and every paper's methodology section.*
