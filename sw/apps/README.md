# Applications and Benchmarks

Applications and benchmark sources live here. M-07 runs CoreMark and Dhrystone
2.1; see [`M07.md`](M07.md) for implementation notes.

## Run M-07

From the repository root, build and run both benchmarks, validate output, and
apply the regression gate:

```bash
make bench
```

`CONFIG` defaults to `s1_base` and labels the results; it does not select an RTL
configuration for these app builds. Override it with `make bench CONFIG=<label>`.

Requirements: Python 3, GNU make, `riscv64-unknown-elf-gcc` with bare-metal
Newlib, and `spike` on `PATH`. M-07 targets `riscv64-unknown-elf`,
`rv64imac_zicsr_zifencei_zicbom_zicboz`/`lp64`, with the `rv64imac/lp64`
multilib. Documented local versions: GCC 16.1.0, binutils 2.46, Newlib 4.6.0,
Spike 1.1.1-dev.

For custom iterations or output, invoke the runner directly from the repository root:

```bash
python3 scripts/run_ci.py --configuration local-spike \
  --iterations 40 --dhrystone-runs 10000 --output-dir build/bench
```

Defaults are `temporary-spike`, 40 CoreMark iterations, 10,000 Dhrystone runs,
and output directory `build/bench/`. Reports and logs follow `--output-dir`;
history stays at `build/bench/results-history.json` unless `--history` is set.
The app Makefiles also leave intermediate build artifacts in their app folders.

## PASS and regression behavior

PASS requires both runs to succeed and their correctness and timing output to
parse. CoreMark must print its validation marker and CRCs; Dhrystone must
complete with expected final values and positive, consistent timing.

With no accepted result for a benchmark/configuration, `baseline` succeeds.
Against accepted history, a slowdown up to and including 3% passes; over 3% is
`blocked` and returns non-zero. Blocked entries are retained but never become
future baselines.

These are temporary Spike results, not MEDS-S1 hardware scores. The GitHub
Actions benchmark job is currently disabled.

## Add a benchmark

Put the source and app-specific build/run recipe in a directory under
`sw/apps/`. Extend `scripts/parse_results.py` to validate its output, return the
benchmark/configuration/metric/`valid` fields, and format its result row. Add
its build/run and parse calls to `scripts/run_ci.py`, and metric validation to
`scripts/regression_gate.py`. Add parser/gate tests for valid and corrupted
output. Keep generated results under `build/bench/`, not in source directories.

---
*Conventions: [`docs/guidelines/CODING_STANDARD.md`](../../docs/guidelines/CODING_STANDARD.md)*
