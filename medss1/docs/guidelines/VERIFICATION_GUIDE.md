# MEDS-S1 Verification Guide

**Status:** Draft for Phase-0 ratification · **Owner:** verification lead

> The verification lead has authority to block merges. If that authority does not exist, the CI gate
> does not exist either — it is a suggestion with a green tick.

---

## 1. The five layers

Each layer catches a different bug class. All five are needed; none substitutes for another.

| Layer | What it checks | Runs | Catches | Owner project |
|---|---|---|---|---|
| **0** Lint + elaboration | syntax, latches, width mismatches, all four configs build | every push | typos, latches, config rot | M-10 |
| **1** Unit tests | one module against hand-derived expectations | every PR | logic errors inside a block | M-05, M-06 |
| **2** Co-simulation | every retired instruction vs Spike over RVFI | every PR | integration and semantic errors | R-05 |
| **3** ACT4 | compliance with the ratified ISA vs Sail | every PR | spec misreadings, corner cases | M-11, T-07 |
| **4** Random + coverage | randomly generated sequences, functional coverage | nightly | hazards, timing, the unimagined | T-07 |
| — | **Formal** (orthogonal) | riscv-formal, SVA liveness | nightly | unreachable states, deadlock | R-01, T-07 |

**Layer 2 is the backbone and it is built before the datapath exists.** A directed test costs twenty
minutes and covers one case. A co-simulation harness costs three days and covers every case any
program exercises, forever. Teams that skip it spend the three days anyway as one-off debugging and
get no reusable asset for it.

---

## 2. Where your work goes

```
verif/
├── unit/          layer 1 — you are probably here
├── cosim/         layer 2 — Spike comparison over RVFI
├── riscof/        layer 3 — architectural compliance (ACT)
├── formal/        riscv-formal + SVA properties
├── conformance/   MXIF and socket conformance — reusable, outlive every accelerator
└── common/        clock/reset generators, BFMs, scoreboards
```

---

## 3. Writing a unit testbench

Copy [`verif/unit/tb_s1_alu.sv`](../../verif/unit/tb_s1_alu.sv). It is the worked reference and it
demonstrates the three habits below.

### 3.1 Derive expectations from parameters, not constants (R-V2)

```systemverilog
// GOOD — runs unmodified at every XLEN
check("SLL shamt masked", result, 64'd1);
corner[2] = {1'b0, {W-1{1'b1}}};      // INT_MAX, whatever W is

// BAD — silently wrong the moment someone builds a different config
if (result != 64'h7FFFFFFFFFFFFFFF) ...
```

This is what let MEDS-V run the same CSR testbench at VLEN 128, 256 and 512 and watch the check
count rise. A suite written against constants has to be rewritten for the configuration sweep, which
in practice means the sweep does not happen.

### 3.2 Write the golden model from the spec, not from the RTL

If your expected value is a copy of the design's expression, the test proves only that the code
equals itself. Write it from the ISA manual. In `tb_s1_alu.sv` the `golden()` function is
deliberately written in a different style from the DUT.

### 3.3 Test what causes hangs, not only wrong answers (R-V5)

```systemverilog
// If CMP_NONE ever floats, every non-branch instruction becomes a random
// branch. That is a hang, not a wrong answer, and it is far harder to debug.
cmp_op = CMP_NONE; #1;
check1("CMP_NONE is 0", cmp_result, 1'b0);
```

Ready/valid liveness, FIFO full-and-empty, arbiter fairness, and "does this FSM always leave this
state" belong in every testbench that has them.

### 3.4 Report a count and fail loudly (R-V3)

```systemverilog
if (errors == 0) begin
  $display("=== PASS : %0d checks ===", checks);
  $finish;
end else begin
  $display("=== FAIL : %0d errors of %0d checks ===", errors, checks);
  $fatal(1, "tb_<module> failed");
end
```

The runner requires **both** exit code 0 and the `=== PASS` line. A testbench that compiles, runs and
checks nothing exits 0 too — requiring the count is what catches that.

---

## 4. Running things

```bash
make test-unit                     # every unit testbench
make test-unit TB=s1_alu           # just one
python3 scripts/run_unit_tests.py --tb alu --keep    # reuse the build dir while iterating
make lint                          # elaboration + lint, all configs
make check                         # structure conventions
```

Build artefacts land in `build/unit/<tb_name>/`. Waveforms: add `--trace` to the runner's Verilator
flags locally; **do not** commit VCDs.

---

## 5. Definition of done for a verification task

- ☐ Testbench in `verif/unit/`, named `tb_<module>.sv`
- ☐ Passes, and prints a check count that is plausibly large
- ☐ Expectations derived from parameters (R-V2)
- ☐ At least one hang-class property checked (R-V5)
- ☐ Runs in CI — i.e. it is committed and `make test-unit` finds it
- ☐ Coverage contribution stated in the PR description
- ☐ Module page in `docs/modules/` records the verification status

---

## 6. Adding ACT (architectural compliance) — the growth path

Layer 3 is scaffolded and **intentionally skipped in CI** until M-11 and T-07 land. The job exists in
`.github/workflows/pr.yml` so that turning it on is a one-line change rather than a new pipeline.

Order of work:

1. `verif/riscof/config.ini` — DUT plugin (MEDS-S1) and reference plugin (Sail).
2. `verif/riscof/meds_s1/` — the DUT plugin: how to build a test, run it, and produce a signature.
3. Get `riscof run --suite=riscv-arch-test/riscv-test-suite/rv64i_m/I` green locally.
4. Delete the `if: false` on the `archtest` job and set the pass threshold to 100%.
5. Extend to `M`, `C`, `Zicsr`, `Zifencei`, then privileged.

The signature-comparison model means a test either matches the Sail reference exactly or it does
not. There is no partial credit, which is why this layer is worth having.

---

## 7. Common mistakes

| Mistake | Why it hurts |
|---|---|
| Testbench that only prints, never compares | passes forever, catches nothing |
| Expected values copied from the RTL | proves the code equals itself |
| Hard-coded 64-bit constants | breaks the moment someone builds `s1_nano` |
| `$random` instead of `$urandom` | not reproducible; a failure you cannot re-run is not a bug report |
| Testing only the happy path | the bugs are in backpressure, full FIFOs and reset |
| Waiting for the design to be "ready" | layer 2 is built *before* the datapath, deliberately |
