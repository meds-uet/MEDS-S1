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
| **R-N6** | Combinational/registered signal pairs use `_d`/`_q`: `count_d` (next-state, comb) feeds `count_q` (registered). Never `_next`, `_reg`, or unsuffixed pairs. | **[auto]** |
| **R-N7** | A signal that has crossed a clock domain through a synchroniser carries a `_sync` marker before its direction suffix: `req_sync_i`. Lets a reviewer spot a CDC boundary from the signal name alone. | |
| **R-N8** | Pipelined copies of a signal: `_q` is one cycle of latency, `_q2` two cycles, `_q3` three, and so on. | |
| **R-N9** | Enum values should be `ALL_CAPS` for true constants (opcodes `OP_JALR`), `ALL_CAPS` for a "don't-care" value set like FSM states (`ST_IDLE`). | **[auto: typedef + storage type]** |
| **R-N10** | Clock is `clk_i`, reset is `rst_ni`, always. One clock and one reset per module. | |


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

**Assignment discipline is tied to the block, no exceptions:** `always_comb` uses blocking (`=`)
only; `always_ff` uses non-blocking (`<=`) only. Mixing them inside either block is a simulation/
synthesis mismatch waiting to happen, and it is exactly the kind of bug a linter catches for free —
so it does not go to review, it fails CI.
###

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

### R-C8 — shared types live in the package and parameters

If two modules must agree on a struct's shape, it goes in `s1_pkg.sv`. A struct declared in a module
file that another module also needs is how field-order bugs happen.

### R-C9 — no clock-domain crossing outside a named synchroniser

CDC lives in `rtl/common/` synchronisers and in `meds_s1_accel_socket`. If you are writing a
two-flop synchroniser by hand, stop and ask — you are probably solving a problem the socket already
solves (NFR-6).

### R-C10 — handshakes are AXI-style

`valid` must not depend combinationally on `ready`. Once asserted, `valid` stays asserted with
stable payload until `ready`. This one rule prevents most fabric deadlocks.

### R-C11 — `case` no `casex`, `casez` justified only **[auto]**

`casex` is banned outright it treats both `x` and `z` as don't-care in the comparison, which is
the direct mechanism behind X-optimism bugs: a design that behaves in simulation but fails in
silicon because synthesis resolves the don't-cares differently. `casez` is permitted only for
priority-encoder-style patterns with an explicit reviewer sign-off in the PR description; default
to `unique case` / `unique0 case` on parameterised widths instead.

### R-C12 — no `.*` port connections **[auto]**

Every port connection is named explicitly: `.clk_i(clk_i)`, never `.*`. Implicit connection
silently matches by name — rename a signal in one module and a stale connection elsewhere fails
silently instead of failing to compile. Named connections turn that into a compile error, which is
exactly where you want the failure to happen.

### R-C13 — no implicit width truncation **[auto via lint]**

An assignment or port connection where the RHS is wider than the LHS must be sliced explicitly
(`data_i[7:0]`), not left for the tool to truncate silently. Verilator's `WIDTH` warning is
promoted from warning to error in `verif/verilator.vlt` if a
specific case is genuinely intentional (it should carry a comment explaining why).

### R-C14 — `localparam` unless it must be overridden at instantiation

A parameter only stays `parameter` if some instantiation legitimately needs to override it.
Anything derived from another parameter (a width computed via `$clog2`, an internal constant) is
`localparam`. 

### R-C15 — no implicit width extension **[auto via lint]**

When the RHS is narrower than the LHS, extend it explicitly using zero/sign extension or an explicit `unsigned'() / signed'()` cast. Do not rely on implicit extension. Verilator treats `WIDTHEXPAND` as an error.

### R-C16 — a simple mux is an expression, not a module

A 2:1 or narrow N:1 select belongs inline as a ternary or a `case` inside `always_comb` /
`assign`, not wrapped in its own `s1_mux_*` module. A standalone mux module earns its keep only
when it is wide, reused verbatim in many places, or needs its own testbench for a non-trivial
select policy — default is inline.

```systemverilog
assign result_o = sel_i ? operand_b_i : operand_a_i;
```

### R-C17 — no `#delay` in synthesizable RTL **[auto]**

`#` delays have no synthesis meaning and only exist in simulation; if it compiles differently
than it simulates, it does not belong in `rtl/`. Confined to `verif/` testbenches only.

### R-C18 — flip-flops over latches

`always_latch` is permitted (R-C1 names it) but discouraged by default prefer restructuring
into `always_ff`. A latch that survives review needs a comment saying why a flip-flop doesn't work.

### R-C19 — no two non-blocking assignments to the same bit **[auto]**

Two `<=` writes to the same signal (or overlapping bits of it) in the same clocked block is almost
always a copy-paste bug or a forgotten `else`; the second write silently wins and the first is dead
code that looks alive.

```systemverilog
always_ff @(posedge clk_i or negedge rst_ni) begin
  if (!rst_ni)      count_q <= '0;
  else if (clr_i)   count_q <= '0;
  else if (en_i)    count_q <= count_q + 1;
  else               count_q <= count_q;
end
```

### R-C20 — no multi-bit signal in boolean context **[auto via lint]**

Putting a multi-bit signal directly into an `if`/boolean condition implicitly means "any bit is
set" — but that intent isn't clearly visible at the call site, so always write the comparison
explicitly with `!= '0'`.

```systemverilog
if (my_multibit_signal != '0) begin
  ...
end
```

### R-C21 — no cyclic package dependencies **[auto via lint]**
A signal must not combinationally depend on itself, directly or through a chain of assign/always_comb logic, with no register in the cycle. Verilator's UNOPTFLAT warning is promoted from warning to error in verif/verilator.vlt.

### R-C22 — ANSI (Verilog-2001) port declarations only **[auto]**

Full combined port-and-type declaration in the module header; no Verilog-95 list style, no
separate `input`/`output` re-declarations in the body. Opening `(` on the module-declaration line;
first port starts the next line; closing `)` alone in column zero. Clock port(s) first, then
reset(s), then the rest. Ports align in tabular style (R-F5): no space before the opening paren of
the longest port name, none just inside `(` or just before `)` of a port expression.

```systemverilog
module s1_counter #(
  parameter int unsigned Width = 8
) (
  input  logic             clk_i,
  input  logic             rst_ni,
  input  logic             en_i,
  input  logic             clr_i,
  output logic [Width-1:0] count_o
);
```

### R-C23 — every generate block is named **[auto]**

Every branch of a generate-`if` and every generate-`for` body gets an explicit `begin : label`.
Without it, different tools produce different hierarchical names for the generated instances, and
a waveform or a synthesis report becomes tool-dependent. Labels are `lower_snake_case`, one space
between `begin` and the label (R-F6 applies to it same as any other block label).

```systemverilog
if (TypeIsPosedge) begin : posedge_type
  always_ff @(posedge clk_i) foo_q <= bar_i;
end else begin : negedge_type
  always_ff @(negedge clk_i) foo_q <= bar_i;
end

for (genvar ii = 0; ii < NumberOfBuses; ii++) begin : my_buses
  my_bus #(.Index(ii)) i_my_bus (.foo_i(foo), .bar_i(bar[ii]));
end
```

No extra `begin`/`end` wrapping a generate construct, and no `generate`/`endgenerate` region —
both are redundant now that every block is individually named.

### R-C24 — use signed arithmetic constructs, not manual sign handling

Wherever signed arithmetic is genuinely needed, declare the signal `signed` and use SystemVerilog's
signed operators don't hand-roll two's-complement logic.  

### R-C25 — no hierarchical references in synthesizable RTL **[auto]**

Tool support for hierarchical references is inconsistent — some synthesisers accept them, some
error, some silently ignore them, and any of those is a simulation/synthesis mismatch waiting to
happen. The one exception: a hierarchical reference inside an SVA that is macro-guarded out of the
synthesis view.

### R-C26 — array endianness

Packed arrays are (`logic [N-1:0] foo`, bit 0 on the right). Unpacked arrays are (`byte_t arr[0:N-1]`, index 0 first). 

### R-C27 — prefer registered module outputs

Where a choice exists, register a module's outputs rather than exposing purely combinational
paths at the boundary — keeps timing closure local to the module instead of leaking a long combinational
path into whatever instantiates it. 

## R-C28. Finite state machines — R-M

Every FSM is exactly three blocks never two, never one. Mixing next-state and output logic into
a single combinational block is the most common FSM review comment there is; naming the three
blocks by convention (R-M2) makes the split checkable at a glance instead of something a reviewer
has to reconstruct by reading.

| ID | Rule | |
|---|---|---|
| **R-M1** | State register is a `typedef`'d enum, never raw `logic [N-1:0]`. Encoding (binary/one-hot/gray) is the designer's call per-FSM, but the RTL never compares it as a bare integer — always via the enum name. | **[auto]** |
| **R-M2** | Every FSM is exactly three blocks: one `always_ff` for the state register (`state_q <= state_d`), one `always_comb` for next-state logic (computes `state_d` from `state_q` and inputs), one `always_comb` for output logic (computes outputs from `state_q`, and inputs for a Mealy output). No block does more than its one job — the sequential block never computes outputs, the next-state block never drives an output, the output block never assigns `state_d`. | **[auto: block-count + assignment-target check]** |
| **R-M3** | Next-state logic uses `unique case (state_q)`  with a `default` that returns to a safe/reset state never `state_q` unchanged, never `'x`. | **[auto]** |

---

## 4. Formatting — R-F

### R-F1 — indentation: 2 spaces, spaces only **[auto]**

No tabs anywhere in the tree. A tab renders differently per editor/viewer, and a mixed
tabs/spaces file is how a diff shows every line changed when only one was.

### R-F2 — `begin`/`end` placement **[auto]**

`begin` stays on the line that opens the block; `end else begin` is one line, not `end` /
`begin` on separate lines.

```systemverilog
if (condition) begin
  foo = bar;
end else begin
  foo = bum;
end
```

### R-F3 — line length: 120 columns **[auto]**

Beyond 120 columns, break the line and indent the continuation. Applies inside
`always_comb`/`always_ff`/`always_latch` blocks same as anywhere else.

### R-F4 — right-align line continuations **[auto via lint]**

A wrapped line's continuation aligns to the right of the operator/opening delimiter on the line
above it, not to column zero and not arbitrarily indented.

### R-F5 — tabular alignment for grouped lines

Two or more adjacent, structurally similar lines (port lists, case items, signal declarations)
align their identical columns vertically, so the differences are the only thing that jumps out:

```systemverilog
unique case (my_state)
  StInit:   $display("Shall we begin");
  StError:  $display("Oh boy this is bad");
  default: begin
    my_state  = StInit;
    interrupt = 1;
  end
endcase
```

### R-F6 — comma and colon spacing **[auto]**

One space after a comma, none before. One space before and after a block label's colon
(`foo : begin`). No space before a case-item's colon; at least one space after it.

### R-F7 — no space before `(` on calls **[auto]**

Function calls, task calls, and macro calls: no space between the name and the opening
parenthesis — `my_func(a, b)`, not `my_func (a, b)`.

### R-F8 — keyword spacing **[auto via lint]**

Use consistent whitespace around keywords. Keywords normally have a space before and after them when surrounding syntax allows it. Do not add whitespace before a keyword at the start of a line, after a group-opening delimiter when the syntax requires no space, or after a keyword at the end of a line.

### R-F9 — parenthesize ambiguous precedence

If a reasonable reviewer would need to check an operator-precedence chart, add parentheses
instead. Ternaries nested inside another ternary's true-branch must be parenthesized:

```systemverilog
assign a = ((addr & mask) == My_addr) ? b[1] : ~b[0];   
```

### R-F10 — comment style

`//` preferred; `/* */` permitted but not the default.

### R-F11 — declare before use, declare near use **[auto]**

Implicit net declarations are banned every signal is declared before it is referenced.
Recommended: declare a signal, type, `enum`, or `localparam` at the top of the module.

---

## 5. Lint — R-L

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

## 6. Documentation — R-D

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

## 7. Verification — R-V

Full detail in [`VERIFICATION_GUIDE.md`](VERIFICATION_GUIDE.md). The rules the checker enforces:

| ID | Rule | |
|---|---|---|
| **R-V1** | A unit testbench is `verif/unit/tb_<module>.sv` and the module must exist. | **[auto]** |
| **R-V2** | Derive expectations from parameters, never constants — the same testbench must run at every config. | |
| **R-V3** | Print `=== PASS : <n> checks ===` and exit non-zero on failure. The runner requires both, so a testbench that checks nothing cannot report success. | **[auto]** |
| **R-V4** | `$urandom`, never `$random` — reproducible seeding. | **[auto]** |
| **R-V5** | Test the properties that cause hangs, not only wrong answers. | |
| **R-V6** | The DUT instance in a testbench is named after the module itself, in uppercase — never `dut` or `uut`. | **[auto]** |

---

## 8. Git — R-G

| ID | Rule |
|---|---|
| **R-G1** | Branch `wp<N>/<short-description>` or `<project-id>/<short-description>`, e.g. `m-01/uart-wrapper`. |
| **R-G2** | Branches live ≤ 2 weeks. Longer means the task was mis-sized. |
| **R-G3** | Commit subject: `<project-id>: <imperative summary>`; body explains why; footer `Closes #NNN`. |
| **R-G4** | Squash merge. One issue, one commit on `main`. |
| **R-G5** | Never commit build output. `build/`, `*.vcd`, `obj_dir/` are in `.gitignore`. |

---

## 9. What a reviewer will block on

Not style preferences — these are the things that cost someone else a week:

1. An inferred latch (R-C3).
2. A memory not behind `meds_s1_sram` (R-C5).
3. A change to a frozen interface without an `interface-change` issue.
4. A module with no testbench, or a testbench that checks nothing.
5. Hard-coded widths that break another configuration.
6. A missing module README (R-D3) — because the next contributor pays for it, not you.
7. `valid` depending combinationally on `ready` (R-C10).

---

## 10. Proposing a change to this file

Open an issue labelled `type:docs` + `area:guidelines`. State the rule, the bug class it prevents,
and how it will be checked. Rules are cheap to add and expensive to remove, so the bar is: **has
this actually bitten us, or is it likely to?**
