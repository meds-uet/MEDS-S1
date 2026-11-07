# MEDS-S1 Coding Standard

**Status:** Draft for Phase-0 ratification ·
**Enforced by:** `make check`

> Rules with a **[auto]** tag are checked by `scripts/check_structure.py` or the linter and will
> fail CI. Rules without it are review items. A rule nobody can check is advice, not a standard —
> so when you propose a new rule, propose the check with it.

Run before every push:

```bash
make check      # structure + lint
make test-unit  # your testbench
```

---

## 1. Why these rules exist

20+ projects run in parallel and contributors rotate every few semesters. The cost of an
inconsistent repository is not aesthetic — it is that the next person cannot find anything, cannot
tell finished work from a stub, and cannot review safely. Every rule below buys navigability or
prevents a specific bug class we know we will otherwise hit.

Three rules matter more than the rest. If you remember nothing else:

- **R-C3** — pre-assign outputs before a `case`. Prevents inferred latches.
- **R-C5** — every memory goes through `meds_s1_sram`. Keeps an ASIC port possible.
- **R-V2** — derive expectations from parameters, never constants. Keeps testbenches alive across configs.

---

## 2. Naming — R-N

| ID | Rule | |
|---|---|---|
| **R-N1** | A file contains a module of the same name: `s1_alu.sv` holds `module s1_alu`. | **[auto]** |
| **R-N2** | Module prefixes: `s1_*` core, `meds_s1_*` platform/shared, `meds_v_*` vector, `tb_*` testbench. | **[auto]** |
| **R-N3** | Ports carry a direction suffix: `_i`, `_o`, `_io`. Exceptions: `clk_i`, `rst_ni`. | **[auto]** |
| **R-N4** | Active-low signals end `_n` *before* the direction suffix: `rst_ni`. | |
| **R-N5** | `UPPER_SNAKE` parameters, `lower_snake` signals, `lower_snake_t` types, `lower_snake_e` enum types with `UPPER_SNAKE` values. | |
| **R-N6** | Clock is `clk_i`, reset is `rst_ni`, always. One clock and one reset per module. | |

```systemverilog
module s1_regfile
  import s1_pkg::*;
#(
  parameter int unsigned N_READ = 2
) (
  input  logic                  clk_i,
  input  logic                  rst_ni,
  input  logic [REG_ADDR_W-1:0] raddr_i [N_READ],
  output logic [XLEN-1:0]       rdata_o [N_READ]
);
```

---

## 3. Coding — R-C

### R-C1 — no bare `always` **[auto]**

Use `always_ff`,`always_comb`, `always_latch`. The use of `always @(...)` is banned: it hides intent and lets
a sensitivity-list mistake become a simulation/synthesis mismatch.

### R-C2 — `logic`, never `reg` or `wire` **[auto]**

SystemVerilog's `logic` covers both. Mixing the three tells the reader nothing and invites
multiple-driver confusion.

### R-C3 — assign a default before every `case` **[auto via lint]**

```systemverilog
// GOOD
always_comb begin
  result_o = '0;              // default first
  unique case (op_i)
    ALU_ADD: result_o = sum;
    ALU_AND: result_o = a_i & b_i;
    ...
  endcase
end
```

`unique case` on a fully-covered enum is *logically* latch-free, but neither Verilator nor a
synthesiser can prove it, and an out-of-range value at runtime makes it false anyway. Pre-assigning
makes the property **structural instead of an argument**. `rtl/core/s1_alu.sv` is the reference.

### R-C4 — reset policy

Asynchronous assert, synchronous de-assert, active-low. One reset per clock domain. **No local
reset generation inside a leaf module.**

```systemverilog
always_ff @(posedge clk_i or negedge rst_ni) begin
  if (!rst_ni) count_q <= '0;
  else         count_q <= count_d;
end
```

### R-C5 — every memory goes through `meds_s1_sram` **[auto]**

Register file, cache tags, cache data, TLB, VRF, any FIFO deeper than 32 entries. No exceptions.
Read latency is **one cycle, registered output, everywhere**. This is what keeps a tape-out possible
without a rewrite, and it costs nothing now.

### R-C6 — 800 lines per file **[auto]**

Longer means it should be split. Waivers go in `scripts/check_structure.py` with a reason.

### R-C7 — no magic numbers

Widths and depths come from parameters or `$clog2`. `64'h1000` in the middle of a datapath is a
review blocker; a named parameter in `s1_pkg.sv` is not.

### R-C8 — shared types live in the package

If two modules must agree on a struct's shape, it goes in `s1_pkg.sv`. A struct declared in a module
file that another module also needs is how field-order bugs happen.

### R-C9 — no clock-domain crossing outside a named synchroniser

CDC lives in `rtl/common/` synchronisers and in `meds_s1_accel_socket`. If you are writing a
two-flop synchroniser by hand, stop and ask — you are probably solving a problem the socket already
solves (NFR-6).

### R-C10 — handshakes are AXI-style

`valid` must not depend combinationally on `ready`. Once asserted, `valid` stays asserted with
stable payload until `ready`. This one rule prevents most fabric deadlocks.

---

## 4. Lint — R-L

| ID | Rule | |
|---|---|---|
| **R-L1** | `make lint` clean before every PR. | **[auto]** |
| **R-L2** | Every waiver lives in `verif/verilator.vlt` and carries a justification comment. A waiver without a reason is a review blocker. | **[auto]** |
| **R-L3** | Never waive a warning inline to make CI pass. Fix it, or waive it centrally with a reason a reviewer can argue with. | |

Two traps when editing `verif/verilator.vlt`:

- `` `verilator_config `` must be the **first line** of the file.
- A comment must not begin with the tool's own name, or it parses as a metacomment and becomes a
  syntax error.

---

## 5. Documentation — R-D

| ID | Rule | |
|---|---|---|
| **R-D1** | Every source directory has a `README.md` saying what lives there, what does not, and how to add something. | **[auto]** |
| **R-D2** | Every `.sv` and `.py` file carries the SPDX header. | **[auto]** |
| **R-D3** | Every RTL module has a page in `docs/modules/` following `TEMPLATE.md`, merged with the module (NFR-7). | **[auto: presence]** |
| **R-D4** | A module header states what it does, its status tag, and where its contract is specified. | |
| **R-D5** | Comments explain *why*, not *what*. `// increment counter` above `count_d = count_q + 1` is noise; `// saturates rather than wrapping, because the PLIC treats 0 as no-interrupt` is not. | |

Status tags in module headers, so a reader can tell finished from stub at a glance:

```
[COMPLETE]              works and is verified
[COMPLETE -- REFERENCE] works, verified, and is the house-style example to copy
[SKELETON -- <project>] ports and structure only; named project will implement it
[WIP -- <project>]      under active development, not yet verified
```

---

## 6. Verification — R-V

Full detail in [`VERIFICATION_GUIDE.md`](VERIFICATION_GUIDE.md). The rules the checker enforces:

| ID | Rule | |
|---|---|---|
| **R-V1** | A unit testbench is `verif/unit/tb_<module>.sv` and the module must exist. | **[auto]** |
| **R-V2** | Derive expectations from parameters, never constants — the same testbench must run at every config. | |
| **R-V3** | Print `=== PASS : <n> checks ===` and exit non-zero on failure. The runner requires both, so a testbench that checks nothing cannot report success. | **[auto]** |
| **R-V4** | `$urandom`, never `$random` — reproducible seeding. | **[auto]** |
| **R-V5** | Test the properties that cause hangs, not only wrong answers. | |

---

## 7. Git — R-G

| ID | Rule |
|---|---|
| **R-G1** | Branch `wp<N>/<short-description>` or `<project-id>/<short-description>`, e.g. `m-01/uart-wrapper`. |
| **R-G2** | Branches live ≤ 2 weeks. Longer means the task was mis-sized. |
| **R-G3** | Commit subject: `<project-id>: <imperative summary>`; body explains why; footer `Closes #NNN`. |
| **R-G4** | Squash merge. One issue, one commit on `main`. |
| **R-G5** | Never commit build output. `build/`, `*.vcd`, `obj_dir/` are in `.gitignore`. |

---

## 8. What a reviewer will block on

Not style preferences — these are the things that cost someone else a week:

1. An inferred latch (R-C3).
2. A memory not behind `meds_s1_sram` (R-C5).
3. A change to a frozen interface without an `interface-change` issue.
4. A module with no testbench, or a testbench that checks nothing.
5. Hard-coded widths that break another configuration.
6. A missing module README (R-D3) — because the next contributor pays for it, not you.
7. `valid` depending combinationally on `ready` (R-C10).

---

## 9. Proposing a change to this file

Open an issue labelled `type:docs` + `area:guidelines`. State the rule, the bug class it prevents,
and how it will be checked. Rules are cheap to add and expensive to remove, so the bar is: **has
this actually bitten us, or is it likely to?**
