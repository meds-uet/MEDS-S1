# M-07 Results and Automation

This directory contains generated CoreMark and Dhrystone logs and result files
from the M-07 parser and CI runner.

`sw/apps/results-history.json` records each run by default. The gate compares
CoreMark ticks per iteration and Dhrystone cycles per run with the latest
accepted result for the same configuration. A regression strictly greater than
3 percent is `blocked`; an exact 3 percent regression passes. A blocked run is
retained in history but is not used as the next baseline.

Run both benchmarks and generate the result files from the repository root:

```bash
python3 sw/apps/run_ci.py --output-dir sw/apps/results-ci
```

The runner writes `results.json` and `results.md`, together with the benchmark
logs used to produce them. To parse existing logs directly:

```bash
python3 sw/apps/parse_results.py \
  --coremark path/to/coremark.log \
  --dhrystone path/to/dhrystone.log \
  --format json
```

Results use the temporary Spike platform and must not be presented as final
MEDS-S1 hardware scores.

To compare an existing result file without running the benchmarks:

```bash
python3 sw/apps/regression_gate.py \
  sw/apps/results-ci/results.json \
  --history sw/apps/results-history.json \
  --record
```

`baseline` means no accepted result exists for that benchmark and configuration.
`pass` means the result is at or below the 3 percent threshold, including an
improvement. `blocked` means the result is more than 3 percent slower. Both
passing and blocked valid runs are recorded, but only passing runs become future
baselines.